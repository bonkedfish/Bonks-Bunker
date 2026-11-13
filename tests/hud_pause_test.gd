# HudPauseTest — checks D-066..D-068: starts an offline singleplayer world, adds every chem effect and a Meepo,
# screenshots the HUD (icon chips + minimap) into res://tests/_look/hud_icons.png and an effect close-up, checks the
# minimap shows and hides under the big map, opens the pause menu with Esc (solo -> tree paused), its Controls list,
# Esc closes it (unpaused), then Save & Quit -> back on a fresh start screen with the world saved.
# Results: tests/_look/hud_pause_result.txt. Depends on: scenes/main.tscn, PauseMenu, StatusBar, Minimap, SaveStore.
extends Node

const OUT_DIR := "res://tests/_look"

var _log := PackedStringArray()
var _fails := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz hud")
	main.menu.play_offline.emit()
	await get_tree().create_timer(5.0).timeout
	var player: Node3D = get_tree().get_first_node_in_group("local_player")
	var slug: String = main.saves.world_slug
	var hud := get_tree().get_first_node_in_group("hud")
	player.inventory.host_add("meepo", 1)
	for id: String in ["baked", "tripping_shrooms", "tripping_acid", "rolling", "nodding", "fried", "dope_sick", "comedown"]:
		player.effects.host_add(id)
	await get_tree().create_timer(1.5).timeout
	_check("status chips show the effects: %s" % [hud.status.effect_names()], hud.status.effect_names().size() >= 6)
	var mini: Control = null
	for c in hud.get_children():
		if c.get_script() == preload("res://scripts/ui/minimap.gd"):
			mini = c
	_check("minimap visible in game", mini != null and mini.visible)
	# Walk out of the bunker so the minimap has streets on it.
	player.global_position = main.get_node("World").spawn_hint + Vector3(-20, 3, 30)
	await get_tree().create_timer(3.0).timeout
	await _shot("hud_icons.png")
	var img := get_viewport().get_texture().get_image()
	img.get_region(Rect2i(0, img.get_height() - 90, 1100, 90)).save_png(OUT_DIR + "/hud_icons_close.png")
	img.get_region(Rect2i(0, 0, 250, 250)).save_png(OUT_DIR + "/hud_minimap_close.png")
	var map := get_tree().get_first_node_in_group("world_map_ui")
	map.open()
	await get_tree().create_timer(0.3).timeout
	_check("minimap hides under the big map", mini != null and not mini.visible)
	map.close()
	# Pause.
	_esc()
	await get_tree().create_timer(0.3).timeout
	var pause := get_tree().get_first_node_in_group("pause_menu")
	_check("Esc opens the pause menu, solo game paused", pause.visible and get_tree().paused)
	pause._toggle_controls()
	await _shot("pause_menu.png")
	_esc()
	await get_tree().create_timer(0.3).timeout
	_check("Esc again resumes (unpaused)", not pause.visible and not get_tree().paused)
	_esc()
	await get_tree().create_timer(0.3).timeout
	pause.save_and_quit()
	await get_tree().create_timer(2.0).timeout
	var fresh: Node = null
	for c in get_children():
		if is_instance_valid(c) and c.name == "Main":
			fresh = c
	_check("Save & Quit -> fresh start screen", fresh != null and fresh != main and fresh.menu.visible
		and get_tree().get_first_node_in_group("local_player") == null)
	_check("world was saved on quit", SaveStore.list_worlds().any(func(w: Dictionary) -> bool: return str(w.slug) == slug))
	await _shot("after_quit.png")
	SaveStore.delete(slug)
	_say("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/hud_pause_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()


func _esc() -> void:
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	Input.parse_input_event(ev)


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
	print("HUDPAUSE: " + s)
	_log.append(s)
