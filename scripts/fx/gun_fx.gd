# GunFx — pooled muzzle flashes and ejected casings for every peer (D-122). "GunFx" on Main, group "gun_fx".
# Flashes: a few billboard quads + small shadowless lights made once; a shot shows one for flash_seconds.
# Casings: a fixed pool of small meshes flown by GunFeelRules.casing_step (no physics bodies), bouncing on the
# shooter's floor height, gone after casing_life_s; only shots within casing_max_m of the camera eject any, and the
# oldest casing is reused when the pool is full. Nothing is allocated per shot or per frame.
# CombatWorld calls shot() for every drawn shot; WeaponHolder calls eject_now() for a revolver's reload.
# Presentation only: never decides anything for the game.
# Depends on: GunFeelRules, data/weapons/gun_feel.json, WeaponDB (feel / eject per gun), Sfx.
class_name GunFx
extends Node3D

var _t: Dictionary
var _flash: Array[MeshInstance3D] = []
var _light: Array[OmniLight3D] = []
var _flash_left := PackedFloat32Array()
var _next_flash := 0
var _case: Array[MeshInstance3D] = []
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _spin := PackedVector3Array()
var _floor := PackedFloat32Array()
var _left := PackedFloat32Array()    # seconds until it disappears
var _delay := PackedFloat32Array()   # seconds until it flies out (pump / bolt guns)
var _moving := PackedByteArray()
var _shell := PackedByteArray()
var _landed := PackedByteArray()     # first touch of the ground played its sound
var _next_case := 0
var _casing_mesh: Mesh
var _shell_mesh: Mesh
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("gun_fx")
	_t = GunFeelRules.tuning()
	var c: Array = _t.flash_color
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 0.9, 1))
	grad.set_color(1, Color(c[0], c[1], c[2], 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.albedo_texture = tex
	fm.albedo_color = Color(c[0], c[1], c[2])
	fm.no_depth_test = false
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * float(_t.flash_size_m)
	quad.material = fm
	for i in int(_t.flash_pool):
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_flash.append(mi)
		var l := OmniLight3D.new()
		l.light_color = Color(c[0], c[1], c[2])
		l.light_energy = float(_t.flash_light_energy)
		l.omni_range = float(_t.flash_light_range_m)
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_light.append(l)
	_flash_left.resize(_flash.size())
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.86, 0.66, 0.3)
	brass.metallic = 0.9
	brass.roughness = 0.35
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0045
	cm.bottom_radius = 0.0045
	cm.height = 0.02
	cm.radial_segments = 6
	cm.rings = 1
	cm.material = brass
	_casing_mesh = cm
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.62, 0.08, 0.06)
	red.roughness = 0.6
	var sm := CylinderMesh.new()
	sm.top_radius = 0.0095
	sm.bottom_radius = 0.0095
	sm.height = 0.065
	sm.radial_segments = 8
	sm.rings = 1
	sm.material = red
	_shell_mesh = sm
	var n := int(_t.casing_pool)
	for i in n:
		var mi := MeshInstance3D.new()
		mi.mesh = _casing_mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_case.append(mi)
	_pos.resize(n)
	_vel.resize(n)
	_spin.resize(n)
	_floor.resize(n)
	_left.resize(n)
	_delay.resize(n)
	_moving.resize(n)
	_shell.resize(n)
	_landed.resize(n)


# A drawn shot: a flash at `muzzle` and, by the gun's "eject", a casing now or after its pump / bolt cycle.
# right = the shooter's right (casings fly that way), floor_y = the ground under the shooter.
func shot(weapon_id: String, muzzle: Vector3, right: Vector3, floor_y: float) -> void:
	if not WeaponDB.has_weapon(weapon_id):  # raiders' generic "gun": flash only; spit and the like: nothing
		if weapon_id == "gun":
			_show_flash(muzzle, 1.0)
		return
	var w := WeaponDB.get_weapon(weapon_id)
	var feel: Dictionary = w.get("feel", {})
	_show_flash(muzzle, float(feel.get("flash", 1.0)))
	var eject := str(w.get("eject", "fire"))
	if eject == "reload":
		return
	var delay := 0.0 if eject == "fire" else float(w.get("cycle", {}).get("at", 0.3))
	eject_now(muzzle, right, floor_y, weapon_id == "shotgun_pump", delay)


