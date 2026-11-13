# HudIcons — flat vector icons drawn in code for the HUD (D-066), so no image files are needed. draw() paints one
# icon centred on `c` about `s` pixels across onto any CanvasItem during its _draw(). Icons: health (heart),
# food (can), water (drop), meepo (longboard), and one per chem effect: baked (leaf), tripping_shrooms (mushroom),
# tripping_acid (blotter tab), rolling (pill), nodding (Zz), comedown (down arrow), fried (lightning), dope_sick (sick
# face). Unknown ids get a plain dot. Presentation only. Depends on: nothing.
class_name HudIcons
extends RefCounted

const COLORS := {
	"health": Color(0.9, 0.2, 0.2), "food": Color(0.85, 0.55, 0.25), "water": Color(0.3, 0.6, 1.0),
	"meepo": Color(0.2, 0.9, 1.0), "baked": Color(0.35, 0.8, 0.3), "tripping_shrooms": Color(0.85, 0.25, 0.2),
	"tripping_acid": Color(0.95, 0.5, 1.0), "rolling": Color(1.0, 0.5, 0.75), "nodding": Color(0.6, 0.55, 0.95),
	"comedown": Color(0.6, 0.65, 0.75), "fried": Color(1.0, 0.85, 0.2), "dope_sick": Color(0.55, 0.75, 0.3),
}


static func color_of(id: String) -> Color:
	return COLORS.get(id, Color(0.85, 0.85, 0.85))


