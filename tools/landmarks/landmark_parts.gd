# LandmarkParts — data-driven building parts shared by the D-079 landmark generators (Merryman, Big Apple, Cope
# Stadium, RV park, country club): box "masses" (four walls with door / window gaps + flat roof), free walls,
# floor slabs, stairs, stepped seating rows, plain props, and the placed things every landmark has: signs (Label3D),
# lights (OmniLight3D), loot containers and lair spawn markers. All coordinates are landmark-local metres
# (x, y up, z), the same frame the data file uses.
# Data shapes (arrays are plain JSON arrays):
#   outline {poly [[x, z], ...], top, mat, t?, y0?, gaps? {"<edge i>": [gap, ...]}, tops? {"<edge i>": top}}
#   mass   {rect [x0, z0, x1, z1], y0?, top, t?, mat, roof?, roof_y?, sides? {n|e|s|w: "skip" | [gap, ...]}}
#          gap = [at (m from the side's west / north end), half width, sill?, top?, glazed?] (sill > 0 = window,
#          glazed unless the 5th value is 0, which makes a doorway that starts at the sill height)
#   wall   {a [x, z], b [x, z], y0?, top, t?, mat, gaps? [gap, ...]}
#   floor  {rect [x0, z0, x1, z1], y, mat, thick?}  or  {poly [[x, z], ...], y, mat}
#   stair  {a [x, y, z] (bottom centre), b [x, y, z] (top centre), w, mat}
#   rows   {axis "x"|"z", start, step, count, rise, y0, span [a, b], aisles? [[a, b], ...], mat, seat_mat?,
#           seat_w?, bench?, face?, thick?}  rows run across `span` on the other axis; row i is `step` further
#           along and `rise` higher than row i-1.
#   prop   {box [cx, cy, cz, sx, sy, sz], mat, yaw?, collide?} | {cyl [x, y, z, r, h], mat, sides?, collide?}
#   sign   {text, pos [x, y, z], yaw_deg, pitch_deg?, size, color [r, g, b], visible_m?}
#   light  {pos [x, y, z], color, energy, range}
#   loot   {id, name, table, pos [x, z] | [x, y, z], size [sx, sy, sz], color?, yaw_deg?}  (container_id = prefix_id)
#   spawn  [name, enemy id, [x, z] | [x, y, z]]   (Marker3D "<prefix>_<name>", group lair_spawns, meta enemy)
# Depends on: LandmarkKit, scenes/loot_container.tscn.
extends RefCounted

const LOOT := preload("res://scenes/loot_container.tscn")


static func build_all(k: LandmarkKit, d: Dictionary, prefix: String, floor_y: float) -> void:
	for o: Dictionary in d.get("outlines", []):
		outline(k, o)
	for m: Dictionary in d.get("masses", []):
		mass(k, m)
	for w: Dictionary in d.get("walls", []):
		wall(k, _v2(w.a), _v2(w.b), float(w.get("t", 0.2)), float(w.get("y0", floor_y - 0.3)), float(w.top),
			str(w.mat), w.get("gaps", []), float(w.get("door_h", 2.3)))
	for f: Dictionary in d.get("floors", []):
		slab(k, f)
	for s: Dictionary in d.get("stairs", []):
		k.ramp(_v3(s.a), _v3(s.b), float(s.w), 0.3, str(s.mat))
	for r: Dictionary in d.get("rows", []):
		rows(k, r)
	for p: Dictionary in d.get("props", []):
		prop(k, p)
	signs(k, d.get("signs", []))
	lights(k, d.get("lights", []))
	loot(k, prefix, d.get("loot", []), floor_y)
	spawns(k, prefix, d.get("spawns", []), floor_y)


# --- walls -----------------------------------------------------------------------------------------

