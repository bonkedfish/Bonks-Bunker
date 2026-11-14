# BikeTest — motorcycles (D-083). Pure: the five bikes load; each gear tops out near its data speed on the limiter;
# letting the clutch out with no gas stalls, a launch on the gas doesn't; no shifting without the clutch; leaning back
# in 1st lifts a wheelie on the dirt bike, not much on the cruiser; cell bikes are the same for the same world and
# about spawn_chance of cells have one; refuel and crash damage math. In game (singleplayer, god mode, on Cope
# Stadium's field between the tents): a test bike parks, E rides it (no gun in hand, no shots), clutch + E for 1st,
# launch, 1st -> 2nd, a wheelie, braking, F gets off (the bike parks there and is saved as moved), dumping the clutch
# stalls and B restarts it with the clutch in, R refuels from a gas can, a looped wheelie crashes you off, and all five
# bikes parked in a row. Screenshots tests/_look/bike_*.png, perf while riding.
# Results: tests/_look/bike_result.txt (ends with the failure count).
# Depends on: scenes/main.tscn, BikeRules, BikeDirector (group "bike_director"), BikeRider, SaveStore, the cope_stadium landmark.
extends Node

const OUT_DIR := "res://tests/_look"

var _log := PackedStringArray()
var _fails := 0
var _me: Node3D
var _xf: Transform3D
var _cam: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_pure()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz bikes")
	main.menu.play_offline.emit()
	await get_tree().create_timer(4.0).timeout
	_me = get_tree().get_first_node_in_group("local_player")
	var prompt := get_tree().get_first_node_in_group("name_prompt")
	if prompt and prompt.visible:
		prompt.submit("Bonk")
	_me.health.damage_mult = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var lm := get_tree().root.find_child("cope_stadium", true, false) as Node3D
	_check(lm != null, "cope_stadium placed")
	if lm == null:
		await _finish(main)
		return
	_xf = lm.global_transform
	_me.global_position = _xf * Vector3(3, 1.0, -56)
	await get_tree().create_timer(4.0).timeout
	await _ride_tests(main)
	await _finish(main)


# --- pure ----------------------------------------------------------------------------------------

