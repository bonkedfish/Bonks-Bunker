# CombatWorld — host-side attack resolution with lag compensation, plus combat feedback RPCs.
# Hittables (group "hittable") provide: health: Health, team: StringName, hit_radius: float,
# hit_capsule_at(tick: float) -> Vector4(feet xyz, height). The host rewinds each target to the
# shooter's view tick (clamped by NetClock), tests the shot with CombatRules, and checks walls with a
# world-only raycast. Clients never decide hits.
# Guns (D-087): spread_deg scatters each shot inside a cone and pellets fires several at once (shotguns); damage per
# target is summed so one blast gives one hit marker. Thrown (D-088, the Golden Ace): the host flies the disc out
# along the aim until its range or a wall, then back to the thrower, hitting each target once per throw; every peer
# animates the same path (out deterministic, back toward the thrower's body).
# Depends on: CombatRules, NetClock (group "net_clock"), TracerPool (group "tracers"), HUD (group "hud"),
#             ZombieDirector (group "zombie_director", for attack noise), Sfx (shot / melee-hit sounds, D-077).
extends Node3D

const WORLD_MASK := 1   # static level geometry
const VISUAL_MASK := 3  # world + bodies, for local tracer endpoints only

var _tuning: Dictionary
var _clock: NetClock
var _tracers: Node
var _hud: Node
var _director: Node
var _rng := RandomNumberGenerator.new()
var _throws := {}  # host: thrower peer id -> {shooter, w, pos, dir, out, back, t, hit}
var _vis := {}     # every peer: thrower peer id -> {mesh, pos, dir, out, back, speed, t}
var _disc_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("combat_world")
	_tuning = CombatRules.load_tuning()
	_clock = get_tree().get_first_node_in_group("net_clock")
	_tracers = get_tree().get_first_node_in_group("tracers")
	_hud = get_tree().get_first_node_in_group("hud")
	_director = get_tree().get_first_node_in_group("zombie_director")
	_rng.randomize()


# --- host ----------------------------------------------------------------------

# hits_teammates = false: the shot passes through the shooter's own team (Bonk). Returns true on a kill/down.
func host_fire(shooter: Node, weapon: Dictionary, origin: Vector3, dir: Vector3, view_tick: float,
		hits_teammates: bool = true) -> bool:
	var tick := _clock.rewind_tick(view_tick, _tuning.max_rewind_seconds)
	_make_noise(origin, weapon)
	var pellets := maxi(int(weapon.get("pellets", 1.0)), 1)
	var spread := deg_to_rad(float(weapon.get("spread_deg", 0.0)))
	var targets := get_tree().get_nodes_in_group("hittable")
	var dmg_by := {}  # target -> summed damage
	var ends := PackedVector3Array()
	for p in pellets:
		var d_dir := spread_dir(dir, spread, _rng) if spread > 0.0 else dir
		var best_dist := _world_distance(origin, d_dir, float(weapon.range))
		var best: Node = null
		for target in targets:
			if target == shooter or target.health.is_dead() or (not hits_teammates and target.team == shooter.team):
				continue
			var cap: Vector4 = target.hit_capsule_at(tick)
			var d := CombatRules.ray_vs_capsule(origin, d_dir, best_dist,
				Vector3(cap.x, cap.y, cap.z), target.hit_radius, cap.w)
			if d >= 0.0 and d < best_dist:
				best_dist = d
				best = target
		if best:
			dmg_by[best] = float(dmg_by.get(best, 0.0)) + float(weapon.damage)
		ends.append(origin + d_dir * best_dist)
	var killed := false
	for t: Node in dmg_by:
		killed = _damage(t, shooter, dmg_by[t]) or killed
	if pellets == 1:
		_fx_shot.rpc(origin, ends[0], shooter.peer_id, "%s_fire" % weapon.get("id", "gun"))
	else:
		_fx_pellets.rpc(origin, ends, shooter.peer_id, "%s_fire" % weapon.get("id", "gun"))
	return killed


# A direction inside a cone of half-angle `cone` (radians) around `dir`, uniform over the cone's base.
static func spread_dir(dir: Vector3, cone: float, rng: RandomNumberGenerator) -> Vector3:
	var right := dir.cross(Vector3.UP)
	if right.length_squared() < 1e-6:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(dir).normalized()
	var a := rng.randf() * TAU
	var r := tan(cone * sqrt(rng.randf()))
	return (dir + (right * cos(a) + up * sin(a)) * r).normalized()


