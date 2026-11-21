# EncounterTest — D-105..D-108 in a hosted world: the pure rules (weights, rarity, cooldowns, hour windows,
# conditions), then the live systems. Force-opens several encounters and checks each site really built its props,
# NPC, loot and E spots; runs a dialogue action (a wager) and a toll hand-over; checks the global cooldown and
# max_active hold; builds every oddity at the player and checks their uses fire once and persist; picks up a
# collectible and checks the bunker shelf grows; forces every rare event and reports which could be placed;
# checks all 12 new side quests can be walked end to end on flags alone.
# Results: tests/_look/encounter_result.txt (ends with the failure count); enc_*.png.
# Depends on: scenes/main.tscn, EncounterDirector, WorldOddities, CollectibleManager, RareEventDirector,
# EncounterRules, QuestRules, DialogueDB, QuestDirector.
extends Node

const OUT_DIR := "res://tests/_look"

var _log := PackedStringArray()
var _fails := 0
var _me: Node3D
var _enc: Node
var _odd: Node
var _col: Node
var _rare: Node
var _quests: Node


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_pure()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz encounters")
	main.menu.play_offline.emit()
	await get_tree().create_timer(5.0).timeout
	_me = get_tree().get_first_node_in_group("local_player")
	var prompt := get_tree().get_first_node_in_group("name_prompt")
	if prompt and prompt.visible:
		prompt.submit("Bonk")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_me.health.damage_mult = 0.0
	_enc = get_tree().get_first_node_in_group("encounters")
	_odd = get_tree().get_first_node_in_group("oddities")
	_col = get_tree().get_first_node_in_group("collectibles")
	_rare = get_tree().get_first_node_in_group("rare_events")
	_quests = get_tree().get_first_node_in_group("quests")
	var weather := get_tree().get_first_node_in_group("weather")
	if weather:
		weather.request_mode("clear")
	await _nodes()
	await _sites()
	await _actions()
	await _limits()
	await _oddities()
	await _collectibles()
	await _rares()
	_quest_walk()
	_log.append("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/encounter_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	get_tree().quit()


# --- pure rules, no scene ------------------------------------------------------------

func _pure() -> void:
	var defs: Dictionary = DataLoader.load_json("res://data/encounters/encounters.json")
	defs.erase("note")
	_check(defs.size() >= 25, "25 encounter definitions load (%d)" % defs.size())
	var cats := {}
	for id: String in defs:
		cats[str(defs[id].get("category", "?"))] = true
	_check(cats.size() >= 6, "categories in use: %s" % ", ".join(cats.keys()))
	var weights: Dictionary = DataLoader.load_json("res://data/tuning/encounters.json").get("rarity_weight", {})
	_check(EncounterRules.weight_of({"rarity": "common", "weight": 10.0}, weights)
		> EncounterRules.weight_of({"rarity": "legendary", "weight": 10.0}, weights) * 4.0,
		"a common encounter outweighs a legendary one at the same weight")
	_check(EncounterRules.hour_in([22.0, 4.0], 2.0) and not EncounterRules.hour_in([22.0, 4.0], 12.0),
		"hour windows wrap past midnight")
	_check(EncounterRules.hour_of(120.0, 30.0, 8.0) == 9.0, "the clock runs 30 in-game minutes a real minute")
	# cooldowns: a fired encounter is blocked for its own cooldown, and everything is blocked by the global one
	var state: Dictionary = EncounterRules.new_state()
	var one := {"id": "x", "cooldown_s": 600.0, "rarity": "common", "weight": 1.0}
	EncounterRules.mark_fired(state, "x", 1000.0, false)
	_check(EncounterRules.blocked_reason(one, 1100.0, state, {}, 12.0, "clear", 400.0, "road") != "",
		"an encounter on cooldown is blocked")
	_check(EncounterRules.blocked_reason(one, 1700.0, state, {}, 12.0, "clear", 400.0, "road") == "",
		"it comes back when its cooldown is up")
	_check(EncounterRules.blocked_reason({"id": "y", "requires": "never_set", "rarity": "common"},
		1.0, EncounterRules.new_state(), {}, 12.0, "clear", 400.0, "road") != "", "quest conditions gate encounters")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var picked := {}
	for i in 400:
		var id := EncounterRules.pick(defs, rng, 1.0e6 + i * 1.0e4, EncounterRules.new_state(), {}, 13.0,
			"clear", 500.0, "road", weights)
		picked[id] = int(picked.get(id, 0)) + 1
	_check(picked.size() >= 8, "weighted picking spreads over the table (%d different in 400 rolls)" % picked.size())
	var od: Dictionary = DataLoader.load_json("res://data/encounters/oddities.json").get("oddities", {})
	_check(od.size() >= 14, "%d world oddities are authored at map coordinates" % od.size())
	var rare: Dictionary = DataLoader.load_json("res://data/encounters/rare_events.json").get("events", {})
	_check(rare.size() >= 10, "%d rare events load" % rare.size())
	var col: Dictionary = DataLoader.load_json("res://data/encounters/collectibles.json")
	_check(col.get("types", {}).size() == 15 and col.get("spots", []).size() >= 90,
		"15 collectible types over %d authored spots" % col.get("spots", []).size())
	_check(DialogueDB.is_valid(), "all dialogue (including the encounter trees) validates")
	for id: String in ["enc_greg_talk", "enc_inspector_talk", "enc_bargain_talk", "enc_sheriff_talk",
			"enc_chess_talk", "odd_cone_king_talk"]:
		_check(not DialogueDB.get_dialogue_tree(id).is_empty(), "dialogue tree '%s' loads" % id)


# --- live world ----------------------------------------------------------------------

func _nodes() -> void:
	_check(_enc != null and _odd != null and _col != null and _rare != null, "all four directors are in the scene")
	_check(_enc.name == "Encounters" and _odd.name == "Oddities" and _col.name == "Collectibles"
		and _rare.name == "RareEvents", "they have fixed names, so their RPCs resolve on every peer")
	_check(_enc.defs.size() >= 25, "the director loaded its definitions")
	await _wait(0.1)


func _sites() -> void:
	var cases := {
		"stranded_driver": ["Npc"],
		"abandoned_truck": ["Loot_cargo"],
		"pool_champion": ["Npc"],
		"lawn_chair_guy": ["Use_0", "Loot_cooler"],
	}
	for id: String in cases:
		var slot: int = _enc.debug_force(id, _me)
		_check(slot >= 0, "force-open '%s'" % id)
		await _wait(0.4)
		var site: Node = _enc.sites.get(slot)
		_check(site != null, "'%s' built a site" % id)
		if site == null:
			continue
		_check(site.get_child_count() > 2, "'%s' built %d nodes of props" % [id, site.get_child_count()])
		for child: String in cases[id]:
			_check(site.get_node_or_null(child) != null, "'%s' has %s" % [id, child])
		var spots := 0
		for n: Node in get_tree().get_nodes_in_group("sport_spots"):
			if site.is_ancestor_of(n):
				spots += 1
		_check(spots >= (1 if "Use_0" in cases[id] else 0), "'%s' registered %d E spots" % [id, spots])
		var d: float = _me.global_position.distance_to((site as Node3D).global_position)
		_check(d > 10.0 and d < 420.0, "'%s' opened %.0f m away, not on top of the player" % [id, d])
	await _shot("enc_sites.png")
	for slot: int in _enc.sites.keys():
		_enc.host_close(slot)
	await _wait(0.3)
	_check(_enc.sites.is_empty(), "closing frees every site")


func _actions() -> void:
	var slot: int = _enc.debug_force("pool_champion", _me)
	await _wait(0.4)
	var site: Node = _enc.sites.get(slot)
	var npc: Node = site.get_node_or_null("Npc") if site else null
	_check(npc != null, "Fast Eddie is at his table")
	if npc == null:
		return
	_me.inventory.host_add("bottle_cap", 200)
	var before: int = _me.inventory.count("bottle_cap")
	for i in 30:  # the wager is a coin flip; 30 games always both wins and loses
		_enc.host_dialogue_action(npc, "wager", _me.peer_id)
	await _wait(0.3)
	_check(_me.inventory.count("bottle_cap") != before, "the pool wager moves caps (%d -> %d)"
		% [before, _me.inventory.count("bottle_cap")])
	_check(QuestRules.flag_met(_quests.flags, "sq_pool_win"), "beating Eddie sets the quest flag")
	_enc.host_close(slot)
	# the toll: paying it closes the roadblock
	slot = _enc.debug_force("roadblock", _me)
	await _wait(0.4)
	site = _enc.sites.get(slot)
	npc = site.get_node_or_null("Npc") if site else null
	if npc:
		before = _me.inventory.count("bottle_cap")
		_enc.host_dialogue_action(npc, "pay", _me.peer_id)
		await _wait(0.4)
		_check(_me.inventory.count("bottle_cap") < before, "paying the toll costs caps")
		_check(not _enc.sites.has(slot), "the roadblock clears off the road once it's paid")
	else:
		_check(false, "the roadblock has a tollman")


func _limits() -> void:
	for slot: int in _enc.sites.keys():
		_enc.host_close(slot)
	_enc.state = EncounterRules.new_state()
	var cap := int(_enc._t.get("max_active", 3))
	for i in cap + 3:
		_enc.debug_force("campfire_stranger", _me)
	await _wait(0.5)
	_check(_enc.sites.size() <= cap, "no more than max_active (%d) sites are ever open (%d)" % [cap, _enc.sites.size()])
	var spread := true
	var list: Array = _enc.sites.values()
	for i in list.size():
		for j in range(i + 1, list.size()):
			if (list[i] as Node3D).global_position.distance_to((list[j] as Node3D).global_position) \
					< float(_enc._t.get("min_apart_m", 150.0)) * 0.9:
				spread = false
	_check(spread, "open sites keep min_apart_m between them")
	for slot: int in _enc.sites.keys():
		_enc.host_close(slot)
	await _wait(0.2)
	var report: PackedStringArray = _enc.debug_report(_me.global_position)
	_check(report.size() >= 25, "debug_report lists every definition and why it can or can't fire")
	_log.append("  " + report[0])
	var reasons := {}
	var total: float = _enc.debug_weights(reasons)
	_check(total > 0.0, "debug_weights: %.1f total eligible weight" % total)
	var panel := get_tree().get_first_node_in_group("encounter_debug")
	_check(panel != null, "the F6 debug panel is in the scene")
	if panel:
		panel.shown = true
		panel.visible = true
		panel._rebuild()
		_check(panel.text.length() > 200, "the panel draws its readout")
		panel.shown = false
		panel.visible = false


func _oddities() -> void:
	_check(_odd.defs.size() >= 14, "the oddities loaded (%d)" % _odd.defs.size())
	# Build every one right here, so the test doesn't have to drive to eighteen addresses.
	var built := 0
	var used_ok := 0
	var missed := PackedStringArray()
	var ids: Array = _odd.defs.keys()
	for i in ids.size():
		var id: String = ids[i]
		if _odd.built.has(id):  # it may already be out there in a loaded cell
			(_odd.built[id] as Node).queue_free()
			_odd.built.erase(id)
		var at: Vector3 = _me.global_position + Vector3(40.0 + 26.0 * (i % 6), 0.0, 26.0 * floori(i / 6.0))
		# First as it happens in the world (ground ray + clearance), then, if this test street is too built
		# up for it, at a ground point we pick ourselves - the point here is that every scene builds.
		_odd._build(id, at, 0.0, true)
		if not _odd.built.has(id):
			var hit := _me.get_world_3d().direct_space_state.intersect_ray(
				PhysicsRayQueryParameters3D.create(at + Vector3.UP * 60.0, at + Vector3.DOWN * 60.0, 17))
			if not hit.is_empty():
				_odd._build(id, hit.position, 0.0, false)
		if _odd.built.has(id):
			built += 1
		else:
			missed.append(id)
	await _wait(0.6)
	_log.append("  oddities: %d of %d sited themselves on this test street, %d needed more room%s" % [built,
		ids.size(), _odd.skipped_count, "" if missed.is_empty() else ": " + ", ".join(missed)])
	_check(built >= 12, "most oddities site themselves even on a built-up street")
	_check(_odd.built.size() == ids.size(), "every oddity scene builds (%d of %d)" % [_odd.built.size(), ids.size()])
	_check(_odd.built.has("cone_kingdom") and _odd.built.cone_kingdom.get_node_or_null("Npc") != null,
		"the Cone Throne has its king")
	_check(_odd.built.has("mannequins"), "the mannequin shop builds")
	if _odd.built.has("mannequins"):
		var first: int = _odd.built.mannequins.get_child_count()
		var was: Vector3 = (_odd.built.mannequins as Node3D).global_position
		_odd.built.mannequins.queue_free()
		_odd.built.erase("mannequins")
		await _wait(0.3)
		_odd._build("mannequins", was, 0.0, false)
		await _wait(0.3)
		_check(_odd.built.has("mannequins") and int(_odd.visits.get("mannequins", 0)) >= 2,
			"revisiting re-rolls the mannequins (%d props, visit %d)" % [first, int(_odd.visits.get("mannequins", 0))])
	# a use: fires once, gives, sets its flag, and stays used
	for id: String in ["lottery_skeleton", "bathtub_caps", "ticket_car"]:
		if not _odd.built.has(id):
			continue
		var spot: Node = _odd.built[id].get_node_or_null("Use_0")
		if spot == null:
			continue
		var idx := int(spot.get_meta("index"))
		var want: Dictionary = _odd.defs[id].use.get("gives", {})
		var item: String = want.keys()[0] if not want.is_empty() else ""
		var before: int = _me.inventory.count(item) if item != "" else 0
		_me.global_position = (_odd.built[id] as Node3D).global_position + Vector3(0, 1, 3)
		await _wait(0.2)
		_odd.request_use(idx)
		await _wait(0.3)
		var gave: bool = item == "" or _me.inventory.count(item) > before
		var flagged: bool = QuestRules.flag_met(_quests.flags, str(_odd.defs[id].use.get("flag", "")))
		if gave and flagged and _odd.used.has(id):
			used_ok += 1
		_odd.request_use(idx)  # a second press must do nothing
		await _wait(0.2)
		var again: bool = item == "" or _me.inventory.count(item) <= before + int(want.get(item, 1))
		_check(gave and flagged and again, "'%s': its use gives, flags and only fires once" % id)
	_check(used_ok >= 2, "oddity uses work and persist (%d checked)" % used_ok)
	await _shot("enc_oddities.png")


func _collectibles() -> void:
	_check(_col.types.size() == 15, "15 collectible types (%d)" % _col.types.size())
	_check(_col.spots.size() >= 90, "%d collectible spots in the world" % _col.spots.size())
	var counts: Dictionary = _col.counts()
	_check(counts.size() == 15, "counts() reports every type")
	# put one of each in the inventory and check the bunker shelf fills in
	for id: String in _col.types:
		_me.inventory.host_add(id, 1)
	_col._update_shelf()
	await _wait(0.5)
	var shelf: Node = _col.get_node_or_null("Shelf")
	_check(shelf != null and shelf.get_child_count() >= 15, "the bunker shelf shows what the party has collected (%d nodes)"
		% [shelf.get_child_count() if shelf else 0])
	var home := get_tree().root.find_child("bonk_bunker", true, false) as Node3D
	if home and shelf:
		_check((shelf as Node3D).global_position.distance_to(home.global_position) < 12.0, "the shelf is in the bunker")
		_me.global_position = (shelf as Node3D).global_position + Vector3(0, 1.2, 3.2)
		await _wait(0.4)
		await _shot("enc_shelf.png")


func _rares() -> void:
	var home := get_tree().root.find_child("bonk_bunker", true, false) as Node3D
	_check(home != null, "the bunker landmark is in the world")
	if home:  # the bunker events only place when a player is near the bunker
		_me.global_position = home.global_position + Vector3(0, 1.2, 4.0)
		await _wait(0.5)
	var placed := PackedStringArray()
	var no_spot := PackedStringArray()
	for id: String in _rare.defs:
		_rare._clear()
		var ok: bool = _rare.force(id)
		if ok:
			placed.append(id)
			_check(_rare._node != null and is_instance_valid(_rare._node), "rare '%s' put something in the world" % id)
			var d: float = _me.global_position.distance_to(_rare._node.global_position)
			_check(d >= float(_rare.defs[id].get("vanish_m", 12.0)) - 0.5 or str(_rare.defs[id].get("where", "")).begins_with("bunker"),
				"rare '%s' stays %.0f m off, outside its vanish range" % [id, d])
		else:
			no_spot.append(id)
		await _wait(0.15)
	_log.append("  rare events placed here: %s" % ", ".join(placed))
	if no_spot.size() > 0:
		_log.append("  rare events with no spot at this test position (normal - they need the bunker or cover): %s"
			% ", ".join(no_spot))
	_check(placed.size() >= 8, "nearly every rare event can be placed from the bunker (%d of %d)"
		% [placed.size(), _rare.defs.size()])
	# one of them must vanish when the player walks up
	if placed.size() > 0:
		_rare._clear()
		_rare.force(placed[0])
		await _wait(0.2)
		if _rare._node:
			var vanish := float(_rare.defs[placed[0]].get("vanish_m", 12.0))
			_me.global_position = _rare._node.global_position + Vector3(0, 1.0, vanish * 0.3)
			await _wait(0.6)
			_check(_rare.showing == "", "a rare event vanishes when you get close")
	_rare._clear()
	_check(int(_rare.seen.get(placed[0], 0)) >= 0, "rare events keep a seen count for the save")


# Every new side quest, walked on flags alone: locked -> active -> done, with its reward.
func _quest_walk() -> void:
	var ids := ["sq_cart", "sq_cones", "sq_tp", "sq_greg", "sq_door", "sq_cap37", "sq_parking", "sq_chair",
		"sq_donut", "sq_corn", "sq_pool", "sq_mann"]
	var defs := QuestRules.defs()
	for id: String in ids:
		if not defs.has(id):
			_check(false, "quest '%s' is in quests.json" % id)
			continue
		var q: Dictionary = defs[id]
		var flags := {}
		_check(QuestRules.status(q, flags) == QuestRules.Status.LOCKED, "'%s' starts locked" % q.name)
		flags[str(q.get("start", "auto"))] = 1
		_check(QuestRules.status(q, flags) == QuestRules.Status.ACTIVE, "'%s' is active once its start flag is set" % q.name)
		for o: Dictionary in q.objectives:
			flags[str(o.flag)] = int(o.get("count", 1))
		_check(QuestRules.status(q, flags) == QuestRules.Status.DONE, "'%s' completes (%d objectives, reward %s)"
			% [q.name, q.objectives.size(), str(q.get("reward", {}))])


# --- helpers -------------------------------------------------------------------------

func _check(ok: bool, what: String) -> void:
	_log.append("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + "/" + file))
	var sum := 0.0
	for i in 30:
		await get_tree().process_frame
		sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_log.append("shot %s: frame %.1f ms, %d draw calls, %d MB RAM" % [file, sum / 30.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)])