func _pure() -> void:
	var d := BikeRules.data()
	_check(d.get("bikes", {}).size() == 5, "five bikes load: %s" % [d.get("bikes", {}).keys()])
	var t := BikeRules.tuning()
	for id: String in d.bikes:
		var b: Dictionary = d.bikes[id]
		var tops := PackedStringArray()
		var ok := true
		for g in range(1, BikeRules.gears(b) + 1):
			var s := BikeRules.new_state(5.0)
			s.gear = g
			s.speed = BikeRules.top_mps(b, g) * 0.75
			s.free_rpm = float(b.redline_rpm) * 0.75
			for i in 600:
				BikeRules.step(s, b, t, 1.0, 0.0, 0.0, 0.0, false, true, 1.0 / 60.0)
			tops.append("%d" % roundi(float(s.speed) * 3.6))
			if g < BikeRules.gears(b) and absf(float(s.speed) - BikeRules.top_mps(b, g)) > BikeRules.top_mps(b, g) * 0.06:
				ok = false
		_check(ok, "%s gear tops (km/h) %s vs data %s" % [id, ", ".join(tops), b.gear_top_kmh])
	var dirt := BikeRules.bike("dirt_250")
	var s := BikeRules.new_state(5.0)
	s.free_rpm = 1500.0
	BikeRules.step(s, dirt, t, 0.0, 0.0, 0.0, 0.0, true, true, 1.0 / 60.0)
	_check(not BikeRules.shift(BikeRules.new_state(5.0), dirt, 1), "no shifting with the clutch out")
	_check(BikeRules.shift(s, dirt, 1) and int(s.gear) == 1, "clutch in: N -> 1st")
	for i in 60:
		BikeRules.step(s, dirt, t, 0.0, 0.0, 0.0, 0.0, false, true, 1.0 / 60.0)
	_check(not bool(s.engine), "letting the clutch out with no gas stalls")
	s = BikeRules.new_state(5.0)
	s.free_rpm = 1500.0
	s.clutch = 0.0
	s.gear = 1
	var max_p := 0.0
	for i in 120:
		BikeRules.step(s, dirt, t, 1.0, 0.0, 0.0, 1.0, false, true, 1.0 / 60.0)
		max_p = maxf(max_p, float(s.pitch))
	_check(bool(s.engine) and float(s.speed) > 5.0, "a launch on the gas doesn't stall (%.1f m/s after 2 s)" % float(s.speed))
	_check(max_p > deg_to_rad(20.0), "dirt bike: 1st + lean back wheelies (%.0f deg)" % rad_to_deg(max_p))
	var cr := BikeRules.bike("cruiser_1200")
	s = BikeRules.new_state(5.0)
	s.free_rpm = 900.0
	s.clutch = 0.0
	s.gear = 1
	max_p = 0.0
	for i in 120:
		BikeRules.step(s, cr, t, 1.0, 0.0, 0.0, 1.0, false, true, 1.0 / 60.0)
		max_p = maxf(max_p, float(s.pitch))
	_check(max_p < deg_to_rad(40.0), "cruiser: hard to wheelie (%.0f deg)" % rad_to_deg(max_p))
	var a := BikeRules.cell_bike(1234, Vector2i(3, -2), 12)
	_check(a == BikeRules.cell_bike(1234, Vector2i(3, -2), 12), "cell bikes are the same for the same world")
	var found := 0
	for x in 20:
		for y in 20:
			if not BikeRules.cell_bike(99, Vector2i(x, y), 10).is_empty():
				found += 1
	_check(absf(found / 400.0 - float(t.spawn_chance)) < 0.08, "cells with a bike: %d / 400 (chance %.2f)" % [found, float(t.spawn_chance)])
	var r := BikeRules.refuel(1.0, 3, dirt, t)
	_check(is_equal_approx(float(r[0]), 7.0) and int(r[1]) == 2, "refuel 1 L + 3 cans into a 7 L tank: %s" % [r])
	_check(BikeRules.crash_damage(20.0, t) > 20.0 and BikeRules.crash_damage(2.0, t) == 0.0,
		"crash damage at 20 m/s %.0f, at 2 m/s %.0f" % [BikeRules.crash_damage(20.0, t), BikeRules.crash_damage(2.0, t)])


# --- in game -------------------------------------------------------------------------------------

