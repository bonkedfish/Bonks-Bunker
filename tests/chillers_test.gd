# ChillersTest — checks the Chillers HQ at UNK + chems (D-052, D-053): hosts a throwaway world, screenshots the union,
# camp and rooms into res://tests/_look/chillers_*.png, walks in the south door to Meekachu's throne, buys Kush and
# Acid from him (with and without the goods), uses them (effects start, speed / damage-taken / drain change, HUD shows
# them), checks comedowns chain (pure EffectRules), screenshots the acid trip, and reports perf there.
# Results: tests/_look/chillers_result.txt. Depends on: scenes/main.tscn, SaveStore, the "chillers_hq" landmark node,
# DialogueDirector, InventoryHolder, ItemUse, ActiveEffects, EffectRules.
extends Node

const OUT_DIR := "res://tests/_look"
const SHOTS := [
	["chillers_south.png", Vector3(10, 3, 75), Vector3(0, 4, 20)],
	["chillers_camp.png", Vector3(-18, 2.5, 52), Vector3(5, 1, 36)],
	["chillers_air.png", Vector3(80, 55, 90), Vector3(0, 0, 5)],
	["chillers_lounge.png", Vector3(10, 1.7, 17), Vector3(-15, 1.2, -2)],
	["chillers_grow.png", Vector3(16, 2.2, 18), Vector3(38, 1.0, -10)],
	["chillers_throne.png", Vector3(-30, 1.7, 3), Vector3(-41, 1.4, 0)],
]
const ROUTE := [Vector2(0, 30), Vector2(0, 22), Vector2(-4, 19.5), Vector2(-25, 19.5), Vector2(-25, 0), Vector2(-33, 0),
	Vector2(-36.6, 0)]

