# BigUpdateTest — checks D-082. Pure: drinks and chems compound (8 drinks holds you wasted, then hungover; chem doses
# cap at 3), how messed up 8 drinks make you look, vomiting only when very drunk, course records + the board text,
# drunk throw error, quick keys never pick booze, hunger/thirst 3x slower. In game (offline world): John Pork's camp
# at Centennial (tent, vendor, records board, Meepo dock), buying water from him, docking + taking back a Meepo
# (charged, no riding while docked), a hole record showing on the board, being 8 drinks deep (impairment, stumbling,
# throwing up, double vision screenshot), a disc thrown into Cottonmill Lake (stops at the water, drop on the shore
# where it went in), and the throw swing other players see. Screenshots into res://tests/_look/bu_*.png, perf at the
# camp. Results: tests/_look/big_update_result.txt. Depends on: scenes/main.tscn, DiscGolfDirector, DiscCourse,
# VendorCamp, MeepoDock, ActiveEffects, EffectRules, DiscRecordsRules, DiscGolfRules, SurvivalRules, DialogueDirector,
# CharacterAnimator, SaveStore.
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
	main.world_picker.choose_new("zz bigupdate")
	main.menu.play_offline.emit()
	await get_tree().create_timer(5.0).timeout
	var player: Node3D = get_tree().get_first_node_in_group("local_player")
	var prompt: Control = get_tree().get_first_node_in_group("name_prompt")
	if prompt and prompt.visible:
		prompt.submit("Bonk")
	var slug: String = main.saves.world_slug
	var me := multiplayer.get_unique_id()
	var dg: DiscGolfDirector = get_tree().get_first_node_in_group("disc_golf")
	var course: DiscCourse = dg.course_node("centennial")
	player.global_position = course.box_position() + Vector3(2.5, 1.5, 0)
	for i in 30:
		await get_tree().create_timer(0.5).timeout
		if course.is_snapped():
			break
	await get_tree().create_timer(2.0).timeout
	var camp: VendorCamp = course.camp
	_check("John Pork's camp at Centennial", camp != null and camp.is_inside_tree())
	var npc: Node = null
	for n in get_tree().get_nodes_in_group("npcs"):
		if "npc_id" in n and n.npc_id == "john_pork" and camp.is_ancestor_of(n):
			npc = n
	var dock: MeepoDock = null
	for d in get_tree().get_nodes_in_group("meepo_docks"):
		if camp.is_ancestor_of(d):
			dock = d
	_check("vendor, records board and dock at the camp", npc != null and camp.board != null and dock != null)
	var cp := camp.global_position
	_say("camp at (%.1f, %.1f, %.1f), %.1f m from the course box; ground under it %.2f m away" % [cp.x, cp.y, cp.z,
		Vector2(cp.x, cp.z).distance_to(Vector2(course.box_position().x, course.box_position().z)), _ground_gap(cp)])
	_check("camp sits on the ground", absf(_ground_gap(cp)) < 0.4)
	# Look at the camp from out front.
	var front := -camp.global_basis.z
	_stand(player, cp + front * 11.0 + front.cross(Vector3.UP) * 2.0 + Vector3(0, 0.3, 0), cp + Vector3(0, 1.3, 0))
	await get_tree().create_timer(1.5).timeout
	await _shot("bu_camp.png")
	await _perf("camp")
	# Buy water from John Pork: shop -> food -> "1 scrap metal for 3 waters".
	var dlg := get_tree().get_first_node_in_group("dialogue")
	player.inventory.host_add("scrap_metal", 2)
	var water0: int = player.inventory.count("water_bottle")
	_stand(player, cp + front * 3.0 + Vector3(0, 0.3, 0), npc.global_position + Vector3(0, 1.45, 0))
	await get_tree().create_timer(0.6).timeout
	dlg.request_talk(npc.get_path())
	await get_tree().create_timer(0.3).timeout
	dlg.request_choice(0)  # What've you got?
	await get_tree().create_timer(0.2).timeout
	dlg.request_choice(0)  # Food and water.
	await get_tree().create_timer(0.2).timeout
	await _shot("bu_john_pork.png")
	dlg.request_choice(0)  # 1 scrap metal for 3 waters
	await get_tree().create_timer(0.3).timeout
	_check("bought 3 waters from John Pork for 1 scrap (%d -> %d water, %d scrap left)" % [water0, player.inventory.count("water_bottle"),
		player.inventory.count("scrap_metal")], player.inventory.count("water_bottle") == water0 + 3 and player.inventory.count("scrap_metal") == 1)
	dlg.request_leave()
	await get_tree().create_timer(0.3).timeout
	# Meepo dock: dock a half-empty board, it's charged, no riding; take it back.
	var m: MeepoRider = player.meepo
	player.inventory.host_add("meepo", 1)
	m._level = 20.0
	m.net_battery = 20.0
	_stand(player, dock.global_position + dock.global_basis.z * -1.6 + Vector3(0, 0.3, 0), dock.global_position + Vector3(0, 0.6, 0))
	await get_tree().create_timer(0.8).timeout
	dock.request_use(0)
	await get_tree().create_timer(0.3).timeout
	_check("docked: in a slot, charged to %d%%" % roundi(m.net_battery), dock.slot_of(me) >= 0 and m.net_battery >= 99.0)
	await _shot("bu_dock.png")
	m._host_toggle()
	_check("can't ride while it's docked", not m.net_riding)
	dock.request_use(0)
	await get_tree().create_timer(0.3).timeout
	m._host_toggle()
	_check("took it back and can ride", dock.slot_of(me) < 0 and m.net_riding)
	m._host_toggle()
	# A hole record shows on the board.
	player.global_position = course.box_position() + Vector3(2.5, 1.5, 0)
	await get_tree().create_timer(0.5).timeout
	dg.request_start("centennial")
	await get_tree().create_timer(0.5).timeout
	dg.card[me].throws = 2
	dg._host_land(me, Vector3.ZERO, true)
	await get_tree().create_timer(0.5).timeout
	var rec: Dictionary = dg.records.get("centennial", {})
	_check("hole 1 record kept (%s)" % str(rec), not rec.is_empty() and int(rec.values()[0].holes[0]) == 2)
	_check("board shows it under your name", camp.board.text.contains("1: 2 Bonk"))
	var bc := camp.board.global_position + Vector3(0, -0.8, 0)
	_stand(player, bc + front * 2.4 + Vector3(0, -0.6, 0), bc)
	await get_tree().create_timer(6.0).timeout  # the scorecard after a hole goes away
	await _shot("bu_board.png")
	# 8 drinks deep.
	var fx: ActiveEffects = player.effects
	player.inventory.host_add("beer_platte_light", 8)
	for i in 8:
		fx.host_add("drunk", 1.0)
	await get_tree().create_timer(0.3).timeout
	_check("8 drinks: impaired %.2f, double vision %.0f px" % [fx.impairment(), float(fx._look.double_px)], fx.impairment() > 0.5 and float(fx._look.double_px) > 10.0)
	var straight := Vector2(0, -1)
	var off := fx.stumble(straight)
	await get_tree().create_timer(0.7).timeout
	var off2 := fx.stumble(straight)
	_check("can't walk straight (%s, %s)" % [off, off2], off.distance_to(straight) > 0.05 or off2.distance_to(straight) > 0.05)
	var needs0: Vector2 = player.needs.value()
	_stand(player, course.box_position() + Vector3(-6, 0.3, 4), course.box_position() + Vector3(-30, 1, -10))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().create_timer(2.0).timeout
	await _shot("bu_drunk.png")
	var threw_up := false
	for i in 40:  # first one comes within ~16 s
		await get_tree().create_timer(0.5).timeout
		if player.needs.value().y < needs0.y - 5.0:
			threw_up = true
			break
	_check("threw up (water %.0f -> %.0f)" % [needs0.y, player.needs.value().y], threw_up)
	fx.host_clear()
	# Disc into Cottonmill Lake: stops at the water, drop on the shore where it went in.
	var cm: DiscCourse = dg.course_node("cottonmill")
	var shore := _shore_point(Vector2(cm.box_position().x, cm.box_position().z))
	player.global_position = Vector3(shore.x, cm.box_position().y + 2.0, shore.y)
	for i in 30:
		await get_tree().create_timer(0.5).timeout
		if cm.is_snapped():
			break
	await get_tree().create_timer(2.0).timeout
	var lake_c := _lake_centre()
	var inland := (shore - lake_c).normalized()
	var from := Vector3(shore.x, 0, shore.y) + Vector3(inland.x, 0, inland.y) * 12.0
	from.y = _ground_y(from) + 1.4
	var aim := Vector3(-inland.x, 0, -inland.y)
	var f := DiscFlightRules.launch(DiscFlightRules.discs()["disc_mid"], 0.6, from, atan2(-aim.x, -aim.z),
		DiscFlightRules.launch_pitch(0.0, DiscFlightRules.tuning()), 0.0, false, DiscFlightRules.tuning())
	var out: Array = dg._simulate(f, cm.basket_position(0), cm)
	var drop: Vector3 = dg._shore_drop(out[0], cm) if out[5] else Vector3.INF
	var shore3 := Vector3(shore.x, from.y, shore.y)
	_check("into the lake: stopped at the water (%s), dropped %.1f m from where it crossed" % [out[5],
		Vector2(drop.x, drop.z).distance_to(shore) if drop != Vector3.INF else -1.0],
		out[5] and drop != Vector3.INF and Vector2(drop.x, drop.z).distance_to(shore) < 15.0 and not _over_water(drop))
	_say("  water point %s, drop %s, shore %s" % [out[2], drop, shore3])
	# The throw other players see: a remote-style body throws.
	var body := CharacterAnimator.new()
	add_child(body)
	body.set_model("ubc_scavenger_m")
	body.global_position = from + aim * 3.0 - Vector3(0, 1.4, 0)
	body.global_position.y = _ground_y(body.global_position)
	body.rotation.y = atan2(aim.x, aim.z)
	var lead := body.throw_disc(Color(0.95, 0.3, 0.15), false)
	_check("throw swing plays (release after %.2f s), disc in hand" % lead, lead > 0.05 and body._disc_hold != null and body._disc_hold.visible)
	_stand(player, body.global_position + Vector3(aim.z, 0, -aim.x) * 3.5 + Vector3(0, 0.8, 0), body.global_position + Vector3(0, 1.1, 0))
	for i in 6:
		body.update(0.05, false, false, 100.0, false, false)
		await get_tree().create_timer(0.05).timeout
	await _shot("bu_throw.png")
	for i in 30:
		body.update(0.05, false, false, 100.0, false, false)
	_check("disc let go after the release", not body._disc_hold.visible)
	SaveStore.delete(slug)
	_say("%d failure(s)" % _fails)
	var file := FileAccess.open(OUT_DIR + "/big_update_result.txt", FileAccess.WRITE)
	file.store_string("\n".join(_log))
	file.close()
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()


