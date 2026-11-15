# PickleballTest — the pickleball rework (D-089).
# Pure: swing timing grades (PERFECT at the contact point, GOOD / EARLY / LATE by the time to the ball's closest
# pass, WHIFF out of reach); volley faults (two-bounce rule, kitchen) and a legal volley from the baseline; the CPU
# lobs a net camper; the landing prediction.
# In game (offline world): 1) camping at the net spam-clicking (every 50 ms) no longer beats the CPU - the CPU
# outscores it; 2) a player that gets behind the ball's hop and swings on time gets PERFECT / GOOD grades and
# rallies. Screenshot tests/_look/pickle_*.png. Results: tests/_look/pickleball_result.txt (ends with the failure count).
# Depends on: scenes/main.tscn, PickleballRules, DropZone (DzCourt), SportInput.
extends Node

const OUT_DIR := "res://tests/_look"

var _log := PackedStringArray()
var _fails := 0
var _me: Node3D
var _grades := {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_pure()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz pickle")
	main.menu.play_offline.emit()
	await get_tree().create_timer(5.0).timeout
	_me = get_tree().get_first_node_in_group("local_player")
	var prompt := get_tree().get_first_node_in_group("name_prompt")
	if prompt and prompt.visible:
		prompt.submit("Bonk")
	_me.health.damage_mult = 0.0
	await _spam()
	await _timed()
	_log.append("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/pickleball_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	get_tree().quit()


func _pure() -> void:
	var p := PickleballRules.tuning()
	var v := Vector3(0, 0, 8.0)  # coming at the player (+z)
	_check(PickleballRules.swing_grade(Vector3(0, 0, 0), v, p) == "PERFECT"
		and PickleballRules.swing_grade(Vector3(0, 0, -0.8), v, p) == "GOOD"
		and PickleballRules.swing_grade(Vector3(0, 0, -1.6), v, p) == "EARLY"
		and PickleballRules.swing_grade(Vector3(0, 0, 1.6), v, p) == "LATE"
		and PickleballRules.swing_grade(Vector3(0, 0, -4.0), v, p) == "WHIFF", "grades: perfect / good / early / late / whiff")
	_check(PickleballRules.volley_fault(false, 1, 5.0, p) == "Two-bounce rule" and PickleballRules.volley_fault(false, 3, 1.0, p) == "Kitchen volley"
		and PickleballRules.volley_fault(false, 3, 5.0, p) == "" and PickleballRules.volley_fault(true, 0, 1.0, p) == "",
		"faults: volleyed return, kitchen volley; baseline volley and bounced balls are fine")
	_check(PickleballRules.cpu_should_lob(1.2, p) and not PickleballRules.cpu_should_lob(5.5, p), "the CPU lobs a net camper only")
	var b := PickleballRules.Ball.new()
	b.pos = Vector3(0, 1.0, -5.0)
	b.vel = PickleballRules.aim(b.pos, Vector2(1.0, 4.0), 2.0, p)
	var land := PickleballRules.landing(b, p)
	_check(land != Vector3.INF and Vector2(land.x - 1.0, land.z - 4.0).length() < 0.3, "landing prediction (%.2f, %.2f) for an aim at (1, 4)" % [land.x, land.z])


func _court() -> DzCourt:
	return (get_tree().get_first_node_in_group("drop_zone") as DropZone).get_node("Court0")


func _stand(ct: DzCourt, x: float, z: float) -> void:
	_me.global_position = ct.dz().to_world(ct.position + Vector3(x, 0.2, z))
	var look: Vector3 = ct.dz().to_world(ct.position + Vector3(0, 0, -6))
	var d := look - _me.global_position
	_me.yaw = atan2(-d.x, -d.z)
	_me.rotation.y = _me.yaw


func _start(ct: DzCourt) -> void:
	_stand(ct, 0.0, 5.0)
	await get_tree().create_timer(0.8).timeout
	ct.request_use(0)
	await get_tree().create_timer(0.3).timeout


func _spam() -> void:
	var ct := _court()
	await _start(ct)
	_check(_me.sport.mode == "pickle", "pickleball game on")
	var reasons := {}
	var t0 := Time.get_ticks_msec()
	var shot := false
	while ct.player_peer != 0 and Time.get_ticks_msec() - t0 < 40000 and ct.score.x + ct.score.y < 8:
		_stand(ct, clampf(ct._ball.pos.x, -2.5, 2.5), 1.0)  # glued to the net, following the ball sideways
		ct.request_hit(_me.yaw)
		if ct.callout_time > 1.9:
			reasons[ct.callout.get_slice("!", 0)] = true
		if not shot and ct.rally >= 1 and ct.phase == "rally":
			await _snap("pickle_net.png")
			shot = true
		await get_tree().create_timer(0.05).timeout
	_check(ct.score.y > ct.score.x, "net camping + spam clicks: you %d - %d CPU (%s)" % [ct.score.x, ct.score.y, ", ".join(reasons.keys())])
	ct.player_peer = 0
	ct.phase = "idle"
	ct._state(0, ct.score, ct.serving, "idle")
	await get_tree().create_timer(0.5).timeout


func _timed() -> void:
	var ct := _court()
	await _start(ct)
	var p := PickleballRules.tuning()
	var best_rally := 0
	var t0 := Time.get_ticks_msec()
	var swung_for := -1
	var shot := false
	while ct.player_peer != 0 and Time.get_ticks_msec() - t0 < 45000 and ct.score.x + ct.score.y < 6:
		await get_tree().physics_frame
		best_rally = maxi(best_rally, ct.rally)
		if _me.sport.grade_time > 1.5 and _me.sport.last_grade != "":
			_grades[_me.sport.last_grade] = int(_grades.get(_me.sport.last_grade, 0)) + 1
			_me.sport.grade_time = 1.4
		if ct.phase == "serve" and ct.serving == 1:
			_stand(ct, 0.0, 5.5)
			ct.request_hit(_me.yaw)
			continue
		if ct.phase != "rally" or ct._last_hitter == 1 or ct._ball.vel.z <= 0.0:
			continue
		# Under the top of the hop after it bounces on our side, a little behind; swing windup_s before it gets there.
		var c := PickleballRules.Ball.new()
		c.pos = ct._ball.pos
		c.vel = ct._ball.vel
		var bounced := ct._bounces > 0 and ct._bounce_side == 1
		var tt := 0.0
		for i in 180:
			var ev := PickleballRules.step(c, 1.0 / 60.0, p)
			tt += 1.0 / 60.0
			if ev == PickleballRules.Event.BOUNCE:
				bounced = true
			elif bounced and c.vel.y <= 0.0:
				break
		_stand(ct, c.pos.x, c.pos.z + 0.25)
		if tt <= float(p.windup_s) + 0.02 and swung_for != ct.rally:
			swung_for = ct.rally
			ct.request_hit(_me.yaw)
			if not shot:
				await _snap("pickle_rally.png")
				shot = true
	_check(int(_grades.get("PERFECT", 0)) + int(_grades.get("GOOD", 0)) >= 2 and best_rally >= 3,
		"timed swings: grades %s, best rally %d, you %d - %d CPU" % [_grades, best_rally, ct.score.x, ct.score.y])


func _snap(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR + "/" + file))
	_say("shot " + file)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	_say(("PASS " if ok else "FAIL ") + what)


func _say(s: String) -> void:
	_log.append(s)
	print("PICKLE: " + s)
