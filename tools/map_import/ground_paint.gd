# GroundPaint — D-080: paints flat ground surfaces (golf greens, tees, fairways, bunkers, cart paths) onto the
# generated terrain. A landmark's "ground_paint" data file lists polygons and path lines in landmark-local metres;
# each is clipped to every terrain triangle it covers and laid on that triangle's plane, a few cm up (one lift per
# layer so overlapping layers never z-fight; paths go above sidewalk strips). One mesh per paint material per cell,
# no collision, no shadows. Used only by the offline importer (build_cells).
# Paint file: {materials {id: {color, roughness?, texture?, tile_m?}}, layers [id, ...] (bottom to top),
#   polys [{mat, poly [[x, z], ...]}], paths [{mat, width, line [[x, z], ...]}]}
# Depends on: imported textures (assets/textures/<id>/albedo.jpg).
extends RefCounted

const LIFT_BASE := 0.03
const LIFT_STEP := 0.02
const TEXTURES_DIR := "res://assets/textures"

var _mat_dir := ""
var _order: Array[String] = []    # material keys, bottom to top
var _mats: Dictionary = {}        # key -> Material
var _lift: Dictionary = {}        # key -> metres above the terrain
var _shapes: Array = []           # [key, PackedVector2Array map-space polygon, Rect2 bounds]


func _init(mat_dir: String) -> void:
	_mat_dir = mat_dir


# Adds one landmark's paint file; pos / rot place its local frame on the map (as LandmarkLoader does).
func add(paint: Dictionary, prefix: String, pos: Vector2, rot: float) -> void:
	var layers: Array = paint.get("layers", [])
	for i in layers.size():
		var id := str(layers[i])
		var key := prefix + "_" + id
		_order.append(key)
		_lift[key] = LIFT_BASE + LIFT_STEP * i
		_mats[key] = _material(key, paint.materials[id])
	for p: Dictionary in paint.get("polys", []):
		var poly := PackedVector2Array()
		for v: Array in p.poly:
			poly.append(Vector2(v[0], v[1]).rotated(-rot) + pos)
		_add_shape(prefix + "_" + str(p.mat), poly)
	for p: Dictionary in paint.get("paths", []):  # each segment a rectangle, run on half a width past both ends
		var half := float(p.width) * 0.5
		var line: Array = p.line
		for j in range(line.size() - 1):
			var a := Vector2(line[j][0], line[j][1]).rotated(-rot) + pos
			var b := Vector2(line[j + 1][0], line[j + 1][1]).rotated(-rot) + pos
			if a.distance_to(b) < 0.01:
				continue
			var d := (b - a).normalized() * half
			var s := d.orthogonal()
			_add_shape(prefix + "_" + str(p.mat), PackedVector2Array([a - d - s, b + d - s, b + d + s, a - d + s]))


# Paint meshes for one cell under `root`. ground(x, z) gives the terrain vertex heights on the `step` grid.
func add_cell(rect: Rect2, root: Node3D, ground: Callable, step: float) -> int:
	var tris := 0
	for key: String in _order:
		var st: SurfaceTool = null
		for sh: Array in _shapes:
			if sh[0] != key or not (sh[2] as Rect2).intersects(rect):
				continue
			if st == null:
				st = SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tris += _paint_shape(st, sh[1], (sh[2] as Rect2).intersection(rect), rect.position, ground, step, float(_lift[key]))
		if st == null:
			continue
		var mesh := st.commit()
		if mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Paint_" + key
		mi.mesh = mesh
		mi.material_override = _mats[key]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return tris


func _add_shape(key: String, poly: PackedVector2Array) -> void:
	if not _mats.has(key) or poly.size() < 3:
		return
	var r := Rect2(poly[0], Vector2.ZERO)
	for v in poly:
		r = r.expand(v)
	_shapes.append([key, poly, r])


# Clip `poly` (a simple polygon, so no clipped piece has holes) to each terrain triangle of the quads covering
# `area` (grid anchored at `origin`) and lay the pieces on the triangles' planes. Terrain quads are
# a(x0,z0) b(x1,z0) c(x1,z1) d(x0,z1), split a-b-c / a-c-d (build_cells).
func _paint_shape(st: SurfaceTool, poly: PackedVector2Array, area: Rect2, origin: Vector2, ground: Callable, step: float,
		lift: float) -> int:
	var count := 0
	var i0 := floori((area.position.x - origin.x) / step)
	var i1 := ceili((area.end.x - origin.x) / step)
	var j0 := floori((area.position.y - origin.y) / step)
	var j1 := ceili((area.end.y - origin.y) / step)
	for j in range(j0, j1):
		for i in range(i0, i1):
			var x0 := origin.x + i * step
			var z0 := origin.y + j * step
			var a := Vector3(x0, ground.call(x0, z0), z0)
			var b := Vector3(x0 + step, ground.call(x0 + step, z0), z0)
			var c := Vector3(x0 + step, ground.call(x0 + step, z0 + step), z0 + step)
			var d := Vector3(x0, ground.call(x0, z0 + step), z0 + step)
			count += _clip_tri(st, poly, a, b, c, lift)
			count += _clip_tri(st, poly, a, c, d, lift)
	return count


func _clip_tri(st: SurfaceTool, poly: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3, lift: float) -> int:
	var tri := PackedVector2Array([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)])
	var n := (b - a).cross(c - a)
	if absf(n.y) < 0.000001:
		return 0
	var up := n.normalized() * signf(n.y)
	var count := 0
	for piece: PackedVector2Array in Geometry2D.intersect_polygons(poly, tri):
		var idx := Geometry2D.triangulate_polygon(piece)
		for k in range(0, idx.size(), 3):
			var p0 := piece[idx[k]]
			var p1 := piece[idx[k + 1]]
			var p2 := piece[idx[k + 2]]
			if (p1 - p0).cross(p2 - p0) < 0.0:  # same winding as the terrain triangles
				var t := p1
				p1 = p2
				p2 = t
			for p: Vector2 in [p0, p1, p2]:
				st.set_normal(up)
				st.set_uv(p)
				st.add_vertex(Vector3(p.x, a.y - (n.x * (p.x - a.x) + n.z * (p.y - a.z)) / n.y + lift, p.y))
			count += 1
	return count


func _material(key: String, spec: Dictionary) -> Material:
	var m := StandardMaterial3D.new()
	var col: Array = spec.get("color", [1, 1, 1])
	m.albedo_color = Color(col[0], col[1], col[2])
	m.roughness = float(spec.get("roughness", 1.0))
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if spec.has("texture"):
		m.albedo_texture = load("%s/%s/albedo.jpg" % [TEXTURES_DIR, spec.texture])
		m.uv1_scale = Vector3.ONE / float(spec.get("tile_m", 2.0))
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var path := "%s/paint_%s.tres" % [_mat_dir, key]
	ResourceSaver.save(m, path, ResourceSaver.FLAG_CHANGE_PATH)
	return m
