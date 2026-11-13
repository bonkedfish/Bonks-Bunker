# StartMenu — the start screen (D-063), Main's $UI/Menu: "BONK'S BUNKER" with Singleplayer (offline, no lobby),
# Multiplayer (host a world with a lobby code, or join one), Settings (opens the shared SettingsMenu), Controls
# (every keybind, read live from the InputMap) and Quit. Singleplayer and Multiplayer share one WorldPicker
# (saved worlds, new world, delete). Main connects the play_offline / host / join signals and writes status_label.
# Builds its controls in code. Depends on: WorldPicker, ControlsList, SettingsMenu ($UI/Settings, group "settings_menu").
extends ColorRect

signal play_offline
signal host
signal join

const WorldPicker := preload("res://scripts/ui/world_picker.gd")
const ControlsList := preload("res://scripts/ui/controls_list.gd")

var world_picker: VBoxContainer
var code_field: LineEdit
var status_label: Label

var _pages: Dictionary = {}
var _title: Label


func _ready() -> void:
	color = Color(0.05, 0.045, 0.035, 0.92)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	_title = Label.new()
	_title.text = "BONK'S BUNKER"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 44)
	_title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45))
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_title.add_theme_constant_override("outline_size", 8)
	box.add_child(_title)
	var sub := Label.new()
	sub.text = "Kearney, Nebraska  -  five years after"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6))
	box.add_child(sub)
	world_picker = WorldPicker.new()
	code_field = LineEdit.new()
	code_field.placeholder_text = "Lobby code, e.g. K7QPX"
	code_field.max_length = 5
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Pages.
	var home := _page(box, "home")
	for spec: Array in [["Singleplayer", _show.bind("single")], ["Multiplayer", _show.bind("multi")],
			["Settings", _open_settings], ["Controls", _show.bind("controls")], ["Quit", func() -> void: get_tree().quit()]]:
		_button(home, str(spec[0]), spec[1])
	var single := _page(box, "single")
	_heading(single, "SINGLEPLAYER")
	_hint(single, "Plays offline: no lobby, no internet needed.")
	_button(single, "Play", func() -> void: play_offline.emit())
	_button(single, "Back", _show.bind("home"))
	var multi := _page(box, "multi")
	_heading(multi, "MULTIPLAYER")
	_hint(multi, "Host a world and share the lobby code (up to 6 players), or join a friend's code.")
	_button(multi, "Host", func() -> void: host.emit())
	var sep := HSeparator.new()
	multi.add_child(sep)
	multi.add_child(code_field)
	_button(multi, "Join", func() -> void: join.emit())
	_button(multi, "Back", _show.bind("home"))
	var controls := _page(box, "controls")
	_heading(controls, "CONTROLS")
	controls.add_child(ControlsList.build())
	_button(controls, "Back", _show.bind("home"))
	box.add_child(status_label)
	single.add_child(world_picker)  # in the tree from the start (tests pick a world before any page is shown)
	single.move_child(world_picker, 2)
	_show("home")


func _show(page: String) -> void:
	for id: String in _pages:
		_pages[id].visible = id == page
	if page == "single" or page == "multi":  # both use the same world list, just above their buttons
		if world_picker.get_parent():
			world_picker.get_parent().remove_child(world_picker)
		var p: VBoxContainer = _pages[page]
		p.add_child(world_picker)
		p.move_child(world_picker, 2)
		world_picker.refresh()
	status_label.text = ""


func _open_settings() -> void:
	var s := get_tree().get_first_node_in_group("settings_menu")
	if s:
		s.open()


func _keys_for(action: String) -> String:
	return ControlsList.keys_for(action)


func _page(parent: Control, id: String) -> VBoxContainer:
	var p := VBoxContainer.new()
	p.add_theme_constant_override("separation", 8)
	parent.add_child(p)
	_pages[id] = p
	return p


func _heading(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 20)
	parent.add_child(l)


func _hint(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
	parent.add_child(l)


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 38)
	b.pressed.connect(action)
	parent.add_child(b)
	return b
