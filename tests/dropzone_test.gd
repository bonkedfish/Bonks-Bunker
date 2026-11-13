# DropZoneTest — checks D-074. Pure: club carries, target scoring (bullseye), a putt rolled with the HUD's power drops,
# a pickleball aim lands where aimed. In game (offline world): the Drop Zone scene is placed with its game nodes;
# a bay game (E, swing at a target, scores, last ball ends it, best saved), the putting course (hole 1 played out),
# pickleball vs the CPU (serve, rally until points are scored). Screenshots into res://tests/_look/dz_*.png, perf.
# Results: tests/_look/dropzone_result.txt. Depends on: scenes/main.tscn, DropZone, DzRange, DzPutting, DzCourt,
# GolfBallRules, PickleballRules, SportInput.
extends Node

const OUT_DIR := "res://tests/_look"

var _log := PackedStringArray()
var _fails := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_pure()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz dropzone")
	main.menu.play_offline.emit()
	await get_tree().create_timer(5.0).timeout
	var player: Node3D = get_tree().get_first_node_in_group("local_player")
	var slug: String = main.saves.world_slug
	var dz: DropZone = get_tree().get_first_node_in_group("drop_zone")
	_check("Drop Zone placed with its games", dz != null and dz.has_node("Range") and dz.has_node("Putting") and dz.has_node("Court3"))
	var rg: DzRange = dz.get_node("Range")
	var me := multiplayer.get_unique_id()
	# Outside view, then into bay 3 (ground floor).
	_stand(player, dz.to_world(Vector3(-60, 0.3, 40)), dz.to_world(Vector3(0, 4, 0)))
	await get_tree().create_timer(4.0).timeout
	await _shot("dz_outside.png")
	var tee := rg.bay_spot(2)
	_stand(player, dz.to_world(tee + Vector3(-0.4, 0.3, 0)), dz.to_world(Vector3(120, 0, tee.z)))
	await get_tree().create_timer(1.5).timeout
	rg.request_use(2)
	await get_tree().create_timer(0.3).timeout
	_check("E at bay 3 starts a game in range mode", rg.games.has(me) and player.sport.mode == "range")
	# Aim at the middle red target with the wedge at the HUD's power.
	var t := GolfBallRules.tuning()
	var red: Dictionary = dz.data.targets[1]
	var aim := Vector3(float(red.x), 0, float(red.z))
	var d := aim - Vector3(tee.x, 0, tee.z)
	var yaw := atan2(-d.x, -d.z)
	var power := _power_for("wedge", d.length(), t)
	player.sport.charge = 0.7
	await _shot("dz_range.png")
	player.sport.charge = 0.0
	rg.request_shot("wedge", power, yaw)
	await get_tree().create_timer(0.4).timeout
	await _shot("dz_range_flight.png")
	while rg.is_flying(me) or rg._in_flight.has(me):
		await get_tree().create_timer(0.2).timeout
	_check("wedge at the red target (%.0f m, power %.2f) scores: %d" % [d.length(), power, int(rg.games[me].score)], int(rg.games[me].score) > 0)
	rg.games[me].balls = 1
	var white: Dictionary = dz.data.targets[6]
	d = Vector3(float(white.x), 0, float(white.z)) - Vector3(tee.x, 0, tee.z)
	rg.request_shot("driver", _power_for("driver", d.length(), t), atan2(-d.x, -d.z))
	await get_tree().create_timer(0.3).timeout
	while rg._in_flight.has(me):
		await get_tree().create_timer(0.2).timeout
	await get_tree().create_timer(0.3).timeout
	var quests := get_tree().get_first_node_in_group("quests")
	_check("last ball ends the game, best saved (%d)" % int(quests.flags.get("dz_best_range", 0)), not rg.games.has(me) and int(quests.flags.get("dz_best_range", 0)) > 0 and player.sport.mode == "")
	# Putting course.
	var pg: DzPutting = dz.get_node("Putting")
	var s: Array = dz.data.putting.start
	_stand(player, dz.to_world(Vector3(s[0], 0.3, float(s[1]) - 2.0)), dz.to_world(Vector3(5, 0, -60)))
	await get_tree().create_timer(1.0).timeout
	pg.request_use(0)
	await get_tree().create_timer(0.3).timeout
	_check("putting card started (putt mode)", pg.cards.has(me) and player.sport.mode == "putt")
	var putts := 0
	while int(pg.cards[me].hole) == 0 and putts < 7:
		var ball: Vector2 = pg.cards[me].ball
		var cup := Vector2(pg.hole_def(0).cup[0], pg.hole_def(0).cup[1])
		var to := cup - ball
		var py := atan2(-to.x, -to.y)
		_stand(player, dz.to_world(Vector3(ball.x, 0.3, ball.y) - Vector3(to.normalized().x, 0, to.normalized().y) * 0.6), dz.to_world(Vector3(cup.x, 0, cup.y)))
		await get_tree().create_timer(0.3).timeout
		if putts == 0:
			await _shot("dz_putt.png")
		pg.request_shot("", GolfBallRules.putt_power(to.length() + 0.15, t), py)
		putts += 1
		await get_tree().create_timer(0.2).timeout
		while pg._in_flight.has(me):
			await get_tree().create_timer(0.2).timeout
		await get_tree().create_timer(0.2).timeout
	_check("putting hole 1 holed in %d (par %d)" % [int(pg.cards[me].strokes[0]), int(pg.hole_def(0).par)], int(pg.cards[me].strokes[0]) > 0 and int(pg.cards[me].hole) == 1)
	# Pickleball.
	var ct: DzCourt = dz.get_node("Court0")
	var cc: Array = dz.data.courts[0].c
	var half := PickleballRules.half_size(dz.data.court_size)
	_stand(player, dz.to_world(Vector3(float(cc[0]), 0.3, float(cc[1]) + half.y - 1.0)), dz.to_world(Vector3(float(cc[0]), 0, float(cc[1]) - 5.0)))
	await get_tree().create_timer(1.0).timeout
	ct.request_use(0)
	await get_tree().create_timer(0.3).timeout
	_check("pickleball game on (pickle mode)", ct.player_peer == me and player.sport.mode == "pickle")
	ct.request_hit(player.yaw)  # serve
	var hits := 1
	var cpu_returns := 0
	var last := 1
	var shot_taken := false
	for i in 300:  # ~30 s of play: follow the ball and swing when it comes
		await get_tree().create_timer(0.1).timeout
		if ct.player_peer != me:
			break
		if ct._last_hitter == -1 and last == 1 and ct.phase == "rally":
			cpu_returns += 1
		last = ct._last_hitter
		var b: Vector3 = ct._ball.pos
		if ct.phase == "rally" and b.z > 0.5 and ct._last_hitter != 1:
			player.global_position = dz.to_world(Vector3(float(cc[0]) + b.x, 0.2, float(cc[1]) + b.z + 0.6))
			if b.y < 1.4:
				ct.request_hit(atan2(0.0, 1.0))
				hits += 1
		elif ct.phase == "serve" and ct.serving == 1:
			ct.request_hit(atan2(0.0, 1.0))
		if not shot_taken and ct.phase == "rally" and i > 8:
			await _shot("dz_pickle.png")
			shot_taken = true
		if ct.score.x + ct.score.y >= 4:
			break
	_check("pickleball points scored: you %d - %d CPU (%d swings, CPU returned %d)" % [ct.score.x, ct.score.y, hits, cpu_returns],
		ct.score.x + ct.score.y >= 2 and cpu_returns >= 1)
	await _perf()
	SaveStore.delete(slug)
	_say("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/dropzone_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()


func _pure() -> void:
	var t := GolfBallRules.tuning()
	var want := {"driver": [185.0, 215.0], "iron7": [125.0, 155.0], "wedge": [78.0, 102.0]}
	for id: String in want:
		var c := GolfBallRules.carry(t.clubs[id], 1.0, t)
		_check("%s full carry %.0f m (%.0f yd)" % [id, c, c * 1.0936], c >= want[id][0] and c <= want[id][1])
	var targets := [{"x": 100.0, "z": 0.0, "r": 6.0, "points": 20}]
	var hit := GolfBallRules.target_score(Vector3(101, 0, 0), targets, t)
	var edge := GolfBallRules.target_score(Vector3(105, 0, 0), targets, t)
	var miss := GolfBallRules.target_score(Vector3(110, 0, 0), targets, t)
	_check("targets: bullseye %d, ring %d, miss %d" % [hit.x, edge.x, miss.x], hit.x == 40 and edge.x == 20 and miss.x == 0)
	var hole := {"tee": [0, 0], "cup": [0, -8], "par": 2, "green": {"c": [0, -4], "a": 6.0, "b": 2.5, "rot": PI * 0.5}}
	var res := GolfBallRules.roll_putt(Vector2.ZERO, 0.0, GolfBallRules.putt_power(8.15, t), hole, [-20, -20, 20, 20], t)
	_check("8 m putt at the HUD's power drops: holed %s, ends %s" % [res.holed, res.end], res.holed)
	var p := PickleballRules.tuning()
	var b := PickleballRules.Ball.new()
	b.pos = Vector3(0, 0.9, 5)
	b.vel = PickleballRules.aim(b.pos, Vector2(1.0, -4.0), 2.2, p)
	var ev := PickleballRules.Event.NONE
	var steps := 0
	while ev != PickleballRules.Event.BOUNCE and steps < 600:
		ev = PickleballRules.step(b, 1.0 / 60.0, p)
		steps += 1
	_check("pickleball aim lands on target: %s (want (1, -4))" % Vector2(b.pos.x, b.pos.z), Vector2(b.pos.x, b.pos.z).distance_to(Vector2(1, -4)) < 0.4)


func _power_for(club: String, metres: float, t: Dictionary) -> float:
	for i in range(1, 101):
		if GolfBallRules.carry(t.clubs[club], i / 100.0, t) >= metres:
			return i / 100.0
	return 1.0


func _stand(player: Node3D, at: Vector3, look_at_pos: Vector3) -> void:
	var d := look_at_pos - at
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.yaw = atan2(-d.x, -d.z)
	player.rotation.y = player.yaw
	player.pitch = -0.1
	player.head.rotation.x = player.pitch


func _perf() -> void:
	await RenderingServer.frame_post_draw
	_say("perf at Drop Zone: %.1f ms frame, %d draw calls, %d objects, %.0f MB static mem" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])


func _shot(file: String) -> void:
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT_DIR + "/" + file)
	_say("shot " + file)


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	_say(("PASS " if ok else "FAIL ") + what)


func _say(s: String) -> void:
	print("DROPZONE: " + s)
	_log.append(s)
