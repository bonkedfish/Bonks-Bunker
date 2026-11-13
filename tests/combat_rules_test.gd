# CombatRulesTest — prints PASS/FAIL for the pure combat math and data loading, then quits.
# Run this scene directly. Depends on: CombatRules, PositionHistory, WeaponDB.
extends Node

var _failures := 0


func _ready() -> void:
	var fwd := CombatRules.aim_direction(0.0, 0.0)
	_check("aim forward is -Z", fwd.is_equal_approx(Vector3.FORWARD))
	_check("aim yaw +90deg is -X", CombatRules.aim_direction(PI / 2, 0.0).is_equal_approx(Vector3.LEFT))

	# Capsule standing 10 m ahead; shot at chest height hits its front surface at 10 - radius.
	var base := Vector3(0, 0, -10)
	var d := CombatRules.ray_vs_capsule(Vector3(0, 1.0, 0), fwd, 80.0, base, 0.35, 1.8)
	_check("ray hits capsule ahead at ~9.65 m (got %.2f)" % d, absf(d - 9.65) < 0.05)
	_check("ray misses capsule 1 m to the side",
		CombatRules.ray_vs_capsule(Vector3(1.0, 1.68, 0), fwd, 80.0, base, 0.35, 1.8) < 0.0)
	_check("ray out of range misses",
		CombatRules.ray_vs_capsule(Vector3(0, 1.68, 0), fwd, 5.0, base, 0.35, 1.8) < 0.0)
	_check("ray over the head misses",
		CombatRules.ray_vs_capsule(Vector3(0, 2.5, 0), fwd, 80.0, base, 0.35, 1.8) < 0.0)

	var near := Vector3(0, 0, -1.5)
	_check("melee hits target in front within reach",
		CombatRules.melee_hits_capsule(Vector3(0, 1.68, 0), fwd, 2.2, 80.0, near, 0.35, 1.8))
	_check("melee misses target behind",
		not CombatRules.melee_hits_capsule(Vector3(0, 1.68, 0), fwd, 2.2, 80.0, Vector3(0, 0, 1.5), 0.35, 1.8))
	_check("melee misses target out of reach",
		not CombatRules.melee_hits_capsule(Vector3(0, 1.68, 0), fwd, 2.2, 80.0, Vector3(0, 0, -4), 0.35, 1.8))

	_check("friendly fire scales", is_equal_approx(CombatRules.scaled_damage(40.0, true, 0.25), 10.0))
	_check("enemy damage unscaled", is_equal_approx(CombatRules.scaled_damage(40.0, false, 0.25), 40.0))

	var h := PositionHistory.new()
	h.record(100, Vector3(0, 0, 0), 1.8)
	h.record(101, Vector3(1, 0, 0), 1.8)
	_check("history interpolates between ticks", is_equal_approx(h.sample(100.5).x, 0.5))
	_check("history missing tick reports missing", h.sample(5.0).w < 0.0)

	_check("combat tuning loads", not CombatRules.load_tuning().is_empty())
	_check("pistol data loads", WeaponDB.get_weapon("pistol_9mm").get("kind", "") == "gun")
	_check("bat data loads", WeaponDB.get_weapon("bat_baseball").get("kind", "") == "melee")

	_test_life_state()
	_test_zombie_brain()
	_test_snapshot_buffer()
	_test_inventory_and_loot()
	_test_bonk()
	_test_save_format()
	_test_graphics()
	_test_map_math()

	print("COMBAT TESTS: %s (%d failures)" % ["ALL PASS" if _failures == 0 else "FAILED", _failures])
	await get_tree().create_timer(20.0).timeout  # keep output readable by external tools
	get_tree().quit()