func host_melee(shooter: Node, weapon: Dictionary, origin: Vector3, dir: Vector3, view_tick: float,
		hits_teammates: bool = true) -> bool:
	var tick := _clock.rewind_tick(view_tick, _tuning.max_rewind_seconds)
	_make_noise(origin, weapon)
	var killed := false
	var hit_any := false
	var hit_at := Vector3.ZERO
	for target in get_tree().get_nodes_in_group("hittable"):
		if target == shooter or target.health.is_dead() or (not hits_teammates and target.team == shooter.team):
			continue
		var cap: Vector4 = target.hit_capsule_at(tick)
		var base := Vector3(cap.x, cap.y, cap.z)
		if not CombatRules.melee_hits_capsule(origin, dir, float(weapon.range), float(weapon.arc_degrees),
				base, target.hit_radius, cap.w):
			continue
		if _world_blocked(origin, base + Vector3.UP * cap.w * 0.5):
			continue
		killed = _damage(target, shooter, float(weapon.damage)) or killed
		if not hit_any:
			hit_any = true
			hit_at = base + Vector3.UP * cap.w * 0.6
	if hit_any:
		_fx_melee_hit.rpc(hit_at, "%s_hit" % weapon.get("id", "melee"))
	return killed


func _damage(target: Node, shooter: Node, base_damage: float) -> bool:
	var amount := CombatRules.scaled_damage(base_damage, target.team == shooter.team,
		_tuning.friendly_fire_multiplier)
	var killed: bool = target.health.apply_damage(amount, shooter.peer_id)
	if shooter.peer_id > 0:  # AI shooters (Bonk, peer 0) get no hit marker
		_hit_confirm.rpc_id(shooter.peer_id, killed)
	return killed


# Attacks are noisy (D-017): zombies within the weapon's noise_radius come to investigate.
func _make_noise(origin: Vector3, weapon: Dictionary) -> void:
	if _director:
		_director.host_noise(origin, float(weapon.get("noise_radius", 0.0)))
	var lairs := get_tree().get_first_node_in_group("lair_director")
	if lairs:
		lairs.host_noise(origin, float(weapon.get("noise_radius", 0.0)))


func _world_distance(origin: Vector3, dir: Vector3, max_dist: float) -> float:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_dist, WORLD_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return max_dist if hit.is_empty() else origin.distance_to(hit.position)


