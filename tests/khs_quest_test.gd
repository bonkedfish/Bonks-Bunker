# KhsQuestTest — checks the main quest + Kearney High (D-054, D-055): hosts a throwaway world, checks Act 1 starts,
# walks the story flags through mq1 and mq2 (with rewards), screenshots Kearney High (outside, lobby, halls,
# cafeteria, gym) into res://tests/_look/khs_*.png, checks lair enemies wake near the player, talks to Hunter Conner
# into the fight (NPC hides, boss + guards spawn), kills him (boss flag, eagle keycard drop -> pickup -> Detention
# done, Acknowledged active), frees Wren, opens the quest book, and reports perf in the school.
# Results: tests/_look/khs_result.txt. Depends on: scenes/main.tscn, SaveStore, QuestDirector, QuestRules,
# LairDirector, DialogueDirector, WorldDrops, QuestBookUI, the "kearney_high" landmark node.
extends Node

const OUT_DIR := "res://tests/_look"
const SHOTS := [
	["khs_air.png", Vector3(160, 120, 160), Vector3(0, 0, 20)],
	["khs_outside.png", Vector3(40, 3, -20), Vector3(-10, 4, -40)],
	["khs_lobby.png", Vector3(-6, 1.7, -28), Vector3(-45, 1.5, -25)],
	["khs_hall_north.png", Vector3(5, 1.7, -92), Vector3(110, 1.5, -92)],
	["khs_cafeteria.png", Vector3(-5, 1.7, -50), Vector3(-45, 1.0, -95)],
	["khs_gym.png", Vector3(-42, 3.0, 82), Vector3(-90, 1.0, 82)],
]

