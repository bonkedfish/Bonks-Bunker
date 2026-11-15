# GearTest — armor, weapons, mods and rarity (D-087) and the Golden Ace (D-088).
# Pure: data loads; roll odds follow rarity.json weights; legendaries roll a perk; the Golden Ace is always
# legendary; weapon_stats applies rarity, condition and mods; equip slots (auto-equip, wrong slot refused, remove
# unequips, save round trip); armor resistance adds up and caps; armor wear; repair cost.
# In game (offline world, god mode): the starting kit is a rolled pistol (full mag) + bat; a shotgun goes to slot 2
# and one blast hits a training dummy with several pellets; Kevlar cuts a 50 damage hit and wears; an extended mag
# goes on at the workbench (6 -> 9 rounds) and a repair costs scrap; the Golden Ace hits the dummy and comes back;
# a dropped gun keeps its roll when picked up; the save holds the gear; an old save's weapon counts become gear.
# Screenshots tests/_look/gear_*.png. Results: tests/_look/gear_result.txt (ends with the failure count).
# Depends on: scenes/main.tscn, scenes/training_dummy.tscn, GearRules, Inventory, WeaponDB, ItemDB, SaveStore.
extends Node

const OUT_DIR := "res://tests/_look"
const DUMMY := preload("res://scenes/training_dummy.tscn")

