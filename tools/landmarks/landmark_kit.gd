# LandmarkKit — geometry helpers for generated landmark scenes (D-047): collects boxes, cylinders, roofs, ramps,
# flower clumps and swept profiles into ONE mesh per material (built at tool time, so the landmark costs a handful
# of draw calls) plus one StaticBody with box/trimesh collision. Materials come from the landmark's data file:
# photo textures from assets/textures/<id>/ (world triplanar, so no UVs are needed) or flat colours (+ optional "emission"); "visible_m"
# sets a visibility range on that material's mesh. place() adds scene instances (loot, NPCs). save() writes the scene. Depends on: nothing (tool-time only).
class_name LandmarkKit
extends RefCounted

const TEXTURES_DIR := "res://assets/textures"

var root := Node3D.new()
var body := StaticBody3D.new()
var frame := Transform3D.IDENTITY  # applied to everything added (place/rotate a sub-part of the landmark)
var _defs: Dictionary
var _mats: Dictionary = {}  # id -> Material
var _sts: Dictionary = {}   # id -> SurfaceTool
var _tris := 0


func _init(scene_name: String, material_defs: Dictionary) -> void:
	root.name = scene_name
	body.name = "Collision"
	root.add_child(body)
	_defs = material_defs


# --- solids ------------------------------------------------------------------------------

# Box of `size` centred at `xf.origin`, rotated by xf.basis. collide adds a matching BoxShape3D.
func box_xf(xf: Transform3D, size: Vector3, mat: String, collide := true, skip_faces: Array = []) -> void:
	var h := size * 0.5
	var c := []
	for i in 8:
		c.append(xf * Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	var faces := {"top": [2, 6, 7, 3], "bottom": [0, 1, 5, 4], "north": [0, 2, 3, 1], "south": [4, 5, 7, 6],
		"west": [0, 4, 6, 2], "east": [1, 3, 7, 5]}
	for f: String in faces:
		if f in skip_faces:
			continue
		var q: Array = faces[f]
		quad(c[q[0]], c[q[1]], c[q[2]], c[q[3]], mat)
	if collide:
		var shape := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = size
		shape.shape = b
		shape.transform = frame * xf
		body.add_child(shape)


func box(center: Vector3, size: Vector3, mat: String, yaw := 0.0, collide := true) -> void:
	box_xf(Transform3D(Basis(Vector3.UP, yaw), center), size, mat, collide)


# Box spanning lo..hi (axis aligned).
func block(lo: Vector3, hi: Vector3, mat: String, collide := true) -> void:
	box((lo + hi) * 0.5, hi - lo, mat, 0.0, collide)


# Walkable ramp of width w from a (bottom centre of the start edge) to b (top centre of the end edge).
func ramp(a: Vector3, b: Vector3, w: float, thick: float, mat: String) -> void:
	var along := b - a
	var fwd := along.normalized()
	var side := Vector3(fwd.z, 0, -fwd.x).normalized()
	var up := fwd.cross(side).normalized()
	if up.y < 0:
		up = -up
		side = -side
	var basis := Basis(side, up, fwd)
	box_xf(Transform3D(basis, (a + b) * 0.5 - up * thick * 0.5), Vector3(w, thick, along.length()), mat)


# Vertical post/cylinder (sides segments), no caps underneath.
func cylinder(base: Vector3, radius: float, height: float, mat: String, sides := 8, collide := false) -> void:
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := base + Vector3(cos(a0), 0, sin(a0)) * radius
		var p1 := base + Vector3(cos(a1), 0, sin(a1)) * radius
		quad(p0, p0 + Vector3.UP * height, p1 + Vector3.UP * height, p1, mat)
		tri(base + Vector3.UP * height, p1 + Vector3.UP * height, p0 + Vector3.UP * height, mat)
	if collide:
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = radius
		cyl.height = height
		shape.shape = cyl
		shape.transform = frame * Transform3D(Basis(), base + Vector3.UP * height * 0.5)
		body.add_child(shape)


# Disc (flat, facing up) of radius at centre, e.g. flower heads, pads.
func disc(centre: Vector3, radius: float, mat: String, sides := 12, normal := Vector3.UP) -> void:
	var t := normal.cross(Vector3.FORWARD if absf(normal.y) > 0.9 else Vector3.UP).normalized()
	var b := normal.cross(t)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		tri(centre, centre + (t * cos(a1) + b * sin(a1)) * radius, centre + (t * cos(a0) + b * sin(a0)) * radius, mat)


# Four-sided (hip) roof: eave rectangle lo..hi (x, z) at height y, rising `rise` to a ridge of length ridge_x.
func hip_roof(lo: Vector2, hi: Vector2, y: float, rise: float, mat: String, ridge_x := 0.0) -> void:
	var c := (lo + hi) * 0.5
	var r0 := Vector3(c.x - ridge_x * 0.5, y + rise, c.y)
	var r1 := Vector3(c.x + ridge_x * 0.5, y + rise, c.y)
	var a := Vector3(lo.x, y, lo.y)
	var b := Vector3(hi.x, y, lo.y)
	var cc := Vector3(hi.x, y, hi.y)
	var d := Vector3(lo.x, y, hi.y)
	quad(a, r0, r1, b, mat)   # north slope
	quad(cc, r1, r0, d, mat)  # south slope
	tri(b, r1, cc, mat)
	tri(d, r0, a, mat)
	quad(a, b, cc, d, mat)    # soffit


# Thin railing along a polyline at height h above each point (top rail + posts every `post_m`).
func railing(pts: PackedVector3Array, h: float, mat: String, post_m := 1.5, collide := true) -> void:
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var d := b - a
		var len_h := Vector2(d.x, d.z).length()
		var yaw := atan2(d.x, d.z)
		var mid := (a + b) * 0.5
		var tilt := atan2(d.y, len_h)
		var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -tilt), mid + Vector3.UP * h)
		box_xf(xf, Vector3(0.06, 0.06, d.length()), mat, false)
		box_xf(Transform3D(xf.basis, mid + Vector3.UP * h * 0.5), Vector3(0.03, 0.03, d.length()), mat, false)
		var n := maxi(1, ceili(len_h / post_m))
		for k in n + 1:
			var p := a.lerp(b, float(k) / n)
			box(p + Vector3.UP * h * 0.5, Vector3(0.06, h, 0.06), mat, 0.0, false)
		if collide:
			box_xf(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -tilt), mid + Vector3.UP * h * 0.5),
				Vector3(0.1, h, d.length()), "", true)


