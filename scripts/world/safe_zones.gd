# SafeZones — the places hostiles stay away from (D-101): the disc golf courses, the country club course and the
# Drop Zone, plus buffer_m around each (data/tuning/safe_zones.json). Every peer has it (main.gd adds "SafeZones",
# group "safe_zones"); only the host's AI asks it anything. Landmark zones follow the landmark's placed transform,
# found lazily (landmarks load after Main) and re-looked-up at most every few seconds until found.
# API: contains(pos) -> bool, exit_point(pos) -> a spot just outside the zone pos is in (pos itself if none).
# Depends on: SafeZoneRules, DataLoader, data/tuning/safe_zones.json, data/discgolf/courses.json, landmark nodes.
class_name SafeZones
extends Node

const PATH := "res://data/tuning/safe_zones.json"
const COURSES_PATH := "res://data/discgolf/courses.json"
const LOOKUP_MS := 3000

var _buffer := 60.0
var _zones: Array = []  # [{rect: Rect2, landmark: String, xf_inv: Transform3D, ready: bool}]
var _next_lookup := 0


func _ready() -> void:
	add_to_group("safe_zones")
	var data := DataLoader.load_json(PATH)
	var courses := DataLoader.load_json(COURSES_PATH)
	_buffer = float(data.get("buffer_m", 60.0))
	for z: Dictionary in data.get("zones", []):
		if z.has("course"):
			var b: Array = courses.get(str(z.course), {}).get("bounds", [])
			if b.size() == 4:  # map coords: no landmark transform needed
				_zones.append({"rect": Rect2(b[0], b[1], b[2] - b[0], b[3] - b[1]), "landmark": "",
					"xf_inv": Transform3D.IDENTITY, "ready": true})
		elif z.has("landmark") and (z.get("rect", []) as Array).size() == 4:
			var r: Array = z.rect
			_zones.append({"rect": Rect2(r[0], r[1], r[2] - r[0], r[3] - r[1]), "landmark": str(z.landmark),
				"xf_inv": Transform3D.IDENTITY, "ready": false})


func contains(pos: Vector3) -> bool:
	return _zone_at(pos) >= 0


func exit_point(pos: Vector3) -> Vector3:
	var i := _zone_at(pos)
	if i < 0:
		return pos
	var z: Dictionary = _zones[i]
	var local: Vector3 = z.xf_inv * pos
	var out := SafeZoneRules.exit_point(Vector2(local.x, local.z), z.rect, _buffer)
	return z.xf_inv.affine_inverse() * Vector3(out.x, local.y, out.y)


func _zone_at(pos: Vector3) -> int:
	_resolve()
	for i in _zones.size():
		var z: Dictionary = _zones[i]
		if not z.ready:
			continue
		var local: Vector3 = z.xf_inv * pos
		if SafeZoneRules.inside(Vector2(local.x, local.z), z.rect, _buffer):
			return i
	return -1


func _resolve() -> void:
	if Time.get_ticks_msec() < _next_lookup:
		return
	var missing := false
	for z: Dictionary in _zones:
		if z.ready:
			continue
		var lm := get_tree().root.find_child(str(z.landmark), true, false) as Node3D
		if lm:
			z.xf_inv = lm.global_transform.affine_inverse()
			z.ready = true
		else:
			missing = true
	_next_lookup = Time.get_ticks_msec() + (LOOKUP_MS if missing else 1 << 30)
