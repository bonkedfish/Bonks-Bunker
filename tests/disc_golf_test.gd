# DiscGolfTest — checks D-069. Pure: full-power carries of the three discs, power scaling, tilt / forehand curve
# directions, basket catch / spit / bounce. In game (offline singleplayer world): the Centennial Park course is
# built and on the ground, E at the box starts a round (discs handed out, zombies blocked), hole 1 is played for real
# (aim at the basket, power from the reach table, walk to each lie) until it is scored, the rest of the card is
# scored directly to test finishing (rewards, best score, round over). Screenshots into res://tests/_look/
# (dg_tee1, dg_basket, dg_power, dg_card) plus frame time / draw calls at the course.
# Results: tests/_look/disc_golf_result.txt. Depends on: scenes/main.tscn, DiscFlightRules, DiscGolfRules,
# DiscGolfDirector, DiscCourse, DiscThrower.
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
	main.world_picker.choose_new("zz discgolf")
	main.menu.play_offline.emit()
	await get_tree().create_timer(5.0).timeout
	var player: Node3D = get_tree().get_first_node_in_group("local_player")
	var slug: String = main.saves.world_slug
	var dg: DiscGolfDirector = get_tree().get_first_node_in_group("disc_golf")
	var course: DiscCourse = dg.course_node("centennial")
	_check("course built (%d holes)" % (course.hole_count() if course else 0), course != null and course.hole_count() == 9)
	player.global_position = course.box_position() + Vector3(2.5, 1.5, 0)
	for i in 30:  # cells around the park stream in
		await get_tree().create_timer(0.5).timeout
		if course.is_snapped():
			break
	await get_tree().create_timer(2.0).timeout
	_check("course pieces on the ground", course.is_snapped())
	for i in 9:
		var hl: Dictionary = course.course.holes[i]
		var d := Vector2(course.tee_position(i).x, course.tee_position(i).z).distance_to(Vector2(course.basket_position(i).x, course.basket_position(i).z))
		_say("hole %d: %.1f m (%d ft UDisc), tee y %.2f basket y %.2f" % [i + 1, d, int(hl.length_ft), course.tee_position(i).y, course.basket_position(i).y])
	# Start the round at the box.
	dg.request_start("centennial")
	await get_tree().create_timer(0.3).timeout
	var me := multiplayer.get_unique_id()
	_check("E at the box starts a round with you in it", dg.round_active and dg.card.has(me))
	_check("discs handed out", player.inventory.count("disc_driver") == 1 and player.inventory.count("disc_mid") == 1 and player.inventory.count("disc_putter") == 1)
	_check("zombies can't spawn in the park", dg.blocks_spawn(course.basket_position(4)))
	# Tee 1 view + power HUD.
	_stand(player, course.tee_position(0), course.basket_position(0))
	player.disc._next_disc()
	await get_tree().create_timer(1.0).timeout
	player.disc.charge = 0.6
	await _shot("dg_tee1.png")
	_check("disc out: 3 picks the driver, gun can't fire", player.disc.active and player.disc.disc_id == "disc_driver")
	player.disc.charge = 0.0
	# Play hole 1 for real.
	var throws := 0
	var start_d := 0.0
	while int(dg.card[me].hole) == 0 and throws < 9:
		var e: Dictionary = dg.card[me]
		var lie: Vector3 = e.lie
		var basket := course.basket_position(0)
		_stand(player, lie, basket)
		await get_tree().create_timer(0.4).timeout
		var dist := Vector2(lie.x, lie.z).distance_to(Vector2(basket.x, basket.z))
		if throws == 0:
			start_d = dist
		var disc := "disc_putter" if dist < 40.0 else "disc_mid"
		var power := DiscFlightRules.power_for(DiscFlightRules.reach_table(DiscFlightRules.discs()[disc], DiscFlightRules.tuning()), dist)
		var t0 := Time.get_ticks_usec()
		dg.request_throw(disc, power, player.yaw, 0.0, 0.0, false)
		_say("  host flight simulation: %.1f ms, %d course trees" % [(Time.get_ticks_usec() - t0) / 1000.0, dg._trees.size()])
		if throws == 0:
			var again := DiscFlightRules.launch(DiscFlightRules.discs()[disc], power, lie + Vector3.UP * 1.4, player.yaw, 0.1, 0.0, false, DiscFlightRules.tuning())
			t0 = Time.get_ticks_usec()
			dg._simulate(again, basket, course)
			_say("  same flight again with trees cached: %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
		throws += 1
		await get_tree().create_timer(0.15).timeout
		_check("throw %d accepted (%s, %.0f m, power %.2f)" % [throws, disc, dist, power], dg.is_flying(me))
		if throws == 1:
			await get_tree().create_timer(1.0).timeout
			await _shot("dg_flight.png")
		while dg.is_flying(me) or dg._in_flight.has(me):
			await get_tree().create_timer(0.2).timeout
		await get_tree().create_timer(0.3).timeout
		var after: Dictionary = dg.card[me]
		var left := Vector2(after.lie.x, after.lie.z).distance_to(Vector2(basket.x, basket.z)) if int(after.hole) == 0 else 0.0
		_say("  landed: %.1f m from the basket, hole %d, throws %d" % [left, int(after.hole) + 1, int(after.throws)])
	_check("hole 1 scored in %d (started %.0f m out)" % [int(dg.card[me].strokes[0]), start_d], int(dg.card[me].strokes[0]) > 0 and int(dg.card[me].hole) == 1)
	_check("lie moved to tee 2", Vector2(dg.card[me].lie.x, dg.card[me].lie.z).distance_to(Vector2(course.tee_position(1).x, course.tee_position(1).z)) < 0.1)
	# A throw from far away is refused.
	player.global_position = course.tee_position(1) + Vector3(20, 1, 0)
	await get_tree().create_timer(0.3).timeout
	dg.request_throw("disc_driver", 1.0, 0.0, 0.0, 0.0, false)
	await get_tree().create_timer(0.2).timeout
	_check("throw away from your lie is refused", not dg.is_flying(me) and int(dg.card[me].throws) == 0)
	# Basket close-up.
	_stand(player, course.basket_position(1) + (course.tee_position(1) - course.basket_position(1)).normalized() * 4.0, course.basket_position(1))
	player.pitch = -0.15
	player.head.rotation.x = player.pitch
	await get_tree().create_timer(1.0).timeout
	await _shot("dg_basket.png")
	# Score the rest directly (3 each, an ace on hole 5) and finish.
	var before: int = player.inventory.count("disc_golden_ace")
	for h in range(1, 9):
		dg.card[me].throws = 1 if h == 4 else 3
		dg._host_land(me, Vector3.ZERO, true)
	await get_tree().create_timer(0.5).timeout
	var total := 0
	for s: Variant in dg.card[me].strokes:
		total += int(s)
	_check("card finished: total %d" % total, dg.card[me].done and not dg.round_active)
	_check("ace reward (Golden Ace Disc)", player.inventory.count("disc_golden_ace") == before + 1)
	var quests := get_tree().get_first_node_in_group("quests")
	_check("best score saved as a flag (%d)" % int(quests.flags.get("dg_best_centennial", 0)), int(quests.flags.get("dg_best_centennial", 0)) == total)
	var hud_dg: Node = null
	for c in get_tree().get_first_node_in_group("hud").get_children():
		if c.get_script() == preload("res://scripts/ui/disc_golf_hud.gd"):
			hud_dg = c
	_check("scorecard pops at the end of the round", hud_dg != null and hud_dg._card_left > 0.0)
	_stand(player, course.tee_position(0), course.basket_position(0))
	await get_tree().create_timer(0.5).timeout
	await _shot("dg_card.png")
	await get_tree().create_timer(2.0).timeout
	await _perf()
	# Street sign + minimap street names at 7th Ave & W 11th St (D-070).
	_stand(player, Vector3(1032, 0, -288), Vector3(1022, 1.5, -297))
	await get_tree().create_timer(3.0).timeout
	player.global_position.y = _ground_y(player.global_position) + 0.2
	await get_tree().create_timer(1.0).timeout
	var signs := 0
	for cell in get_tree().get_first_node_in_group("world_streamer").near_loaded.values():
		var h: Node = cell.get_node_or_null("StreetSigns")
		if h:
			signs += h.get_child_count()
	_check("street signs in the loaded cells (%d nodes)" % signs, signs > 0)
	await _shot("street_sign.png")
	# Cottonmill (D-073): built, 19 holes with the 9½, on the ground; a round can start there.
	var cm: DiscCourse = dg.course_node("cottonmill")
	_check("Cottonmill course built (%d holes, label 10 = %s)" % [cm.hole_count() if cm else 0, DiscGolfRules.hole_label(cm.course, 9) if cm else "?"],
		cm != null and cm.hole_count() == 19 and DiscGolfRules.hole_label(cm.course, 9) == "9½")
	player.global_position = cm.box_position() + Vector3(2.5, 3.0, 0)
	for i in 30:
		await get_tree().create_timer(0.5).timeout
		if cm.is_snapped():
			break
	_check("Cottonmill pieces on the ground", cm.is_snapped())
	_stand(player, cm.tee_position(0) + Vector3(0, 0.2, 0), cm.basket_position(0))
	await get_tree().create_timer(1.5).timeout
	await _shot("cottonmill_tee1.png")
	_stand(player, cm.tee_position(15) + Vector3(0, 0.2, 0), cm.basket_position(15))
	await get_tree().create_timer(2.5).timeout
	await _shot("cottonmill_tee15.png")
	player.global_position = cm.box_position() + Vector3(2.0, 0.3, 0)
	await get_tree().create_timer(1.0).timeout
	dg.request_start("cottonmill")
	await get_tree().create_timer(0.3).timeout
	_check("round starts at Cottonmill", dg.round_active and dg.round_course == "cottonmill")
	await _perf()
	SaveStore.delete(slug)
	_say("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/disc_golf_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()


func _pure() -> void:
	var t := DiscFlightRules.tuning()
	var discs := DiscFlightRules.discs()
	_check("3 discs + tuning load", discs.size() == 3 and not t.is_empty())
	var want := {"disc_driver": [95.0, 125.0], "disc_mid": [68.0, 92.0], "disc_putter": [45.0, 65.0]}
	for id: String in want:
		var full := DiscFlightRules.flat_distance(discs[id], 1.0, t)
		var half := DiscFlightRules.flat_distance(discs[id], 0.5, t)
		_check("%s: full power %.0f m (%.0f ft), half %.0f m" % [id, full, full * 3.28, half], full >= want[id][0] and full <= want[id][1] and half < full * 0.6)
	var left := _lateral("disc_mid", 20.0, false)
	var right := _lateral("disc_mid", -20.0, false)
	_check("tilt left curves left (%.1f), tilt right curves right (%.1f)" % [left, right], left < -3.0 and right > 3.0)
	var bh := _lateral("disc_driver", 0.0, false)
	var fh := _lateral("disc_driver", 0.0, true)
	_check("forehand mirrors the driver's flight (%.1f vs %.1f)" % [bh, fh], absf(bh + fh) < 0.5 and absf(bh) > 1.0)
	var slow := DiscGolfRules.basket_contact(Vector3(0.1, 1.0, 0.0), Vector3(0.4, 1.05, 0.0), 8.0, t)
	var fast := DiscGolfRules.basket_contact(Vector3(0.1, 1.0, 0.0), Vector3(0.4, 1.05, 0.0), 30.0, t)
	var side := DiscGolfRules.basket_contact(Vector3(0.3, 0.6, 0.0), Vector3(0.5, 0.6, 0.0), 8.0, t)
	var miss := DiscGolfRules.basket_contact(Vector3(0.6, 1.0, 0.0), Vector3(0.8, 1.0, 0.0), 8.0, t)
	_check("basket: chains catch / fast spits / tray side bounces / wide misses",
		slow == DiscGolfRules.Basket.CATCH and fast == DiscGolfRules.Basket.SPIT and side == DiscGolfRules.Basket.BOUNCE and miss == DiscGolfRules.Basket.NONE)
	var putt_power := DiscFlightRules.power_for(DiscFlightRules.reach_table(discs.disc_putter, t), 4.0)
	var putt := DiscFlightRules.launch(discs.disc_putter, putt_power, Vector3(0, 1.4, 0), 0.0, DiscFlightRules.launch_pitch(0.0, t), 0.0, false, t)
	while putt.pos.z > -4.0 and putt.time < 5.0:
		DiscFlightRules.step(putt, 1.0 / 60.0, t)
	_check("4 m putt arrives at the chains: height %.2f, %.2f m off line" % [putt.pos.y, putt.pos.x], absf(putt.pos.x) < 0.15 and putt.pos.y > 0.75 and putt.pos.y < 1.3)
	_check("score names", DiscGolfRules.score_name(1, 3) == "ACE!" and DiscGolfRules.score_name(2, 3) == "Birdie" and DiscGolfRules.score_name(4, 3) == "Bogey")
	var c: Dictionary = DiscGolfRules.courses().centennial
	var ft := 0
	for h: Dictionary in c.holes:
		ft += int(h.length_ft)
	_check("Centennial: 9 holes, par %d, %d ft (UDisc 1,845)" % [DiscGolfRules.par_total(c), ft], c.holes.size() == 9 and DiscGolfRules.par_total(c) == 27 and ft == 1845)


# Sideways landing offset (+X = right of a throw toward -Z) for a full-power throw.
func _lateral(id: String, tilt: float, forehand: bool) -> float:
	var t := DiscFlightRules.tuning()
	var f := DiscFlightRules.launch(DiscFlightRules.discs()[id], 1.0, Vector3(0, 1.4, 0), 0.0, DiscFlightRules.launch_pitch(0.0, t), tilt, forehand, t)
	while f.pos.y > 0.0 and f.time < 15.0:
		DiscFlightRules.step(f, 1.0 / 60.0, t)
	return f.pos.x


func _stand(player: Node3D, at: Vector3, look_at_pos: Vector3) -> void:
	var d := look_at_pos - at
	player.global_position = at + Vector3.UP * 0.2
	player.velocity = Vector3.ZERO
	player.yaw = atan2(-d.x, -d.z)
	player.rotation.y = player.yaw
	player.pitch = 0.0
	player.head.rotation.x = 0.0


func _ground_y(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 60, p + Vector3.DOWN * 60, 1)
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
	return float(hit.position.y) if not hit.is_empty() else p.y


func _perf() -> void:
	await RenderingServer.frame_post_draw
	_say("perf at the course: %.1f ms frame, %d draw calls, %d objects, %.0f MB static mem" % [
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
	print("DISCGOLF: " + s)
	_log.append(s)
