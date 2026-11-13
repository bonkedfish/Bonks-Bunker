# SubtitleUI — NPC barks and conversation lines as Fallout-style captions (D-034, style D-036):
# speaker name on top, line underneath, centred low on screen, white text with a dark outline, no box.
# One speaker at a time: a player's reply shows first, then the NPC's answer.
# Everyone within the speaking NPC's subtitle_range (sent with each line) sees them (the talker always does). Only the talker gets the
# reply options; while choosing, the mouse is free and Esc leaves the conversation.
# Builds its controls in code. Group "subtitles". Depends on: DialogueDirector (group "dialogue"),
# local Player (group "local_player").
extends Control

const MIN_SHOW := 3.0
const SECONDS_PER_CHAR := 0.05
const REPLY_MIN_SHOW := 1.2
const REPLY_SECONDS_PER_CHAR := 0.035
const TEXT_SIZE := 22
const OUTLINE_SIZE := 7
const TEXT_COLOR := Color(1, 1, 1)
const OUTLINE_COLOR := Color(0, 0, 0, 0.85)
const CHOICE_COLOR := Color(0.85, 0.85, 0.85)
const CHOICE_HOVER := Color(1.0, 0.82, 0.35)
const MAX_WIDTH := 900.0

var choosing := false

var _root: VBoxContainer
var _name: Label
var _label: Label
var _choices: VBoxContainer
var _hide_at := 0.0
# Bonk's line waiting while the player's reply is on screen.
var _pending := false
var _pending_at := 0.0
var _pending_speaker := ""
var _pending_text := ""
var _pending_choices := PackedStringArray()
var _pending_is_talker := false


func _ready() -> void:
	add_to_group("subtitles")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root = VBoxContainer.new()
	_root.anchor_left = 0.5
	_root.anchor_right = 0.5
	_root.anchor_top = 1.0
	_root.anchor_bottom = 1.0
	_root.offset_left = -MAX_WIDTH * 0.5
	_root.offset_right = MAX_WIDTH * 0.5
	_root.offset_bottom = -90.0
	_root.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.alignment = BoxContainer.ALIGNMENT_END
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_theme_constant_override("separation", 2)
	add_child(_root)
	_name = _caption_label()
	_root.add_child(_name)
	_label = _caption_label()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(MAX_WIDTH, 0)
	_root.add_child(_label)
	_choices = VBoxContainer.new()
	_choices.alignment = BoxContainer.ALIGNMENT_CENTER
	_choices.add_theme_constant_override("separation", 0)
	_root.add_child(_choices)
	_root.hide()


func show_line(speaker: String, text: String, reply: String, choices: PackedStringArray, talker: int,
		at: Vector3, heard_m: float) -> void:
	var is_talker := talker == multiplayer.get_unique_id()
	if not is_talker and not _near(at, heard_m):
		return
	_clear_choices()
	if reply != "":
		_show_caption("You" if is_talker else "Friend", reply)
		_hide_at = INF
		_pending = true
		_pending_at = _now() + maxf(REPLY_MIN_SHOW, reply.length() * REPLY_SECONDS_PER_CHAR)
		_pending_speaker = speaker
		_pending_text = text
		_pending_choices = choices
		_pending_is_talker = is_talker
		return
	_show_bonk_line(speaker, text, choices, is_talker)


func show_bark(speaker: String, text: String, at: Vector3, heard_m: float) -> void:
	if choosing or _pending or not _near(at, heard_m):
		return
	_clear_choices()
	_show_caption(speaker, text)
	_hide_at = _now() + maxf(MIN_SHOW, text.length() * SECONDS_PER_CHAR)


func end_conversation() -> void:
	_clear_choices()
	if choosing:
		_set_choosing(false)
	if _pending:  # the conversation ended on a reply: still show Bonk's last word
		_pending_choices = PackedStringArray()
	else:
		_hide_at = minf(_hide_at, _now() + 1.0)


func _show_bonk_line(speaker: String, text: String, choices: PackedStringArray, is_talker: bool) -> void:
	_show_caption(speaker, text)
	if is_talker and not choices.is_empty():
		for i in choices.size():
			_choices.add_child(_choice_button(i, choices[i]))
		_set_choosing(true)
		_hide_at = INF
	else:
		if is_talker and choosing:
			_set_choosing(false)  # final line: back to playing
		_hide_at = _now() + maxf(MIN_SHOW, text.length() * SECONDS_PER_CHAR)


func _show_caption(speaker: String, text: String) -> void:
	_name.text = speaker
	_label.text = text
	_root.show()


func _caption_label() -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", TEXT_SIZE)
	l.add_theme_color_override("font_color", TEXT_COLOR)
	l.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	l.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# Reply options: plain outlined text like the captions, highlighted on hover.
func _choice_button(index: int, text: String) -> Button:
	var b := Button.new()
	b.text = "%d.  %s" % [index + 1, text]
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", TEXT_SIZE - 2)
	b.add_theme_color_override("font_color", CHOICE_COLOR)
	b.add_theme_color_override("font_hover_color", CHOICE_HOVER)
	b.add_theme_color_override("font_pressed_color", CHOICE_HOVER)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5))
	b.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	b.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	b.pressed.connect(_choose.bind(index))
	return b


func _clear_choices() -> void:
	for c in _choices.get_children():
		c.queue_free()


func _choose(index: int) -> void:
	for c in _choices.get_children():
		(c as Button).disabled = true
	var dialogue := get_tree().get_first_node_in_group("dialogue")
	if dialogue:
		dialogue.request_choice.rpc_id(1, index)


func _set_choosing(value: bool) -> void:
	choosing = value
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if choosing and event.is_action_pressed("ui_cancel"):
		var dialogue := get_tree().get_first_node_in_group("dialogue")
		if dialogue:
			dialogue.request_leave.rpc_id(1)
		end_conversation()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _pending and _now() >= _pending_at:
		_pending = false
		_show_bonk_line(_pending_speaker, _pending_text, _pending_choices, _pending_is_talker)
	elif _root.visible and not choosing and not _pending and _now() >= _hide_at:
		_root.hide()


func _near(at: Vector3, heard_m: float) -> bool:
	var me := get_tree().get_first_node_in_group("local_player")
	return me != null and me.global_position.distance_to(at) <= heard_m


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
