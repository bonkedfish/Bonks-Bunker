# WeatherDirector — "Weather" node added by Main (group "weather", same path on every peer) (D-099).
#   Host: runs the schedule (WeatherRules: clear / fog / rain / storm, random lengths) or the state the host forced
#         from the pause menu (request_mode), sends each change to everyone; in a storm it calls lightning: most
#         strikes far away (flash + thunder), some aimed at a player standing outside - a warning on their screen
#         and a glow on the ground, then the strike warn_s later where they stood: damage falls off over radius_m,
#         players under a roof take none. Tells zombies to hear less (hearing_mult) and disc golf to blow harder
#         (storm_wind).
#   Every peer: blends rain / storm / fog levels toward the state, drives Atmosphere.set_weather (clouds, sky,
#         fog, sun, flashes), rain streaks around the camera (not indoors), WeatherSound (rain bed, thunder after the
#         sound's travel time), and draws the bolts.
# Depends on: WeatherRules, WeatherSound, Atmosphere (sibling "Atmosphere"), DropZone.toast (HUD toasts), Player
# (group "players": peer_id, health, is_local).
class_name WeatherDirector
extends Node3D

const ROOF_MASK := 1

var state := "clear"
var mode := "auto"           # "auto" or a forced state (host's pause menu)
var levels := Vector3.ZERO   # (rain, storm, fog) now, blended

var _t: Dictionary
var _rng := RandomNumberGenerator.new()
var _left := 0.0             # host: seconds until the next state
var _strike_in := 0.0        # host: seconds until the next lightning
var _flash := 0.0
var _atmos: Node
var _sound: WeatherSound
var _rain: GPUParticles3D
var _bolt: MeshInstance3D
var _bolt_mesh: ImmediateMesh
var _bolt_time := 0.0
var _glow: MeshInstance3D
var _roof_timer := 0.0
var _indoors := false
var _skip: Array[RID] = []


func _ready() -> void:
	add_to_group("weather")
	_t = WeatherRules.tuning()
	_rng.randomize()
	_atmos = get_parent().get_node_or_null("Atmosphere")
	state = str(_t.start)
	_left = WeatherRules.duration_s(state, _rng, _t)
	_strike_in = _rng.randf_range(float(_t.lightning.interval_s[0]), float(_t.lightning.interval_s[1]))
	_sound = WeatherSound.new()
	add_child(_sound)
	_build_rain()
	_bolt_mesh = ImmediateMesh.new()
	_bolt = MeshInstance3D.new()
	_bolt.mesh = _bolt_mesh
	_bolt.material_override = _unshaded(Color(0.9, 0.92, 1.0), false)
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.visible = false
	add_child(_bolt)
	var torus := TorusMesh.new()
	torus.inner_radius = 3.6
	torus.outer_radius = 4.5
	torus.ring_segments = 4
	_glow = MeshInstance3D.new()
	_glow.mesh = torus
	_glow.material_override = _unshaded(Color(0.65, 0.75, 1.0, 0.55), true)
	_glow.visible = false
	add_child(_glow)
	multiplayer.peer_connected.connect(_on_peer_connected)


func hearing_mult() -> float:
	return WeatherRules.hearing_mult(levels, _t)


func storm_wind(wind: Vector2, rng: RandomNumberGenerator) -> Vector2:
	return WeatherRules.storm_wind(wind, levels.y, rng, _t)


# --- host ---------------------------------------------------------------------------------------

# Host's pause menu: "auto" or a state to hold.
@rpc("any_peer", "call_local", "reliable")
func request_mode(new_mode: String) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() not in [0, 1, multiplayer.get_unique_id()]:
		return
	if new_mode != "auto" and not (_t.states as Dictionary).has(new_mode):
		return
	mode = new_mode
	var next := state if new_mode == "auto" else new_mode
	_left = WeatherRules.duration_s(next, _rng, _t)
	_set_state.rpc(next, mode)


func _host_tick(delta: float) -> void:
	if mode == "auto":
		_left -= delta
		if _left <= 0.0:
			var next := WeatherRules.pick_next(state, _rng, _t)
			_left = WeatherRules.duration_s(next, _rng, _t)
			_set_state.rpc(next, mode)
	if levels.y < 0.6:
		return
	_strike_in -= delta
	if _strike_in > 0.0:
		return
	var l: Dictionary = _t.lightning
	_strike_in = _rng.randf_range(float(l.interval_s[0]), float(l.interval_s[1]))
	var outside: Array[Node3D] = []
	for p in get_tree().get_nodes_in_group("players"):
		if "peer_id" in p and not p.health.is_dead() and not _under_roof((p as Node3D).global_position):
			outside.append(p)
	if not outside.is_empty() and _rng.randf() < float(l.near_chance):
		var target: Node3D = outside[_rng.randi() % outside.size()]
		var off: Array = l.offset_m
		var at := target.global_position + Vector3.FORWARD.rotated(Vector3.UP, _rng.randf() * TAU) * _rng.randf_range(float(off[0]), float(off[1]))
		_warn.rpc(at, int(target.peer_id))
		get_tree().create_timer(float(l.warn_s)).timeout.connect(_host_strike.bind(at))
		return
	var who: Node3D = get_tree().get_first_node_in_group("local_player")
	var any_players := get_tree().get_nodes_in_group("players")
	if not any_players.is_empty():
		who = any_players[_rng.randi() % any_players.size()]
	if who == null:
		return
	var fd: Array = l.far_dist_m
	var far := who.global_position + Vector3.FORWARD.rotated(Vector3.UP, _rng.randf() * TAU) * _rng.randf_range(float(fd[0]), float(fd[1]))
	_strike.rpc(far)


