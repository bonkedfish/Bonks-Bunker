# PauseMenu — Esc in game (D-068): Resume, Settings (the shared SettingsMenu on top), Controls (keybind list),
# Save & Quit (host / singleplayer saves the world first, then everyone in this game goes back to the start screen)
# and Quit to Desktop (saves first when you're the host). Singleplayer freezes the game while it's open; in co-op the
# world keeps running. Leaves Esc to any other open window (inventory, loot, map, quest book, dialogue choice).
# Builds its controls in code; added under $UI by Main. Group "pause_menu". Depends on: Net autoload,
# SaveDirector (group "save_director"), SettingsMenu (group "settings_menu"), ControlsList.
extends Control

const ControlsList := preload("res://scripts/ui/controls_list.gd")
const OTHER_UIS := ["inventory_ui", "loot_ui", "crafting_ui", "world_map_ui", "quest_book", "settings_menu"]

var _controls: Control
var _note: Label


func _ready() -> void:
	add_to_group("pause_menu")
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45))
	box.add_child(title)
	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_font_size_override("font_size", 13)
	_note.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
	box.add_child(_note)
	for spec: Array in [["Resume", close], ["Settings", _settings], ["Controls", _toggle_controls],
			["Save & Quit to Menu", save_and_quit], ["Quit to Desktop", _quit_desktop]]:
		var b := Button.new()
		b.text = str(spec[0])
		b.custom_minimum_size = Vector2(0, 34)
		b.pressed.connect(spec[1])
		box.add_child(b)
	_controls = ControlsList.build()
	_controls.hide()
	box.add_child(_controls)
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	var settings := get_tree().get_first_node_in_group("settings_menu") as CanvasItem
	if settings and settings.visible:
		return  # Esc closes Settings first, back to this menu
	if visible:
		close()
		get_viewport().set_input_as_handled()
		return
	if not _can_open():
		return
	open()
	get_viewport().set_input_as_handled()


func _can_open() -> bool:
	if get_tree().get_first_node_in_group("local_player") == null:
		return false  # start screen or no body yet
	var menu := get_parent().get_node_or_null("Menu") as CanvasItem
	if menu and menu.visible:
		return false
	for g: String in OTHER_UIS:
		var ui := get_tree().get_first_node_in_group(g) as CanvasItem
		if ui and ui.visible:
			return false
	var subs := get_tree().get_first_node_in_group("subtitles")
	return not (subs != null and subs.choosing)


func is_solo() -> bool:
	return multiplayer.multiplayer_peer is OfflineMultiplayerPeer


func open() -> void:
	_controls.hide()
	_note.text = "Singleplayer: the game is paused" if is_solo() else "Co-op: the world keeps running"
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_solo():
		get_tree().paused = true


func close() -> void:
	if not visible:
		return
	hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func save_and_quit() -> void:
	_save_if_host()
	get_tree().paused = false
	Net.leave_to_menu.call_deferred(get_parent().get_parent())  # UI -> Main


func _quit_desktop() -> void:
	_save_if_host()
	get_tree().quit()


func _save_if_host() -> void:
	if multiplayer.is_server():
		var saves := get_tree().get_first_node_in_group("save_director")
		if saves:
			saves.host_save("quit")


func _settings() -> void:
	var s := get_tree().get_first_node_in_group("settings_menu")
	if s:
		s.process_mode = Node.PROCESS_MODE_ALWAYS
		s.open()


func _toggle_controls() -> void:
	_controls.visible = not _controls.visible