var _log := PackedStringArray()
var _fails := 0
var _me: Node3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_pure()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz gear")
	main.menu.play_offline.emit()
	await get_tree().create_timer(4.0).timeout
	_me = get_tree().get_first_node_in_group("local_player")
	var prompt := get_tree().get_first_node_in_group("name_prompt")
	if prompt and prompt.visible:
		prompt.submit("Bonk")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _game(main)
	_log.append("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/gear_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	get_tree().quit()


func _pure() -> void:
	var ids := ["pistol_9mm", "revolver_44", "smg_9mm", "shotgun_pump", "rifle_hunting", "rifle_ar", "rifle_sniper",
		"bat_baseball", "knife_combat", "axe_fire", "disc_golden_ace"]
	var ok := true
	for id: String in ids:
		ok = ok and WeaponDB.has_weapon(id) and ItemDB.has_item(id) and GearRules.is_gear(id)
	_check(ok and GearRules.is_armor("chest_kevlar") and GearRules.is_mod("mod_scope_4x"), "11 weapons, armor and mods load")
	var rng := RandomNumberGenerator.new()
	rng.seed = 87
	var counts := {"worn": 0, "standard": 0, "pristine": 0, "legendary": 0}
	var perks_ok := true
	for i in 4000:
		var g := GearRules.roll("rifle_ar", rng)
		counts[g.rarity] += 1
		if g.rarity == "legendary" and str(g.perk) == "":
			perks_ok = false
	_check(absf(counts.worn / 4000.0 - 0.5) < 0.03 and absf(counts.legendary / 4000.0 - 0.04) < 0.015 and perks_ok,
		"roll odds follow the weights, legendaries have a perk: %s" % counts)
	var ace := GearRules.roll("disc_golden_ace", rng)
	_check(ace.rarity == "legendary" and is_equal_approx(float(ace.cond), 1.0), "the Golden Ace always rolls legendary")
	var std := {"id": "pistol_9mm", "rarity": "standard", "cond": 1.0, "mods": [], "perk": ""}
	var worn := {"id": "pistol_9mm", "rarity": "worn", "cond": 0.35, "mods": [], "perk": ""}
	var smg := {"id": "smg_9mm", "rarity": "standard", "cond": 1.0, "mods": ["mod_ext_mag", "mod_suppressor"], "perk": ""}
	var ws := GearRules.weapon_stats(worn)
	var ms := GearRules.weapon_stats(smg)
	_check(is_equal_approx(float(GearRules.weapon_stats(std).damage), 25.0) and absf(float(ws.damage) - 15.725) < 0.01,
		"pistol damage 25 standard, %.2f worn at 35%%" % float(ws.damage))
	_check(int(ms.mag_size) == 45 and absf(float(ms.noise_radius) - 12.0) < 0.01 and GearRules.display_name(worn) == "Worn 9mm Pistol",
		"SMG + extended mag 45 rounds, suppressed noise %.0f m; names '%s'" % [float(ms.noise_radius), GearRules.display_name(worn)])
	_check(not GearRules.can_attach(smg, "mod_quick_mag") and GearRules.can_attach(smg, "mod_red_dot")
		and not GearRules.can_attach({"id": "shotgun_pump", "mods": []}, "mod_scope_4x"), "mod slots: one per slot, only slots the gun has")
	var inv := Inventory.new()
	var a := inv.add_gear({"id": "pistol_9mm", "rarity": "standard", "cond": 1.0, "mods": [], "perk": "", "mag": 0})
	var b := inv.add_gear({"id": "shotgun_pump", "rarity": "worn", "cond": 0.5, "mods": [], "perk": "", "mag": 0})
	var c := inv.add_gear({"id": "rifle_ar", "rarity": "worn", "cond": 0.5, "mods": [], "perk": "", "mag": 0})
	var d := inv.add_gear({"id": "axe_fire", "rarity": "worn", "cond": 0.5, "mods": [], "perk": "", "mag": 0})
	_check(int(inv.equip.gun1) == a and int(inv.equip.gun2) == b and not inv.equip.values().has(c) and int(inv.equip.melee) == d,
		"auto-equip: gun1, gun2, then the bag; melee")
	_check(not inv.equip_gear(c, "melee") and inv.equip_gear(c, "gun1") and int(inv.equip.gun1) == c, "a gun can't go in melee; swaps into gun1")
	inv.remove_gear(c)
	var copy := Inventory.new()
	copy.gear_from_dict(inv.gear_to_dict())
	_check(not inv.equip.has("gun1") and copy.gear.size() == 3 and int(copy.equip.gun2) == b and copy.next_uid == inv.next_uid,
		"remove unequips; gear survives a save round trip")
	var kevlar := {"id": "chest_kevlar", "rarity": "standard", "cond": 1.0, "perk": ""}
	var pieces := [{"id": "chest_kevlar", "rarity": "legendary", "cond": 1.0, "perk": "sturdy"}, {"id": "helmet_riot", "rarity": "legendary", "cond": 1.0, "perk": "sturdy"},
		{"id": "legs_riot", "rarity": "legendary", "cond": 1.0, "perk": "sturdy"}]
	var wear := GearRules.armor_wear([kevlar], 20.0)
	_check(is_equal_approx(GearRules.armor_dr(kevlar), 0.24) and is_equal_approx(GearRules.total_resist(pieces), 0.7)
		and absf(wear[0] - 0.94) < 0.001, "Kevlar blocks 24%%, a full legendary set caps at 70%%, 20 blocked -> Kevlar %.2f" % wear[0])
	_check(GearRules.repair_cost({"cond": 0.5}) == 3 and GearRules.repair_cost({"cond": 1.0}) == 0, "repair: half a bar = 3 scrap")


func _game(main: Node) -> void:
	var inv: InventoryHolder = _me.inventory
	var w: WeaponHolder = _me.weapons
	var gun1 := inv.equipped("gun1")
	var melee := inv.equipped("melee")
	_check(str(gun1.get("id", "")) == "pistol_9mm" and str(melee.get("id", "")) == "bat_baseball" and w.net_mag == 12
		and w.net_mesh == "Pistol", "starting kit: %s (mag %d) + %s" % [GearRules.display_name(gun1), w.net_mag, GearRules.display_name(melee)])
	_me.health.damage_mult = 0.0
	# Shotgun into slot 2, blast a dummy 4 m ahead.
	inv.host_add("shotgun_pump", 1)
	inv.host_add("ammo_shells", 12)
	var shotgun := inv.equipped("gun2")
	if not shotgun.is_empty():  # a known roll, so the mag mod always fits
		shotgun = {"uid": shotgun.uid, "id": "shotgun_pump", "rarity": "standard", "cond": 1.0, "mods": [], "perk": "", "mag": 0}
		inv.host_set_gears({int(shotgun.uid): shotgun})
	_check(str(shotgun.get("id", "")) == "shotgun_pump", "a looted shotgun goes to slot 2 (%s)" % GearRules.display_name(shotgun))
	for n in get_tree().get_nodes_in_group("players"):  # Bonk wanders the bunker: park him out of the line of fire
		if n != _me:
			n.process_mode = Node.PROCESS_MODE_DISABLED
			n.global_position += Vector3(0, 0, 40)
	var bench: Node3D = get_tree().get_first_node_in_group("workbenches")
	var stand := bench.global_position + Vector3(0, 0.1, -1.3)
	_me.global_position = stand
	await get_tree().create_timer(0.5).timeout
	var dummy := DUMMY.instantiate()
	dummy.position = _me.global_position + Vector3(0, -0.1, -4.0)
	add_child(dummy)
	_aim_at(dummy.global_position + Vector3(0, 1.1, 0))
	_me._select_slot(1)
	await get_tree().create_timer(0.4).timeout
	Input.action_press("reload")
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame  # physics_frame fires before the player reads its input: hold it a few ticks
	Input.action_release("reload")
	await get_tree().create_timer(3.2).timeout
	var hp0: float = dummy.health.current
	Input.action_press("fire")
	await get_tree().create_timer(0.1).timeout
	Input.action_release("fire")
	await get_tree().create_timer(0.3).timeout
	var dealt := hp0 - float(dummy.health.current)
	_check(dealt > float(GearRules.weapon_stats(shotgun).damage) * 1.5 and w.net_mesh == "Shotgun",
		"shotgun blast: %.0f damage from several pellets (mag %d, holding %s)" % [dealt, w.net_mag, w.net_mesh])
	await _shot("gear_shotgun.png")
	# Armor.
	inv.host_add("chest_kevlar", 1)
	var vest := inv.equipped("chest")
	var resist: float = _me.health.resist
	_me.health.damage_mult = 1.0
	var h0: float = _me.health.current
	_me.health.apply_damage(50.0, 0)
	var took: float = h0 - float(_me.health.current)
	var vest_after := inv.equipped("chest")
	_check(resist > 0.1 and absf(took - 50.0 * (1.0 - resist)) < 0.05 and float(vest_after.cond) < float(vest.cond),
		"%s blocks %d%%: 50 -> %.1f damage, condition %.3f -> %.3f" % [GearRules.display_name(vest), roundi(resist * 100.0), took,
		float(vest.cond), float(vest_after.cond)])
	_me.health.current = _me.health.max_health
	_me.health.damage_mult = 0.0
	# Workbench: extended mag + repair.
	inv.host_add("mod_ext_mag", 1)
	bench.request_attach(int(shotgun.uid), "mod_ext_mag")
	await get_tree().process_frame
	var modded := inv.get_gear(int(shotgun.uid))
	_check("mod_ext_mag" in modded.get("mods", []) and int(w.weapon_in_slot(1).mag_size) == 9 and inv.count("mod_ext_mag") == 0,
		"extended mag on the shotgun at the bench: %d rounds" % int(w.weapon_in_slot(1).mag_size))
	var worn := modded.duplicate(true)
	worn.cond = 0.5
	inv.host_set_gears({int(shotgun.uid): worn})
	inv.host_add("scrap_metal", 5)
	var scrap0 := inv.count("scrap_metal")
	bench.request_repair(int(shotgun.uid))
	await get_tree().process_frame
	_check(is_equal_approx(float(inv.get_gear(int(shotgun.uid)).cond), 1.0) and inv.count("scrap_metal") == scrap0 - 3,
		"repair: back to 100%% for 3 scrap")
	# Golden Ace in the melee slot: throw at the dummy, it comes back.
	inv.host_add("disc_golden_ace", 1)
	var ace_uid := -1
	for g: Dictionary in inv.gear_list():
		if str(g.id) == "disc_golden_ace":
			ace_uid = int(g.uid)
	inv.request_equip(ace_uid, "melee")
	_me._select_slot(2)
	await get_tree().create_timer(0.4).timeout
	dummy.health.reset()
	_aim_at(dummy.global_position + Vector3(0, 1.1, 0))
	await get_tree().create_timer(0.2).timeout
	var combat := get_tree().get_first_node_in_group("combat_world")
	Input.action_press("fire")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("fire")
	var thrown: bool = combat.host_has_throw(_me)
	await get_tree().create_timer(0.35).timeout
	await _shot("gear_ace_flight.png")
	var t0 := Time.get_ticks_msec()
	while combat.host_has_throw(_me) and Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame
	_check(thrown and float(dummy.health.current) < float(dummy.health.max_health) and not combat.host_has_throw(_me),
		"Golden Ace: thrown, hit the dummy (%.0f left), back in hand after %.1f s" % [float(dummy.health.current),
		(Time.get_ticks_msec() - t0) / 1000.0 + 0.35])
	# Drop the shotgun, pick it back up.
	var drops: WorldDrops = get_tree().get_first_node_in_group("world_drops")
	var before := inv.get_gear(int(shotgun.uid)).duplicate(true)
	drops.request_drop_gear(int(shotgun.uid))
	await get_tree().process_frame
	var drop_id := -1
	for id: int in drops.drops:
		if not (drops.drops[id][3] as Dictionary).is_empty() and str(drops.drops[id][0]) == "shotgun_pump":
			drop_id = id
	_check(drop_id > 0 and inv.get_gear(int(shotgun.uid)).is_empty() and drops.display_name(drop_id) == GearRules.display_name(before),
		"dropped: on the ground as '%s'" % drops.display_name(drop_id))
	drops.request_pickup(drop_id)
	await get_tree().process_frame
	var back := {}
	for g: Dictionary in inv.gear_list():
		if str(g.id) == "shotgun_pump":
			back = g
	_check(not back.is_empty() and back.rarity == before.rarity and is_equal_approx(float(back.cond), float(before.cond))
		and back.mods == before.mods, "picked up with the same roll (%s, %d%%, %s)" % [back.get("rarity", "-"),
		roundi(float(back.get("cond", 0)) * 100.0), back.get("mods", [])])
	# Save holds the gear; an old save's counts become gear.
	main.saves.host_save("test")
	var entry: Dictionary = main.saves.world.players.values()[0]
	_check(entry.has("gear") and (entry.gear.list as Array).size() == inv.gear_list().size(),
		"the save holds %d pieces of gear" % (entry.gear.list as Array).size())
	inv.net_items = {"pistol_9mm": 1, "axe_fire": 1, "ammo_9mm": 5}
	inv.net_gear = {}
	inv.host_upgrade_legacy()
	_check(inv.count("pistol_9mm") == 0 and inv.gear_list().size() == 2 and str(inv.equipped("gun1").get("id", "")) == "pistol_9mm"
		and inv.count("ammo_9mm") == 5, "old save: weapon counts -> rolled gear, pistol equipped, ammo kept")
	await _perf()
	dummy.queue_free()


func _aim_at(target: Vector3) -> void:
	var eye: Vector3 = _me.camera.global_position
	var d := target - eye
	_me.yaw = atan2(-d.x, -d.z)
	_me.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	_me.rotation.y = _me.yaw
	_me.head.rotation.x = _me.pitch


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
	print("GEAR: " + s)