# A clump of wild flowers / tall grass: n crossed vertical quads on material `mat` (shaders/wild_flowers.gdshader
# cuts stems and petal heads out of each quad: COLOR = petal colour, UV = quad 0..1, UV2.x = per-quad seed).
func flowers(centre: Vector3, radius: float, n: int, colors: Array, rng: RandomNumberGenerator, mat: String,
		height := Vector2(0.35, 0.9)) -> void:
	for i in n:
		var a := rng.randf() * TAU
		var p := centre + Vector3(cos(a), 0, sin(a)) * sqrt(rng.randf()) * radius
		var h := rng.randf_range(height.x, height.y)
		var w := h * rng.randf_range(0.9, 1.3)
		var col: Color = colors[rng.randi_range(0, colors.size() - 1)]
		col = col * rng.randf_range(0.8, 1.1)
		var yaw := rng.randf() * PI
		for k in 2:
			var e := Vector3(cos(yaw + k * PI * 0.5), 0, sin(yaw + k * PI * 0.5)) * w * 0.5
			var sd := Vector2(rng.randf() * 100.0, 0.0)
			_vert(p - e, col, mat, Vector2(0, 0), sd)
			_vert(p + e + Vector3.UP * h, col, mat, Vector2(1, 1), sd)
			_vert(p + e, col, mat, Vector2(1, 0), sd)
			_vert(p - e, col, mat, Vector2(0, 0), sd)
			_vert(p - e + Vector3.UP * h, col, mat, Vector2(0, 1), sd)
			_vert(p + e + Vector3.UP * h, col, mat, Vector2(1, 1), sd)


# Surface swept around `centre` from angle a0 to a1 (radians, 0 = +x, PI/2 = +z) through a radial profile of
# (radius, height) points; tread_mat on flat parts, riser_mat on steep parts. Adds trimesh collision.
func sweep(centre: Vector3, profile: PackedVector2Array, a0: float, a1: float, segs: int, tread_mat: String,
		riser_mat: String) -> void:
	var faces := PackedVector3Array()
	for s in segs:
		var t0 := lerpf(a0, a1, float(s) / segs)
		var t1 := lerpf(a0, a1, float(s + 1) / segs)
		var d0 := Vector3(cos(t0), 0, sin(t0))
		var d1 := Vector3(cos(t1), 0, sin(t1))
		for i in range(profile.size() - 1):
			var p := profile[i]
			var q := profile[i + 1]
			var mat := riser_mat if absf(q.y - p.y) > (q.x - p.x) * 0.6 else tread_mat
			var v := [centre + d0 * p.x + Vector3.UP * p.y, centre + d1 * p.x + Vector3.UP * p.y,
				centre + d1 * q.x + Vector3.UP * q.y, centre + d0 * q.x + Vector3.UP * q.y]
			quad(v[0], v[1], v[2], v[3], mat)
			faces.append_array(PackedVector3Array([v[0], v[1], v[2], v[0], v[2], v[3]]))
	trimesh(faces)


