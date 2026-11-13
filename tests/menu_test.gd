# MenuTest — checks the start screen and this round's fixes (D-063..D-065): screenshots the start screen pages
# (home, singleplayer, controls) into res://tests/_look/menu_*.png, starts an offline singleplayer world, takes ONE
# Meepo from the dock with the loot window's Take 1 (then Take Stack), toggles quest tracking in the quest book
# (main quest untracked -> HUD empty, Last Call ticked -> on the HUD), checks the downtown bars are on the world map,
# then quits back to the picker and deletes the save with the Delete button's confirm.
# Results: tests/_look/menu_result.txt. Depends on: scenes/main.tscn, StartMenu, WorldPicker, LootUI, QuestBookUI,
# WorldMapUI, SaveStore.
extends Node

const OUT_DIR := "res://tests/_look"

var _log := PackedStringArray()
var _fails := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.5).timeout
	var menu: Control = main.menu
	_check("start screen shows BONK'S BUNKER", menu.visible and menu._title.text == "BONK'S BUNKER")
	await _shot("menu_home.png")
	menu._show("controls")
	await _shot("menu_controls.png")
	_check("controls list the ride key: %s" % menu._keys_for("ride"), menu._keys_for("ride").contains("B"))
	menu._show("single")
	main.world_picker.choose_new("zz solo")
	await _shot("menu_single.png")
	menu.play_offline.emit()
	await get_tree().create_timer(5.0).timeout
	var player: Node3D = get_tree().get_first_node_in_group("local_player")
	_check("singleplayer started offline (no lobby code, player spawned)", player != null and not menu.visible
		and Net.lobby_code == "" and multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if player == null:
		_finish(main)
		return
	# Take 1 / Take Stack.
	var dock: Node3D = get_tree().get_first_node_in_group("meepo_chargers")
	var ui := get_tree().get_first_node_in_group("loot_ui")
	player.global_position = dock.global_position + Vector3(-1.2, 0.3, 0)
	await get_tree().create_timer(1.0).timeout
	dock.request_open()
	await get_tree().create_timer(0.5).timeout
	var before: int = int(dock.contents.get("meepo", 0))
	ui._take_one()
	await get_tree().create_timer(0.5).timeout
	_check("Take 1: dock %d -> %d, carrying %d" % [before, int(dock.contents.get("meepo", 0)), player.inventory.count("meepo")],
		int(dock.contents.get("meepo", 0)) == before - 1 and player.inventory.count("meepo") == 1)
	await _shot("menu_loot_window.png")
	ui._take_selected()
	await get_tree().create_timer(0.5).timeout
	_check("Take Stack empties that stack (carrying %d)" % player.inventory.count("meepo"), int(dock.contents.get("meepo", 0)) == 0)
	ui.close()
	# Quest tracking.
	var book := get_tree().get_first_node_in_group("quest_book")
	var hud := get_tree().get_first_node_in_group("hud")
	_check("main quest tracked by default: %s" % [book.tracked_quests()], book.tracked_quests().has("mq1_static"))
	book.set_tracked("mq1_static", false)
	await get_tree().create_timer(0.6).timeout
	_check("untracked -> HUD tracker empty", book.tracked_quests().is_empty() and hud._tracker.text == "")
	book.set_tracked("sq_last_call", true)
	book.set_tracked("mq1_static", true)
	await get_tree().create_timer(0.6).timeout
	_check("two tracked -> both on the HUD", hud._tracker.text.contains("Last Call") and hud._tracker.text.contains("Five Years"))
	book.open()
	await _shot("menu_quest_book.png")
	book.close()
	# World map labels.
	var map := get_tree().get_first_node_in_group("world_map_ui")
	map._load()
	var names: Array = []
	for l: Dictionary in map._meta.get("labels", []):
		names.append(str(l.name))
	_check("downtown bars on the world map", "Copperfields (raiders)" in names and "Gillie's (raiders)" in names)
	# Delete the world from the picker.
	main.saves.host_save("test")
	var slug: String = main.saves.world_slug
	var picker: Node = main.world_picker
	picker.refresh()
	var idx := -1
	for i in picker._worlds.size():
		if str(picker._worlds[i].slug) == slug:
			idx = i
	if idx >= 0:
		picker._list.select(idx)
		picker._on_selected(idx)
		picker._ask_delete()
		await get_tree().create_timer(0.3).timeout
		picker._confirm.hide()
		picker._do_delete()
		_check("Delete removes the saved world", not SaveStore.list_worlds().any(func(w: Dictionary) -> bool: return str(w.slug) == slug))
	else:
		_say("(world wasn't saved yet - nothing to delete; Delete checked on a fresh save next)")
	_finish(main)


func _finish(main: Node) -> void:
	_say("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/menu_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if main.saves.world_slug != "":
		SaveStore.delete(main.saves.world_slug)
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()


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
	print("MENU: " + s)
	_log.append(s)
