# BarBuilding — builds one downtown bar from its data entry into a LandmarkKit (D-059). Local frame: origin = middle
# of the bar's footprint at street level, x across the front, z from the front (-Z, facing the street) to the back.
# Two storeys outside (brick facade, shopfront glass + door, upper windows, flat roof + parapet, sign). Inside: the
# walkable ground floor plus a basement (stairs down through a hole in the floor; the landmark's ground_holes cut the
# terrain there) or an upstairs (stairs up through a hole in the upper floor) — the other storey stays closed.
# Partitions with doorways, furniture (bar_furniture.gd), loot containers, lights, signs and raider spawn markers
# (Marker3D in group "lair_spawns", meta "enemy", D-062) come from the data. Stairs: "from" is the bottom end,
# "to" the top end (centre of each end edge). "annex" rebuilds the rest of the merged
# downtown block as closed storefronts; "outdoor" holds the raider barricades / lookouts / camp around the bar.
# Depends on: LandmarkKit, bar_furniture.gd, scenes/loot_container.tscn.
extends RefCounted

const LOOT := preload("res://scenes/loot_container.tscn")
const Furniture := preload("res://tools/landmarks/bar_furniture.gd")
const T := 0.35           # outer wall thickness
const PT := 0.2           # partition thickness
const SLAB := 0.3
const GROUND := 0.12      # ground floor surface (a hair above the terrain pad)
const CEIL := 4.0         # ground storey ceiling = underside of the upper floor slab
const UP := 4.3           # upstairs floor surface
const ROOF := 7.6
const BASE := -3.3        # basement floor surface
const DOOR_H := 2.6


# Floor surface height of a level name.
static func level_y(level: String) -> float:
	match level:
		"basement":
			return BASE
		"upstairs":
			return UP
	return GROUND