var _log := PackedStringArray()
var _player: Node3D
var _o := Vector3.ZERO
var _fails := 0


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz chillers")
	main._on_host_pressed()
	await get_tree().create_timer(4.0).timeout
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for n: Node in get_tree().get_nodes_in_group("players"):
		if "water" in n:
			_player = n
	_pure_checks()
	var hq: Node3D = get_tree().root.find_child("chillers_hq", true, false)
	_check("chillers_hq landmark loaded", hq != null)
	if hq == null:
		_finish(main)
		return
	_o = hq.global_position
	_say("chillers_hq origin %s" % _o.snapped(Vector3.ONE * 0.1))
	_check("loot containers: %d" % hq.find_children("Loot_*", "", false, false).size(),
		hq.find_children("Loot_*", "", false, false).size() >= 10)
	var meek := hq.get_node_or_null("Meekachu")
	_check("Meekachu + 3 Chillers placed", meek != null and hq.has_node("Bongo") and hq.has_node("Skyler") and hq.has_node("Patches"))
	_player.global_position = _o + Vector3(0, 1, 30)
	_player.velocity = Vector3.ZERO
	await get_tree().create_timer(6.0).timeout
	var cam := Camera3D.new()
	cam.fov = 75.0
	add_child(cam)
	for s: Array in SHOTS:
		cam.make_current()
		cam.global_position = _o + (s[1] as Vector3)
		cam.look_at(_o + (s[2] as Vector3))
		await _shot(str(s[0]))
	await _walk()
	if meek:
		await _talk_and_use(meek)
	var worst := 0.0
	for i in 120:
		await get_tree().process_frame
		worst = maxf(worst, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_say("perf at Meekachu: frame %.1f ms (worst process %.1f ms), draw calls %d, VRAM %d MB" % [
		1000.0 / maxf(Engine.get_frames_per_second(), 1.0), worst,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	_finish(main)


func _pure_checks() -> void:
	var d := EffectRules.defs()
	_check("effects data loads (%d effects)" % d.size(), d.size() >= 8)
	var a := EffectRules.tick({"tripping_acid": 0.5}, 1.0, d)
	_check("acid wears off into 'fried': %s" % a, not a.has("tripping_acid") and a.has("fried"))
	var m := EffectRules.mods(["baked", "rolling"], d)
	_check("baked + rolling mods multiply: speed %.3f, dmg %.2f, hunger %.1f, thirst %.1f" % [m.move_speed, m.damage_taken,
		m.hunger_drain, m.thirst_drain], is_equal_approx(m.move_speed, 0.92 * 1.15) and is_equal_approx(m.damage_taken, 0.85))
	for id: String in ["kush_joint", "magic_mushrooms", "acid_tab", "molly", "black_tar"]:
		var item := ItemDB.get_item(id)
		_check("item %s -> effect %s" % [id, item.get("use", {}).get("effect", "?")],
			EffectRules.has_effect(str(item.get("use", {}).get("effect", ""))))


func _walk() -> void:
	var pc: Camera3D = _player.camera
	pc.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_player.global_position = _o + Vector3(0, 0.5, 30)
	_player.velocity = Vector3.ZERO
	await get_tree().create_timer(1.0).timeout
	var t0 := Time.get_ticks_msec()
	for wp: Vector2 in ROUTE:
		var target := Vector3(_o.x + wp.x, 0, _o.z + wp.y)
		var start := Time.get_ticks_msec()
		while Time.get_ticks_msec() - start < 8000:
			var to := target - _player.global_position
			to.y = 0.0
			if to.length() < 0.35:
				break
			_player.yaw = atan2(-to.x, -to.z)
			Input.action_press("move_forward")
			await get_tree().physics_frame
		Input.action_release("move_forward")
		var at := _player.global_position - _o
		if Vector2(at.x, at.z).distance_to(wp) > 0.6:
			_say("walk: stuck short of %s at local %s" % [wp, at.snapped(Vector3.ONE * 0.1)])
	var lp := _player.global_position - _o
	_check("walk in the south door to the throne: %.1f s, ended at local %s" % [(Time.get_ticks_msec() - t0) / 1000.0,
		lp.snapped(Vector3.ONE * 0.1)], Vector2(lp.x, lp.z).distance_to(ROUTE[-1]) < 1.0)
	_player.yaw = atan2(1.0, 0.0)  # face west, at Meekachu
	_player.pitch = -0.05
	await _shot("chillers_meet_meekachu.png")


func _talk_and_use(meek: Node) -> void:
	var dialogue := get_tree().get_first_node_in_group("dialogue")
	var inv: InventoryHolder = _player.inventory
	dialogue.request_talk(meek.get_path())
	await get_tree().create_timer(0.5).timeout
	_check("talk to Meekachu started (%.1f m)" % _player.global_position.distance_to(meek.global_position),
		dialogue._talker != 0 and dialogue._node_id == "start")
	await _shot("chillers_meekachu_talk.png")
	dialogue.request_choice(0)  # -> shop
	inv.host_remove("canned_beans", inv.count("canned_beans"))
	dialogue.request_choice(0)  # beans -> kush, can't pay
	_check("buy kush without beans -> %s" % dialogue._node_id, dialogue._node_id == "broke")
	dialogue.request_choice(0)  # -> shop
	inv.host_add("canned_beans", 2)
	var k0 := inv.count("kush_joint")
	dialogue.request_choice(0)
	_check("2 beans -> kush %d -> %d" % [k0, inv.count("kush_joint")], inv.count("kush_joint") == k0 + 2 and inv.count("canned_beans") == 0)
	dialogue.request_choice(1)  # "That's all." -> menu
	dialogue.request_choice(0)  # menu -> shop
	inv.host_add("painkillers", 1)
	dialogue.request_choice(2)  # painkillers -> acid
	_check("painkillers -> acid tab (%d)" % inv.count("acid_tab"), inv.count("acid_tab") >= 1)
	dialogue.request_leave()
	await get_tree().create_timer(0.5).timeout
	# Use the kush, then the acid.
	var eff: ActiveEffects = _player.effects
	var speed0 := eff.speed_mult()
	_player.item_use.request("kush_joint")
	await get_tree().create_timer(3.6).timeout
	_check("smoked kush: effects %s, speed x%.2f, damage taken x%.2f, hunger drain x%.1f" % [eff.net_effects, eff.speed_mult(),
		_player.health.damage_mult, _player.needs.drain_mult.x],
		eff.net_effects.has("baked") and eff.speed_mult() < speed0 and _player.health.damage_mult < 1.0 and _player.needs.drain_mult.x > 1.0)
	var hp0: float = _player.health.current
	_player.health.apply_damage(10.0, 99)
	_check("10 damage while baked took %.1f HP" % (hp0 - _player.health.current), is_equal_approx(hp0 - _player.health.current, 8.5))
	_player.item_use.request("acid_tab")
	await get_tree().create_timer(5.0).timeout
	_check("dropped acid: effects %s" % eff.net_effects, eff.net_effects.has("tripping_acid") and eff.net_effects.has("baked"))
	_player.yaw = atan2(-1.0, 0.0)  # look east down the lounge
	await _shot("chillers_acid_trip.png")
	await get_tree().create_timer(2.0).timeout
	await _shot("chillers_acid_trip_2.png")
	var hud := get_tree().get_first_node_in_group("hud")
	var shown: String = " ".join(hud.status.effect_names())
	_check("HUD shows the effects: '%s'" % shown, "Baked" in shown and "Acid" in shown)


func _finish(main: Node) -> void:
	_say("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/chillers_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SaveStore.delete(main.saves.world_slug)
	await get_tree().create_timer(2.0).timeout
	get_tree().quit()


func _shot(file: String) -> void:
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT_DIR + "/" + file)
	_say("shot " + file)


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	_say(("PASS " if ok else "FAIL ") + what)


func _say(s: String) -> void:
	print("CHILLERS: " + s)
	_log.append(s)
