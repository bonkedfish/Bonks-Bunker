# ArchwayTest — checks the Archway landmark + Evan (D-049): hosts a throwaway world, screenshots the Archway
# outside and each museum room into res://tests/_look/archway_*.png, walks the local player in the lobby door and up
# the switchback stairs, through the exhibit rooms to Evan, talks to him (jerky gift, trade with and without duct
# tape), opens a loot container, and reports frame time / draw calls there. Results: tests/_look/archway_result.txt.
# Depends on: scenes/main.tscn, SaveStore, the "archway" landmark node, DialogueDirector, InventoryHolder.
extends Node

const OUT_DIR := "res://tests/_look"
# [file, camera (local, y above origin), look-at (local)]
const SHOTS := [
	["archway_east.png", Vector3(70, 3, 10), Vector3(0, 12, 0)],
	["archway_parking.png", Vector3(-55, 3, -115), Vector3(0, 12, -50)],
	["archway_air.png", Vector3(110, 70, 100), Vector3(0, 8, 0)],
	["archway_under.png", Vector3(45, 2, -17), Vector3(0, 8, -17)],
	["archway_room_wagon.png", Vector3(5, 10.7, -39), Vector3(0, 10, -28)],
	["archway_room_buffalo.png", Vector3(-5, 10.7, -19), Vector3(3, 10, -9)],
	["archway_room_diner.png", Vector3(-3, 10.7, 1), Vector3(8, 10.2, 10)],
	["archway_room_gift.png", Vector3(-5, 10.7, 21), Vector3(0, 10, 32)],
	["archway_evan_camp.png", Vector3(-3, 10.7, 41.5), Vector3(4, 10.3, 49)],
	["archway_lobby.png", Vector3(8, 1.7, -42), Vector3(-6, 3, -48)],
]
const ROUTE := [Vector2(13, -46), Vector2(9, -46), Vector2(-5, -49), Vector2(-6.5, -51), Vector2(-9, -51),
	Vector2(-9, -42.8), Vector2(-8, -41.5), Vector2(-7, -42.8), Vector2(-7, -50.6), Vector2(-3, -51), Vector2(0, -44),
	Vector2(0, -38), Vector2(-5.5, -37), Vector2(-5.5, -22), Vector2(-5.5, -18), Vector2(-5.5, -6), Vector2(6, -1),
	Vector2(6, 2), Vector2(-5.5, 17), Vector2(-6, 22), Vector2(-4, 32), Vector2(-3, 38), Vector2(0, 42), Vector2(0.5, 45)]

