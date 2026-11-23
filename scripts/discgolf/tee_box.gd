# TeeBox — the realistic pieces round a disc golf hole (D-117), presentation only, from data/discgolf/course_looks.json:
# the tee pad (asphalt or concrete slab, textured from assets/textures), the hole sign (board on one wooden post or a
# two-post steel frame; its face carries a drawn map of the hole - fairway from the tee round any doglegs to the
# basket - and the hole / par / length text as a Label3D placed by DiscCourse), and the landscaped mulch ring under a
# basket. Weathering (`wear`): faded board paint, rust streaks, a slight lean. Pads and rings are shared per style;
# each sign is its own mesh. Depends on: nothing (data passed in).
extends RefCounted

const TEXTURES_DIR := "res://assets/textures"

static var _pads: Dictionary = {}
static var _rings: Dictionary = {}


static func pad_mesh(style: Dictionary) -> Mesh:
	var key := style.hash()
	if not _pads.has(key):
		var size: Array = style.size
		var box := BoxMesh.new()
		box.size = Vector3(float(size[0]), 0.3, float(size[1]))
		box.material = _textured(str(style.texture), float(style.tile_m), style.color)
		_pads[key] = box
	return _pads[key]


# [mulch disc, edging ring] for a basket ring style.
static func ring_meshes(style: Dictionary) -> Array[Mesh]:
	var key := style.hash()
	if not _rings.has(key):
		var r := float(style.radius_m)
		var mulch := CylinderMesh.new()
		mulch.top_radius = r
		mulch.bottom_radius = r + 0.05
		mulch.height = 0.12
		mulch.radial_segments = 28
		mulch.rings = 1
		mulch.material = _textured(str(style.texture), 0.8, style.color)
		var edge := TorusMesh.new()
		edge.inner_radius = r - 0.04
		edge.outer_radius = r + 0.06
		edge.rings = 32
		edge.ring_segments = 6
		var em := StandardMaterial3D.new()
		var c: Array = style.edge_color
		em.albedo_color = Color(c[0], c[1], c[2])
		em.roughness = 0.9
		edge.material = em
		_rings[key] = [mulch, edge] as Array[Mesh]
	return _rings[key]


