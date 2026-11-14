# Kenwood — builds Kenwood Elementary (D-078) into a LandmarkKit from data/landmarks/kenwood.json. Local frame: x
# along the building's long axes (the scene is rotated onto the map by landmarks.json), z "south", y up.
# Shell: floor slab over the real footprint polygon (OSM way 1056847663 cleaned up), outer brick walls along every
# footprint edge (door gaps + step-free ramps from the data), window bands, the low flat roof + dropped ceiling
# everywhere except the two tall halls (gym, cafeteria), which get full-height walls and their own higher roof;
# interior walls with doorways; entrance canopies; rooftop units. Site: two playgrounds, the courtyard gazebo,
# painted circle, flagpole, entrance sign. Then KenwoodRooms furniture, and from the data: signs, lights, loot
# containers and lair spawn markers (Marker3D, group "lair_spawns", meta "enemy").
# Depends on: LandmarkKit, kenwood_rooms.gd, scenes/loot_container.tscn.
extends RefCounted

const LOOT := preload("res://scenes/loot_container.tscn")
const Rooms := preload("res://tools/landmarks/kenwood_rooms.gd")


static func build(k: LandmarkKit, d: Dictionary, rng: RandomNumberGenerator) -> void:
	var m: Dictionary = d.dims
	var fy := float(m.floor_y)
	var poly := _poly(d.footprint)
	var halls: Array = d.halls
	# Floor slab: top over the footprint, a skirt down to below the ground, walkable trimesh.
	var faces := PackedVector3Array()
	for tri in _triangles(poly):
		var a := Vector3(tri[0].x, fy, tri[0].y)
		var b := Vector3(tri[1].x, fy, tri[1].y)
		var c := Vector3(tri[2].x, fy, tri[2].y)
		k.tri(a, b, c, "floor")
		faces.append_array(PackedVector3Array([a, b, c]))
	k.trimesh(faces)
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		k.quad(Vector3(p.x, -1.0, p.y), Vector3(q.x, -1.0, q.y), Vector3(q.x, fy, q.y), Vector3(p.x, fy, p.y), "concrete")
	# Low roof + dropped ceiling over everything but the halls.
	var low := [poly]
	for h: Dictionary in halls:
		low = _minus_rect(low, _rect(h.rect))
	var roof_y := float(m.roof_y)
	var ceil_y := float(m.ceiling_y)
	var roof_faces := PackedVector3Array()
	for piece: PackedVector2Array in low:
		for tri in _triangles(piece):
			k.tri(Vector3(tri[0].x, ceil_y, tri[0].y), Vector3(tri[1].x, ceil_y, tri[1].y), Vector3(tri[2].x, ceil_y, tri[2].y), "ceiling")
			var a := Vector3(tri[0].x, roof_y, tri[0].y)
			var b := Vector3(tri[1].x, roof_y, tri[1].y)
			var c := Vector3(tri[2].x, roof_y, tri[2].y)
			k.tri(a, b, c, "roof")
			roof_faces.append_array(PackedVector3Array([a, b, c]))
	k.trimesh(roof_faces)
	# Halls: roof slab at their own height; hall floors get their finish.
	for h: Dictionary in halls:
		var r := _rect(h.rect)
		var top := float(h.top)
		k.block(Vector3(r.position.x, top, r.position.y), Vector3(r.end.x, top + 0.35, r.end.y), "roof")
		if h.has("floor"):
			k.block(Vector3(r.position.x + 0.2, fy, r.position.y + 0.2), Vector3(r.end.x - 0.2, fy + 0.015, r.end.y - 0.2), str(h.floor), false)
		for w: Dictionary in h.get("inner_walls", []):  # sides inside the building: painted to the low roof, brick above it
			var wa := _v2(w.a)
			var wb := _v2(w.b)
			_wall(k, wa, wb, 0.25, roof_y, float(m.door_h), "wall", w.get("doors", []), -1.0)
			_seg(k, wa, (wb - wa).normalized(), 0.0, wa.distance_to(wb), roof_y, top, 0.25, "brick")
	# Outer walls: one per footprint edge, as high as the hall they bound (else roof + parapet).
	var t := float(m.wall_m)
	var inward := 1.0 if _area(poly) > 0.0 else -1.0
	var doors: Dictionary = {}
	for dr: Dictionary in d.outer_doors:
		doors[int(dr.edge)] = doors.get(int(dr.edge), []) + [[float(dr.at), float(dr.half)]]
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var top := roof_y + float(m.parapet_m)
		for h: Dictionary in halls:
			if _on_rect_side(a, b, _rect(h.rect)):
				top = float(h.top) + float(m.parapet_m)
		var n := _normal(a, b) * inward
		var gaps: Array = doors.get(i, [])
		_wall(k, a + n * t * 0.5, b + n * t * 0.5, t, top, float(m.door_h), "brick", gaps, t * 0.5)
		_band(k, a, b, n, t, top, roof_y)
		if (b - a).length() >= 4.0 and not bool(_skip_windows(d, i)):
			_windows(k, a, b, n, t, gaps, top > roof_y + float(m.parapet_m) + 0.1, m)
		for g: Array in gaps:  # step-free ramp out of each door
			var dir := (b - a).normalized()
			var at := a + dir * float(g[0])
			var out := Vector3(at.x - n.x * (t + 1.6), -0.15, at.y - n.y * (t + 1.6))
			k.ramp(out, Vector3(at.x + n.x * 0.05, fy, at.y + n.y * 0.05), float(g[1]) * 2.0 + 0.6, 0.3, "concrete")
	# Interior walls up to the dropped ceiling.
	for w: Dictionary in d.walls:
		_wall(k, _v2(w.a), _v2(w.b), 0.2, ceil_y, float(m.door_h), "wall", w.get("doors", []), -1.0)
	_canopies(k, d)
	_rooftop(k, d, roof_y)
	_site(k, d, rng)
	Rooms.build(k, d, rng)
	_place(k, d)


