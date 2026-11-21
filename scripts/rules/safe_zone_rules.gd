# SafeZoneRules — pure geometry for safe zones (D-101): is a point inside a rectangle grown by a buffer, and the
# nearest point just outside it. Points and rects are 2D (x, z) in the zone's own frame. No nodes.
class_name SafeZoneRules
extends RefCounted


static func inside(p: Vector2, rect: Rect2, buffer: float) -> bool:
	return rect.grow(buffer).has_point(p)


# The closest point `margin` metres outside the grown rect, straight out through its nearest side.
static func exit_point(p: Vector2, rect: Rect2, buffer: float, margin := 5.0) -> Vector2:
	var r := rect.grow(buffer)
	var d_left := p.x - r.position.x
	var d_right := r.end.x - p.x
	var d_top := p.y - r.position.y
	var d_bottom := r.end.y - p.y
	var m := minf(minf(d_left, d_right), minf(d_top, d_bottom))
	if m == d_left:
		return Vector2(r.position.x - margin, p.y)
	if m == d_right:
		return Vector2(r.end.x + margin, p.y)
	if m == d_top:
		return Vector2(p.x, r.position.y - margin)
	return Vector2(p.x, r.end.y + margin)