# Downed / revive / bleed-out timing with default 30 s bleed-out and 3 s revive.
func _test_life_state() -> void:
	var dt := 1.0 / 60.0
	var life := LifeState.new()
	life.host_go_down()
	_check("go down -> DOWNED with 30 s", life.net_state == LifeState.DOWNED and is_equal_approx(life.net_bleed_left, 30.0))
	for i in 600:
		life.host_tick(dt)
	_check("bleeds 10 s (left %.2f)" % life.net_bleed_left, absf(life.net_bleed_left - 20.0) < 0.05)
	for i in 60:
		life.host_revive_step(dt)
		life.host_tick(dt)
	_check("1 s of reviving = ~33%% (got %.2f)" % life.net_revive_progress, absf(life.net_revive_progress - 1.0 / 3.0) < 0.02)
	_check("bleed-out paused while reviving", absf(life.net_bleed_left - 20.0) < 0.05)
	for i in 30:
		life.host_tick(dt)
	_check("progress resets when reviver stops", life.net_revive_progress == 0.0)
	var flags := [false, false]  # revived, bled_out
	life.revived.connect(func() -> void: flags[0] = true)
	for i in 200:
		life.host_revive_step(dt)
		life.host_tick(dt)
	_check("full 3 s revive emits revived", flags[0])
	life.free()

	var life2 := LifeState.new()
	life2.bled_out.connect(func() -> void: flags[1] = true)
	life2.host_go_down()
	for i in 1900:
		life2.host_tick(dt)
	_check("no revive for 30 s -> DEAD + bled_out", life2.net_state == LifeState.DEAD and flags[1])
	life2.free()


# ZombieBrain transitions with the shambler data (windup 0.6, cooldown 1.5, range 1.4, lose interest 8 s).
func _test_zombie_brain() -> void:
	var def := EnemyDB.get_enemy("zombie_shambler")
	_check("shambler data loads", not def.is_empty())
	if def.is_empty():
		return
	var dt := 1.0 / 60.0
	var b := ZombieBrain.new(def)
	b.tick(dt, false, INF, false, true)
	_check("idle zombie wanders", b.state == ZombieBrain.State.WANDER)
	b.tick(dt, false, INF, true, true)
	_check("noise -> INVESTIGATE", b.state == ZombieBrain.State.INVESTIGATE)
	b.tick(dt, false, INF, false, false)
	_check("still walking to noise", b.state == ZombieBrain.State.INVESTIGATE)
	b.tick(dt, true, 10.0, false, false)
	_check("sees player -> CHASE", b.state == ZombieBrain.State.CHASE)
	b.tick(dt, true, 1.0, false, false)
	_check("in range -> ATTACK", b.state == ZombieBrain.State.ATTACK)
	var landed := 0
	for i in 40:  # 0.67 s > 0.6 s windup
		b.tick(dt, true, 1.0, false, false)
		if b.attack_landed:
			landed += 1
	_check("swipe lands once after windup", landed == 1 and b.state == ZombieBrain.State.CHASE)
	b.tick(dt, true, 1.0, false, false)
	_check("cooldown blocks instant re-attack", b.state == ZombieBrain.State.CHASE)
	for i in 500:  # 8.3 s unseen
		b.tick(dt, false, INF, false, false)
	_check("loses interest -> WANDER", b.state == ZombieBrain.State.WANDER)


func _test_snapshot_buffer() -> void:
	var s := SnapshotBuffer.new()
	s.push(1.0, Vector3(0, 0, 0), 0.0)
	s.push(1.1, Vector3(2, 0, 0), 0.0)
	_check("snapshot interpolates", is_equal_approx(s.sample(1.05).x, 1.0))
	_check("snapshot holds newest past the end", is_equal_approx(s.sample(5.0).x, 2.0))


