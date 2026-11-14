# CopeStadium — builds Ron & Carol Cope Stadium at Foster Field (D-079; UNK, 2708 12th Ave) into a LandmarkKit from
# data/landmarks/cope_stadium.json. Local frame: x across the field (east = +x), z along it (south = +z), origin at
# midfield; landmarks.json turns it -1 deg onto the real field. The west stadium building (3 floors: concourse,
# mezzanine, press box + hospitality), the stands, the north end-zone building (locker rooms etc.), rooms, furniture,
# signs, lights, loot and lair markers are data (LandmarkParts); this file adds the field (turf, end zones, yard lines
# and numbers, goal posts), the LED scoreboard, the light towers, the perimeter fence and the triage camp that was
# set up on the field (tents + cots).
# Depends on: LandmarkKit, landmark_parts.gd.
extends RefCounted

const Parts := preload("res://tools/landmarks/landmark_parts.gd")
const YARD := 0.9144


static func build(k: LandmarkKit, d: Dictionary, rng: RandomNumberGenerator) -> void:
	var fy := float(d.dims.floor_y)
	Parts.build_all(k, d, "cope_stadium", fy)
	_field(k, d.field)
	_scoreboard(k, d.scoreboard)
	for t: Array in d.light_towers:  # [x, z, facing yaw_deg]
		_tower(k, Vector3(t[0], 0.0, t[1]), deg_to_rad(float(t[2])))
	_fence(k, d.fence)
	_camp(k, d.camp, rng)


static func _field(k: LandmarkKit, f: Dictionary) -> void:
	var y := float(f.y)
	var hw := float(f.half_width)
	var hl := float(f.half_length)
	var goal := 50.0 * YARD
	var end := 60.0 * YARD
	var side := 53.333 * YARD * 0.5
	k.block(Vector3(-hw, y - 0.3, -hl), Vector3(hw, y, hl), "turf")
	for s: float in [-1.0, 1.0]:  # end zones
		k.block(Vector3(-side, y, minf(s * goal, s * end)), Vector3(side, y + 0.01, maxf(s * goal, s * end)), "end_zone", false)
	for i in 21:  # yard lines every 5 yards
		var z := -goal + i * 5.0 * YARD
		k.block(Vector3(-side, y + 0.012, z - 0.05), Vector3(side, y + 0.016, z + 0.05), "paint_white", false)
	for s: float in [-1.0, 1.0]:  # sidelines + end lines
		k.block(Vector3(s * side - 0.05, y + 0.012, -end), Vector3(s * side + 0.05, y + 0.016, end), "paint_white", false)
		k.block(Vector3(-side, y + 0.012, s * end - 0.05), Vector3(side, y + 0.016, s * end + 0.05), "paint_white", false)
	var nums := ["10", "20", "30", "40", "50", "40", "30", "20", "10"]
	for i in nums.size():
		var z := -goal + (i + 1) * 10.0 * YARD
		for s: float in [-1.0, 1.0]:
			_flat_label(k, nums[i], Vector3(s * (side - 11.0 * YARD), y + 0.02, z), 90.0 * s, 200, Color(0.95, 0.95, 0.95))
	var words: Array = f.end_zone_words
	for i in 2:
		_flat_label(k, str(words[i]), Vector3(0, y + 0.02, (i * 2 - 1) * (goal + end) * 0.5), 180.0 * i, 420, Color(0.95, 0.95, 0.95))
	for s: float in [-1.0, 1.0]:  # goal posts on the end lines
		var z := s * end
		k.cylinder(Vector3(0, y, z + s * 1.8), 0.15, 3.05, "goalpost", 8, true)
		k.box(Vector3(0, y + 3.05, z + s * 0.9), Vector3(0.18, 0.18, 1.8), "goalpost", 0.0, false)
		k.box(Vector3(0, y + 3.05, z), Vector3(5.64, 0.15, 0.15), "goalpost", 0.0, false)
		for u: float in [-2.82, 2.82]:
			k.cylinder(Vector3(u, y + 3.05, z), 0.06, 6.1, "goalpost", 6)