func trimesh(faces: PackedVector3Array) -> void:
	var shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.backface_collision = true
	var world := PackedVector3Array()
	for v in faces:
		world.append(frame * v)
	concave.set_faces(world)
	shape.shape = concave
	body.add_child(shape)


# --- placed scenes ----------------------------------------------------------------------------

# Instances `scene` (e.g. a loot container or an NPC) at xf (under `frame`) with property overrides; saved with
# the landmark as an instance, so the scene's own script runs in game.
func place(scene: PackedScene, xf: Transform3D, props: Dictionary = {}, node_name := "") -> Node3D:
	var n := scene.instantiate() as Node3D
	if node_name != "":
		n.name = node_name
	for key: String in props:
		n.set(key, props[key])
	n.transform = frame * xf
	root.add_child(n)
	return n


# --- raw triangles ---------------------------------------------------------------------------

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, mat: String) -> void:
	tri(a, b, c, mat)
	tri(a, c, d, mat)


func tri(a: Vector3, b: Vector3, c: Vector3, mat: String) -> void:
	if mat == "":
		return
	var st := _st(mat)
	var n := frame.basis * (b - a).cross(c - a).normalized()
	var order := [a, c, b]  # Godot's front faces wind clockwise; n is the counter-clockwise (outward) normal
	if n.y < -0.7:  # flat pieces given in either winding: always face up
		n = -n
		order = [a, b, c]
	for v in order:
		st.set_normal(n)
		st.add_vertex(frame * v)
	_tris += 1


func _vert(v: Vector3, col: Color, mat: String, uv := Vector2.ZERO, uv2 := Vector2.ZERO) -> void:
	var st := _st(mat)
	st.set_color(col)
	st.set_uv(uv)
	st.set_uv2(uv2)
	st.set_normal(Vector3.UP)
	st.add_vertex(frame * v)


func _st(mat: String) -> SurfaceTool:
	if not _sts.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_sts[mat] = st
	return _sts[mat]


# --- output ------------------------------------------------------------------------------------

func save(path: String) -> String:
	var ids: Array = _sts.keys()
	ids.sort()
	for id: String in ids:
		var mi := MeshInstance3D.new()
		mi.name = "Mesh_" + id
		mi.mesh = (_sts[id] as SurfaceTool).commit()
		mi.material_override = _material(id)
		var def: Dictionary = _defs.get(id, {})
		if def.has("visible_m"):
			mi.visibility_range_end = float(def.visible_m)
			mi.visibility_range_end_margin = 10.0
		if not bool(def.get("shadows", true)):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	_own(root, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path, ResourceSaver.FLAG_COMPRESS)
	var msg := "%s: %d meshes, %d tris, %d collision shapes -> %s (err %d)" % [root.name, ids.size(), _tris,
		body.get_child_count(), path, err]
	root.free()
	return msg


func _material(id: String) -> Material:
	if _mats.has(id):
		return _mats[id]
	var def: Dictionary = _defs.get(id, {})
	if def.has("shader"):
		var sm := ShaderMaterial.new()
		sm.shader = load(str(def.shader))
		_mats[id] = sm
		return sm
	var m := ORMMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tint: Array = def.get("color", [1.0, 1.0, 1.0])
	m.albedo_color = Color(tint[0], tint[1], tint[2], float(def.get("alpha", 1.0)))
	if def.has("texture"):
		var dir := "%s/%s" % [TEXTURES_DIR, def.texture]
		m.albedo_texture = load(dir + "/albedo.jpg")
		m.normal_enabled = true
		m.normal_texture = load(dir + "/normal.jpg")
		m.orm_texture = load(dir + "/arm.jpg")
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / float(def.get("tile_m", 2.0))
	else:
		m.roughness = float(def.get("roughness", 0.9))
		m.metallic = float(def.get("metallic", 0.0))
	if bool(def.get("vertex_color", false)):
		m.vertex_color_use_as_albedo = true
	if bool(def.get("cull_back", false)):
		m.cull_mode = BaseMaterial3D.CULL_BACK
	if float(def.get("alpha", 1.0)) < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if def.has("emission"):  # glowing bits (grow lights, string lights): [r, g, b, energy]
		var e: Array = def.emission
		m.emission_enabled = true
		m.emission = Color(e[0], e[1], e[2])
		m.emission_energy_multiplier = float(e[3]) if e.size() > 3 else 1.0
	_mats[id] = m
	return m


func _own(node: Node, owner_node: Node) -> void:
	for c in node.get_children():
		c.owner = owner_node
		if c.scene_file_path == "":  # instanced scenes keep their own children
			_own(c, owner_node)