func _test_inventory_and_loot() -> void:
	var inv := Inventory.new()
	inv.add("pistol_9mm", 1)
	inv.add("ammo_9mm", 500)
	inv.add("scrap_metal", 3)
	_check("inventory counts", inv.count("ammo_9mm") == 500 and inv.count("scrap_metal") == 3)
	_check("ammo is weightless (weight %.1f)" % inv.total_weight(), is_equal_approx(inv.total_weight(), 5.0))
	_check("remove returns what it took", inv.remove("scrap_metal", 10) == 3 and inv.count("scrap_metal") == 0)
	_check("emptied stacks disappear", not inv.items.has("scrap_metal"))

	var t := CarryRules.load_tuning()
	_check("inventory tuning loads", not t.is_empty())
	_check("under capacity: full speed + sprint", CarryRules.speed_multiplier(40.0, t) == 1.0 and CarryRules.can_sprint(40.0, t))
	_check("overweight: slowed, no sprint", CarryRules.speed_multiplier(65.0, t) == 0.5 and not CarryRules.can_sprint(65.0, t))
	_check("way over: stuck", is_equal_approx(CarryRules.speed_multiplier(80.0, t), 0.15))

	_check("pistol uses 9mm ammo", WeaponDB.get_weapon("pistol_9mm").get("ammo_item", "") == "ammo_9mm")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var all_valid := true
	var any_loot := false
	for table_id in ["house_cabinet", "fridge", "toolbox", "ammo_cache", "junk_pile"]:
		var table := LootDB.get_table(table_id)
		if table.is_empty():
			all_valid = false
			continue
		for i in 50:
			var rolled := LootRules.roll(table, rng)
			for id: String in rolled:
				any_loot = true
				if not ItemDB.has_item(id) or int(rolled[id]) <= 0:
					all_valid = false
	_check("all 5 loot tables load and roll only real items", all_valid and any_loot)


# CompanionBrain with Bonk's data (follow 3.5, catch-up 12, reaction 0.5, fire 0.6, melee 2.0, cooldown 4).
func _test_bonk() -> void:
	var def := DataLoader.load_json("res://data/companions/bonk.json")
	_check("bonk data loads", not def.is_empty())
	if def.is_empty():
		return
	var dt := 1.0 / 60.0
	var b := CompanionBrain.new(def)
	b.tick(dt, false, INF, 2.0)
	_check("bonk idles when close to the group", b.state == CompanionBrain.State.FOLLOW and not b.wants_move)
	b.tick(dt, false, INF, 8.0)
	_check("bonk walks after a player 8 m away", b.wants_move and not b.move_fast)
	b.tick(dt, false, INF, 20.0)
	_check("bonk runs to catch up at 20 m", b.wants_move and b.move_fast)
	b.tick(dt, true, 10.0, 2.0)
	_check("zombie seen -> COMBAT", b.state == CompanionBrain.State.COMBAT and b.combat_started and not b.wants_fire)
	var shots := 0
	for i in 90:  # 1.5 s: reaction 0.5 s, then every 0.6 s
		b.tick(dt, true, 10.0, 2.0)
		if b.wants_fire:
			shots += 1
	_check("bonk fires after reacting (%d shots in 1.5 s)" % shots, shots == 2)
	b.tick(dt, true, 1.5, 2.0)
	_check("zombie in bat range -> melee", b.wants_melee and not b.wants_fire)
	for i in 250:  # 4.2 s without seeing a zombie
		b.tick(dt, false, INF, 2.0)
	_check("no zombies for 4 s -> back to FOLLOW", b.state == CompanionBrain.State.FOLLOW)

	# Sidestep rules (D-035): player 1 m south of Bonk walking north at 4 m/s is walking into him.
	var into := CompanionBrain.player_walking_into(Vector3(0, 0, -1), Vector3(0, 0, -4), 1.4, 1.0)
	_check("player walking into bonk -> dodge", into)
	_check("player walking away -> no dodge", not CompanionBrain.player_walking_into(Vector3(0, 0, -1), Vector3(0, 0, 4), 1.4, 1.0))
	_check("player standing still -> no dodge", not CompanionBrain.player_walking_into(Vector3(0, 0, -1), Vector3.ZERO, 1.4, 1.0))
	_check("player far away -> no dodge", not CompanionBrain.player_walking_into(Vector3(0, 0, -5), Vector3(0, 0, -4), 1.4, 1.0))
	var spot := CompanionBrain.dodge_spot(Vector3(0.3, 0, -1), Vector3.ZERO, Vector3(0, 0, -4), 0, 1.5)
	_check("first dodge spot is sideways, away from the player's line (%s)" % spot, spot.is_equal_approx(Vector3(1.8, 0, -1)))
	_check("third dodge spot backs out ahead of the player",
		CompanionBrain.dodge_spot(Vector3(0, 0, -1), Vector3.ZERO, Vector3(0, 0, -4), 2, 1.5).is_equal_approx(Vector3(0, 0, -4)))

	_check("dialogue data validates", DialogueDB.is_valid())
	_check("bonk_talk tree loads", not DialogueDB.get_dialogue_tree("bonk_talk").is_empty())
	var missing := []
	for ctx in ["idle", "combat_start", "kill", "reload", "downed", "self_revive", "revived_by_player", "player_downed", "friendly_fire", "busy"]:
		if DialogueDB.barks(ctx).is_empty():
			missing.append(ctx)
	_check("every bark context has lines (missing: %s)" % [missing], missing.is_empty())