static func build(k: LandmarkKit, id: String, d: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var hw := float(d.w) * 0.5
	var hd := float(d.d) * 0.5
	var second := str(d.second)  # "basement" | "upstairs"
	var fac := str(d.facade)
	var st: Dictionary = d.stairs  # from = bottom end, to = top end (centre of each end edge), w = width
	var a := Vector2(st.from[0], st.from[1])
	var b := Vector2(st.to[0], st.to[1])
	var sw := float(st.w) * 0.5
	var along_z := absf(b.x - a.x) < absf(b.y - a.y)
	var pad := Vector2(sw, 0.0) if along_z else Vector2(0.0, sw)
	var hole := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)) - pad, Vector2.ZERO).expand(Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + pad)
	var open_side := ("pz" if b.y > a.y else "nz") if along_z else ("px" if b.x > a.x else "nx")
	# Slabs: ground floor, upper floor (ceiling), roof; the stair hole is cut from the floor it passes through.
	_slab(k, hw, hd, -SLAB, GROUND, "floor_wood" if not d.has("floor") else str(d.floor), hole if second == "basement" else Rect2())
	_slab(k, hw, hd, CEIL, UP, "floor_wood" if second == "upstairs" else "plaster", hole if second == "upstairs" else Rect2())
	k.block(Vector3(-hw, ROOF, -hd), Vector3(hw, ROOF + 0.3, hd), "roof")
	if second == "basement":
		k.block(Vector3(-hw, BASE - SLAB, -hd), Vector3(hw, BASE, hd), "concrete")
	# Outer walls (bottom of the basement or just below ground, up to the roof).
	var bottom := BASE - SLAB if second == "basement" else -0.6
	var fr: Dictionary = d.front
	var door: Array = fr.door
	var front_holes: Array = [[float(door[0]) - float(door[1]), float(door[0]) + float(door[1]), GROUND, DOOR_H, ""]]
	for wnd: Array in fr.windows:
		front_holes.append([wnd[0], wnd[1], 0.9, 3.1, "glass"])
	for wnd: Array in d.get("upper_windows", []):
		front_holes.append([wnd[0], wnd[1], UP + 0.9, UP + 2.6, "" if second == "upstairs" else "glass_dark"])
	_wall(k, "x", -hd, -hw, hw, bottom, ROOF + 0.9, T, fac, front_holes)
	var back_holes: Array = [[float(d.back_door) - 0.9, float(d.back_door) + 0.9, GROUND, DOOR_H - 0.2, ""]]
	_wall(k, "x", hd, -hw, hw, bottom, ROOF + 0.9, T, fac, back_holes)
	for side: String in ["nx", "px"]:
		var holes: Array = []
		for wnd: Array in d.get("side_" + side, []):
			holes.append([wnd[0], wnd[1], 0.9, 3.1, "glass"])
			holes.append([wnd[0], wnd[1], UP + 0.9, UP + 2.6, "" if second == "upstairs" else "glass_dark"])
		_wall(k, "z", -hw if side == "nx" else hw, -hd + T, hd - T, bottom, ROOF + 0.9, T, fac, holes)
	# Trim: a band between the storeys and a cornice on the front.
	k.block(Vector3(-hw - 0.1, CEIL - 0.1, -hd - 0.15), Vector3(hw + 0.1, CEIL + 0.35, -hd), str(d.trim), false)
	k.block(Vector3(-hw - 0.15, ROOF + 0.6, -hd - 0.2), Vector3(hw + 0.15, ROOF + 0.9, -hd), str(d.trim), false)
	# Step-free thresholds at both doors.
	k.ramp(Vector3(float(door[0]), -0.05, -hd - 1.0), Vector3(float(door[0]), GROUND, -hd), float(door[1]) * 2.0, 0.3, "concrete")
	k.ramp(Vector3(float(d.back_door), -0.05, hd + 1.0), Vector3(float(d.back_door), GROUND, hd), 1.8, 0.3, "concrete")
	# Stairs (a walkable ramp) and a railing round the hole on the upper of the two floors, open where they arrive.
	var low := BASE if second == "basement" else GROUND
	var high := GROUND if second == "basement" else UP
	k.ramp(Vector3(a.x, low, a.y), Vector3(b.x, high, b.y), float(st.w), 0.3, "wood_dark")
	_hole_rail(k, hole, high, open_side)
	# Partitions.
	for p: Dictionary in d.get("partitions", []):
		var y0 := level_y(str(p.level))
		var y1: float = {"ground": CEIL, "upstairs": ROOF, "basement": -SLAB}.get(str(p.level), CEIL)
		var holes: Array = []
		for g: Array in p.get("doors", []):
			holes.append([float(g[0]) - float(g[1]), float(g[0]) + float(g[1]), y0, y0 + 2.4, ""])
		_wall(k, str(p.axis), float(p.at), float(p.from), float(p.to), y0, y1, PT, str(p.get("mat", "plaster")), holes)
	# Annex storefronts and outdoor raider props, then furniture.
	for an: Array in d.get("annex", []):
		_annex(k, an, fac, str(d.trim), rng)
	for f: Dictionary in d.get("furniture", []):
		Furniture.add(k, f, level_y(str(f.get("level", "ground"))), rng)
	for f: Dictionary in d.get("outdoor", []):
		Furniture.add(k, f, 0.0, rng)
	return _place(k, id, d)


# Floor slab over the footprint between y0 and y1, minus an optional hole.
static func _slab(k: LandmarkKit, hw: float, hd: float, y0: float, y1: float, mat: String, hole: Rect2) -> void:
	if hole.size == Vector2.ZERO:
		k.block(Vector3(-hw, y0, -hd), Vector3(hw, y1, hd), mat)
		return
	var x0 := hole.position.x
	var x1 := hole.end.x
	var z0 := hole.position.y
	var z1 := hole.end.y
	k.block(Vector3(-hw, y0, -hd), Vector3(hw, y1, z0), mat)
	k.block(Vector3(-hw, y0, z1), Vector3(hw, y1, hd), mat)
	if x0 > -hw:
		k.block(Vector3(-hw, y0, z0), Vector3(x0, y1, z1), mat)
	if x1 < hw:
		k.block(Vector3(x1, y0, z0), Vector3(hw, y1, z1), mat)


