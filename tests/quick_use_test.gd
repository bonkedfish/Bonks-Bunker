# QuickUseTest — G (quick_eat) and H (quick_heal) as real key presses: standing still in game, while walking, and
# with the inventory open. Results: tests/_look/quick_use_result.txt. Depends on: scenes/main.tscn, ItemUse.
extends Node

const OUT_DIR := "res://tests/_look"

var _log := PackedStringArray()


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz quickuse")
	main.menu.play_offline.emit()
	await get_tree().create_timer(5.0).timeout
	var player: Node = get_tree().get_first_node_in_group("local_player")
	var slug: String = main.saves.world_slug
	player.inventory.host_add("canned_beans", 2)
	player.inventory.host_add("water_bottle", 2)
	player.needs.host_set(Vector2(40, 30))
	_say("mouse mode before: %d, items %s" % [Input.mouse_mode, player.inventory.model.to_dict()])
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().create_timer(0.3).timeout
	_say("mouse mode captured? %d" % Input.mouse_mode)
	_key(KEY_G)
	await get_tree().create_timer(0.3).timeout
	_say("standing, G: using '%s' progress %.2f" % [player.item_use.net_use_item, player.item_use.net_use_progress])
	await get_tree().create_timer(2.0).timeout
	_say("after 2 s: needs %s, using '%s'" % [player.needs.value(), player.item_use.net_use_item])
	var inv := get_tree().get_first_node_in_group("inventory_ui")
	inv.open()
	await get_tree().create_timer(0.3).timeout
	_say("inventory open: %s, mouse %d" % [inv.visible, Input.mouse_mode])
	_key(KEY_G)
	await get_tree().create_timer(0.3).timeout
	_say("inventory, G: using '%s'" % player.item_use.net_use_item)
	var f := FileAccess.open(OUT_DIR + "/quick_use_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(slug)
	get_tree().quit()


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event.call_deferred(up)


func _say(s: String) -> void:
	print("QUICKUSE: " + s)
	_log.append(s)