# --- shell helpers ---------------------------------------------------------------------------------

# Wall from a to b (local x/z), thickness t, floor (below ground) to top, with door gaps [[metres from a, half
# width], ...] and a lintel over each. extend: lengthen both ends (closes outer corners); < 0 = none.
static func _wall(k: LandmarkKit, a: Vector2, b: Vector2, t: float, top: float, door_h: float, mat: String,
		gaps: Array, extend: float) -> void:
	var dir := (b - a).normalized()
	var length := (b - a).length()
	var e := maxf(extend, 0.0)
	var cuts: Array = []
	for g in gaps:
		cuts.append([float(g[0]) - float(g[1]), float(g[0]) + float(g[1]), float(g[2]) if g.size() > 2 else 0.0,
			float(g[3]) if g.size() > 3 else door_h])
	cuts.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	var at := -e
	for c: Array in cuts:
		if c[0] > at:
			_seg(k, a, dir, at, c[0], -1.0, top, t, mat)
		if c[2] > 0.0:  # window-style opening: wall below the sill
			_seg(k, a, dir, c[0], c[1], -1.0, c[2], t, mat)
		_seg(k, a, dir, c[0], c[1], c[3], top, t, mat)
		at = c[1]
	if length + e > at:
		_seg(k, a, dir, at, length + e, -1.0, top, t, mat)


static func _seg(k: LandmarkKit, a: Vector2, dir: Vector2, s0: float, s1: float, y0: float, y1: float, t: float,
		mat: String) -> void:
	if s1 - s0 < 0.01 or y1 - y0 < 0.01:
		return
	var mid := a + dir * (s0 + s1) * 0.5
	var xf := Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.y)), Vector3(mid.x, (y0 + y1) * 0.5, mid.y))
	k.box_xf(xf, Vector3(t, y1 - y0, s1 - s0), mat)


# Darker band along the top of an outer wall (the cap / fascia line seen in the photos).
static func _band(k: LandmarkKit, a: Vector2, b: Vector2, n: Vector2, t: float, top: float, roof_y: float) -> void:
	var dir := (b - a).normalized()
	var o := -n * 0.02
	var mid := (a + b) * 0.5 + o
	var xf := Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.y)), Vector3(mid.x, top - 0.45, mid.y))
	k.box_xf(xf, Vector3(0.05, 0.7, (b - a).length() + t), "fascia", false)
	if top > roof_y + 2.0:  # tall hall: a second band at the low roof line
		k.box_xf(Transform3D(xf.basis, Vector3(mid.x, roof_y + 0.2, mid.y)), Vector3(0.05, 0.35, (b - a).length() + t), "fascia", false)


# Window panes on both faces of an outer wall, skipping doors; tall walls get a high clerestory band instead.
static func _windows(k: LandmarkKit, a: Vector2, b: Vector2, n: Vector2, t: float, gaps: Array, tall: bool,
		m: Dictionary) -> void:
	var dir := (b - a).normalized()
	var length := (b - a).length()
	var basis := Basis(Vector3.UP, atan2(dir.x, dir.y))
	var y0 := 5.6 if tall else 1.0
	var y1 := 7.0 if tall else 2.5
	var pane := 2.4
	var s := 1.2
	while s + pane <= length - 1.0:
		var clear := true
		for g: Array in gaps:
			if absf(s + pane * 0.5 - float(g[0])) < pane * 0.5 + float(g[1]) + 0.4:
				clear = false
		if clear:
			var mid := a + dir * (s + pane * 0.5)
			for side: float in [-1.0, 1.0]:  # outside face, inside face
				var off := n * (t * 0.5 + side * (t * 0.5 + 0.02))
				k.box_xf(Transform3D(basis, Vector3(mid.x + off.x, (y0 + y1) * 0.5, mid.y + off.y)), Vector3(0.02, y1 - y0, pane), "glass", false)
			var sill := n * (-0.08)
			k.box_xf(Transform3D(basis, Vector3(mid.x + sill.x, y0 - 0.06, mid.y + sill.y)), Vector3(0.18, 0.08, pane + 0.1), "trim", false)
		s += pane + float(m.window_gap_m)