static func mass(k: LandmarkKit, m: Dictionary) -> void:
	var r: Array = m.rect
	var t := float(m.get("t", 0.3))
	var y0 := float(m.get("y0", -0.3))
	var top := float(m.top)
	var sides: Dictionary = m.get("sides", {})
	var h := t * 0.5
	var edges := {"n": [Vector2(r[0], float(r[1]) + h), Vector2(r[2], float(r[1]) + h)],
		"s": [Vector2(r[0], float(r[3]) - h), Vector2(r[2], float(r[3]) - h)],
		"w": [Vector2(float(r[0]) + h, r[1]), Vector2(float(r[0]) + h, r[3])],
		"e": [Vector2(float(r[2]) - h, r[1]), Vector2(float(r[2]) - h, r[3])]}
	for side: String in edges:
		var g = sides.get(side, [])
		if g is String and g == "skip":
			continue
		wall(k, edges[side][0], edges[side][1], t, y0, top, str(m.mat), g, float(m.get("door_h", 2.4)))
	if str(m.get("roof", "roof")) != "":
		var ry := float(m.get("roof_y", top))
		k.block(Vector3(r[0], ry, r[1]), Vector3(r[2], ry + 0.25, r[3]), str(m.get("roof", "roof")))


# Outer walls along a footprint polygon {poly [[x, z], ...], t, y0, top, mat, gaps {"<edge index>": [gap, ...]},
# tops? {"<edge index>": top}}: one wall per edge (point i -> i+1), centred t/2 inside the outline.
static func outline(k: LandmarkKit, o: Dictionary) -> void:
	var pts := PackedVector2Array()
	for p: Array in o.poly:
		pts.append(Vector2(p[0], p[1]))
	var area := 0.0
	for i in pts.size():
		area += pts[i].cross(pts[(i + 1) % pts.size()])
	var t := float(o.get("t", 0.3))
	var gaps: Dictionary = o.get("gaps", {})
	var tops: Dictionary = o.get("tops", {})
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var n := (b - a).normalized().orthogonal() * (-1.0 if area > 0.0 else 1.0)  # inward
		wall(k, a + n * t * 0.5, b + n * t * 0.5, t, float(o.get("y0", -0.3)), float(tops.get(str(i), o.top)), str(o.mat),
			gaps.get(str(i), []), float(o.get("door_h", 2.4)))


# Wall from a to b (centre line), thickness t, from y0 to top, with gaps [at, half, sill?, top?] measured from a.
static func wall(k: LandmarkKit, a: Vector2, b: Vector2, t: float, y0: float, top: float, mat: String, gaps: Array,
		door_h := 2.4) -> void:
	var dir := (b - a).normalized()
	var length := a.distance_to(b)
	var cuts: Array = []
	for g: Array in gaps:
		cuts.append([float(g[0]) - float(g[1]), float(g[0]) + float(g[1]), float(g[2]) if g.size() > 2 else 0.0,
			float(g[3]) if g.size() > 3 else door_h, g.size() < 5 or bool(g[4])])
	cuts.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	var at := 0.0
	for c: Array in cuts:
		if c[0] > at:
			seg(k, a, dir, at, c[0], y0, top, t, mat)
		if c[2] > 0.0:  # window (or a raised doorway when the gap's 5th value is 0): wall below the sill + glass
			seg(k, a, dir, c[0], c[1], y0, c[2], t, mat)
			if c[4]:
				seg(k, a, dir, c[0], c[1], c[2], c[3], 0.04, "glass", false)
		seg(k, a, dir, c[0], c[1], c[3], top, t, mat)
		at = c[1]
	if length > at:
		seg(k, a, dir, at, length, y0, top, t, mat)


static func seg(k: LandmarkKit, a: Vector2, dir: Vector2, s0: float, s1: float, y0: float, y1: float, t: float,
		mat: String, collide := true) -> void:
	if s1 - s0 < 0.01 or y1 - y0 < 0.01:
		return
	var mid := a + dir * (s0 + s1) * 0.5
	k.box_xf(Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.y)), Vector3(mid.x, (y0 + y1) * 0.5, mid.y)),
		Vector3(t, y1 - y0, s1 - s0), mat, collide)