func _host_strike(at: Vector3) -> void:
	_strike.rpc(at)
	for p in get_tree().get_nodes_in_group("players"):
		if not "peer_id" in p or p.health.is_dead():
			continue
		var pos := (p as Node3D).global_position
		var dmg := WeatherRules.strike_damage(Vector2(pos.x - at.x, pos.z - at.z).length(), _t)
		if dmg > 0.0 and not _under_roof(pos):
			p.health.apply_damage(dmg, 0)


# Something solid (not a tree) within roof_check_m above head height.
func _under_roof(pos: Vector3) -> bool:
	var from := pos + Vector3.UP * 1.8
	var to := from + Vector3.UP * float(_t.lightning.roof_check_m)
	var space := get_world_3d().direct_space_state
	for i in 4:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, ROOF_MASK, _skip))
		if hit.is_empty():
			return false
		if hit.collider is CollisionObject3D and (hit.collider as Node).name == "Colliders":  # trees are no shelter
			_skip.append((hit.collider as CollisionObject3D).get_rid())
			continue
		return true
	return false


func _on_peer_connected(peer: int) -> void:
	if multiplayer.is_server():
		_set_state.rpc_id(peer, state, mode)


# --- every peer -----------------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _set_state(new_state: String, new_mode: String) -> void:
	state = new_state
	mode = new_mode
	if new_state != "clear":
		_sound.prepare()


@rpc("authority", "call_local", "reliable")
func _warn(at: Vector3, peer: int) -> void:
	_glow.global_position = at + Vector3.UP * 0.1
	_glow.visible = true
	get_tree().create_timer(float(_t.lightning.warn_s)).timeout.connect(func() -> void: _glow.visible = false)
	if peer == multiplayer.get_unique_id():
		DropZone.toast(self, "Your hair stands up... LIGHTNING! Get under a roof!", 2.0)


@rpc("authority", "call_local", "reliable")
func _strike(at: Vector3) -> void:
	_sound.prepare()
	var cam := get_viewport().get_camera_3d()
	var dist := cam.global_position.distance_to(at) if cam else 500.0
	_flash = clampf(1.2 - dist / 900.0, 0.25, 1.0)
	_draw_bolt(at)
	_sound.thunder(dist, float(_t.lightning.sound_speed_mps))


func _process(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_host_tick(delta)
	levels = WeatherRules.blend(levels, WeatherRules.levels(state, _t), delta, _t)
	_flash = maxf(0.0, _flash - delta * 2.5)
	if _atmos and _atmos.has_method("set_weather"):
		_atmos.set_weather(levels.x, levels.y, levels.z, _flash)
	_bolt_time -= delta
	if _bolt.visible and _bolt_time <= 0.0:
		_bolt.visible = false
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_roof_timer -= delta
	if _roof_timer <= 0.0:
		_roof_timer = 0.5
		_indoors = levels.x > 0.01 and _under_roof(cam.global_position - Vector3.UP * 1.6)
	_rain.global_position = cam.global_position + Vector3.UP * float(_t.rain.height_m) * 0.5
	_rain.amount_ratio = 0.0 if _indoors else levels.x
	_rain.emitting = levels.x > 0.01 and not _indoors
	_sound.set_rain(levels.x, _indoors)


func _build_rain() -> void:
	var r: Dictionary = _t.rain
	_rain = GPUParticles3D.new()
	_rain.amount = int(r.max_particles)
	_rain.lifetime = float(r.height_m) / float(r.fall_mps) * 1.6
	_rain.visibility_aabb = AABB(Vector3(-r.area_m, -r.height_m, -r.area_m), Vector3(r.area_m * 2, r.height_m * 2, r.area_m * 2))
	_rain.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(float(r.area_m), 0.5, float(r.area_m))
	pm.direction = Vector3(0.05, -1, 0)
	pm.spread = 3.0
	pm.initial_velocity_min = float(r.fall_mps)
	pm.initial_velocity_max = float(r.fall_mps) * 1.15
	pm.gravity = Vector3.ZERO
	pm.particle_flag_align_y = true
	_rain.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.015, 0.55)
	var mat := _unshaded(Color(0.75, 0.8, 0.9, 0.35), true)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	quad.material = mat
	_rain.draw_pass_1 = quad
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.top_level = true
	add_child(_rain)


func _draw_bolt(at: Vector3) -> void:
	_bolt_mesh.clear_surfaces()
	_bolt_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var p := at + Vector3(_rng.randf_range(-20, 20), 260.0, _rng.randf_range(-20, 20))
	var steps := 14
	for i in steps:
		var f := float(i + 1) / steps
		var q := p.lerp(at, 1.0 / (steps - i)) + Vector3(_rng.randf_range(-6, 6), 0, _rng.randf_range(-6, 6)) * (1.0 - f)
		if i == steps - 1:
			q = at
		for w in 3:  # three strands for a thicker look
			var o := Vector3(w * 0.25, 0, -w * 0.2)
			_bolt_mesh.surface_add_vertex(p + o)
			_bolt_mesh.surface_add_vertex(q + o)
		if _rng.randf() < 0.3 and i < steps - 3:  # a fork
			_bolt_mesh.surface_add_vertex(q)
			_bolt_mesh.surface_add_vertex(q + Vector3(_rng.randf_range(-25, 25), -_rng.randf_range(10, 30), _rng.randf_range(-25, 25)))
		p = q
	_bolt_mesh.surface_end()
	_bolt.visible = true
	_bolt_time = 0.18


func _unshaded(col: Color, alpha: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
