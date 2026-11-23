# WeaponAnimTest — D-123 hand-made weapon animations. A kit survivor (survivor_lis) and a UBC body (ubc_ranger_f)
# in third person plus first-person arms (survivor_lis, like the viewmodel) hold every gun and melee weapon:
# both hands stay on the grips at rest, through each gun's kick and (where the left hand holds it) its reload and
# each melee weapon's swing; the reload moves the gun, the swing sweeps the weapon; switching holsters the old
# weapon then draws the new one; every weapon in weapon_anims.json exists and names real clips.
# Screenshots tests/_look/wanim_*.png. Results: tests/_look/weapon_anim_result.txt (ends with the failure count).
# Depends on: CharacterAnimator, GunPose, WeaponDB.
extends Node3D

const OUT_DIR := "res://tests/_look"
const IDS := ["pistol_9mm", "revolver_44", "smg_9mm", "shotgun_pump", "rifle_hunting", "rifle_ar", "rifle_sniper",
	"bat_baseball", "knife_combat", "axe_fire"]

var _log := PackedStringArray()
var _fails := 0
var _rigs: Array[CharacterAnimator] = []
var _names := ["kit", "ubc", "fp"]
var _cam3: Camera3D
var _camfp: Camera3D
var _ok_m := 0.035


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_ok_m = float(GunPose.data().get("grip_ok_m", 0.035))
	_data_checks()
	_scene()
	for i in 3:
		await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	for id: String in IDS:
		await _weapon(id)
	await _switch()
	_log.append("perf (3 animated bodies, this scene): %.1f ms frame, %d draw calls, %d MB video memory" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)])
	_log.append("ran %.1f s" % ((Time.get_ticks_usec() - t0) / 1e6))
	_log.append("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/weapon_anim_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	get_tree().quit()


func _data_checks() -> void:
	var bad := PackedStringArray()
	var clips: Dictionary = GunPose.data().get("clips", {})
	for id: String in IDS:
		var d := GunPose.weapon(id)
		var w := WeaponDB.get_weapon(id)
		if d.is_empty() or w.is_empty():
			bad.append(id + " missing")
			continue
		var kinds := ["draw", "holster", "kick", "reload"] if str(w.kind) == "gun" else ["draw", "holster", "swing"]
		for k: String in kinds:
			if not clips.has(str(d.get(k, ""))):
				bad.append("%s %s" % [id, k])
	_check(bad.is_empty(), "every weapon has draw / holster / reload + kick or swing clips %s" % ", ".join(bad))


func _scene() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.34, 0.36)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 8)
	floor_mesh.mesh = pm
	add_child(floor_mesh)
	for i in 2:
		var a := CharacterAnimator.new()
		add_child(a)
		a.position = Vector3(-0.55 + 1.1 * i, 0, 0)
		a.rotation_degrees.y = -150.0
		a.set_model(["survivor_lis", "ubc_ranger_f"][i])
		_rigs.append(a)
		a.gun_debug_on = true
	_cam3 = Camera3D.new()
	add_child(_cam3)
	_cam3.position = Vector3(0.1, 1.25, 2.6)
	_cam3.look_at(Vector3(0.0, 1.0, 0.0))
	_camfp = Camera3D.new()
	_camfp.near = 0.05
	add_child(_camfp)
	_camfp.position = Vector3(0, 1.68, 3.5)
	var fp := CharacterAnimator.new()
	_camfp.add_child(fp)
	fp.set_model("survivor_lis", true)
	fp.gun_debug_on = true
	_rigs.append(fp)
	_cam3.current = true


func _process(delta: float) -> void:
	for i in _rigs.size():
		var w := WeaponDB.get_weapon(_rigs[i]._gun_id) if _rigs[i]._gun_id != "" else {}
		_rigs[i].update(delta, false, false, 100.0, str(w.get("kind", "")) == "gun", false)