func _pure() -> void:
	var d := EffectRules.defs()
	var a := EffectRules.add({}, "drunk", 1.0, d)
	_check("one beer: strength %.1f" % EffectRules.strengths(a, d).drunk, is_equal_approx(float(EffectRules.strengths(a, d).drunk), 1.0))
	for i in 7:
		a = EffectRules.add(a, "drunk", 1.0, d)
	_check("8 drinks: strength %.1f, held %.0f s" % [EffectRules.strengths(a, d).drunk, a.drunk.hold], float(EffectRules.strengths(a, d).drunk) >= 8.0 and float(a.drunk.hold) > 300.0)
	var b := EffectRules.tick(a, 300.0, d)
	_check("still wasted after 300 s (hold)", float(EffectRules.strengths(b, d).drunk) >= 8.0)
	b = EffectRules.tick(b, 240.0, d)
	_check("sobering up after the hold: %.1f" % EffectRules.strengths(b, d).drunk, float(EffectRules.strengths(b, d).drunk) < 8.0 and float(EffectRules.strengths(b, d).drunk) > 4.0)
	for i in 100:
		if not b.has("drunk"):
			break
		b = EffectRules.tick(b, 15.0, d)
	_check("drunk wears off into a hangover: %s" % str(b.keys()), not b.has("drunk") and b.has("hungover"))
	var look := EffectRules.look(EffectRules.strengths(a, d), d)
	_check("8 drinks look: sway %.1f deg, drift %.1f deg/s, stumble %.2f, double %.0f px, blur %.2f" % [look.sway_deg, look.drift_deg_s,
		look.stumble, look.double_px, look.blur], float(look.stumble) > 0.3 and float(look.double_px) > 10.0 and float(look.blur) > 0.3)
	var four := EffectRules.add({}, "drunk", 4.0, d)
	_check("vomit at 8 drinks, not at 4", not EffectRules.vomit(EffectRules.strengths(a, d), d).is_empty() and EffectRules.vomit(EffectRules.strengths(four, d), d).is_empty())
	var k := EffectRules.add({}, "baked", 1.0, d)
	k = EffectRules.add(k, "baked", 1.0, d)
	var k2: float = EffectRules.strengths(k, d).baked
	for i in 5:
		k = EffectRules.add(k, "baked", 1.0, d)
	_check("kush compounds: 2 joints %.2f, capped at %.2f, %.0f s" % [k2, EffectRules.strengths(k, d).baked, k.baked.left],
		is_equal_approx(k2, 1.5) and is_equal_approx(float(EffectRules.strengths(k, d).baked), 2.0) and is_equal_approx(float(k.baked.left), 900.0))
	var mods := EffectRules.mods(EffectRules.strengths(k, d), d)
	_check("triple-baked takes %.2fx damage (one joint 0.80x)" % mods.damage_taken, float(mods.damage_taken) < 0.8)
	var rec := DiscRecordsRules.hole_done({}, "a", "Bonk", 0, 2, 9)
	rec = DiscRecordsRules.hole_done(rec, "a", "Bonk", 0, 3, 9)
	rec = DiscRecordsRules.hole_done(rec, "b", "Evan", 4, 1, 9)
	rec = DiscRecordsRules.round_done(rec, "a", "Bonk", 26, 9)
	rec = DiscRecordsRules.round_done(rec, "b", "Evan", 24, 9)
	var course: Dictionary = DiscGolfRules.courses().centennial
	var text := DiscRecordsRules.board_text(rec, course)
	_check("records: best hole kept (2), ace listed, rounds ranked", int(rec.a.holes[0]) == 2 and text.contains("Evan: 5")
		and text.find("1. Evan") < text.find("2. Bonk") and text.contains("1. Evan  24 (-3)"))
	var rng := RandomNumberGenerator.new()
	var t := DiscFlightRules.tuning()
	var sober := DiscGolfRules.impaired_throw(0.7, 0.3, 0.0, 0.0, rng, t)
	var spread := 0.0
	for i in 50:
		var o := DiscGolfRules.impaired_throw(0.7, 0.3, 0.0, 0.8, rng, t)
		spread = maxf(spread, absf(o.y - 0.3))
	_check("sober throws go where aimed; drunk ones up to %.1f deg off" % rad_to_deg(spread), sober == Vector3(0.7, 0.3, 0.0) and spread > deg_to_rad(2.0) and spread <= deg_to_rad(9.0))
	var items := {}
	for id: String in ["water_bottle", "beer_platte_light", "seltzer_lime"]:
		items[id] = ItemDB.get_item(id)
	_check("quick drink takes water over beer", SurvivalRules.quick_pick("eat", {"beer_platte_light": 2, "water_bottle": 1}, items, Vector2(100, 10)) == "water_bottle")
	_check("quick drink never takes booze", SurvivalRules.quick_pick("eat", {"beer_platte_light": 2, "seltzer_lime": 1}, items, Vector2(100, 10)) == "")
	var st := SurvivalRules.tuning()
	_check("hunger 3 h, thirst 2 h", is_equal_approx(float(st.hunger_minutes_to_empty), 180.0) and is_equal_approx(float(st.thirst_minutes_to_empty), 120.0))


