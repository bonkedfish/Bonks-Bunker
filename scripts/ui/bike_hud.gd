# BikeHud — the rider's gauges while on a motorcycle (D-083), added to the HUD by BikeRider: speed (km/h), gear
# (N, 1-6), a rev bar with the redline marked (flashes red on the limiter), a CLUTCH light while Shift is held, the
# fuel bar, and STALLED / OUT OF GAS, with the riding controls listed above the gauges. Bottom right, built in code;
# texts only change when the numbers do. Group "bike_hud" (the debug readout hides while it's up).
# Presentation only. Depends on: nothing.
class_name BikeHud
extends Control

const W := 260.0
const CONTROLS := [["W / S", "throttle / brake"], ["A / D", "lean"], ["Shift + E / Q", "shift up / down"],
	["Space / Ctrl", "wheelie / stoppie"], ["B / R", "start / refuel"], ["F", "get off (slow)"], ["V", "camera"]]

var _speed: Label
var _gear: Label
var _clutch: Label
var _warn: Label
var _rev_back: ColorRect
var _rev: ColorRect
var _red: ColorRect
var _fuel: ColorRect
var _last_speed := -1
var _last_gear := -1
var _flash := 0.0


func _ready() -> void:
	add_to_group("bike_hud")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = -W - 30.0
	offset_top = -200.0
	offset_right = -30.0
	offset_bottom = -50.0
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.size = Vector2(W, 150.0)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_speed = _label(46, Vector2(14, 4))
	_gear = _label(52, Vector2(W - 64, 0))
	_gear.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
	var unit := _label(14, Vector2(16, 60))
	unit.text = "km/h"
	_rev_back = _rect(Vector2(14, 86), Vector2(W - 28, 16), Color(0.15, 0.15, 0.16))
	_rev = _rect(Vector2(14, 86), Vector2(0, 16), Color(0.3, 0.85, 0.4))
	_red = _rect(Vector2(14 + (W - 28) * 0.88, 84), Vector2(3, 20), Color(0.9, 0.15, 0.1))
	var fuel_label := _label(13, Vector2(14, 108))
	fuel_label.text = "GAS"
	_rect(Vector2(50, 112), Vector2(W - 64, 9), Color(0.15, 0.15, 0.16))
	_fuel = _rect(Vector2(50, 112), Vector2(W - 64, 9), Color(0.9, 0.7, 0.2))
	_clutch = _label(15, Vector2(W - 92, 58))
	_clutch.text = "CLUTCH"
	_clutch.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	_warn = _label(16, Vector2(14, 124))
	_warn.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	var rows := CONTROLS.size()
	var top := -8.0 - rows * 19.0 - 12.0
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.35)
	back.position = Vector2(0, top)
	back.size = Vector2(W, rows * 19.0 + 12.0)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	for i in rows:
		var key := _label(14, Vector2(12, top + 5.0 + i * 19.0))
		key.text = str(CONTROLS[i][0])
		key.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
		var what := _label(14, Vector2(118, top + 5.0 + i * 19.0))
		what.text = str(CONTROLS[i][1])


func show_state(speed_mps: float, gear: int, rpm: float, redline: float, clutch_in: bool, fuel: float, tank: float,
		engine_on: bool, limiter: bool) -> void:
	var kmh := roundi(speed_mps * 3.6)
	if kmh != _last_speed:
		_last_speed = kmh
		_speed.text = str(kmh)
	if gear != _last_gear:
		_last_gear = gear
		_gear.text = "N" if gear == 0 else str(gear)
	var frac := clampf(rpm / (redline / 0.88), 0.0, 1.0)  # the bar runs a bit past the redline
	_rev.size.x = (W - 28) * frac
	_flash = fmod(_flash + get_process_delta_time() * 8.0, 1.0)
	_rev.color = Color(0.95, 0.2, 0.15) if limiter and _flash < 0.5 else (Color(1.0, 0.6, 0.15) if frac > 0.8 else Color(0.3, 0.85, 0.4))
	_fuel.size.x = (W - 64) * clampf(fuel / maxf(tank, 0.1), 0.0, 1.0)
	_fuel.color = Color(0.95, 0.25, 0.2) if fuel < tank * 0.15 else Color(0.9, 0.7, 0.2)
	_clutch.visible = clutch_in
	var warn := "OUT OF GAS (R + gas can)" if fuel <= 0.0 else ("STALLED - B to start" if not engine_on else "")
	if _warn.text != warn:
		_warn.text = warn


func _label(font_size: int, pos: Vector2) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
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
