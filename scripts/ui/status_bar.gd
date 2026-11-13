# StatusBar — the HUD's bottom-left status row (D-066): icon chips for health, food and water (value + a small
# fill bar), the Meepo battery when you carry a board (cyan border while riding, "B" hint otherwise), one chip per
# active chem effect (icon + seconds left, on a second row above), and warnings (hungry/thirsty, overweight) as text
# after the main chips.
# HUD calls set_state() only when something changed; this redraws then. Presentation only.
# Depends on: HudIcons, EffectRules (effect names).
extends Control

const CHIP_H := 34.0
const ICON := 22.0
const GAP := 6.0

var _hp := 100.0
var _food := 100
var _water := 100
var _meepo := Vector2i(-1, -1)
var _effects: Dictionary = {}
var _warn := ""
var _bg := StyleBoxFlat.new()
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_bg.bg_color = Color(0, 0, 0, 0.45)
	_bg.set_corner_radius_all(6)


# meepo = (battery %, riding 0/1), or (-1, -1) without a board. effects = { effect id: seconds left }.
func set_state(hp: float, food: int, water: int, meepo: Vector2i, effects: Dictionary, warnings: String) -> void:
	_hp = hp
	_food = food
	_water = water
	_meepo = meepo
	_effects = effects.duplicate()
	_warn = warnings
	queue_redraw()


# Effect names in the order shown (for tests and tooltips).
func effect_names() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in _effects:
		out.append(str(EffectRules.defs().get(id, {}).get("name", id)))
	return out


func _draw() -> void:
	var x := 0.0
	var y := size.y - CHIP_H
	x = _chip(x, y, "health", "%d" % ceili(_hp), _hp / 100.0, Color(0.9, 0.2, 0.2))
	x = _chip(x, y, "food", "%d" % _food, _food / 100.0, Color(0.85, 0.55, 0.25))
	x = _chip(x, y, "water", "%d" % _water, _water / 100.0, Color(0.3, 0.6, 1.0))
	if _meepo.x >= 0:
		x = _chip(x, y, "meepo", "%d%%" % _meepo.x + ("" if _meepo.y == 1 else "  B"), _meepo.x / 100.0, Color(0.2, 0.9, 1.0), _meepo.y == 1)
	var ex := 0.0
	for id: String in _effects:  # effects get their own row above, so they never run into the weapon/ammo text
		ex = _chip(ex, y - CHIP_H - GAP, id, "%ds" % int(_effects[id]), -1.0, HudIcons.color_of(id), true)
	if _warn != "":
		draw_string_outline(_font, Vector2(x + 4.0, y + CHIP_H * 0.68), _warn, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color(0, 0, 0, 0.9))
		draw_string(_font, Vector2(x + 4.0, y + CHIP_H * 0.68), _warn, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.55, 0.3))


# One chip at (x, y): backdrop, icon, value text, optional fill bar (fill < 0 = none) and highlight border.
# Returns the x after it.
func _chip(x: float, y: float, icon: String, text: String, fill: float, col: Color, highlight := false) -> float:
	var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var w := ICON + 14.0 + tw + 8.0
	var r := Rect2(x, y, w, CHIP_H)
	draw_style_box(_bg, r)
	if highlight:
		draw_rect(r.grow(-1.0), Color(col, 0.9), false, 2.0)
	HudIcons.draw(self, icon, Vector2(x + 6.0 + ICON * 0.5, y + CHIP_H * 0.5 - (2.0 if fill >= 0.0 else 0.0)), ICON)
	var tx := x + ICON + 12.0
	draw_string_outline(_font, Vector2(tx, y + CHIP_H * 0.66), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color(0, 0, 0, 0.85))
	draw_string(_font, Vector2(tx, y + CHIP_H * 0.66), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1))
	if fill >= 0.0:
		var bar := Rect2(x + 5.0, y + CHIP_H - 6.0, w - 10.0, 3.0)
		draw_rect(bar, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(fill, 0.0, 1.0), bar.size.y)), col.lightened(0.15) if fill > 0.25 else Color(1.0, 0.3, 0.2))
	return x + w + GAP