# The sign for one hole: posts, board and the drawn hole map, in the sign's frame (its face toward +Z, the ground at
# y 0). `points` = the hole in map x / z from the tee to the basket (doglegs between). Returns the mesh and where the
# text goes (centre of the text area on the face, and its width).
static func sign_mesh(style: Dictionary, points: PackedVector2Array, wear: float, seed_value: int) -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var board: Array = style.board
	var w := float(board[0])
	var h := float(board[1])
	var cy := float(style.height_m)
	var post_col := _c(style.post_color)
	var face := _c(style.board_color).lerp(Color(0.42, 0.42, 0.4), wear * 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	if int(style.posts) == 1:
		_box(st, Vector3(0, (cy - h * 0.5 - 0.3 + 0.05) * 0.5, -0.06), Vector3(0.09, cy - h * 0.5 + 0.35, 0.09), post_col.darkened(0.1))
		_box(st, Vector3(0, cy, -0.06), Vector3(0.09, h * 0.9, 0.09), post_col)
	else:
		for sx: float in [-1.0, 1.0]:
			_box(st, Vector3(sx * (w * 0.5 - 0.04), (cy + h * 0.5 - 0.3) * 0.5, -0.03), Vector3(0.05, cy + h * 0.5 + 0.3, 0.05), post_col)
	_box(st, Vector3(0, cy, 0), Vector3(w, h, 0.02), face)  # board, face at z = +0.01
	_box(st, Vector3(0, cy + h * 0.5 + 0.01, 0), Vector3(w + 0.02, 0.02, 0.035), face.darkened(0.3))  # top edge
	for i in roundi(wear * 4.0):  # rust streaks from the bolts down the face
		var x := rng.randf_range(-w * 0.45, w * 0.45)
		var streak := rng.randf_range(0.08, h * 0.6)
		_quad(st, Vector3(x, cy + h * 0.5 - 0.03 - streak * 0.5, 0.0115), Vector2(0.012, streak), Color(0.36, 0.2, 0.1, 1.0))
	var landscape := w > h
	var text_c := Vector3(-w * 0.27, cy, 0.012) if landscape else Vector3(0, cy + h * 0.29, 0.012)
	var text_w := w * 0.42 if landscape else w * 0.9
	var area := Rect2(Vector2(w * 0.02, -h * 0.42), Vector2(w * 0.44, h * 0.84)) if landscape \
		else Rect2(Vector2(-w * 0.42, -h * 0.47), Vector2(w * 0.84, h * 0.56))
	_hole_map(st, points, area, cy, _c(style.fairway_color).lerp(face, wear * 0.3))
	var m := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	m.surface_set_material(0, mat)
	return [m, text_c, text_w]


# The hole drawn in `area` (board x / y): fairway strip, tee pad mark, basket.
static func _hole_map(st: SurfaceTool, points: PackedVector2Array, area: Rect2, cy: float, fairway: Color) -> void:
	if points.size() < 2:
		return
	var tee := points[0]
	var fwd := (points[points.size() - 1] - tee).normalized()
	var right := Vector2(-fwd.y, fwd.x)
	var local := PackedVector2Array()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		var q := Vector2((p - tee).dot(right), (p - tee).dot(fwd))  # x across, y along the hole
		local.append(q)
		lo = lo.min(q)
		hi = hi.max(q)
	var span := hi - lo
	var k := minf(area.size.y * 0.86 / maxf(span.y, 1.0), area.size.x * 0.8 / maxf(span.x, 1.0))
	var mid := Vector2((lo.x + hi.x) * 0.5, lo.y)
	var at := func(q: Vector2) -> Vector3:
		var b := Vector2(area.get_center().x, area.position.y + area.size.y * 0.07) + (q - mid) * k
		return Vector3(b.x, cy + b.y, 0.0125)
	for i in local.size() - 1:
		var a: Vector3 = at.call(local[i])
		var b: Vector3 = at.call(local[i + 1])
		var d := (b - a).normalized()
		var n := Vector3(-d.y, d.x, 0.0) * 0.018
		_tri(st, a - n, b - n, b + n, fairway)
		_tri(st, a - n, b + n, a + n, fairway)
		_disc2(st, b, 0.018, fairway, 0.0)
	var t0: Vector3 = at.call(local[0])
	_quad(st, t0 + Vector3(0, 0, 0.001), Vector2(0.03, 0.05), Color(0.55, 0.55, 0.55))
	var bk: Vector3 = at.call(local[local.size() - 1])
	_disc2(st, bk, 0.026, Color(0.95, 0.95, 0.9), 0.001)
	_disc2(st, bk, 0.017, Color(0.95, 0.78, 0.15), 0.002)


static func _textured(tex: String, tile_m: float, col: Array) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var path := "%s/%s/albedo.jpg" % [TEXTURES_DIR, tex]
	if ResourceLoader.exists(path):
		m.albedo_texture = load(path)
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / maxf(tile_m, 0.1)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.albedo_color = Color(col[0], col[1], col[2])
	m.roughness = 0.95
	return m


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var corners := [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1),
		Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]
	for f: Array in [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]:
		var q: Array[Vector3] = []
		for i: int in f:
			q.append(c + corners[i] * h)
		var n := ((q[0] + q[1] + q[2] + q[3]) * 0.25 - c).normalized()
		_tri(st, q[0], q[1], q[2], col, n)
		_tri(st, q[0], q[2], q[3], col, n)


# A flat rectangle on the board face (centre c, size along x / y), facing +Z.
static func _quad(st: SurfaceTool, c: Vector3, s: Vector2, col: Color) -> void:
	var a := c + Vector3(-s.x, -s.y, 0) * 0.5
	var b := c + Vector3(s.x, -s.y, 0) * 0.5
	var d := c + Vector3(s.x, s.y, 0) * 0.5
	var e := c + Vector3(-s.x, s.y, 0) * 0.5
	_tri(st, a, d, b, col)
	_tri(st, a, e, d, col)


static func _disc2(st: SurfaceTool, c: Vector3, r: float, col: Color, dz: float) -> void:
	for i in 12:
		var a0 := TAU * i / 12.0
		var a1 := TAU * (i + 1) / 12.0
		_tri(st, c + Vector3(0, 0, dz), c + Vector3(cos(a1) * r, sin(a1) * r, dz), c + Vector3(cos(a0) * r, sin(a0) * r, dz), col)


# A triangle facing `n` (default +Z, the board face): wound clockwise seen from that side, as Godot draws fronts.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, n := Vector3.BACK) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func _c(a: Array) -> Color:
	return Color(float(a[0]), float(a[1]), float(a[2]))