static func draw(ci: CanvasItem, id: String, c: Vector2, s: float) -> void:
	var h := s * 0.5
	var col := color_of(id)
	match id:
		"health":
			var r := h * 0.48
			ci.draw_circle(c + Vector2(-r * 0.95, -r * 0.35), r, col)
			ci.draw_circle(c + Vector2(r * 0.95, -r * 0.35), r, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.93, -h * 0.05), c + Vector2(h * 0.93, -h * 0.05), c + Vector2(0, h * 0.85)]), col)
		"food":
			var body := Rect2(c - Vector2(h * 0.6, h * 0.8), Vector2(h * 1.2, h * 1.6))
			ci.draw_rect(body, Color(0.75, 0.75, 0.78))
			ci.draw_rect(Rect2(body.position + Vector2(0, h * 0.4), Vector2(body.size.x, h * 0.8)), col)
			ci.draw_line(body.position, body.position + Vector2(body.size.x, 0), Color(0.45, 0.45, 0.48), 2.0)
			ci.draw_line(body.end - Vector2(body.size.x, 0), body.end, Color(0.45, 0.45, 0.48), 2.0)
		"water":
			ci.draw_circle(c + Vector2(0, h * 0.3), h * 0.58, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h * 0.95), c + Vector2(h * 0.53, h * 0.08), c + Vector2(-h * 0.53, h * 0.08)]), col)
			ci.draw_circle(c + Vector2(-h * 0.2, h * 0.25), h * 0.14, Color(1, 1, 1, 0.7))
		"meepo":
			var deck := PackedVector2Array()
			for i in 16:  # rounded deck, slightly tilted
				var a := TAU * i / 16.0
				deck.append(c + Vector2(cos(a) * h * 0.95, sin(a) * h * 0.32).rotated(-0.35))
			ci.draw_colored_polygon(deck, Color(0.15, 0.15, 0.17))
			ci.draw_line(c + Vector2(-h * 0.5, 0).rotated(-0.35), c + Vector2(h * 0.5, 0).rotated(-0.35), col, 2.5)
			for x: float in [-0.55, 0.55]:
				ci.draw_circle(c + Vector2(h * x, h * 0.42).rotated(-0.35), h * 0.17, Color(1.0, 0.45, 0.15))
		"baked":
			for i in 7:  # seven leaflets fanning up from the stem
				var a := deg_to_rad(-90.0 + (i - 3) * 28.0)
				var length := h * (0.95 - absf(i - 3) * 0.17)
				var tip := c + Vector2(0, h * 0.35) + Vector2(cos(a), sin(a)) * length
				var side := Vector2(-sin(a), cos(a)) * h * 0.13
				var base := c + Vector2(0, h * 0.35)
				ci.draw_colored_polygon(PackedVector2Array([base, base.lerp(tip, 0.5) + side, tip, base.lerp(tip, 0.5) - side]), col)
			ci.draw_line(c + Vector2(0, h * 0.35), c + Vector2(0, h * 0.95), col.darkened(0.2), 2.0)
		"tripping_shrooms":
			ci.draw_rect(Rect2(c + Vector2(-h * 0.2, -h * 0.05), Vector2(h * 0.4, h * 0.9)), Color(0.95, 0.9, 0.8))
			var cap := PackedVector2Array()
			for i in 13:
				var a := PI + PI * i / 12.0
				cap.append(c + Vector2(cos(a) * h * 0.95, sin(a) * h * 0.85) + Vector2(0, h * 0.05))
			ci.draw_colored_polygon(cap, col)
			for d: Vector2 in [Vector2(-0.45, -0.3), Vector2(0.1, -0.55), Vector2(0.5, -0.2)]:
				ci.draw_circle(c + d * h, h * 0.12, Color(1, 1, 1))
		"tripping_acid":
			var q := PackedVector2Array([c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, 0)])
			ci.draw_colored_polygon(q, Color(0.95, 0.92, 0.85))
			for i in 4:  # rainbow rings
				ci.draw_arc(c, h * (0.62 - i * 0.14), 0.0, TAU, 16, Color.from_hsv(0.1 + i * 0.22, 0.8, 0.95), 2.0)
		"rolling":
			var w := h * 0.42
			var a := c + Vector2(-h * 0.5, h * 0.5)
			var b := c + Vector2(h * 0.5, -h * 0.5)
			var mid := (a + b) * 0.5
			var dir := (b - a).normalized()
			var n := Vector2(-dir.y, dir.x) * w
			ci.draw_circle(a, w, col)
			ci.draw_colored_polygon(PackedVector2Array([a + n, mid + n, mid - n, a - n]), col)
			ci.draw_circle(b, w, Color(0.5, 0.75, 1.0))
			ci.draw_colored_polygon(PackedVector2Array([mid + n, b + n, b - n, mid - n]), Color(0.5, 0.75, 1.0))
		"nodding":
			var font := ThemeDB.fallback_font
			ci.draw_string(font, c + Vector2(-h * 0.95, h * 0.55), "Z", HORIZONTAL_ALIGNMENT_LEFT, -1, int(s * 0.75), col)
			ci.draw_string(font, c + Vector2(h * 0.05, -h * 0.05), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, int(s * 0.5), col)
		"comedown":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.25, -h * 0.9), c + Vector2(h * 0.25, -h * 0.9),
				c + Vector2(h * 0.25, 0), c + Vector2(h * 0.7, 0), c + Vector2(0, h * 0.9), c + Vector2(-h * 0.7, 0), c + Vector2(-h * 0.25, 0)]), col)
		"fried":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(h * 0.2, -h), c + Vector2(-h * 0.6, h * 0.1), c + Vector2(-h * 0.05, h * 0.1),
				c + Vector2(-h * 0.25, h), c + Vector2(h * 0.6, -h * 0.15), c + Vector2(h * 0.05, -h * 0.15)]), col)
		"dope_sick":
			ci.draw_circle(c, h * 0.9, col)
			ci.draw_circle(c + Vector2(-h * 0.32, -h * 0.2), h * 0.12, Color(0.1, 0.12, 0.08))
			ci.draw_circle(c + Vector2(h * 0.32, -h * 0.2), h * 0.12, Color(0.1, 0.12, 0.08))
			var mouth := PackedVector2Array()
			for i in 7:
				mouth.append(c + Vector2(-h * 0.45 + i * h * 0.15, h * 0.35 + (h * 0.08 if i % 2 == 0 else -h * 0.08)))
			ci.draw_polyline(mouth, Color(0.1, 0.12, 0.08), 2.0)
		_:
			ci.draw_circle(c, h * 0.6, col)
