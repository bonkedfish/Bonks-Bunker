# ActStoryTest — D-101..D-104 in a hosted world: safe zones (spawn checks, a zombie inside walks out, players inside
# aren't targeted), the Act 1 finale (Collection Day: escort + Handler wake at the Cash-Wa dock, kills count, the
# Handler drops the manifest, carrying it sets the flag, handing it to Gus ends Act 1, Gus moves to the elevator),
# Act 2 chapter 1 (yard crew, logbook, the hatch reach, Gus), and the Suit watcher (appears 60-120 m away for the
# local player only, vanishes up close). Screenshots of both landmarks and the watcher; frame time at each.
# Results: tests/_look/act_story_result.txt (ends with the failure count); act_*.png.
# Depends on: scenes/main.tscn, QuestDirector, LairDirector, ZombieDirector, SafeZones, SuitWatcher, WorldDrops.
extends Node

const OUT_DIR := "res://tests/_look"
const ZombieScript := preload("res://scripts/ai/zombie.gd")
const ACT1 := ["mq1_static", "mq2_collector", "mq3_detention", "mq4_acknowledged"]

var _log := PackedStringArray()
var _fails := 0
var _me: Node3D
var _quests: Node
var _lairs: Node


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_pure()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz act story")
	main.menu.play_offline.emit()
	await get_tree().create_timer(5.0).timeout
	_me = get_tree().get_first_node_in_group("local_player")
	var prompt := get_tree().get_first_node_in_group("name_prompt")
	if prompt and prompt.visible:
		prompt.submit("Bonk")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_me.health.damage_mult = 0.0
	_quests = get_tree().get_first_node_in_group("quests")
	_lairs = get_tree().get_first_node_in_group("lair_director")
	var weather := get_tree().get_first_node_in_group("weather")
	if weather:
		weather.request_mode("clear")
	for n: Node in get_tree().get_nodes_in_group("players"):  # park Bonk: he'd fight the escort for us
		if n != _me and n.get_script() and str(n.get_script().resource_path).ends_with("bonk.gd"):
			n.global_position += Vector3(0, 400, 0)
			n.process_mode = Node.PROCESS_MODE_DISABLED
	await _safe_zones()
	await _act1()
	await _act2()
	await _watcher()
	_log.append("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/act_story_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	get_tree().quit()


func _pure() -> void:
	var defs := QuestRules.defs()
	_check(defs.has("mq4b_collection") and defs.has("mq5_south") and defs.has("mq5b_halvorsen"), "quests: Collection Day, South of the Tracks, Halvorsen outline load")
	_check(str(defs.mq5_south.start) == "mq4b_collection_done" and str(defs.mq6_soup.start) == "mq5b_halvorsen_done", "quest chain: Collection Day -> Act 2 -> Halvorsen -> S.O.U.P.")
	_check(DialogueDB.is_valid() and not DialogueDB.get_dialogue_tree("gus_elevator").is_empty(), "dialogue valid, Gus has an elevator tree")
	for id: String in ["suit_retriever", "suit_guard", "suit_handler"]:
		_check(not EnemyDB.get_enemy(id).is_empty(), "enemy '%s' loads" % id)
	var r := Rect2(0, 0, 10, 10)
	_check(SafeZoneRules.inside(Vector2(-50, 5), r, 60.0) and not SafeZoneRules.inside(Vector2(-75, 5), r, 60.0)
		and SafeZoneRules.exit_point(Vector2(-50, 5), r, 60.0).x < -60.0, "safe zone rules: 60 m buffer, exit point outside it")


func _flags_through(ids: Array) -> Dictionary:
	var flags := {}
	for id: String in ids:
		for o: Dictionary in QuestRules.defs()[id].objectives:
			flags[str(o.flag)] = int(o.get("count", 1))
	return flags


func _lm(key: String) -> Node3D:
	return get_tree().root.find_child(key, true, false) as Node3D


func _go(at: Vector3) -> void:
	_me.global_position = at + Vector3.UP * 40.0
	_me.velocity = Vector3.ZERO
	await get_tree().create_timer(4.0).timeout
	var hit := _me.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 60.0, at + Vector3.DOWN * 60.0, 17))
	_me.global_position = ((hit.position as Vector3) if not hit.is_empty() else at) + Vector3.UP * 0.3
	_me.velocity = Vector3.ZERO
	await get_tree().create_timer(2.0).timeout


func _look_at(target: Vector3) -> void:
	var to := target - _me.global_position
	_me.yaw = atan2(-to.x, -to.z)
	_me.rotation.y = _me.yaw
	_me.pitch = clampf(atan2(to.y - 1.6, Vector2(to.x, to.z).length()), -1.2, 1.2)
	_me.head.rotation.x = _me.pitch