func _ride_tests(_main: Node) -> void:
	var dir := get_tree().get_first_node_in_group("bike_director")
	var heading := (_xf.basis.get_euler().y) + PI  # bike forward = landmark +z (down the field)
	var start := _xf * Vector3(0, 0.15, -54)
	var id: String = dir.host_spawn_test("dirt_250", 1, 6.0, start, heading)
	await get_tree().process_frame
	var pb := dir.get_node_or_null("B_" + id)
	_check(pb != null and str(pb.get_meta("display_name")).begins_with("Ride the Sandhills"), "test bike parked: %s" % (pb.get_meta("display_name") if pb else "none"))
	_me.global_position = start + _xf.basis * Vector3(1.5, 0.3, 0)
	await get_tree().create_timer(0.5).timeout
	await _shot("bike_parked.png", start + _xf.basis * Vector3(2.4, 1.2, -2.2), start + Vector3.UP * 0.6)
	pb.request_use(0)
	await get_tree().create_timer(0.3).timeout
	var bike: BikeRider = _me.bike
	_check(bike.mounted and not _me.viewmodel.visible, "E rides it, no gun in hand (mounted %s)" % bike.mounted)
	var mag0: int = _me.weapons.net_mag
	Input.action_press("fire")
	await get_tree().create_timer(0.5).timeout
	Input.action_release("fire")
	_check(_me.weapons.net_mag == mag0, "no shooting on the bike (mag %d -> %d)" % [mag0, _me.weapons.net_mag])
	# Clutch in, E for 1st, ease off the clutch on the gas.
	Input.action_press("sprint")
	await get_tree().create_timer(0.2).timeout
	_tap("bike_shift_up")
	await get_tree().create_timer(0.2).timeout
	_check(int(bike._s.gear) == 1, "clutch + E: 1st (gear %d)" % int(bike._s.gear))
	Input.action_press("move_forward")
	await get_tree().create_timer(0.3).timeout
	Input.action_release("sprint")
	var top1 := 0.0
	var max_pitch := 0.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2500:
		await get_tree().physics_frame
		top1 = maxf(top1, float(bike._s.speed))
		max_pitch = maxf(max_pitch, float(bike._s.pitch))
	_check(bike.mounted and top1 > 8.0, "launch in 1st: %.0f km/h, still riding %s" % [top1 * 3.6, bike.mounted])
	await _shot_player("bike_riding.png")
	# 1st -> 2nd.
	Input.action_press("sprint")
	Input.action_release("move_forward")
	await get_tree().create_timer(0.1).timeout
	_tap("bike_shift_up")
	await get_tree().create_timer(0.15).timeout
	Input.action_release("sprint")
	Input.action_press("move_forward")
	var top2 := 0.0
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500:
		await get_tree().physics_frame
		top2 = maxf(top2, float(bike._s.speed))
	_check(int(bike._s.gear) == 2 and top2 > top1, "2nd gear: %.0f km/h (gear %d)" % [top2 * 3.6, int(bike._s.gear)])
	# Brake to a stop.
	Input.action_release("move_forward")
	Input.action_press("move_back")
	Input.action_press("sprint")
	await get_tree().create_timer(2.5).timeout
	Input.action_release("move_back")
	_check(float(bike._s.speed) < 1.0, "brakes stop it, then S paddles it back (%.1f m/s)" % float(bike._s.speed))
	# Down to 1st, wheelie: lean back + gas.
	_tap("bike_shift_down")
	await get_tree().create_timer(0.1).timeout
	Input.action_press("jump")
	Input.action_press("move_forward")
	await get_tree().create_timer(0.25).timeout
	Input.action_release("sprint")
	t0 = Time.get_ticks_msec()
	var shot := false
	while Time.get_ticks_msec() - t0 < 1500 and bike.mounted:
		await get_tree().physics_frame
		max_pitch = maxf(max_pitch, float(bike._s.pitch))
		if float(bike._s.pitch) > deg_to_rad(25.0) and float(bike._s.pitch) < deg_to_rad(65.0) and not shot:
			shot = true
			await _shot_player("bike_wheelie.png")
		if float(bike._s.pitch) > deg_to_rad(55.0):
			Input.action_release("move_forward")
	Input.action_release("move_forward")
	Input.action_release("jump")
	_check(max_pitch > deg_to_rad(20.0), "wheelie: %.0f deg" % rad_to_deg(max_pitch))
	if not bike.mounted:
		_say("  (crashed out of the wheelie - remounting)")
		await _remount(dir)
	# Stop and get off.
	Input.action_press("move_back")
	Input.action_press("sprint")
	await get_tree().create_timer(2.5).timeout
	Input.action_release("move_back")
	var at: Vector3 = _me.global_position
	_tap("bike_dismount")
	await get_tree().create_timer(0.4).timeout
	Input.action_release("sprint")
	var saved: Dictionary = dir.host_save()
	_check(not bike.mounted and _me.viewmodel.visible and saved.parked.has(bike_id_of(saved, at)),
		"F gets off; the bike parks there and is saved as moved (%d moved bikes)" % saved.parked.size())
	# Stall + restart.
	await _remount(dir)
	Input.action_press("sprint")
	await get_tree().create_timer(0.15).timeout
	_tap("bike_shift_up")
	await get_tree().create_timer(0.15).timeout
	Input.action_release("sprint")
	await get_tree().create_timer(1.0).timeout
	_check(not bool(bike._s.engine), "dumping the clutch with no gas stalls (engine %s)" % bike._s.engine)
	_tap("ride")
	await get_tree().create_timer(0.2).timeout
	var started_wrong := bool(bike._s.engine)
	Input.action_press("sprint")
	await get_tree().create_timer(0.15).timeout
	_tap("ride")
	await get_tree().create_timer(0.3).timeout
	_check(not started_wrong and bool(bike._s.engine), "B restarts it only with the clutch in")
	# Refuel.
	_me.inventory.host_add("gas_can", 1)
	var fuel0 := float(bike._s.fuel)
	_tap("reload")
	await get_tree().create_timer(0.3).timeout
	_check(float(bike._s.fuel) > fuel0 and _me.inventory.count("gas_can") == 0, "R refuels: %.1f -> %.1f L" % [fuel0, float(bike._s.fuel)])
	# Perf while riding (3rd person).
	await _perf("riding")
	# Crash: a fresh bike in the clear lane (x 12) - clutch kick in 1st, leaning back, never easing off -> loops.
	bike.host_dismount(false)
	await get_tree().create_timer(0.3).timeout
	var lane := _xf * Vector3(12, 0.15, -45)
	var id2: String = dir.host_spawn_test("dirt_250", 0, 6.0, lane, heading)
	_me.global_position = lane + Vector3.UP * 0.3
	await get_tree().create_timer(0.3).timeout
	dir.get_node("B_" + id2).request_use(0)
	await get_tree().create_timer(0.3).timeout
	Input.action_press("sprint")
	await get_tree().create_timer(0.15).timeout
	_tap("bike_shift_up")
	await get_tree().create_timer(0.15).timeout
	_me.health.damage_mult = 1.0
	var hp0: float = _me.health.current
	Input.action_press("move_forward")
	Input.action_press("jump")
	await get_tree().create_timer(0.6).timeout
	Input.action_release("sprint")
	t0 = Time.get_ticks_msec()
	var peak := 0.0
	while Time.get_ticks_msec() - t0 < 5000 and bike.mounted:
		await get_tree().physics_frame
		peak = maxf(peak, float(bike._s.pitch))
	Input.action_release("move_forward")
	Input.action_release("jump")
	await get_tree().create_timer(1.0).timeout
	_check(not bike.mounted, "holding a big wheelie loops it and throws you off (peak %.0f deg, HP %.0f -> %.0f)" % [
		rad_to_deg(peak), hp0, _me.health.current])
	_me.health.damage_mult = 0.0
	await _shot("bike_crashed.png", _me.global_position + _xf.basis * Vector3(3, 2.0, -3), _me.global_position)
	# All five, parked in a row.
	var x := -8.0
	for m: String in BikeRules.data().bikes:
		dir.host_spawn_test(m, 0, 5.0, _xf * Vector3(x, 0.15, -20), _xf.basis.get_euler().y + PI * 0.5)
		x += 4.0
	await get_tree().create_timer(0.5).timeout
	await _shot("bike_lineup.png", _xf * Vector3(0, 2.2, -12.5), _xf * Vector3(0, 0.6, -20))