static func _flat_label(k: LandmarkKit, text: String, pos: Vector3, yaw_deg: float, size: int, col: Color) -> void:
	var l := Label3D.new()
	l.name = "Paint_%d" % k.root.get_child_count()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.01
	l.modulate = col
	l.shaded = true
	l.position = pos
	l.rotation = Vector3(deg_to_rad(-90.0), deg_to_rad(yaw_deg), 0.0)
	l.visibility_range_end = 120.0
	k.root.add_child(l)


static func _scoreboard(k: LandmarkKit, s: Dictionary) -> void:
	var c := Vector3(s.pos[0], 0.0, s.pos[1])
	var w := float(s.width)
	for u: float in [-w * 0.35, w * 0.35]:
		k.box(c + Vector3(u, float(s.bottom) * 0.5, 0), Vector3(0.6, float(s.bottom), 0.6), "steel")
	k.box(c + Vector3(0, float(s.bottom) + float(s.height) * 0.5, 0), Vector3(w, float(s.height), 0.8), "scoreboard_case")
	k.box(c + Vector3(0, float(s.bottom) + float(s.height) * 0.5, -0.41), Vector3(w - 0.6, float(s.height) - 0.6, 0.02), "led_dead", false)
	for t: Dictionary in s.text:
		var p: Array = t.pos
		var l := Label3D.new()
		l.name = "Score_%d" % k.root.get_child_count()
		l.text = str(t.text)
		l.font_size = int(t.size)
		l.pixel_size = 0.01
		l.modulate = Color(t.color[0], t.color[1], t.color[2])
		l.position = c + Vector3(p[0], p[1], -0.43)
		l.rotation.y = PI
		l.visibility_range_end = 220.0
		k.root.add_child(l)


static func _tower(k: LandmarkKit, base: Vector3, yaw: float) -> void:
	k.cylinder(base, 0.45, 24.0, "steel", 8, true)
	var xf := Transform3D(Basis(Vector3.UP, yaw), base + Vector3(0, 24.0, 0))
	k.box_xf(xf.translated_local(Vector3(0, 1.2, 0)), Vector3(5.0, 2.8, 0.4), "steel", false)
	for r in 3:
		for c in 5:
			k.box_xf(xf.translated_local(Vector3(-2.0 + c, 0.3 + r * 0.9, -0.3)), Vector3(0.7, 0.7, 0.2), "lamp", false)


static func _fence(k: LandmarkKit, f: Dictionary) -> void:
	var h := float(f.height)
	for line: Array in f.lines:
		var pts := PackedVector3Array()
		for p: Array in line:
			pts.append(Vector3(p[0], 0.0, p[1]))
		k.railing(pts, h, "fence_post", 3.0, true)
		for i in range(pts.size() - 1):
			k.quad(pts[i] + Vector3.UP * 0.05, pts[i + 1] + Vector3.UP * 0.05, pts[i + 1] + Vector3.UP * h, pts[i] + Vector3.UP * h, "chainlink")


# Triage camp: rows of tents along the field with cots; some tents collapsed.
static func _camp(k: LandmarkKit, c: Dictionary, rng: RandomNumberGenerator) -> void:
	var y := float(c.y)
	for t: Array in c.tents:  # [x, z, yaw_deg]
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(t[2]))), Vector3(t[0], y, t[1]))
		var down := rng.randf() < float(c.collapsed)
		if down:
			k.box_xf(Transform3D(xf.basis * Basis(Vector3.RIGHT, 0.12), xf.origin + Vector3(0, 0.25, 0)), Vector3(4.0, 0.15, 6.0), "tent", false)
		else:
			for s: float in [-1.0, 1.0]:  # two roof slopes over a ridge pole
				k.box_xf(Transform3D(xf.basis * Basis(Vector3.BACK, s * 0.75), xf * Vector3(s * 1.05, 1.35, 0)), Vector3(2.9, 0.06, 6.0), "tent")
			for e: float in [-3.0, 3.0]:
				k.box_xf(xf.translated_local(Vector3(0, 1.1, e)), Vector3(0.08, 2.2, 0.08), "steel", false)
		for i in 3:  # cots inside
			k.box_xf(xf.translated_local(Vector3(-1.0 + i * 1.0, 0.25, 0.4 * (i % 2 * 2 - 1))), Vector3(0.7, 0.4, 1.9), "cot", false)