func _shot(file: String) -> void:
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR + "/" + file))
	var sum := 0.0
	for i in 30:
		await get_tree().process_frame
		sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_log.append("shot %s: frame %.1f ms, %d draw calls" % [file, sum / 30.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])


func _active(prefix: String) -> Array:
	var out: Array = []
	for z in _lairs.get("_pool"):
		if z.net_active and not z.health.is_dead() and str(z.net_enemy).begins_with(prefix):
			out.append(z)
	return out


func _safe_zones() -> void:
	var safe := get_tree().get_first_node_in_group("safe_zones")
	var zd := get_tree().get_first_node_in_group("zombie_director")
	_check(safe != null, "SafeZones node exists")
	if safe == null:
		return
	var cent := Vector3((895.0 + 1192.0) * 0.5, 0, (-528.0 - 292.0) * 0.5)
	var club := _lm("country_club")
	_check(safe.contains(cent) and safe.contains(cent + Vector3(0, 0, 150)) and not safe.contains(cent + Vector3(0, 0, 400)),
		"Centennial: inside, inside 30 m past its edge, outside 150 m past it")
	_check(club != null and safe.contains(club.global_position) and safe.contains(club.global_transform * Vector3(-640, 0, 0)),
		"Country Club: the clubhouse and 40 m past the west edge of the course are safe")
	_check(not safe.contains(_lm("bonk_house").global_position), "Bonk's house is not a safe zone")
	_check(not bool(zd.call("_spawn_ok", cent, [], _me.get_world_3d().direct_space_state)), "street zombies never spawn on a course")
	# a zombie dropped inside Centennial walks out, and doesn't target a player there
	await _go(cent)
	var z: Node = null
	for b in zd.get("_pool"):
		if not b.net_active:
			z = b
			break
	z.net_enemy = "zombie_shambler"
	z.activate(_me.global_position + Vector3(4, 0, 0))
	await get_tree().create_timer(1.5).timeout
	var exit: Vector3 = safe.exit_point(cent)
	_check(not bool(z.get("_sees_target")) and Vector2(z.nav.target_position.x - exit.x, z.nav.target_position.z - exit.z).length() < 200.0
		and not safe.contains(z.nav.target_position), "a zombie inside a course ignores the player there and heads out (%s)" % str(z.nav.target_position.round()))
	z.deactivate()


func _act1() -> void:
	_quests.host_load_state(_flags_through(ACT1))
	await get_tree().physics_frame
	_check(QuestRules.status(QuestRules.defs().mq4b_collection, _quests.flags) == QuestRules.Status.ACTIVE, "after Gus, Collection Day is active")
	var cp := _lm("collection_point")
	_check(cp != null, "the collection point landmark is placed")
	if cp == null:
		return
	await _go(cp.global_transform * Vector3(15, 0, 22))
	await get_tree().create_timer(2.0).timeout
	var esc := _active("suit_")
	_log.append("collection point: %d suits awake: %s" % [esc.size(), str(esc.map(func(e): return e.net_enemy))])
	_check(esc.size() == 7, "the escort (6 Retrievers) and the Handler wake at the dock")
	_check(QuestRules.flag_met(_quests.flags, "cd_reach"), "reaching the dock ticks the first objective")
	_look_at(cp.global_transform * Vector3(45, 2, 0))
	ZombieScript.frozen = true
	await _shot("act_collection_point.png")
	var drops := get_tree().get_first_node_in_group("world_drops")
	var before: int = drops.drops.size()
	for e: Node in esc:
		e.health.apply_damage(99999.0, _me.peer_id)
	await get_tree().create_timer(1.5).timeout
	ZombieScript.frozen = false
	_check(int(_quests.flags.get("kills_suit_retriever", 0)) >= 6 and QuestRules.flag_met(_quests.flags, "boss_suit_handler_dead"),
		"6 Retriever kills counted and the Handler's death flagged")
	var manifest := false
	for id in drops.drops:
		if str(drops.drops[id][0]) == "collection_manifest":
			manifest = true
	_check(manifest and drops.drops.size() > before, "the Handler drops the collection manifest")
	_me.inventory.host_add("collection_manifest", 1)
	await get_tree().create_timer(1.0).timeout
	_check(QuestRules.flag_met(_quests.flags, "cd_have_manifest"), "carrying the manifest ticks its objective")
	var gus_tree := DialogueDB.get_dialogue_tree("gus_talk")
	_check(gus_tree.nodes.has("manifest_2") and str(gus_tree.nodes.manifest_3.get("flag", "")) == "cd_gus", "Gus has the manifest hand-in (cost) ending in cd_gus")
	_quests.host_set_flag("cd_gus")
	await get_tree().create_timer(1.0).timeout
	_check(QuestRules.flag_met(_quests.flags, "mq4b_collection_done"), "handing it to Gus finishes Act 1")
	_check(QuestRules.status(QuestRules.defs().mq5_south, _quests.flags) == QuestRules.Status.ACTIVE, "Act 2: South of the Tracks starts")
	await get_tree().create_timer(2.0).timeout
	_check(_active("suit_retriever").is_empty(), "the escort doesn't come back once Act 1 is done")