func bike_id_of(saved: Dictionary, at: Vector3) -> String:
	for id: String in saved.parked:
		var p: Array = saved.parked[id].pos
		if Vector3(p[0], p[1], p[2]).distance_to(at) < 3.0:
			return id
	return "?"


func _remount(dir: Node) -> void:
	await get_tree().create_timer(0.3).timeout
	var best: Node = null
	for c in dir.get_children():
		if c is ParkedBike and (best == null or (c as Node3D).global_position.distance_to(_me.global_position) < (best as Node3D).global_position.distance_to(_me.global_position)):
			best = c
	if best == null:
		return
	_me.global_position = (best as Node3D).global_position + Vector3(0, 0.3, 0)
	best.request_use(0)
	await get_tree().create_timer(0.3).timeout


func _tap(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var u := InputEventAction.new()
	u.action = action
	u.pressed = false
	Input.parse_input_event(u)


func _perf(where: String) -> void:
	var worst := 0.0
	var sum := 0.0
	for i in 120:
		await get_tree().process_frame
		var ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		sum += ms
		worst = maxf(worst, ms)
	_say("perf %s: frame %.1f ms (worst process %.1f ms), draw calls %d, VRAM %.0f MB" % [where, sum / 120.0, worst,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])


func _shot(file: String, from: Vector3, look_at_pos: Vector3) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 70.0
		add_child(_cam)
	_cam.global_position = from
	_cam.look_at(look_at_pos)
	_cam.make_current()
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR + "/" + file))
	_me.camera.make_current()
	_say("shot " + file)


func _shot_player(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR + "/" + file))
	_say("shot " + file)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	_say(("PASS " if ok else "FAIL ") + what)


func _say(s: String) -> void:
	_log.append(s)
	print("BIKES: " + s)


func _finish(main: Node) -> void:
	_log.append("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/bike_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	get_tree().quit()
