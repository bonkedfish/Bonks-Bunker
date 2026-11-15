# SwingMeterDraw — draws the 3-click golf swing meter (D-086) for the HUDs (DzHud, CourseGolfHud). The bar runs from
# the accuracy zone (left of the white line) to full power (right end): the power fill, the moving marker, the
# PERFECT band on the line, coloured marks the caller passes (power that reaches a target / the cup), the phase hint
# and the last swing's grade popping up above. Presentation only. Depends on: SportInput (meter, last_grade,
# grade_time), SwingMeter.
class_name SwingMeterDraw
extends RefCounted

const GRADE_COLORS := {"PERFECT": Color(1.0, 0.85, 0.2), "GOOD": Color(0.5, 1.0, 0.5), "HOOK": Color(1.0, 0.55, 0.3),
	"SLICE": Color(1.0, 0.55, 0.3), "SHANK": Color(1.0, 0.3, 0.25), "EARLY": Color(1.0, 0.6, 0.3), "LATE": Color(1.0, 0.6, 0.3),
	"WHIFF": Color(1.0, 0.3, 0.25), "CPU LOB": Color(0.6, 0.8, 1.0), "CPU SMASH": Color(1.0, 0.4, 0.4)}


# marks: [[power 0..1, Color], ...]
static func draw(ci: CanvasItem, font: Font, bar: Rect2, sp: SportInput, marks: Array) -> void:
	var m: SwingMeter = sp.meter
	var z := m.zone()
	var x0 := bar.position.x
	var w := bar.size.x
	var at := func(v: float) -> float: return x0 + (v + z) / (1.0 + z) * w
	var zero: float = at.call(0.0)
	ci.draw_rect(bar, Color(0.1, 0.1, 0.1, 0.9))
	ci.draw_rect(Rect2(x0, bar.position.y, zero - x0, bar.size.y), Color(0.35, 0.2, 0.2, 0.9))  # accuracy zone
	var good: float = float(m._cfg.get("good", 0.065))
	var sweet: float = float(m._cfg.get("sweet", 0.025))
	ci.draw_rect(Rect2(at.call(-good), bar.position.y, at.call(good) - at.call(-good), bar.size.y), Color(0.3, 0.6, 0.3, 0.6))
	ci.draw_rect(Rect2(at.call(-sweet), bar.position.y, at.call(sweet) - at.call(-sweet), bar.size.y), Color(1.0, 0.85, 0.2, 0.75))
	var fill := m.value if m.phase == SwingMeter.Phase.POWER else m.power
	if fill > 0.0:
		ci.draw_rect(Rect2(zero, bar.position.y + 3.0, at.call(fill) - zero, bar.size.y - 6.0),
			Color(0.3, 0.85, 0.35).lerp(Color(1.0, 0.45, 0.2), fill))
	for mk: Array in marks:
		if float(mk[0]) <= 1.0:
			var mx: float = at.call(float(mk[0]))
			ci.draw_line(Vector2(mx, bar.position.y - 5.0), Vector2(mx, bar.end.y + 5.0), mk[1], 3.0)
	ci.draw_line(Vector2(zero, bar.position.y - 4.0), Vector2(zero, bar.end.y + 4.0), Color(1, 1, 1), 2.0)
	ci.draw_rect(bar, Color(1, 1, 1, 0.5), false, 1.0)
	if m.busy():
		var mx: float = at.call(m.value)
		ci.draw_rect(Rect2(mx - 2.0, bar.position.y - 7.0, 4.0, bar.size.y + 14.0), Color(1, 1, 1))
	var hint := "Left click: start the swing"
	match m.phase:
		SwingMeter.Phase.POWER:
			hint = "Click: set the power"
		SwingMeter.Phase.ACCURACY:
			hint = "Click on the white line!"
	text(ci, font, Vector2(x0, bar.position.y - 10.0), hint, 13, Color(0.95, 0.95, 0.85))
	if sp.grade_time > 0.0 and sp.last_grade != "":
		var col: Color = GRADE_COLORS.get(sp.last_grade, Color(1, 1, 1))
		col.a = clampf(sp.grade_time * 2.0, 0.0, 1.0)
		var size := 34
		var tw := font.get_string_size(sp.last_grade, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		text(ci, font, Vector2(x0 + w * 0.5 - tw * 0.5, bar.position.y - 46.0), sp.last_grade, size, col)


static func text(ci: CanvasItem, font: Font, at: Vector2, s: String, size: int, col: Color) -> void:
	ci.draw_string_outline(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.85 * col.a))
	ci.draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
