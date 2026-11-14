# PoolTest — pool at the Big Apple (D-084). Pure: a fresh rack has 16 balls on the table, none touching; a full-power
# break hits the rack, keeps every ball on the table or in a pocket and stops; the aim probe finds the ball in line;
# 8-ball judging: a scratch hands the other player ball in hand, potting your own ball keeps the turn, the first ball
# after the break sets the groups, the 8 early loses, the 8 last wins, the 8 on the break is re-spotted.
# In game (singleplayer, god mode): both tables are placed; E sits you at table 1 (practice, SportInput "pool"); the
# aim line shows; holding left click and letting go breaks; the shot plays back and the balls end up somewhere new;
# E again leaves. Screenshots tests/_look/pool_*.png, perf at the table.
# Results: tests/_look/pool_result.txt (ends with the failure count).
# Depends on: scenes/main.tscn, PoolRules, PoolTable (group "pool_tables"), SaveStore.
extends Node

const OUT_DIR := "res://tests/_look"

var _log := PackedStringArray()
var _fails := 0
var _me: Node3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_pure()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz pool")
	main.menu.play_offline.emit()
	await get_tree().create_timer(4.0).timeout
	_me = get_tree().get_first_node_in_group("local_player")
	var prompt := get_tree().get_first_node_in_group("name_prompt")
	if prompt and prompt.visible:
		prompt.submit("Bonk")
	_me.health.damage_mult = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _game()
	_log.append("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/pool_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	get_tree().quit()


func _pure() -> void:
	var t := PoolRules.tuning()
	_check(not t.is_empty(), "pool data loads")
	var pos := PoolRules.rack(7, t)
	var ok := pos.size() == 16
	for i in 16:
		if absf(pos[i].x) > float(t.length) * 0.5 or absf(pos[i].y) > float(t.width) * 0.5:
			ok = false
		for j in range(i + 1, 16):
			if pos[i].distance_to(pos[j]) < float(t.ball_r) * 2.0:
				ok = false
	_check(ok, "a fresh rack: 16 balls on the table, none touching")
	var t0 := Time.get_ticks_usec()
	var s := PoolRules.run_shot(pos, Vector2(float(t.max_speed), 0.01), t)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var inside := true
	for p: Vector2 in (s.pos as PackedVector2Array):
		if p != PoolRules.OUT and (absf(p.x) > float(t.length) * 0.5 or absf(p.y) > float(t.width) * 0.5):
			inside = false
	_check(int(s.first_hit) >= 1 and inside and bool(s.done),
		"break: hits ball %d first, %d down %s, all on the table, %.1f s of play in %.0f ms of work" % [int(s.first_hit),
		(s.pocketed as Array).size(), s.pocketed, float(s.time), ms])
	var probe := PoolRules.aim_probe(pos, Vector2(1, 0), t)
	_check(int(probe.hit) >= 1, "aim probe finds the rack (ball %d)" % int(probe.hit))
	# Judging (two players, seats 11 and 22).
	var names := ["A", "B"]
	var g := PoolRules.new_game([11, 22])
	g.break_shot = false
	var before := pos.duplicate()
	s = {"pos": pos.duplicate(), "pocketed": [0], "first_hit": 3}
	PoolRules.judge(g, s, before, t, names)
	_check(int(g.turn) == 1 and bool(g.ball_in_hand), "a scratch: the other player, ball in hand (%s)" % g.msg)
	g = PoolRules.new_game([11, 22])
	g.break_shot = false
	var p2 := pos.duplicate()
	p2[3] = PoolRules.OUT
	s = {"pos": p2, "pocketed": [3], "first_hit": 3}
	PoolRules.judge(g, s, before, t, names)
	_check(int(g.turn) == 0 and str(g.groups[0]) == "solids" and str(g.groups[1]) == "stripes",
		"first ball after the break sets groups (A solids) and keeps the turn")
	g = PoolRules.new_game([11, 22])
	g.break_shot = false
	g.groups = ["solids", "stripes"]
	var p3 := pos.duplicate()
	p3[8] = PoolRules.OUT
	s = {"pos": p3, "pocketed": [8], "first_hit": 1}
	PoolRules.judge(g, s, before, t, names)
	_check(bool(g.over) and int(g.winner) == 1, "the 8 early loses (%s)" % g.msg)
	g = PoolRules.new_game([11, 22])
	g.break_shot = false
	g.groups = ["solids", "stripes"]
	var cleared := pos.duplicate()
	for b in range(1, 8):
		cleared[b] = PoolRules.OUT
	var p4 := cleared.duplicate()
	p4[8] = PoolRules.OUT
	s = {"pos": p4, "pocketed": [8], "first_hit": 8}
	PoolRules.judge(g, s, cleared, t, names)
	_check(bool(g.over) and int(g.winner) == 0, "the 8 last wins (%s)" % g.msg)
	g = PoolRules.new_game([11, 22])
	var p5 := pos.duplicate()
	p5[8] = PoolRules.OUT
	s = {"pos": p5, "pocketed": [8], "first_hit": 1}
	PoolRules.judge(g, s, before, t, names)
	_check(not bool(g.over) and (s.pos as PackedVector2Array)[8] != PoolRules.OUT, "the 8 on the break is re-spotted")


func _game() -> void:
	var tables := get_tree().get_nodes_in_group("pool_tables")
	_check(tables.size() == 2, "both Big Apple pool tables placed (%d)" % tables.size())
	if tables.is_empty():
		return
	var table: PoolTable = tables[0]
	var t := PoolRules.tuning()
	var xf := table.global_transform
	_me.global_position = xf * Vector3(-float(t.length) * 0.25 - 0.95, 0.3, 0.0)
	await get_tree().create_timer(4.0).timeout  # cells + landmark around it
	var fwd := xf.basis * Vector3(1, 0, 0)
	_me.yaw = atan2(-fwd.x, -fwd.z)
	_me.pitch = -0.55
	_me.rotation.y = _me.yaw
	_me.head.rotation.x = _me.pitch
	table.request_use(0)
	await get_tree().create_timer(0.5).timeout
	_check(table.my_seat() == 0 and _me.sport.mode == "pool", "E sits you at the table (seat %d, mode '%s')" % [table.my_seat(), _me.sport.mode])
	await get_tree().create_timer(0.3).timeout
	_check(table._aim_line.visible, "your shot: the aim line shows")
	await _shot("pool_aim.png")
	var before: PackedVector2Array = table.pos.duplicate()
	Input.action_press("fire")
	await get_tree().create_timer(float(t.charge_seconds) * 0.95).timeout
	Input.action_release("fire")
	var t0 := Time.get_ticks_msec()
	var shot_taken := false
	while Time.get_ticks_msec() - t0 < 15000:
		await get_tree().process_frame
		if table.busy():
			shot_taken = true
		elif shot_taken:
			break
		if Time.get_ticks_msec() - t0 > 1500 and Time.get_ticks_msec() - t0 < 1600:
			await _shot("pool_break.png")
	var moved := 0
	for i in 16:
		if table.pos[i].distance_to(before[i]) > 0.05:
			moved += 1
	_check(shot_taken and moved >= 4 and not table.busy(), "the break plays out: %d balls moved, %s" % [moved, table.state.msg])
	await _perf()
	await _shot("pool_after.png")
	table.request_use(0)
	await get_tree().create_timer(0.4).timeout
	_check(table.my_seat() < 0 and _me.sport.mode == "", "E again leaves the table")


func _perf() -> void:
	var worst := 0.0
	var sum := 0.0
	for i in 120:
		await get_tree().process_frame
		var ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		sum += ms
		worst = maxf(worst, ms)
	_say("perf at the table: frame %.1f ms (worst process %.1f ms), draw calls %d" % [sum / 120.0, worst,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR + "/" + file))
	_say("shot " + file)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	_say(("PASS " if ok else "FAIL ") + what)


func _say(s: String) -> void:
	_log.append(s)
	print("POOL: " + s)
