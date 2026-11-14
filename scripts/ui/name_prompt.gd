# NamePrompt — "Name your survivor" (D-081). The host opens it on a player's own screen (Player.ask_name) when their
# character in this world has no name yet; Enter or Start sends the name to the host (Player.submit_name), which
# cleans it, keeps it in the world save and shows it on that player's name tag. Esc can't skip it.
# Builds its controls in code; added under $UI by Main. Group "name_prompt". Depends on: NameTag (max_length).
extends Control

const NameTag := preload("res://scripts/player/name_tag.gd")

var _player: Node
var _field: LineEdit


func _ready() -> void:
	add_to_group("name_prompt")
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
	panel.custom_minimum_size = Vector2(380, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "NAME YOUR SURVIVOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45))
	box.add_child(title)
	var note := Label.new()
	note.text = "Kept with this world's save. Other players see it over your head."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
	box.add_child(note)
	_field = LineEdit.new()
	_field.placeholder_text = "Name"
	_field.max_length = int(NameTag.load_tuning().get("max_length", 20))
	_field.custom_minimum_size = Vector2(0, 34)
	_field.text_submitted.connect(func(_t: String) -> void: submit())
	box.add_child(_field)
	var b := Button.new()
	b.text = "Start"
	b.custom_minimum_size = Vector2(0, 34)
	b.pressed.connect(submit)
	box.add_child(b)
	hide()


func open(player: Node) -> void:
	_player = player
	_field.text = ""
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_field.grab_focus()


# Sends the typed name (tests call this with the name). Blank names keep the prompt open.
func submit(typed := "") -> void:
	var t := (typed if typed != "" else _field.text).strip_edges()
	if t == "" or not is_instance_valid(_player):
		return
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_player.submit_name.rpc_id(1, t)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()  # no pause menu over the prompt