# Waist-high railing round a stair hole at floor height y, leaving the side the stairs come in from open
# (open_side: "nx" | "px" | "nz" | "pz", the edge the walkable top of the stairs meets).
static func _hole_rail(k: LandmarkKit, hole: Rect2, y: float, open_side: String) -> void:
	var p0 := hole.position
	var p1 := hole.end
	var sides := {"nz": [Vector3(p0.x, y, p0.y), Vector3(p1.x, y, p0.y)], "pz": [Vector3(p0.x, y, p1.y), Vector3(p1.x, y, p1.y)],
		"nx": [Vector3(p0.x, y, p0.y), Vector3(p0.x, y, p1.y)], "px": [Vector3(p1.x, y, p0.y), Vector3(p1.x, y, p1.y)]}
	for s: String in sides:
		if s == open_side:
			continue
		var pts := PackedVector3Array(sides[s])
		k.railing(pts, 1.0, "steel", 1.2, true)


# Axis-aligned wall. axis "x": runs along x at z = at (from..to are x); axis "z": along z at x = at. Holes are
# [s0, s1, y0, y1, fill] in along-wall coordinates; fill "" leaves an opening, otherwise a pane of that material.
static func _wall(k: LandmarkKit, axis: String, at: float, from: float, to: float, y0: float, y1: float, t: float,
		mat: String, holes: Array) -> void:
	holes = holes.duplicate()
	holes.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))
	var s := from
	var i := 0
	while i < holes.size():
		# Group holes sharing the same span (a shopfront window with an upper window above it).
		var h: Array = holes[i]
		var s0 := clampf(float(h[0]), from, to)
		var s1 := clampf(float(h[1]), from, to)
		var col: Array = [h]
		var j := i + 1
		while j < holes.size() and float(holes[j][0]) < s1 - 0.01:
			col.append(holes[j])
			s1 = maxf(s1, clampf(float(holes[j][1]), from, to))
			j += 1
		if s0 > s:
			_piece(k, axis, at, s, s0, y0, y1, t, mat)
		col.sort_custom(func(p: Array, q: Array) -> bool: return float(p[2]) < float(q[2]))
		var y := y0
		for c: Array in col:
			var c0 := clampf(float(c[0]), from, to)
			var c1 := clampf(float(c[1]), from, to)
			if c0 > s0:  # narrower hole in a grouped column: fill beside it
				_piece(k, axis, at, s0, c0, float(c[2]), float(c[3]), t, mat)
			if c1 < s1:
				_piece(k, axis, at, c1, s1, float(c[2]), float(c[3]), t, mat)
			if float(c[2]) > y:
				_piece(k, axis, at, s0, s1, y, float(c[2]), t, mat)
			if str(c[4]) != "":
				_piece(k, axis, at, c0, c1, float(c[2]), float(c[3]), 0.06, str(c[4]))
			y = float(c[3])
		if y1 > y:
			_piece(k, axis, at, s0, s1, y, y1, t, mat)
		s = s1
		i = j
	if to > s:
		_piece(k, axis, at, s, to, y0, y1, t, mat)


static func _piece(k: LandmarkKit, axis: String, at: float, s0: float, s1: float, y0: float, y1: float, t: float,
		mat: String) -> void:
	if s1 - s0 < 0.01 or y1 - y0 < 0.01:
		return
	if axis == "x":
		k.block(Vector3(s0, y0, at - t * 0.5), Vector3(s1, y1, at + t * 0.5), mat)
	else:
		k.block(Vector3(at - t * 0.5, y0, s0), Vector3(at + t * 0.5, y1, s1), mat)


# Closed storefront block: [x0, z0, x1, z1, height, faces] (faces: string of the street sides, e.g. "nz px"):
# solid brick with a dark shopfront, an upper window row and a cornice on each listed face.
static func _annex(k: LandmarkKit, an: Array, fac: String, trim: String, rng: RandomNumberGenerator) -> void:
	var lo := Vector3(an[0], -0.6, an[1])
	var hi := Vector3(an[2], float(an[4]), an[3])
	k.block(lo, hi, "brick_tan" if rng.randf() < 0.5 else fac)
	var faces := str(an[5]) if an.size() > 5 else ""
	for f: String in faces.split(" ", false):
		var along_x := f == "nz" or f == "pz"
		var s0 := float(an[0]) if along_x else float(an[1])
		var s1 := float(an[2]) if along_x else float(an[3])
		var at := float(an[1]) if f == "nz" else float(an[3]) if f == "pz" else float(an[0]) if f == "nx" else float(an[2])
		var out := -0.04 if f == "nz" or f == "nx" else 0.04
		var s := s0 + 0.6
		while s < s1 - 2.0:
			var e := minf(s + rng.randf_range(4.0, 7.0), s1 - 0.6)
			_face_panel(k, along_x, at + out, s, e - 0.5, 0.3, 3.0, "glass_dark")
			_face_panel(k, along_x, at + out * 2.0, s, e - 0.5, 3.0, 3.6, "awning_%d" % rng.randi_range(0, 2))
			for wx in range(int((e - s) / 2.2)):
				var w0 := s + 0.4 + wx * 2.2
				_face_panel(k, along_x, at + out, w0, w0 + 1.2, 4.6, 6.2, "glass_dark")
			s = e
		_face_panel(k, along_x, at + out * 3.0, s0, s1, float(an[4]) - 0.5, float(an[4]) - 0.1, trim)