# --- floors, rows, props --------------------------------------------------------------------------

static func slab(k: LandmarkKit, f: Dictionary) -> void:
	var y := float(f.y)
	if f.has("rect"):
		var r: Array = f.rect
		k.block(Vector3(r[0], y - float(f.get("thick", 0.15)), r[1]), Vector3(r[2], y, r[3]), str(f.mat))
		return
	var poly := PackedVector2Array()
	for p: Array in f.poly:
		poly.append(Vector2(p[0], p[1]))
	var idx := Geometry2D.triangulate_polygon(poly)
	var faces := PackedVector3Array()
	for i in range(0, idx.size(), 3):
		var t := [poly[idx[i]], poly[idx[i + 1]], poly[idx[i + 2]]]
		var v := [Vector3(t[0].x, y, t[0].y), Vector3(t[1].x, y, t[1].y), Vector3(t[2].x, y, t[2].y)]
		k.tri(v[0], v[1], v[2], str(f.mat))
		faces.append_array(PackedVector3Array(v))
	k.trimesh(faces)


# Stepped seating: row i covers [start + i*step, start + (i+1)*step] along `axis`, its floor at y0 + i*rise, running
# across `span` (other axis). Each row is a solid step (collision) in `mat`; seats are individual chairs (seat_w
# apart) or one bench, set at the row's back edge and facing `face` (-1 = toward -axis, default: toward row 0).
static func rows(k: LandmarkKit, r: Dictionary) -> void:
	var along_x := str(r.axis) == "x"
	var step := float(r.step)
	var face := float(r.get("face", -signf(step)))
	var span: Array = r.span
	var aisles: Array = r.get("aisles", [])
	var seat_mat := str(r.get("seat_mat", ""))
	var seat_w := float(r.get("seat_w", 0.55))
	var bench := bool(r.get("bench", false))
	for i in int(r.count):
		var a := float(r.start) + i * step
		var y := float(r.y0) + i * float(r.rise)
		var lo := minf(a, a + step)
		var hi := maxf(a, a + step)
		_rows_block(k, along_x, lo, hi, float(span[0]), float(span[1]), y - float(r.get("thick", 0.6)), y, str(r.mat))
		if seat_mat == "":
			continue
		var s0 := float(span[0])
		var pieces: Array = []
		for ai: Array in aisles:
			pieces.append([s0, float(ai[0])])
			s0 = float(ai[1])
		pieces.append([s0, float(span[1])])
		var seat := (hi - 0.35) if face < 0.0 else (lo + 0.35)  # seat near the back edge, legroom toward `face`
		var back := seat - face * 0.24
		for p: Array in pieces:
			if bench:
				_rows_block(k, along_x, seat - 0.15, seat + 0.15, float(p[0]) + 0.1, float(p[1]) - 0.1, y + 0.38, y + 0.45, seat_mat, false)
				continue
			var n := floori((float(p[1]) - float(p[0])) / seat_w)
			for j in n:
				var c := float(p[0]) + (j + 0.5) * seat_w
				var sp := Vector3(seat, y + 0.45, c) if along_x else Vector3(c, y + 0.45, seat)
				var bk := Vector3(back, y + 0.75, c) if along_x else Vector3(c, y + 0.75, back)
				var ss := Vector3(0.45, 0.08, seat_w - 0.06) if along_x else Vector3(seat_w - 0.06, 0.08, 0.45)
				var bs := Vector3(0.06, 0.55, seat_w - 0.06) if along_x else Vector3(seat_w - 0.06, 0.55, 0.06)
				k.box(sp, ss, seat_mat, 0.0, false)
				k.box(bk, bs, seat_mat, 0.0, false)


