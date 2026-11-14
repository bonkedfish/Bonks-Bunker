# PoolHud — the seated pool player's overlay (D-084), added to the HUD by PoolTable: whose shot it is (and your
# group once groups are set), the table's last message, the power bar while it's your shot, and the ball-in-hand hint.
# Bottom centre, built in code; texts only change when they do. Presentation only. Depends on: nothing.
class_name PoolHud
extends Control

const W := 420.0

var _title: Label
var _msg: Label
var _bar_back: ColorRect
var _bar: ColorRect
var _last := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -W * 0.5
	offset_right = W * 0.5
	offset_top = -170.0
	offset_bottom = -90.0
	_title = _label(22, Vector2(0, 0))
	_msg = _label(15, Vector2(0, 28))
	_msg.add_theme_color_override("font_color", Color(0.85, 0.85, 0.8))
	_bar_back = _rect(Vector2(0, 54), Vector2(W, 14), Color(0, 0, 0, 0.55))
	_bar = _rect(Vector2(0, 54), Vector2(0, 14), Color(0.95, 0.75, 0.25))


func show_state(my_turn: bool, msg: String, group: String, charge: float, placing: bool, shooter: String) -> void:
	var title := ("Your shot" if my_turn else "%s's shot" % shooter) + (" - you're %s" % group if group != "" else "")
	if placing:
		title = "Ball in hand - click the felt to place the cue ball"
	var key := title + "|" + msg
	if key != _last:
		_last = key
		_title.text = title
		_msg.text = msg
	_bar_back.visible = my_turn and not placing
	_bar.visible = _bar_back.visible
	_bar.size.x = W * clampf(charge, 0.0, 1.0)


func _label(font_size: int, pos: Vector2) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(W, 26)
	l.position = pos
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _rect(pos: Vector2, sz: Vector2, col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = sz
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r