static func _canopies(k: LandmarkKit, d: Dictionary) -> void:
	for c: Dictionary in d.get("canopies", []):
		var pts := _poly(c.points)
		var y := float(c.y)
		for tri in _triangles(pts):
			k.tri(Vector3(tri[0].x, y, tri[0].y), Vector3(tri[1].x, y, tri[1].y), Vector3(tri[2].x, y, tri[2].y), "fascia")
		for p in c.get("posts", []):
			k.box(Vector3(p[0], y * 0.5, p[1]), Vector3(0.25, y, 0.25), "trim")


static func _rooftop(k: LandmarkKit, d: Dictionary, roof_y: float) -> void:
	for u: Array in d.get("rooftop_units", []):
		k.box(Vector3(u[0], roof_y + float(u[4]) * 0.5 + 0.3, u[1]), Vector3(u[2], float(u[4]), u[3]), "steel")


# Playgrounds, gazebo, painted circle, flagpole (outside the walls; ground at y 0).
static func _site(k: LandmarkKit, d: Dictionary, rng: RandomNumberGenerator) -> void:
	var s: Dictionary = d.site
	for p: Array in s.play_structures:
		var c := Vector3(p[0], 0.0, p[1])
		k.box(c + Vector3(0, 0.02, 0), Vector3(9.0, 0.04, 7.0), "mulch", 0.0, false)
		for dx: float in [-2.0, 2.0]:
			for dz: float in [-1.5, 1.5]:
				k.box(c + Vector3(dx, 1.4, dz), Vector3(0.14, 2.8, 0.14), "plastic_green")
		k.box(c + Vector3(0, 1.5, 0), Vector3(4.2, 0.12, 3.2), "plastic_yellow")
		k.box(c + Vector3(0, 2.85, 0), Vector3(4.6, 0.1, 3.6), "plastic_red", 0.0, false)
		k.ramp(c + Vector3(4.6, 0.0, 0.8), c + Vector3(2.1, 1.5, 0.8), 0.9, 0.12, "plastic_red")  # slide
		k.ramp(c + Vector3(-4.2, 0.0, -0.6), c + Vector3(-2.1, 1.5, -0.6), 1.0, 0.12, "plastic_yellow")  # ramp up
		if rng.randf() < 0.7:
			k.box(c + Vector3(rng.randf_range(-3, 3), 0.25, 3.0), Vector3(0.6, 0.5, 0.3), "plastic_green", rng.randf() * TAU, false)
	for sw: Array in s.swings:
		var c := Vector3(sw[0], 0.0, sw[1])
		var yaw := deg_to_rad(float(sw[2]))
		var along := Vector3(cos(yaw), 0, -sin(yaw))
		var side := Vector3(sin(yaw), 0, cos(yaw))
		for e: float in [-3.0, 3.0]:
			for f: float in [-0.9, 0.9]:
				k.box(c + along * e + side * f + Vector3(0, 1.25, 0), Vector3(0.1, 2.5, 0.1), "steel", yaw)
		k.box(c + Vector3(0, 2.5, 0), Vector3(6.2, 0.1, 0.1), "steel", yaw)
		for e: float in [-1.6, 0.0, 1.6]:
			var hang := rng.randf_range(-0.2, 0.2)
			k.box(c + along * e + Vector3(0, 1.45, hang), Vector3(0.02, 1.9, 0.02), "steel", yaw, false)
			k.box(c + along * e + Vector3(0, 0.5, hang), Vector3(0.5, 0.05, 0.25), "plastic_red", yaw, false)
	for g: Array in s.gazebos:
		var c := Vector3(g[0], 0.0, g[1])
		for i in 8:
			var a := TAU * i / 8.0
			k.box(c + Vector3(cos(a) * 3.2, 1.3, sin(a) * 3.2), Vector3(0.18, 2.6, 0.18), "trim")
		k.box(c + Vector3(0, 0.05, 0), Vector3(7.0, 0.1, 7.0), "concrete", PI / 8.0, false)
		k.hip_roof(Vector2(c.x - 3.6, c.z - 3.6), Vector2(c.x + 3.6, c.z + 3.6), 2.6, 1.4, "fascia")
	for c: Array in s.circles:
		k.disc(Vector3(c[0], 0.03, c[1]), float(c[2]), "paint_yellow", 24)
		k.disc(Vector3(c[0], 0.025, c[1]), float(c[2]) + 0.12, "concrete", 24)
	var f: Array = s.flagpole
	k.cylinder(Vector3(f[0], 0.0, f[1]), 0.08, 9.0, "steel", 8, true)
	k.box(Vector3(f[0] + 0.5, 8.2, f[1]), Vector3(0.9, 0.55, 0.02), "plastic_red", 0.0, false)


