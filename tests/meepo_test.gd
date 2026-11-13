# MeepoTest — checks the Meepo electric longboard (D-057): hosts a throwaway world, takes a board from the bunker's
# Meepo Charging Dock, hops on (B), measures riding vs walking speed on an open street, checks no firing while riding,
# battery drain, a big hit knocking the rider off, and recharging at the dock. Screenshot: tests/_look/meepo_ride.png.
# Results: tests/_look/meepo_result.txt. Depends on: scenes/main.tscn, SaveStore, MeepoRider, LootContainer.
extends Node

const OUT_DIR := "res://tests/_look"

var _log := PackedStringArray()
var _fails := 0
var _p: Node3D


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz meepo")
	main._on_host_pressed()
	await get_tree().create_timer(5.0).timeout
	_p = get_tree().get_first_node_in_group("local_player")
	var dock: Node3D = null
	for c in get_tree().get_nodes_in_group("meepo_chargers"):
		dock = c
	_check("Meepo dock in the bunker", dock != null)
	if dock == null:
		_finish(main)
		return
	_p.global_position = dock.global_position + Vector3(-1.2, 0.3, 0)
	await get_tree().create_timer(1.0).timeout
	dock.request_open()
	await get_tree().create_timer(0.3).timeout
	dock.request_take("meepo", 1)
	await get_tree().create_timer(0.5).timeout
	var m: MeepoRider = _p.meepo
	_check("took a Meepo (dock had %s)" % dock.contents, m.has_board())
	var ui := get_tree().get_first_node_in_group("loot_ui")
	if ui and ui.visible and ui.has_method("close"):
		ui.close()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Open street: walk speed vs ride speed.
	_p.global_position = main.get_node("World").spawn_hint + Vector3(-20, 3, 30)  # open ground (see ubc_look_test)
	_p.velocity = Vector3.ZERO
	_p.yaw = PI
	await get_tree().create_timer(3.0).timeout
	var walk := await _speed()
	m._host_toggle()
	await get_tree().physics_frame
	_check("hopped on", m.net_riding)
	var ride := await _speed()
	_check("speed walking %.1f m/s, riding %.1f m/s" % [walk, ride], ride > walk * 2.0)
	Input.action_press("sprint")
	var boost := await _speed()
	Input.action_release("sprint")
	_check("Shift boosts: %.1f m/s (cruise %.1f)" % [boost, ride], boost > ride + 1.5)
	_p.pitch = -0.9
	await _shot("meepo_ride.png")
	_p.pitch = 0.0
	var mag0: int = _p.weapons.net_mag
	Input.action_press("fire")
	await get_tree().create_timer(0.6).timeout
	Input.action_release("fire")
	await get_tree().create_timer(0.3).timeout
	_check("no shooting while riding (mag %d -> %d)" % [mag0, _p.weapons.net_mag], _p.weapons.net_mag == mag0)
	var b0 := m._level
	await _speed()
	_check("battery drains while rolling: %.2f -> %.2f (30 min per charge)" % [b0, m._level], m._level < b0 and b0 - m._level < 0.5)
	_p.health.apply_damage(20.0, 99)
	await get_tree().physics_frame
	_check("20 damage knocks you off", not m.net_riding)
	m._level = 50.0
	m.net_battery = 50.0
	_p.global_position = dock.global_position + Vector3(-1.2, 0.3, 0)
	await get_tree().create_timer(1.5).timeout
	_check("recharges instantly at the dock: 50 -> %.1f" % m.net_battery, m.net_battery >= 100.0)
	_check("Bonk has Meepo lines", not DialogueDB.barks("meepo").is_empty())
	_finish(main)


# Holds forward for 2 s and returns the average horizontal speed.
func _speed() -> float:
	var start := _p.global_position
	Input.action_press("move_forward")
	await get_tree().create_timer(2.0).timeout
	Input.action_release("move_forward")
	var d := Vector2(_p.global_position.x - start.x, _p.global_position.z - start.z).length()
	await get_tree().create_timer(0.8).timeout
	return d / 2.0


func _finish(main: Node) -> void:
	_say("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/meepo_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SaveStore.delete(main.saves.world_slug)
	await get_tree().create_timer(2.0).timeout
	get_tree().quit()


func _shot(file: String) -> void:
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT_DIR + "/" + file)


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	_say(("PASS " if ok else "FAIL ") + what)


func _say(s: String) -> void:
	print("MEEPO: " + s)
	_log.append(s)
