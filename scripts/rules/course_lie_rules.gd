# CourseLies — what the ball is sitting on at the country club course (D-086), pure (no nodes): the painted OSM
# course shapes (data/landmarks/country_club_paint.json: green / bunker / tee / fairway polygons, landmark-local
# x z), "rough" anywhere else inside the course bounds, "out" beyond them. Polygons keep a bounding rect so a lookup
# only tests the few shapes around the point. Water is found by the shot itself (the water bed collider).
# Depends on: DataLoader.
class_name CourseLies
extends RefCounted

const PAINT_PATH := "res://data/landmarks/country_club_paint.json"
const ORDER := ["green", "bunker", "tee", "fairway"]  # first match wins

var bounds := Rect2()
var _shapes: Array = []  # [kind, PackedVector2Array, Rect2]


func _init(course_bounds: Array, paint_path := PAINT_PATH) -> void:
	bounds = Rect2(Vector2(course_bounds[0], course_bounds[1]),
		Vector2(float(course_bounds[2]) - float(course_bounds[0]), float(course_bounds[3]) - float(course_bounds[1])))
	var paint := DataLoader.load_json(paint_path)
	for kind: String in ORDER:
		for p: Dictionary in paint.get("polys", []):
			if str(p.mat) != kind:
				continue
			var poly := PackedVector2Array()
			for q: Array in p.poly:
				poly.append(Vector2(float(q[0]), float(q[1])))
			if poly.size() < 3:
				continue
			var r := Rect2(poly[0], Vector2.ZERO)
			for q in poly:
				r = r.expand(q)
			_shapes.append([kind, poly, r])


func lie_at(p: Vector2) -> String:
	if not bounds.has_point(p):
		return "out"
	for s: Array in _shapes:
		if (s[2] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, s[1]):
			return s[0]
	return "rough"