# SaveFormat (D-037): new worlds pass the check, junk and newer versions are rejected, stale items dropped.
func _test_save_format() -> void:
	var w := SaveFormat.new_world("Test", 1000)
	_check("new world passes the save check", SaveFormat.check(w) == "")
	_check("save from a newer game is rejected", SaveFormat.migrate({"version": SaveFormat.VERSION + 1}).is_empty())
	_check("save without a version is rejected", SaveFormat.migrate({"name": "x"}).is_empty())
	w.players["abc"] = SaveFormat.player_entry(Vector3(1.234, -4.0, 2.0), 55.0, {"ammo_9mm": 12}, [7, 0])
	_check("world with a character passes", SaveFormat.check(w) == "")
	var round_trip: Dictionary = JSON.parse_string(JSON.stringify(w))
	var pos := SaveFormat.array_to_vec(round_trip.players.abc.position)
	_check("character survives JSON (pos %s)" % pos, SaveFormat.check(round_trip) == "" and pos.is_equal_approx(Vector3(1.23, -4.0, 2.0)))
	w.players["bad"] = {"position": [1, 2], "health": 10, "items": {}}
	_check("malformed character is caught", SaveFormat.check(w) != "")
	var cleaned := SaveFormat.clean_items({"ammo_9mm": 5.0, "removed_item_xyz": 3, "scrap_metal": 0})
	_check("unknown items and empty stacks are dropped (%s)" % cleaned, cleaned == {"ammo_9mm": 5})
	_check("world names become safe file names", SaveFormat.slug("Bonk's World!") == "bonk_s_world" and SaveFormat.slug("???") == "world")
	_check("player IDs are 32 hex chars", PlayerIdentity.is_valid(PlayerIdentity.uid()) and not PlayerIdentity.is_valid("../../etc"))


# GraphicsRules (D-038): tier data validates; GPU names pick sensible tiers.
func _test_graphics() -> void:
	var data := GraphicsRules.load_data()
	_check("graphics tiers + budgets load", not data.is_empty() and data.budgets.has("frame_ms"))
	if data.is_empty():
		return
	_check("RTX 4060 -> high", GraphicsRules.pick_tier("NVIDIA GeForce RTX 4060", false, data.auto) == "high")
	_check("GTX 1060 -> medium", GraphicsRules.pick_tier("NVIDIA GeForce GTX 1060 6GB", false, data.auto) == "medium")
	_check("integrated Intel -> low", GraphicsRules.pick_tier("Intel(R) UHD Graphics 620", true, data.auto) == "low")
	_check("Radeon RX 6600 -> high", GraphicsRules.pick_tier("AMD Radeon RX 6600", false, data.auto) == "high")