var _log := PackedStringArray()
var _player: Node3D
var _o := Vector3.ZERO
var _fails := 0
var _q: Node


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz khs")
	main._on_host_pressed()
	await get_tree().create_timer(4.0).timeout
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for n: Node in get_tree().get_nodes_in_group("players"):
		if "water" in n:
			_player = n
	_q = get_tree().get_first_node_in_group("quests")
	var defs := QuestRules.defs()
	_check("quests load: %d" % defs.size(), defs.size() >= 10)
	_check("Five Years of Static active at start", QuestRules.status(defs.mq1_static, _q.flags) == QuestRules.Status.ACTIVE)
	# Story flags through mq1 + mq2.
	var ammo0: int = _player.inventory.count("ammo_9mm")
	for f: String in ["mq_bonk_static", "mq_reach_archway", "mq_met_evan", "mq_evan_ack"]:
		_q.host_set_flag(f)
	_check("mq1 done -> reward ammo %d -> %d, Collector active" % [ammo0, _player.inventory.count("ammo_9mm")],
		QuestRules.flag_met(_q.flags, "mq1_static_done") and QuestRules.status(defs.mq2_collector, _q.flags) == QuestRules.Status.ACTIVE
		and _player.inventory.count("ammo_9mm") == ammo0 + 20)
	for f: String in ["mq_evan_key", "mq_reach_chillers", "mq_meek_taken", "mq_meek_hunter"]:
		_q.host_set_flag(f)
	_check("mq2 done -> Detention active", QuestRules.status(defs.mq3_detention, _q.flags) == QuestRules.Status.ACTIVE)
	var khs: Node3D = get_tree().root.find_child("kearney_high", true, false)
	_check("kearney_high landmark loaded", khs != null)
	if khs == null:
		_finish(main)
		return
	_o = khs.global_position
	_say("kearney_high origin %s; %d loot, %d spawn markers" % [_o.snapped(Vector3.ONE * 0.1),
		khs.find_children("Loot_*", "", false, false).size(), get_tree().get_nodes_in_group("lair_spawns").size()])
	# Walk up to the front doors: the reach objective should tick.
	_player.global_position = _o + Vector3(-8, 1.0, -25)
	_player.velocity = Vector3.ZERO
	await get_tree().create_timer(6.0).timeout
	_check("reached KHS -> mq_reach_khs", QuestRules.flag_met(_q.flags, "mq_reach_khs"))
	var cam := Camera3D.new()
	cam.fov = 75.0
	add_child(cam)
	for s: Array in SHOTS:
		_player.global_position = _o + (s[1] as Vector3) * Vector3(1, 0, 1) + Vector3(0, 1.0, 0)
		_player.velocity = Vector3.ZERO
		await get_tree().create_timer(2.0).timeout
		cam.make_current()
		cam.global_position = _o + (s[1] as Vector3)
		cam.look_at(_o + (s[2] as Vector3))
		await _shot(str(s[0]))
	var lairs := get_tree().get_first_node_in_group("lair_director")
	_check("lair enemies awake near the gym: %d" % lairs.active_count, lairs.active_count > 0)
	# Wren in the holding cell.
	var wren := khs.get_node_or_null("Wren")
	var dialogue := get_tree().get_first_node_in_group("dialogue")
	if wren:
		_player.global_position = wren.global_position + Vector3(0, 0.3, 1.8)
		await get_tree().create_timer(1.0).timeout
		dialogue.request_talk(wren.get_path())
		await get_tree().create_timer(0.5).timeout
		dialogue.request_leave()
		_check("found Wren -> mq_wren, Skyler's Sister started", QuestRules.flag_met(_q.flags, "mq_wren"))
	# Hunter: talk into the fight.
	var hunter := khs.get_node_or_null("HunterNpc")
	_check("Hunter Conner NPC in the gym", hunter != null)
	if hunter:
		_player.global_position = hunter.global_position + Vector3(2.0, 0.3, 0)
		_player.yaw = atan2(2.0, 0.0)
		await get_tree().create_timer(1.0).timeout
		dialogue.request_talk(hunter.get_path())
		await get_tree().create_timer(0.5).timeout
		await _shot("khs_hunter_talk.png")
		dialogue.request_choice(3)  # straight to the fight
		await get_tree().create_timer(2.5).timeout
		_check("fight started: flag set, NPC hidden", QuestRules.flag_met(_q.flags, "hunter_fight") and not hunter.visible)
		var boss: Node3D = null
		for b in get_tree().get_nodes_in_group("bosses"):
			if b.net_enemy == "hunter_conner":
				boss = b
		_check("Hunter Conner boss spawned", boss != null)
		if boss:
			_player.health.current = _player.health.max_health
			_player.global_position = boss.global_position + Vector3(8, 0.5, 0)
			_player.yaw = atan2(8.0, 0.0)
			await get_tree().create_timer(2.0).timeout
			await _shot("khs_hunter_boss.png")
			var hp0: float = _player.health.current
			await get_tree().create_timer(2.0).timeout
			_say("Hunter + guards over 2 s: player HP %d -> %d" % [roundi(hp0), roundi(_player.health.current)])
			_player.health.damage_mult = 0.0  # test god mode for the rest of the run
			_player.health.current = _player.health.max_health
			if _player.life.net_state != LifeState.ALIVE:
				_player.life.host_set_alive()
			boss.health.apply_damage(boss.health.max_health * 0.6, 1)
			await get_tree().create_timer(0.5).timeout
			_check("enraged below half", boss._enraged)
			boss.health.apply_damage(boss.health.max_health, 1)
			await get_tree().create_timer(1.0).timeout
			_check("boss_hunter_conner_dead set", QuestRules.flag_met(_q.flags, "boss_hunter_conner_dead"))
			var drops: WorldDrops = get_tree().get_first_node_in_group("world_drops")
			var card := 0
			for id: int in drops.drops:
				if drops.drops[id][0] == "eagle_keycard":
					card = id
			_check("eagle keycard dropped", card > 0)
			if card > 0:
				_player.global_position = drops.drops[card][2] + Vector3(0, 0.3, 0.8)
				await get_tree().create_timer(0.5).timeout
				drops.request_pickup(card)
				await get_tree().create_timer(1.5).timeout
			_check("keycard picked up -> Detention done, Acknowledged active", QuestRules.flag_met(_q.flags, "mq3_detention_done")
				and QuestRules.status(defs.mq4_acknowledged, _q.flags) == QuestRules.Status.ACTIVE)
	if wren:
		_player.global_position = wren.global_position + Vector3(0, 0.3, 1.8)
		await get_tree().create_timer(1.0).timeout
		dialogue.request_talk(wren.get_path())
		await get_tree().create_timer(0.5).timeout
		_check("Wren freed after the boss (node %s)" % dialogue._node_id, QuestRules.flag_met(_q.flags, "wren_free"))
		await get_tree().create_timer(1.0).timeout
		_check("Wren left the school", not wren.visible)
	# Quest book.
	var book := get_tree().get_first_node_in_group("quest_book")
	var ev := InputEventAction.new()
	ev.action = "quest_book"
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().create_timer(1.0).timeout
	_check("quest book opens on J", book.visible)
	await _shot("khs_quest_book.png")
	var worst := 0.0
	_player.global_position = _o + Vector3(30, 1.0, -92)
	if book.visible:
		Input.parse_input_event(ev)
	await get_tree().create_timer(4.0).timeout
	for i in 120:
		await get_tree().process_frame
		worst = maxf(worst, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_say("perf in the north hall: frame %.1f ms (worst process %.1f ms), draw calls %d, VRAM %d MB, lair active %d" % [
		1000.0 / maxf(Engine.get_frames_per_second(), 1.0), worst,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, lairs.active_count])
	_finish(main)


func _finish(main: Node) -> void:
	_say("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/khs_result.txt", FileAccess.WRITE)
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
	print("KHS: " + s)
	_log.append(s)