static func _rows_block(k: LandmarkKit, along_x: bool, a0: float, a1: float, s0: float, s1: float, y0: float, y1: float,
		mat: String, collide := true) -> void:
	if along_x:
		k.block(Vector3(a0, y0, s0), Vector3(a1, y1, s1), mat, collide)
	else:
		k.block(Vector3(s0, y0, a0), Vector3(s1, y1, a1), mat, collide)


static func prop(k: LandmarkKit, p: Dictionary) -> void:
	if p.has("box"):
		var b: Array = p.box
		k.box(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]), str(p.mat), deg_to_rad(float(p.get("yaw", 0.0))),
			bool(p.get("collide", true)))
	elif p.has("cyl"):
		var c: Array = p.cyl
		k.cylinder(Vector3(c[0], c[1], c[2]), float(c[3]), float(c[4]), str(p.mat), int(p.get("sides", 8)),
			bool(p.get("collide", false)))


# --- placed things -------------------------------------------------------------------------------

static func signs(k: LandmarkKit, list: Array) -> void:
	var i := k.root.get_child_count()
	for s: Dictionary in list:
		var p: Array = s.pos
		var c: Array = s.color
		var l := Label3D.new()
		l.name = "Sign_%d" % i
		l.text = str(s.text)
		l.font_size = int(s.size)
		l.pixel_size = 0.01
		l.outline_size = 8
		l.modulate = Color(c[0], c[1], c[2])
		l.shaded = true
		l.double_sided = false
		l.position = Vector3(p[0], p[1], p[2])
		l.rotation = Vector3(deg_to_rad(float(s.get("pitch_deg", 0.0))), deg_to_rad(float(s.yaw_deg)), 0.0)
		l.visibility_range_end = float(s.get("visible_m", 60.0))
		k.root.add_child(l)
		i += 1


static func lights(k: LandmarkKit, list: Array) -> void:
	var i := 0
	for ld: Dictionary in list:
		var p: Array = ld.pos
		var c: Array = ld.color
		var light := OmniLight3D.new()
		light.name = "Light_%d" % i
		light.position = Vector3(p[0], p[1], p[2])
		light.light_color = Color(c[0], c[1], c[2])
		light.light_energy = float(ld.energy)
		light.omni_range = float(ld.range)
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 45.0
		light.distance_fade_length = 15.0
		k.root.add_child(light)
		i += 1


static func loot(k: LandmarkKit, prefix: String, list: Array, floor_y: float) -> void:
	for l: Dictionary in list:
		var p: Array = l.pos
		var sz: Array = l.size
		var col: Array = l.get("color", [0.35, 0.36, 0.4])
		var base := float(p[1]) if p.size() > 2 else floor_y
		var xz := Vector2(p[0], p[2] if p.size() > 2 else p[1])
		k.place(LOOT, Transform3D(Basis(Vector3.UP, deg_to_rad(float(l.get("yaw_deg", 0.0)))), Vector3(xz.x, base + float(sz[1]) * 0.5, xz.y)),
			{"container_id": prefix + "_" + str(l.id), "display_name": str(l.name), "loot_table": str(l.table),
			"size": Vector3(sz[0], sz[1], sz[2]), "color": Color(col[0], col[1], col[2])}, "Loot_" + str(l.id))


static func spawns(k: LandmarkKit, prefix: String, list: Array, floor_y: float) -> void:
	for s: Array in list:
		var p: Array = s[2]
		var mk := Marker3D.new()
		mk.name = prefix + "_" + str(s[0])
		mk.position = Vector3(p[0], float(p[1]) + 0.05, p[2]) if p.size() > 2 else Vector3(p[0], floor_y + 0.05, p[1])
		mk.set_meta("enemy", str(s[1]))
		mk.add_to_group("lair_spawns", true)
		k.root.add_child(mk)


static func _v2(a: Array) -> Vector2:
	return Vector2(a[0], a[1])


static func _v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])