# Nearest Cottonmill Lake shore point (water.json override lake) to `near`.
func _shore_point(near: Vector2) -> Vector2:
	var pts: Array = DataLoader.load_json("res://data/map/water.json").overrides[0].lakes[0]
	var best := Vector2.ZERO
	var best_d := INF
	for p: Array in pts:
		var v := Vector2(float(p[0]), float(p[1]))
		if v.distance_to(near) < best_d:
			best_d = v.distance_to(near)
			best = v
	return best


func _lake_centre() -> Vector2:
	var pts: Array = DataLoader.load_json("res://data/map/water.json").overrides[0].lakes[0]
	var c := Vector2.ZERO
	for p: Array in pts:
		c += Vector2(float(p[0]), float(p[1]))
	return c / pts.size()


func _over_water(p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 30.0, p + Vector3.DOWN * 30.0, 32)
	return not get_viewport().get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _ground_y(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 200.0, p.z), Vector3(p.x, p.y - 200.0, p.z), 1)
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
	return float(hit.position.y) if not hit.is_empty() else p.y


func _ground_gap(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 50.0, p.z), Vector3(p.x, p.y - 50.0, p.z), 1)
	var dg: DiscGolfDirector = get_tree().get_first_node_in_group("disc_golf")
	q.exclude = dg.course_node("centennial").body_rids()
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
	return p.y - float(hit.position.y) if not hit.is_empty() else 99.0


func _stand(player: Node3D, at: Vector3, look_at_pos: Vector3) -> void:
	var d := look_at_pos - at
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.yaw = atan2(-d.x, -d.z)
	player.rotation.y = player.yaw
	player.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	player.head.rotation.x = player.pitch


func _perf(where: String) -> void:
	await RenderingServer.frame_post_draw
	_say("perf at the %s: %.1f ms frame, %d draw calls, %d objects, %.0f MB static mem" % [where,
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
	print("BIGUPDATE: " + s)
	_log.append(s)