# --- placed things from the data -------------------------------------------------------------------

static func _place(k: LandmarkKit, d: Dictionary) -> void:
	var fy := float(d.dims.floor_y)
	var i := 0
	for s: Dictionary in d.signs:
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
		l.rotation.y = deg_to_rad(float(s.yaw_deg))
		l.visibility_range_end = float(s.get("visible_m", 60.0))
		k.root.add_child(l)
		i += 1
	i = 0
	for ld: Dictionary in d.lights:
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
	for l: Dictionary in d.loot:
		var p: Array = l.pos
		var sz: Array = l.size
		var col: Array = l.get("color", [0.35, 0.36, 0.4])
		k.place(LOOT, Transform3D(Basis(Vector3.UP, deg_to_rad(float(l.get("yaw_deg", 0.0)))), Vector3(p[0], fy + float(sz[1]) * 0.5, p[1])),
			{"container_id": "kenwood_" + str(l.id), "display_name": str(l.name), "loot_table": str(l.table),
			"size": Vector3(sz[0], sz[1], sz[2]), "color": Color(col[0], col[1], col[2])}, "Loot_" + str(l.id))
	for s: Array in d.spawns:
		var mk := Marker3D.new()
		mk.name = "kenwood_" + str(s[0])
		var xz: Array = s[2]
		mk.position = Vector3(xz[0], fy + 0.05, xz[1])
		mk.set_meta("enemy", str(s[1]))
		mk.add_to_group("lair_spawns", true)
		k.root.add_child(mk)


# --- 2D geometry -----------------------------------------------------------------------------------

static func _poly(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in pts:
		out.append(Vector2(p[0], p[1]))
	return out


static func _v2(p: Array) -> Vector2:
	return Vector2(p[0], p[1])


static func _rect(r: Array) -> Rect2:
	return Rect2(Vector2(r[0], r[1]), Vector2(float(r[2]) - float(r[0]), float(r[3]) - float(r[1])))


static func _triangles(p: PackedVector2Array) -> Array:
	var out: Array = []
	var idx := Geometry2D.triangulate_polygon(p)
	for i in range(0, idx.size(), 3):
		out.append([p[idx[i]], p[idx[i + 1]], p[idx[i + 2]]])
	return out


static func _area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a := p[i]
		var b := p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


# Left-hand normal of a -> b; flipped by the caller so it points into the building.
static func _normal(a: Vector2, b: Vector2) -> Vector2:
	var d := (b - a).normalized()
	return Vector2(-d.y, d.x)


# Polygons minus a rectangle, split at the rectangle's centre first so no piece ever has a hole.
static func _minus_rect(polys: Array, r: Rect2) -> Array:
	var out: Array = []
	var cx := r.get_center().x
	var big := 10000.0
	var halves := [PackedVector2Array([Vector2(-big, -big), Vector2(cx, -big), Vector2(cx, big), Vector2(-big, big)]),
		PackedVector2Array([Vector2(cx, -big), Vector2(big, -big), Vector2(big, big), Vector2(cx, big)])]
	var hole := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	for p: PackedVector2Array in polys:
		for h: PackedVector2Array in halves:
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(p, h):
				out.append_array(Geometry2D.clip_polygons(piece, hole))
	return out


static func _on_rect_side(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var e := 0.05
	for x: float in [r.position.x, r.end.x]:
		if absf(a.x - x) < e and absf(b.x - x) < e and minf(a.y, b.y) >= r.position.y - e and maxf(a.y, b.y) <= r.end.y + e:
			return true
	for y: float in [r.position.y, r.end.y]:
		if absf(a.y - y) < e and absf(b.y - y) < e and minf(a.x, b.x) >= r.position.x - e and maxf(a.x, b.x) <= r.end.x + e:
			return true
	return false


static func _skip_windows(d: Dictionary, edge: int) -> bool:
	for e in d.get("no_window_edges", []):
		if int(e) == edge:
			return true
	return false