static func _face_panel(k: LandmarkKit, along_x: bool, at: float, s0: float, s1: float, y0: float, y1: float, mat: String) -> void:
	if along_x:
		k.block(Vector3(s0, y0, at - 0.03), Vector3(s1, y1, at + 0.03), mat, false)
	else:
		k.block(Vector3(at - 0.03, y0, s0), Vector3(at + 0.03, y1, s1), mat, false)


# Signs, lights, loot and spawn markers. Returns counts for the build log.
static func _place(k: LandmarkKit, id: String, d: Dictionary) -> Dictionary:
	var i := 0
	for s: Dictionary in d.get("signs", []):
		var p: Array = s.pos
		var c: Array = s.get("color", [0.95, 0.9, 0.8])
		var l := Label3D.new()
		l.name = "Sign_%d" % i
		l.text = str(s.text)
		l.font_size = int(s.get("size", 120))
		l.pixel_size = 0.01
		l.outline_size = int(s.get("outline", 10))
		l.modulate = Color(c[0], c[1], c[2])
		l.shaded = not bool(s.get("glow", false))
		l.double_sided = false
		l.position = Vector3(p[0], p[1], p[2])
		l.rotation.y = deg_to_rad(float(s.get("yaw_deg", 180.0)))
		l.visibility_range_end = float(s.get("visible_m", 200.0))
		k.root.add_child(l)
		i += 1
	i = 0
	for ld: Dictionary in d.get("lights", []):
		var p: Array = ld.pos
		var c: Array = ld.color
		var light := OmniLight3D.new()
		light.name = "Light_%d" % i
		light.position = Vector3(p[0], level_y(str(ld.get("level", "ground"))) + float(p[1]), p[2])
		light.light_color = Color(c[0], c[1], c[2])
		light.light_energy = float(ld.energy)
		light.omni_range = float(ld.range)
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 45.0
		light.distance_fade_length = 12.0
		k.root.add_child(light)
		i += 1
	for l: Dictionary in d.get("loot", []):
		var p: Array = l.pos
		var sz: Array = l.size
		var y := level_y(str(l.get("level", "ground"))) + float(l.get("y", 0.0))
		k.place(LOOT, Transform3D(Basis(Vector3.UP, deg_to_rad(float(l.get("yaw_deg", 0.0)))), Vector3(p[0], y, p[1])),
			{"container_id": "%s_%s" % [id, l.id], "display_name": str(l.name), "loot_table": str(l.table),
			"size": Vector3(sz[0], sz[1], sz[2]), "color": Color(0.3, 0.27, 0.24)}, "Loot_" + str(l.id))
	for s: Array in d.get("spawns", []):
		var mk := Marker3D.new()
		mk.name = "%s_%s" % [id, s[0]]
		var xz: Array = s[3]
		mk.position = Vector3(xz[0], level_y(str(s[2])) + (float(xz[2]) if xz.size() > 2 else 0.0) + 0.05, xz[1])
		mk.rotation.y = deg_to_rad(float(s[4]) if s.size() > 4 else 0.0)
		mk.set_meta("enemy", str(s[1]))
		mk.add_to_group("lair_spawns", true)
		k.root.add_child(mk)
	return {"loot": d.get("loot", []).size(), "spawns": d.get("spawns", []).size(), "lights": d.get("lights", []).size()}
