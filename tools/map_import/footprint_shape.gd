# FootprintShape — pure 2D geometry on building footprints (map metres, x east / y = world z):
# signed area, and the minimum-area oriented rectangle used for pitched roofs (D-041 phase 1).
# No dependencies.
class_name FootprintShape
extends RefCounted


static func area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


# Smallest rectangle around the footprint, aligned to one of its edges.
# Returns { centre: Vector2, axis: Vector2 (unit, along the long side), length, width } (length >= width).
static func oriented_rect(poly: PackedVector2Array) -> Dictionary:
	var best := {}
	var best_area := INF
	for i in poly.size():
		var e := poly[(i + 1) % poly.size()] - poly[i]
		if e.length_squared() < 0.0001:
			continue
		var u := e.normalized()
		var v := Vector2(-u.y, u.x)
		var lo := Vector2(INF, INF)
		var hi := -lo
		for p in poly:
			var q := Vector2(p.dot(u), p.dot(v))
			lo = lo.min(q)
			hi = hi.max(q)
		var size := hi - lo
		if size.x * size.y < best_area:
			best_area = size.x * size.y
			var mid := (lo + hi) * 0.5
			var centre := u * mid.x + v * mid.y
			if size.x >= size.y:
				best = {"centre": centre, "axis": u, "length": size.x, "width": size.y}
			else:
				best = {"centre": centre, "axis": v, "length": size.y, "width": size.x}
	return best


# Footprint area / its oriented rectangle's area (1 = a perfect rectangle).
static func rectangularity(poly: PackedVector2Array, rect: Dictionary) -> float:
	if rect.is_empty():
		return 0.0
	return area(poly) / maxf(float(rect.length) * float(rect.width), 0.0001)


# The rectangle's corners, counter-clockwise when seen from above (y up, z = map y).
static func rect_corners(rect: Dictionary) -> PackedVector2Array:
	var u: Vector2 = rect.axis * (float(rect.length) * 0.5)
	var v: Vector2 = Vector2(-rect.axis.y, rect.axis.x) * (float(rect.width) * 0.5)
	var c: Vector2 = rect.centre
	return PackedVector2Array([c - u - v, c + u - v, c + u + v, c - u + v])