func _act2() -> void:
	var el := _lm("coop_elevator")
	_check(el != null, "the co-op elevator landmark is placed")
	if el == null:
		return
	await _go(el.global_transform * Vector3(0, 0, 22))
	var gus := el.find_child("GusElevator", true, false)
	_check(gus != null and not bool(gus.get("_hidden")), "Gus waits on the scale house porch")
	var home_gus := _lm("chillers_hq").find_child("Gus", true, false) if _lm("chillers_hq") else null
	_check(home_gus == null or bool(home_gus.get("_hidden")), "Gus has left the Chillers' fire")
	_quests.host_set_flag("a2_gus_elevator")
	await get_tree().create_timer(2.0).timeout
	var guards := _active("suit_guard")
	_check(guards.size() == 5, "the 5-man yard crew wakes (%d)" % guards.size())
	_look_at(el.global_transform * Vector3(0, 14, -8))
	ZombieScript.frozen = true
	await _shot("act_elevator.png")
	for g: Node in guards:
		g.health.apply_damage(99999.0, _me.peer_id)
	await get_tree().create_timer(1.5).timeout
	ZombieScript.frozen = false
	_check(int(_quests.flags.get("kills_suit_guard", 0)) >= 5, "yard crew kills counted")
	var desk := el.find_child("Loot_scale_desk", true, false)
	_check(desk != null and str(desk.loot_table) == "a2_logbook" and LootRules.roll(LootDB.get_table("a2_logbook"), RandomNumberGenerator.new()).has("elevator_logbook"),
		"the scale house desk holds the logbook")
	_me.inventory.host_add("elevator_logbook", 1)
	await get_tree().create_timer(1.0).timeout
	_check(QuestRules.flag_met(_quests.flags, "a2_have_logbook"), "carrying the logbook ticks its objective")
	_me.global_position = el.global_transform * Vector3(0, 0.4, 6.5)  # inside the shed (a drop from above lands on its roof)
	_me.velocity = Vector3.ZERO
	_look_at(el.global_transform * Vector3(0, -1.0, 4.0))
	await get_tree().create_timer(1.0).timeout
	_check(QuestRules.flag_met(_quests.flags, "a2_hatch_seen"), "standing at the grate ticks 'look down through the floor'")
	await _shot("act_hatch.png")
	_quests.host_set_flag("a2_ch1_gus")
	await get_tree().create_timer(1.0).timeout
	_check(QuestRules.flag_met(_quests.flags, "mq5_south_done") and QuestRules.status(QuestRules.defs().mq5b_halvorsen, _quests.flags) == QuestRules.Status.LOCKED,
		"Act 2 chapter 1 done; Halvorsen's Notebook waits as an outline")


func _watcher() -> void:
	var w := get_tree().get_first_node_in_group("local_player")
	var watcher := get_tree().root.find_child("SuitWatcher", true, false)
	_check(watcher != null, "SuitWatcher node exists")
	if watcher == null:
		return
	await _go(_lm("bonk_house").global_transform * Vector3(0, 0, 40))
	var ok := false
	for i in 6:
		if watcher.appear_now():
			ok = true
			break
		_me.yaw += 1.0
		_me.rotation.y = _me.yaw
	_check(ok and watcher.showing, "he appears for the local player")
	if not ok:
		return
	var d := Vector2(watcher.global_position.x - w.global_position.x, watcher.global_position.z - w.global_position.z).length()
	_check(d >= 59.0 and d <= 121.0, "he stands 60-120 m away (%.0f m)" % d)
	_look_at(watcher.global_position + Vector3.UP * 1.6)
	await _shot("act_watcher.png")
	_check(watcher.call("_in_view", w), "looking at him: he's on screen with nothing in the way")
	var cam := get_viewport().get_camera_3d()
	var px: Vector2 = cam.unproject_position(watcher.global_position + Vector3.UP * 0.9)
	_log.append("watcher on screen at %s" % str(px.round()))
	_check(watcher.showing, "he stays while watched from afar")
	var to: Vector3 = (w.global_position - watcher.global_position)
	to.y = 0.0
	_me.global_position = watcher.global_position + to.normalized() * 30.0 + Vector3.UP * 0.3
	_look_at(watcher.global_position + Vector3.UP * 1.2)
	await get_tree().create_timer(1.0).timeout
	await _shot("act_watcher_30m.png")
	_me.global_position = watcher.global_position + Vector3(12, 0.3, 0)
	await get_tree().create_timer(0.5).timeout
	_check(not watcher.showing, "he vanishes when the player gets within 25 m")


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	_log.append(("PASS " if ok else "FAIL ") + what)