# Streaming map maths (D-039): cell grid, height field with pads, TIFF reading (synthetic files).
func _test_map_math() -> void:
	var g := CellGrid.new(256.0, 8)
	_check("map centre is cell (4,4)", g.cell_of(Vector3.ZERO) == Vector2i(4, 4))
	_check("north-west corner is cell (0,0)", g.cell_of(Vector3(-1024, 0, -1024)) == Vector2i(0, 0))
	_check("outside the map is out of bounds", not g.in_bounds(g.cell_of(Vector3(-1025, 0, 0))))
	var ring := {}
	g.add_square(ring, Vector2i(0, 0), 1)
	var ring2 := {}
	g.add_square(ring2, Vector2i(4, 4), 1)
	_check("3x3 ring clipped at the corner (%d, %d)" % [ring.size(), ring2.size()], ring.size() == 4 and ring2.size() == 9)

	var proj := MapProjection.new(40.68, -99.10)
	var nw := proj.to_lat_lon(-100, -100)
	var se := proj.to_lat_lon(100, 100)
	var vals := PackedFloat32Array([600, 610, 620, 600, 610, 620, 600, 610, 620])
	var f := HeightField.new(3, 3, vals, [nw.y, se.x, se.y, nw.x], proj)
	_check("datum = centre elevation (%.2f)" % f.datum, absf(f.datum - 610.0) < 0.01)
	_check("height rises east (%.2f)" % f.sample(33.333, 0), absf(f.sample(33.333, 0) - 5.0) < 0.05)
	f.add_pad(Rect2(-10, -10, 20, 20), 3.0, 10.0)
	_check("pad flattens its rect", absf(f.sample(0, 0) - 3.0) < 0.001 and absf(f.sample(9, -9) - 3.0) < 0.001)
	_check("pad blends back (%.3f)" % f.sample(15, 0), absf(f.sample(15, 0) - 2.625) < 0.02)
	_check("terrain untouched past the blend (%.2f)" % f.sample(25, 0), absf(f.sample(25, 0) - 3.75) < 0.05)

	var grid := PackedFloat32Array([1.5, -2.25, 3.0, 650.125, 0.0, 99.5])
	for mode in [[1, 1, "plain"], [8, 1, "deflate"], [8, 3, "deflate + float predictor"]]:
		var t := TiffReader.read_f32(_tiff(3, 2, grid, mode[0], mode[1]))
		_check("TIFF %s reads back (%s)" % [mode[2], t.get("error", "")], not t.has("error") and t.width == 3 and t.height == 2 and t["values"] == grid)
	_check("non-TIFF is rejected", TiffReader.read_f32("<html>error</html>".to_utf8_buffer()).has("error"))


# A minimal little-endian one-strip float TIFF, for testing TiffReader without the network.
func _tiff(w: int, h: int, values: PackedFloat32Array, compression: int, predictor: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(w * h * 4)
	if predictor == 3:
		for y in h:
			var row := PackedByteArray()
			row.resize(w * 4)
			for c in w:
				var le := PackedByteArray()
				le.resize(4)
				le.encode_float(0, values[y * w + c])
				for b in 4:
					row[b * w + c] = le[3 - b]
			for i in range(w * 4 - 1, 0, -1):
				row[i] = (row[i] - row[i - 1]) & 0xFF
			for i in w * 4:
				data[y * w * 4 + i] = row[i]
	else:
		for i in values.size():
			data.encode_float(i * 4, values[i])
	if compression == 8:
		data = data.compress(FileAccess.COMPRESSION_DEFLATE)
	var entries := [[256, 3, w], [257, 3, h], [258, 3, 32], [259, 3, compression], [273, 4, 8], [277, 3, 1],
		[278, 3, h], [279, 4, data.size()], [317, 3, predictor], [339, 3, 3]]
	var out := PackedByteArray([0x49, 0x49, 42, 0])
	out.resize(8)
	out.encode_u32(4, 8 + data.size())
	out.append_array(data)
	var ifd := PackedByteArray()
	ifd.resize(2 + entries.size() * 12 + 4)
	ifd.encode_u16(0, entries.size())
	for i in entries.size():
		var e: Array = entries[i]
		ifd.encode_u16(2 + i * 12, e[0])
		ifd.encode_u16(4 + i * 12, e[1])
		ifd.encode_u32(6 + i * 12, 1)
		if e[1] == 3:
			ifd.encode_u16(10 + i * 12, e[2])
		else:
			ifd.encode_u32(10 + i * 12, e[2])
	out.append_array(ifd)
	return out


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print(("PASS  " if ok else "FAIL  ") + label)