func _world_blocked(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# --- feedback --------------------------------------------------------------------

# Owning client draws its own tracer(s) instantly from the gun muzzle (not authoritative, visual only).
func local_tracer(player: Node, weapon: Dictionary) -> void:
	var origin: Vector3 = player.eye_position()
	var aim: Vector3 = -player.camera.global_basis.z
	var spread := deg_to_rad(float(weapon.get("spread_deg", 0.0)))
	for p in maxi(int(weapon.get("pellets", 1.0)), 1):
		var dir := spread_dir(aim, spread, _rng) if spread > 0.0 else aim
		var end := origin + dir * float(weapon.range)
		var query := PhysicsRayQueryParameters3D.create(origin, end, VISUAL_MASK, [player.get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			end = hit.position
		_tracers.show_tracer(player.muzzle_position(), end)


@rpc("authority", "call_local", "unreliable")
func _fx_shot(from: Vector3, to: Vector3, shooter_peer: int, sound: String) -> void:
	if shooter_peer == multiplayer.get_unique_id():
		if not multiplayer.is_server():
			return  # already drawn and heard locally (local_tracer, WeaponHolder.client_step)
		var me := get_tree().get_first_node_in_group("local_player")
		if me:
			from = me.muzzle_position()
		Sfx.play_local(sound)
	else:
		Sfx.play_at(sound, from)
	_tracers.show_tracer(from, to)


@rpc("authority", "call_local", "unreliable")
func _fx_pellets(from: Vector3, ends: PackedVector3Array, shooter_peer: int, sound: String) -> void:
	if shooter_peer == multiplayer.get_unique_id():
		if not multiplayer.is_server():
			return
		var me := get_tree().get_first_node_in_group("local_player")
		if me:
			from = me.muzzle_position()
		Sfx.play_local(sound)
	else:
		Sfx.play_at(sound, from)
	for e in ends:
		_tracers.show_tracer(from, e)


@rpc("authority", "call_local", "unreliable")
func _fx_melee_hit(at: Vector3, sound: String) -> void:
	Sfx.play_at(sound, at)


@rpc("authority", "call_local", "reliable")
func _hit_confirm(killed: bool) -> void:
	if _hud:
		_hud.show_hit_marker(killed)


# --- thrown (D-088: the Golden Ace) ----------------------------------------------------------

func host_has_throw(shooter: Node) -> bool:
	return _throws.has(shooter.peer_id)


func host_throw(shooter: Node, weapon: Dictionary, origin: Vector3, dir: Vector3) -> void:
	_make_noise(origin, weapon)
	var start := origin + dir * 0.6
	_throws[shooter.peer_id] = {"shooter": shooter, "w": weapon, "pos": start, "dir": dir, "out": float(weapon.range),
		"back": false, "t": 0.0, "hit": {}}
	_fx_throw.rpc(shooter.peer_id, start, dir, float(weapon.speed), float(weapon.range))


func _physics_process(delta: float) -> void:
	if _throws.is_empty() or not multiplayer.is_server():
		return
	for peer: int in _throws.keys():
		var th: Dictionary = _throws[peer]
		var shooter: Node = th.shooter
		if not is_instance_valid(shooter) or shooter.health.is_dead():
			_end_throw(peer)
			continue
		var prev: Vector3 = th.pos
		if not _step_disc(th, delta, shooter.eye_position() + Vector3.DOWN * 0.3):
			_end_throw(peer)
			continue
		_throw_hits(th, prev, th.pos)


# Moves a flying disc one step (host and visuals share it). False once it's back in the thrower's hand.
func _step_disc(th: Dictionary, delta: float, hand: Vector3) -> bool:
	th.t = float(th.t) + delta
	var prev: Vector3 = th.pos
	var step := float(th.get("speed", th.get("w", {}).get("speed", 20.0))) * delta
	if not th.back:
		var next := prev + (th.dir as Vector3) * step
		var q := PhysicsRayQueryParameters3D.create(prev, next, WORLD_MASK)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			next = hit.position - (th.dir as Vector3) * 0.05
			th.back = true
		th.out = float(th.out) - step
		if float(th.out) <= 0.0:
			th.back = true
		th.pos = next
		return true
	var to := hand - prev
	if to.length() <= step + 0.5 or float(th.t) > 6.0:
		return false
	th.pos = prev + to.normalized() * step
	return true


func _throw_hits(th: Dictionary, from: Vector3, to: Vector3) -> void:
	var seg := to - from
	var length := seg.length()
	if length < 0.001:
		return
	var dir := seg / length
	var shooter: Node = th.shooter
	for target in get_tree().get_nodes_in_group("hittable"):
		if target == shooter or target.health.is_dead() or (th.hit as Dictionary).has(target):
			continue
		var cap: Vector4 = target.hit_capsule_at(float(_clock.tick))
		if CombatRules.ray_vs_capsule(from, dir, length, Vector3(cap.x, cap.y, cap.z), target.hit_radius + 0.12, cap.w) >= 0.0:
			th.hit[target] = true
			_damage(target, shooter, float(th.w.damage))
			_fx_melee_hit.rpc(to, "%s_hit" % th.w.get("id", "thrown"))


func _end_throw(peer: int) -> void:
	_throws.erase(peer)
	_fx_throw_end.rpc(peer)


@rpc("authority", "call_local", "reliable")
func _fx_throw(peer: int, start: Vector3, dir: Vector3, speed: float, reach: float) -> void:
	var v: Dictionary = _vis.get(peer, {})
	if v.is_empty():
		var mi := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.11
		mesh.bottom_radius = 0.11
		mesh.height = 0.025
		mesh.radial_segments = 16
		if _disc_mat == null:
			_disc_mat = StandardMaterial3D.new()
			_disc_mat.albedo_color = Color(1.0, 0.8, 0.2)
			_disc_mat.metallic = 0.85
			_disc_mat.roughness = 0.25
			_disc_mat.emission_enabled = true
			_disc_mat.emission = Color(0.5, 0.35, 0.05)
		mesh.material = _disc_mat
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		v = {"mesh": mi}
		_vis[peer] = v
	v.pos = start
	v.dir = dir
	v.out = reach
	v.back = false
	v.speed = speed
	v.t = 0.0
	(v.mesh as MeshInstance3D).global_position = start
	(v.mesh as MeshInstance3D).visible = true
	set_process(true)


@rpc("authority", "call_local", "reliable")
func _fx_throw_end(peer: int) -> void:
	if _vis.has(peer):
		(_vis[peer].mesh as MeshInstance3D).visible = false


func _process(delta: float) -> void:
	var any := false
	for peer: int in _vis:
		var v: Dictionary = _vis[peer]
		var mi: MeshInstance3D = v.mesh
		if not mi.visible:
			continue
		any = true
		var thrower := _thrower(peer)
		var hand: Vector3 = thrower.eye_position() + Vector3.DOWN * 0.3 if thrower else mi.global_position
		if not _step_disc(v, delta, hand):
			mi.visible = false
			continue
		mi.global_position = v.pos
		mi.rotation.y = wrapf(mi.rotation.y + delta * 25.0, -PI, PI)
	if not any:
		set_process(false)


func _thrower(peer: int) -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if "peer_id" in p and p.peer_id == peer:
			return p
	return null
