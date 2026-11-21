# GolfTest — the golf swing and the country club course (D-086).
# Pure: the 3-click SwingMeter (perfect / hook / slice / shank / power locks at the top); the meter's error curves
# a driver (slice right, hook left); the new clubs' carries; a putt across a sloped green breaks downhill; the
# course lies (green / rough / out).
# In game (offline world, god mode): Drop Zone range swung with the meter (shot flies, grade shown, golf camera
# behind the ball, arc drawn); the putting course with the putt line; the country club: E at the hole 4 tee sign
# starts a card, the camera sits behind the ball on the tee, then the hole is played out (auto club, power to the
# pin, putter on the green) until it's holed or picked up and the card moves to hole 5.
# Screenshots tests/_look/golf_*.png. Results: tests/_look/golf_result.txt (ends with the failure count).
# Depends on: scenes/main.tscn, SwingMeter, GolfBallRules, CourseLies, DropZone (DzRange, DzPutting), CourseGolf,
# SportInput, GolfView.
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
	main.world_picker.choose_new("zz golf")
	main.menu.play_offline.emit()
	await get_tree().create_timer(5.0).timeout
	_me = get_tree().get_first_node_in_group("local_player")
	var prompt := get_tree().get_first_node_in_group("name_prompt")
	if prompt and prompt.visible:
		prompt.submit("Bonk")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_me.health.damage_mult = 0.0
	await _range()
	await _putting()
	await _course()
	await _perf()
	_log.append("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/golf_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	get_tree().quit()


func _pure() -> void:
	var t := GolfBallRules.tuning()
	var sw: Dictionary = t.swing
	var m := SwingMeter.new()
	m.setup(1.0, 1.0, sw)
	m.click()
	_run(m, 0.8)
	m.click()
	_run(m, 0.8)
	m.click()
	_check(m.grade == "PERFECT" and absf(m.power - 0.8) < 0.02 and m.error == 0.0, "meter: power 0.8 then the line = PERFECT (%s %.2f)" % [m.grade, m.power])
	m.click()
	_run(m, 0.5)
	m.click()
	_run(m, 0.4)
	m.click()
	_check(m.grade == "HOOK" and m.error < -0.5, "meter: stopped early = HOOK (error %.2f)" % m.error)
	m.click()
	_run(m, 0.5)
	m.click()
	_run(m, 0.58)
	m.click()
	_check(m.grade == "SLICE" and m.error > 0.4, "meter: stopped late = SLICE (error %.2f)" % m.error)
	m.click()
	_run(m, 1.3)
	_check(is_equal_approx(m.power, 1.0) and m.phase == SwingMeter.Phase.ACCURACY, "meter: power locks at the top by itself")
	_run(m, 1.3)
	_check(m.grade == "SHANK" and m.phase == SwingMeter.Phase.DONE and m.power < 0.7, "meter: never clicked = SHANK (power %.2f)" % m.power)
	var straight := _flight(t, 0.0)
	var slice := _flight(t, 1.0)
	var hook := _flight(t, -1.0)
	_check(slice.x > 15.0 and slice.x < 35.0 and hook.x < -15.0 and absf(straight.x) < 0.5, "driver: straight %.1f m, full slice %.1f m right, full hook %.1f m" % [straight.x, slice.x, hook.x])
	var want := {"wood3": [165.0, 195.0], "iron5": [145.0, 170.0], "iron9": [105.0, 125.0]}
	var ok := true
	var txt := ""
	for id: String in want:
		var c := GolfBallRules.carry(t.clubs[id], 1.0, t)
		ok = ok and c >= want[id][0] and c <= want[id][1]
		txt += " %s %.0f" % [id, c]
	_check(ok, "club carries:%s m" % txt)
	var flat := {"cup": [0.0, -20.0], "green": {"c": [0.0, -10.0], "a": 30.0, "b": 30.0, "rot": 0.0}}
	var sloped := flat.duplicate(true)
	sloped["slope"] = [0.25, 0.0]  # downhill = +x
	var pw := GolfBallRules.putt_power(8.0, t)
	var a := GolfBallRules.roll_putt(Vector2.ZERO, 0.0, pw, flat, [-50, -50, 50, 50], t)
	var b := GolfBallRules.roll_putt(Vector2.ZERO, 0.0, pw, sloped, [-50, -50, 50, 50], t)
	_check(absf(a.end.x) < 0.01 and b.end.x > 0.5, "an 8 m putt: straight on the flat, breaks %.2f m downhill on a 0.25 m/s2 slope" % b.end.x)
	var course := DataLoader.load_json("res://data/golf/country_club_course.json")
	var lies := CourseLies.new(course.bounds)
	var cup: Array = course.holes[3].cup
	_check(lies.lie_at(Vector2(cup[0], cup[1])) == "green" and lies.lie_at(Vector2(5000, 5000)) == "out",
		"course lies: hole 4's cup is on the green, far away is out (between holes: %s)" % lies.lie_at(Vector2(0, -230)))


func _run(m: SwingMeter, secs: float) -> void:
	var n := roundi(secs / 0.01)
	for i in n:
		m.update(0.01)


func _flight(t: Dictionary, err: float) -> Vector3:
	var s := GolfBallRules.launch(t.clubs.driver, 1.0, Vector3.ZERO, 0.0, t, err)
	while not s.landed:
		GolfBallRules.step(s, 1.0 / 60.0, t)
	return s.land


# --- in game ----------------------------------------------------------------------------------

func _range() -> void:
	var dz: DropZone = get_tree().get_first_node_in_group("drop_zone")
	var rg: DzRange = dz.get_node("Range")
	var me := multiplayer.get_unique_id()
	var tee := rg.bay_spot(2)
	_stand(dz.to_world(tee + Vector3(-0.4, 0.3, 0)), dz.to_world(Vector3(120, 0, tee.z)))
	await get_tree().create_timer(1.5).timeout
	rg.request_use(2)
	await get_tree().create_timer(0.5).timeout
	var sp: SportInput = _me.sport
	var view := sp.get_node_or_null("GolfView") as GolfView
	_check(sp.mode == "range" and rg.aim_ready() and view != null and view._cam.current, "range: in a bay, golf camera behind the ball")
	sp.club_index = sp.clubs().find("iron7")
	await get_tree().create_timer(0.3).timeout
	var balls := int(rg.games[me].balls)
	sp.meter.click()
	await get_tree().create_timer(0.6).timeout
	await _shot("golf_range_meter.png")
	sp.meter.click()
	await _until(func() -> bool: return sp.meter.value <= 0.005, 2.0)
	sp.meter.click()
	await get_tree().create_timer(0.5).timeout
	await _shot("golf_range_flight.png")
	_check(int(rg.games[me].balls) == balls - 1 and sp.last_grade in ["PERFECT", "GOOD"], "range: a 3-click swing hits a ball (%s)" % sp.last_grade)
	await _until(func() -> bool: return not rg._in_flight.has(me), 12.0)
	rg.games.erase(me)
	rg._sync(rg.games)
	await get_tree().create_timer(0.3).timeout
	_check(sp.mode == "" and _me.camera.current, "range: leaving gives the first-person camera back")


func _putting() -> void:
	var dz: DropZone = get_tree().get_first_node_in_group("drop_zone")
	var pg: DzPutting = dz.get_node("Putting")
	var me := multiplayer.get_unique_id()
	var s: Array = dz.data.putting.start
	_stand(dz.to_world(Vector3(s[0], 0.3, float(s[1]) - 2.0)), dz.to_world(Vector3(5, 0, -60)))
	await get_tree().create_timer(1.0).timeout
	pg.request_use(0)
	await get_tree().create_timer(0.3).timeout
	pg.cards[me].hole = 4  # a sloped hole
	var tee: Array = pg.hole_def(4).tee
	pg.cards[me].ball = Vector2(tee[0], tee[1])
	pg._sync(pg.cards)
	var cup: Array = pg.hole_def(4).cup
	var to := Vector2(cup[0], cup[1]) - Vector2(tee[0], tee[1])
	_stand(dz.to_world(Vector3(tee[0], 0.3, tee[1]) - Vector3(to.normalized().x, 0, to.normalized().y) * 0.6), dz.to_world(Vector3(cup[0], 0, cup[1])))
	await get_tree().create_timer(0.8).timeout
	_check(_me.sport.mode == "putt" and pg.aim_slope().length() > 0.1, "putting: putt mode on a sloped green (%.2f m/s2)" % pg.aim_slope().length())
	await _shot("golf_putt_line.png")
	pg.cards.erase(me)
	pg._sync(pg.cards)


func _course() -> void:
	var cg: CourseGolf = get_tree().get_first_node_in_group("course_golf")
	_check(cg != null and cg.hole_count() == 18, "country club: Golf node with 18 holes")
	if cg == null:
		return
	var me := multiplayer.get_unique_id()
	var h: Dictionary = cg.hole_def(3)
	var tee_sign := cg.local_to_world(float(h.sign[0]), float(h.sign[1]), 30.0)
	_me.global_position = tee_sign + Vector3(0, 0, 2.0)
	await get_tree().create_timer(4.0).timeout
	_me.global_position = _drop(_me.global_position + Vector3.UP * 20.0) + Vector3.UP * 0.2
	await get_tree().create_timer(1.0).timeout
	cg.request_use(3)
	await get_tree().create_timer(0.4).timeout
	var c: Dictionary = cg.my_card()
	_check(not c.is_empty() and int(c.hole) == 3 and _me.sport.mode == "course", "E at the hole 4 sign: card on hole 4, course mode")
	if c.is_empty():
		return
	var sp: SportInput = _me.sport
	var strokes := 0
	var shots := PackedStringArray()
	var cup := cg.cup_pos(3)
	while cg.my_card().get("hole", 3) == 3 and strokes < 12:
		var ball: Vector3 = cg.my_card().ball
		cup = cg.cup_pos(3)
		var to := cup - ball
		var yaw := atan2(-to.x, -to.z)
		_me.global_position = ball - Vector3(to.x, 0, to.z).normalized() * 1.0 + Vector3.UP * 0.3
		_me.yaw = yaw
		_me.rotation.y = yaw
		await get_tree().create_timer(1.5).timeout
		sp._last_ball = Vector3.INF  # pick the club again for this lie
		await get_tree().process_frame
		var club := sp.club_id()
		var dist := Vector2(to.x, to.z).length()
		var t := GolfBallRules.tuning()
		var power := 1.0
		if club == "putter":
			var dec := float(cg.course.lies.get(str(cg.my_card().lie), cg.course.lies.rough).putt_decel)
			power = clampf(sqrt(2.0 * dec * (dist + 0.25)) / float(t.putting.max_speed), 0.0, 1.0)
		else:
			power = _power_for(t.clubs[club], cg.aim_power_mult(), dist, t)
		if strokes == 0:
			await get_tree().create_timer(0.5).timeout
			_check(cg.aim_ready() and (sp.get_node("GolfView") as GolfView)._cam.current, "on the tee: addressing the ball, golf camera on")
			await _shot("golf_course_tee.png")
		if club == "putter" and not shots.has("green"):
			shots.append("green")
			await _shot("golf_course_green.png")
		cg.request_shot(club, power, yaw, 0.0)
		strokes += 1
		await get_tree().create_timer(0.3).timeout
		if strokes == 1:
			var tr: Node = cg._trails._lines.get(me)
			_check(tr != null and tr.visible, "the tee shot leaves a tracer line")
			await get_tree().create_timer(0.8).timeout
			await _shot("golf_course_tracer.png")
		await _until(func() -> bool: return not cg._in_flight.has(me), 25.0)
		var after: Dictionary = cg.my_card()
		shots.append("%s %.2f -> %s" % [club, power, str(after.get("lie", "done"))])
	_say("hole 4: " + ", ".join(shots))
	await _props_on_ground(cg)
	var card: Dictionary = cg.cards.get(me, {})
	_check(int(card.get("hole", -1)) == 4 and int(card.strokes[3]) > 0 and int(card.strokes[3]) <= 6,
		"hole 4 played out in %d (par 3), card on hole 5" % int(card.get("strokes", [0, 0, 0, 0])[3]))
	cg.cards.erase(me)
	cg._sync(cg.cards)


# Tee signs, pins and cups stand on the ground (D-097: they used to float on the tee E spots / tree tops).
func _props_on_ground(cg: CourseGolf) -> void:
	var props: Node3D = cg.get_parent().get_node("CourseProps")
	var worst := 0.0
	var n := 0
	for l in props.get_children():
		if not (l is Label3D and (l as Label3D).visible):
			continue
		var at := (l as Label3D).global_position
		var hit := _me.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 30.0, 1))
		if not hit.is_empty():
			worst = maxf(worst, at.y - (hit.position as Vector3).y)
			n += 1
	_check(n > 0 and worst < 1.6, "%d tee signs loaded around here, the highest board is %.2f m above the ground" % [n, worst])
	var cup := cg.cup_pos(4)
	var mm: MultiMesh = props._mm.cup
	var placed := mm.get_instance_transform(4).basis.get_scale().x > 0.5
	_check(placed and absf((props.to_global(mm.get_instance_transform(4).origin) - cup).y) < 0.3, "hole 5's cup is drawn on the green")


func _power_for(club: Dictionary, mult: float, metres: float, t: Dictionary) -> float:
	if GolfBallRules.carry(club, mult, t) < metres:
		return 1.0
	var lo := 0.0
	var hi := 1.0
	for i in 12:
		var mid := (lo + hi) * 0.5
		if GolfBallRules.carry(club, mid * mult, t) < metres:
			lo = mid
		else:
			hi = mid
	return hi


func _drop(p: Vector3) -> Vector3:
	var hit := _me.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 200.0, 17))
	return hit.position if not hit.is_empty() else p


func _stand(at: Vector3, look: Vector3) -> void:
	_me.global_position = at
	var d := look - at
	_me.yaw = atan2(-d.x, -d.z)
	_me.rotation.y = _me.yaw


func _until(cond: Callable, secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < secs * 1000.0:
		await get_tree().process_frame


func _perf() -> void:
	var sum := 0.0
	for i in 120:
		await get_tree().process_frame
		sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_say("perf: frame %.1f ms, draw calls %d" % [sum / 120.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])


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
	print("GOLF: " + s)