# Holds weapon `id` on all three; checks the grips at rest, through the kick / reload / swing.
func _weapon(id: String) -> void:
	var w := WeaponDB.get_weapon(id)
	var d := GunPose.weapon(id)
	var mesh := str(w.get("mesh", ""))
	for a in _rigs:
		a.set_weapon(mesh, id)
	await _wait(0.75)  # holster the last one + draw this one
	var rest := await _errors(0.25)
	for i in _rigs.size():
		_log.append("  %s %s: %s" % [_names[i], id, _rigs[i].gun_debug])
	_check(_max(rest) <= _ok_m and _all_holding(), "%s at rest: hands on the grips (R / L max %s m)" % [id, _fmt(rest)])
	var tips: Array[Vector3] = []
	for a in _rigs:
		tips.append(a.global_transform.affine_inverse() * a.weapon_tip(-a.global_basis.z))
	var gun := str(w.kind) == "gun"
	if gun:
		for a in _rigs:
			a.gun_kick()
		var kick := await _errors(float(d.get("kick_s", 0.2)))
		_check(_max(kick) <= _ok_m, "%s kick: hands stay on (%s m)" % [id, _fmt(kick)])
	var kind := "reload" if gun else "swing"
	var secs := float(w.get("reload_time", 2.0)) if gun else float(d.get("swing_s", 0.5))
	for a in _rigs:
		a.gun_action(kind, secs if gun else -1.0)
	var moved := 0.0
	var errs := PackedFloat32Array([0, 0, 0, 0, 0, 0])
	var t := 0.0
	var shot_at := secs * (0.42 if gun else 0.3)
	var shot := false
	while t < secs:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		for i in _rigs.size():
			errs[i * 2] = maxf(errs[i * 2], _rigs[i].grip_error_r)
			errs[i * 2 + 1] = maxf(errs[i * 2 + 1], _rigs[i].grip_error_l)
			var tip := _rigs[i].global_transform.affine_inverse() * _rigs[i].weapon_tip(-_rigs[i].global_basis.z)
			moved = maxf(moved, tip.distance_to(tips[i]))
		if not shot and t >= shot_at and id in ["rifle_ar", "shotgun_pump", "revolver_44", "bat_baseball", "axe_fire", "knife_combat", "rifle_hunting"]:
			shot = true
			await _shots("wanim_%s_%s" % [id, kind])
	_check(_max(errs) <= _ok_m, "%s %s: right hand on the grip, left on the gun whenever it holds it (%s m)" % [id, kind, _fmt(errs)])
	_check(moved > (0.04 if gun else 0.3), "%s %s moves the weapon (tip up to %.2f m from rest)" % [id, kind, moved])
	await _wait(0.2)
	if id in ["pistol_9mm", "smg_9mm", "rifle_ar", "shotgun_pump", "rifle_sniper", "bat_baseball"]:
		await _shots("wanim_%s_rest" % id)


# Switching AR -> pistol: the AR holsters first, then the pistol is drawn.
func _switch() -> void:
	for a in _rigs:
		a.set_weapon("Rifle", "rifle_ar")
	await _wait(0.8)
	for a in _rigs:
		a.set_weapon("Pistol", "pistol_9mm")
	await get_tree().process_frame
	var first: String = _rigs[0].gun_action_playing()
	var held_mid: String = _rigs[0]._gun_id
	await _wait(0.35)
	var then: String = _rigs[0].gun_action_playing()
	_check(first == "holster" and held_mid == "rifle_ar" and then == "draw" and _rigs[0]._gun_id == "pistol_9mm",
		"switching holsters the AR, then draws the pistol (%s -> %s)" % [first, then])
	await _shots("wanim_switch_draw")


func _errors(seconds: float) -> PackedFloat32Array:
	var e := PackedFloat32Array([0, 0, 0, 0, 0, 0])
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
		for i in _rigs.size():
			e[i * 2] = maxf(e[i * 2], _rigs[i].grip_error_r)
			e[i * 2 + 1] = maxf(e[i * 2 + 1], _rigs[i].grip_error_l)
	return e


func _all_holding() -> bool:
	for a in _rigs:
		if a._held == null or not a._held.visible:
			return false
	return true


func _shots(name: String) -> void:
	_cam3.current = true
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT_DIR + "/%s.png" % name)
	_camfp.current = true
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT_DIR + "/%s_fp.png" % name)
	_cam3.current = true
	_log.append("shot %s(_fp).png" % name)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


static func _max(e: PackedFloat32Array) -> float:
	var m := 0.0
	for v in e:
		m = maxf(m, v)
	return m


func _fmt(e: PackedFloat32Array) -> String:
	var parts := PackedStringArray()
	for i in _names.size():
		parts.append("%s %.3f/%.3f" % [_names[i], e[i * 2], e[i * 2 + 1]])
	return ", ".join(parts)


func _check(ok: bool, what: String) -> void:
	_log.append(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1