# One casing (or shotgun shell) out of the right side, after `delay` seconds.
func eject_now(at: Vector3, right: Vector3, floor_y: float, shell: bool, delay := 0.0) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_to(at) > float(_t.casing_max_m):
		return
	var i := _next_case
	_next_case = (_next_case + 1) % _case.size()
	var s: Array = _t.casing_speed
	var r := right.normalized()
	_pos[i] = at - r * 0.02
	_vel[i] = r * float(s[0]) * _rng.randf_range(0.8, 1.2) + Vector3.UP * float(s[1]) * _rng.randf_range(0.8, 1.2) \
		+ r.cross(Vector3.UP) * float(s[2]) * _rng.randf_range(-1.0, 1.0)
	_spin[i] = Vector3(_rng.randf_range(-20, 20), _rng.randf_range(-20, 20), _rng.randf_range(-20, 20))
	_floor[i] = floor_y + 0.01
	_left[i] = float(_t.casing_life_s) + delay
	_delay[i] = delay
	_moving[i] = 1
	_shell[i] = 1 if shell else 0
	_landed[i] = 0
	var mi := _case[i]
	mi.mesh = _shell_mesh if shell else _casing_mesh
	mi.visible = delay <= 0.0
	mi.global_position = _pos[i]


func _show_flash(at: Vector3, scale_mult: float) -> void:
	var i := _next_flash
	_next_flash = (_next_flash + 1) % _flash.size()
	_flash[i].global_position = at
	_flash[i].scale = Vector3.ONE * scale_mult * _rng.randf_range(0.8, 1.2)
	_flash[i].rotation.z = _rng.randf() * TAU
	_flash[i].visible = true
	_light[i].global_position = at
	_light[i].visible = true
	_flash_left[i] = float(_t.flash_seconds)


func active_flashes() -> int:
	var n := 0
	for f in _flash:
		n += int(f.visible)
	return n


func active_casings() -> int:
	var n := 0
	for c in _case:
		n += int(c.visible)
	return n


func _process(delta: float) -> void:
	for i in _flash.size():
		if _flash_left[i] > 0.0:
			_flash_left[i] -= delta
			if _flash_left[i] <= 0.0:
				_flash[i].visible = false
				_light[i].visible = false
	var g := float(_t.casing_gravity)
	var b := float(_t.casing_bounce)
	for i in _case.size():
		if _left[i] <= 0.0:
			continue
		_left[i] -= delta
		var mi := _case[i]
		if _left[i] <= 0.0:
			mi.visible = false
			continue
		if _delay[i] > 0.0:
			_delay[i] -= delta
			if _delay[i] > 0.0:
				continue
			mi.visible = true
		if _moving[i] == 0:
			continue
		var was_up := _pos[i].y > _floor[i] + 0.001
		if not GunFeelRules.casing_step(_pos, _vel, i, _floor[i], delta, g, b):
			_moving[i] = 0
		mi.global_position = _pos[i]
		if _moving[i] == 1:
			mi.rotation += _spin[i] * delta
		else:
			mi.rotation = Vector3(PI * 0.5, mi.rotation.y, 0.0)  # lying on its side
		if was_up and _pos[i].y <= _floor[i] + 0.001 and _landed[i] == 0:
			_landed[i] = 1
			var cam := get_viewport().get_camera_3d()
			if cam and cam.global_position.distance_to(_pos[i]) < float(_t.casing_sound_m):
				Sfx.play_at("shell_drop" if _shell[i] == 1 else "casing_drop", _pos[i])