var _log := PackedStringArray()
var _player: Node3D
var _cam: Camera3D
var _o := Vector3.ZERO
var _fails := 0


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz archway")
	main._on_host_pressed()
	await get_tree().create_timer(4.0).timeout
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for n: Node in get_tree().get_nodes_in_group("players"):
		if "water" in n:
			_player = n
	var arch: Node3D = get_tree().root.find_child("archway", true, false)
	_check("archway landmark loaded", arch != null)
	if arch == null:
		_finish(main)
		return
	_o = arch.global_position
	_say("archway origin %s" % _o.snapped(Vector3.ONE * 0.1))
	var loot := arch.find_children("Loot_*", "", false, false)
	_check("archway loot containers: %d" % loot.size(), loot.size() >= 20)
	var evan := arch.get_node_or_null("Evan")
	_check("Evan placed", evan != null and evan.display_name.begins_with("Evan"))
	_player.global_position = _o + Vector3(13, 1, -46)
	_player.velocity = Vector3.ZERO
	await get_tree().create_timer(6.0).timeout
	_cam = Camera3D.new()
	_cam.fov = 75.0
	add_child(_cam)
	for s: Array in SHOTS:
		_cam.make_current()
		_cam.global_position = _o + (s[1] as Vector3)
		_cam.look_at(_o + (s[2] as Vector3))
		await _shot(str(s[0]))
	await _walk()
	if evan:
		await _talk(evan)
	if loot.size() > 0:
		var c: Node = loot[0]
		for l: Node in loot:  # the host only opens containers within reach
			if l.global_position.distance_to(_player.global_position) < c.global_position.distance_to(_player.global_position):
				c = l
		_player.global_position = c.global_position + Vector3(0, 0.2, -1.2)
		await get_tree().create_timer(0.5).timeout
		c.request_open()
		_check("container %s rolled %s" % [c.container_id, c.contents], c.net_remaining >= 0)
		var ui := get_tree().get_first_node_in_group("loot_ui")
		if ui and ui.has_method("close"):
			ui.close()
	await get_tree().create_timer(1.0).timeout
	var worst := 0.0
	for i in 120:
		await get_tree().process_frame
		worst = maxf(worst, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_say("perf at Evan: frame %.1f ms (worst process %.1f ms), draw calls %d, VRAM %d MB" % [
		1000.0 / maxf(Engine.get_frames_per_second(), 1.0), worst,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	_finish(main)


func _walk() -> void:
	var pc: Camera3D = _player.get_node("Head/Camera3D") if _player.has_node("Head/Camera3D") else null
	if pc:
		pc.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_player.global_position = _o + Vector3(13, 0.5, -46)
	_player.velocity = Vector3.ZERO
	await get_tree().create_timer(1.0).timeout
	var t0 := Time.get_ticks_msec()
	for wp: Vector2 in ROUTE:
		var target := Vector3(_o.x + wp.x, 0, _o.z + wp.y)
		var start := Time.get_ticks_msec()
		while Time.get_ticks_msec() - start < 7000:
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
	await get_tree().create_timer(0.5).timeout
	var lp := _player.global_position - _o
	_check("walk: %.1f s, ended at local %s (deck is 9 m)" % [(Time.get_ticks_msec() - t0) / 1000.0, lp.snapped(Vector3.ONE * 0.1)],
		lp.y > 8.5 and lp.z > 43.0)
	_player.yaw = atan2(-1.5, -2.5)  # toward Evan
	_player.pitch = -0.1
	await _shot("archway_meet_evan.png")


func _talk(evan: Node) -> void:
	var dialogue := get_tree().get_first_node_in_group("dialogue")
	var inv: InventoryHolder = _player.inventory
	_player.global_position = evan.global_position + Vector3(-1.5, 0.2, -1.5)
	await get_tree().create_timer(0.5).timeout
	dialogue.request_talk(evan.get_path())
	await get_tree().create_timer(0.5).timeout
	_check("talk started", dialogue._talker != 0 and dialogue._node_id == "start")
	await _shot("archway_evan_talk.png")
	var jerky0 := inv.count("evans_jerky")
	for i in [3, 0]:  # jerky -> jerky_gift
		dialogue.request_choice(i)
	_check("jerky gift: %d -> %d" % [jerky0, inv.count("evans_jerky")], inv.count("evans_jerky") == jerky0 + 2)
	dialogue.request_choice(0)  # -> menu
	dialogue.request_choice(0)  # -> shop
	inv.host_remove("duct_tape", inv.count("duct_tape"))
	dialogue.request_choice(0)
	_check("trade without tape -> %s" % dialogue._node_id, dialogue._node_id == "broke")
	dialogue.request_choice(0)  # -> shop
	inv.host_add("duct_tape", 1)
	var ammo0 := inv.count("ammo_9mm")
	dialogue.request_choice(0)
	_check("trade tape -> ammo %d -> %d, tape %d" % [ammo0, inv.count("ammo_9mm"), inv.count("duct_tape")],
		inv.count("ammo_9mm") == ammo0 + 15 and inv.count("duct_tape") == 0)
	await get_tree().create_timer(2.0).timeout
	await _shot("archway_evan_trade.png")
	dialogue.request_leave()
	await get_tree().create_timer(0.5).timeout
	_check("talk ended", dialogue._talker == 0)


func _finish(main: Node) -> void:
	_say("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/archway_result.txt", FileAccess.WRITE)
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
	print("ARCHWAY: " + s)
	_log.append(s)
