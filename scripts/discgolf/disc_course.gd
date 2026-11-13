# DiscCourse — one disc golf course in the world (D-069), the landmark scene scenes/disc_course.tscn placed by
# LandmarkLoader (data/map/landmarks.json "centennial_dgc"). Builds from data/discgolf/courses.json at load:
# a Mach II-style basket per hole (pole, tray, chains, glowing yellow band (D-076), hole number; one shared vertex-coloured mesh),
# an asphalt tee pad with a sign (hole, par, length) and the course box at hole 1 (E: start / join a round).
# Course data is in map coordinates; each piece drops onto the ground with a ray when its cell has loaded.
# Group "disc_courses". Course box body: group "course_boxes" (display_name, course_id) on the interactable layer.
# Visual + colliders only; rounds live in DiscGolfDirector. Depends on: DiscGolfRules, WorldStreamer
# (group "world_streamer": cell_loaded).
class_name DiscCourse
extends Node3D

const GROUND_MASK := 1
const BOX_LAYER := 9  # world + interactables

@export var course_id := "centennial"  # replaced by the course whose "landmark" is this node's name

var course: Dictionary = {}

var _baskets: Array[Node3D] = []
var _tees: Array[Node3D] = []
var _box: Node3D
var _unsnapped: Array[Node3D] = []
var _rids: Array[RID] = []

static var _basket_mesh: ArrayMesh
static var _pad_mesh: BoxMesh
static var _sign_mesh: ArrayMesh
static var _box_mesh: ArrayMesh


func _ready() -> void:
	add_to_group("disc_courses")
	for id: String in DiscGolfRules.courses():  # the landmark key picks the course (one scene for every course)
		if str(DiscGolfRules.courses()[id].landmark) == str(name):
			course_id = id
	course = DiscGolfRules.courses().get(course_id, {})
	if course.is_empty():
		push_error("DiscCourse: unknown course '%s'" % course_id)
		return
	_make_meshes()
	var holes: Array = course.holes
	for i in holes.size():
		var h: Dictionary = holes[i]
		var tee := _map(h.tee)
		var basket := _map(h.basket)
		var dir := (basket - tee).normalized()
		_baskets.append(_add_basket(basket, DiscGolfRules.hole_label(course, i)))
		_tees.append(_add_tee(tee, dir, DiscGolfRules.hole_label(course, i), h))
	_box = _add_box(_map(course.box))
	var streamer := get_tree().get_first_node_in_group("world_streamer")
	if streamer and streamer.has_signal("cell_loaded"):
		streamer.cell_loaded.connect(func(_c: Vector2i) -> void: _snap.call_deferred())
	_snap.call_deferred()


func hole_count() -> int:
	return _baskets.size()


func basket_position(i: int) -> Vector3:
	return _baskets[i].global_position


func tee_position(i: int) -> Vector3:
	return _tees[i].global_position


func box_position() -> Vector3:
	return _box.global_position


func is_snapped() -> bool:
	return _unsnapped.is_empty()


# Course colliders (baskets, box) for flight rays to skip: baskets are handled by DiscGolfRules.
func body_rids() -> Array[RID]:
	return _rids


# Course bounds as a map Rect2 (x, z).
func bounds() -> Rect2:
	var b: Array = course.bounds
	return Rect2(Vector2(b[0], b[1]), Vector2(float(b[2]) - float(b[0]), float(b[3]) - float(b[1])))


func _map(xz: Array) -> Vector3:
	return Vector3(float(xz[0]) - global_position.x, 0.0, float(xz[1]) - global_position.z)  # landmark rotation is 0


# Drops every piece not yet on the ground onto it (cells load around players, so far pieces wait).
func _snap() -> void:
	if not is_inside_tree() or _unsnapped.is_empty():
		return
	var space := get_world_3d().direct_space_state
	for i in range(_unsnapped.size() - 1, -1, -1):
		var n := _unsnapped[i]
		var p := n.global_position
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, global_position.y + 80.0, p.z), Vector3(p.x, global_position.y - 80.0, p.z), GROUND_MASK, _rids)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			n.global_position.y = hit.position.y
			_unsnapped.remove_at(i)


func _anchor(local: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = local
	add_child(n)
	_unsnapped.append(n)
	return n


func _add_basket(local: Vector3, number: String) -> Node3D:
	var a := _anchor(local)
	var mi := MeshInstance3D.new()
	mi.mesh = _basket_mesh
	mi.visibility_range_end = 220.0
	a.add_child(mi)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.3
	cyl.height = 1.4
	shape.shape = cyl
	shape.position = Vector3(0, 0.7, 0)
	body.add_child(shape)
	a.add_child(body)
	_rids.append(body.get_rid())
	var label := _label(number, 64, Color(0.1, 0.1, 0.1))
	label.position = Vector3(0, 1.39, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visibility_range_end = 60.0
	a.add_child(label)
	return a


func _add_tee(local: Vector3, dir: Vector3, number: String, h: Dictionary) -> Node3D:
	var a := _anchor(local)
	var yaw := atan2(-dir.x, -dir.z)  # pad's -Z down the fairway
	var pad := MeshInstance3D.new()
	pad.mesh = _pad_mesh
	pad.rotation.y = yaw
	pad.position = Vector3(0, 0.02, 0) + dir * -0.6
	pad.visibility_range_end = 220.0
	a.add_child(pad)
	var board := MeshInstance3D.new()
	board.mesh = _sign_mesh
	board.rotation.y = yaw
	board.position = dir * -2.6 + dir.cross(Vector3.UP) * 1.4
	board.visibility_range_end = 120.0
	a.add_child(board)
	var label := _label("HOLE %s\nPar %d  ·  %d ft" % [number, int(h.par), int(h.length_ft)], 36, Color(0.95, 0.92, 0.8))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = board.position + Vector3(0, 1.25, 0) - dir * 0.03
	label.visibility_range_end = 40.0
	a.add_child(label)
	return a


func _add_box(local: Vector3) -> Node3D:
	var a := _anchor(local)
	var body := StaticBody3D.new()
	body.collision_layer = BOX_LAYER
	body.collision_mask = 0
	body.add_to_group("course_boxes")
	body.set_meta("course_id", course_id)
	body.set_meta("display_name", str(course.name))
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh
	body.add_child(mi)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.2, 1.0, 0.8)
	shape.shape = bs
	shape.position = Vector3(0, 0.5, 0)
	body.add_child(shape)
	a.add_child(body)
	_rids.append(body.get_rid())
	var label := _label(str(course.name).to_upper() + "\nE: start a round", 40, Color(1.0, 0.85, 0.4))
	label.position = Vector3(0, 1.45, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visibility_range_end = 30.0
	a.add_child(label)
	return a


func _label(text: String, font_size: int, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.004
	l.modulate = col
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.9)
	return l


# --- shared meshes (built once) --------------------------------------------------------------

func _make_meshes() -> void:
	if _basket_mesh != null:
		return
	var metal := Color(0.62, 0.64, 0.66)
	var dark := Color(0.38, 0.4, 0.42)
	var yellow := Color(0.95, 0.78, 0.15)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube(st, Vector3.ZERO, 1.45, 0.03, 0.03, 8, dark)                     # pole
	_tube(st, Vector3(0, 0.5, 0), 0.22, 0.33, 0.33, 20, metal)            # tray wall
	_cap(st, Vector3(0, 0.5, 0), 0.33, 20, dark)                           # tray floor
	_cap(st, Vector3(0, 1.4, 0), 0.12, 10, metal)                          # cap plate
	_tube(st, Vector3(0, 1.33, 0), 0.07, 0.03, 0.12, 10, metal)           # cap cone
	for i in 16:  # outer chains: band down to the tray, pinched toward the pole
		var a := TAU * i / 16.0
		var top := Vector3(cos(a) * 0.28, 1.25, sin(a) * 0.28)
		var bottom := Vector3(cos(a + 0.35) * 0.1, 0.74, sin(a + 0.35) * 0.1)
		_strip(st, top, bottom, 0.012, metal)
	for i in 8:  # inner chains
		var a := TAU * (i + 0.5) / 8.0
		_strip(st, Vector3(cos(a) * 0.14, 1.25, sin(a) * 0.14), Vector3(cos(a) * 0.05, 0.76, sin(a) * 0.05), 0.012, metal)
	st.generate_normals()
	_basket_mesh = st.commit()
	_basket_mesh.surface_set_material(0, _vc_material())
	var band := SurfaceTool.new()  # top band: its own glowing surface so the basket stands out (D-076)
	band.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube(band, Vector3(0, 1.25, 0), 0.08, 0.3, 0.3, 20, yellow)
	band.generate_normals()
	band.commit(_basket_mesh)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = yellow
	glow.emission_enabled = true
	glow.emission = yellow
	glow.emission_energy_multiplier = 2.0
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	_basket_mesh.surface_set_material(1, glow)
	_pad_mesh = BoxMesh.new()
	_pad_mesh.size = Vector3(1.5, 0.06, 3.6)
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color(0.17, 0.17, 0.18)
	asphalt.roughness = 0.95
	_pad_mesh.material = asphalt
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cuboid(st, Vector3(0, 0.55, 0), Vector3(0.08, 1.1, 0.08), Color(0.3, 0.24, 0.18))
	_cuboid(st, Vector3(0, 1.25, 0), Vector3(0.9, 0.55, 0.04), Color(0.12, 0.3, 0.16))
	st.generate_normals()
	_sign_mesh = st.commit()
	_sign_mesh.surface_set_material(0, _vc_material())
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cuboid(st, Vector3(0, 0.45, 0), Vector3(1.2, 0.9, 0.8), Color(0.16, 0.34, 0.2))
	_cuboid(st, Vector3(0, 0.93, 0), Vector3(1.26, 0.06, 0.86), Color(0.3, 0.24, 0.18))
	_cuboid(st, Vector3(0.5, 1.0, 0), Vector3(0.22, 0.06, 0.22), Color(0.92, 0.28, 0.16))  # discs on the lid
	_cuboid(st, Vector3(0.2, 1.0, 0.1), Vector3(0.21, 0.04, 0.21), Color(0.98, 0.78, 0.18))
	_cuboid(st, Vector3(-0.15, 1.0, -0.05), Vector3(0.21, 0.04, 0.21), Color(0.25, 0.6, 0.98))
	st.generate_normals()
	_box_mesh = st.commit()
	_box_mesh.surface_set_material(0, _vc_material())


func _vc_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.6
	m.metallic = 0.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED  # thin chains + hand-wound faces: lit from both sides
	return m


func _tube(st: SurfaceTool, base: Vector3, h: float, r0: float, r1: float, sides: int, col: Color) -> void:
	st.set_color(col)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := base + Vector3(cos(a0) * r0, 0, sin(a0) * r0)
		var p1 := base + Vector3(cos(a1) * r0, 0, sin(a1) * r0)
		var q0 := base + Vector3(cos(a0) * r1, h, sin(a0) * r1)
		var q1 := base + Vector3(cos(a1) * r1, h, sin(a1) * r1)
		for v: Vector3 in [p0, q0, q1, p0, q1, p1]:
			st.add_vertex(v)


func _cap(st: SurfaceTool, centre: Vector3, r: float, sides: int, col: Color) -> void:
	st.set_color(col)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		for v: Vector3 in [centre, centre + Vector3(cos(a1) * r, 0, sin(a1) * r), centre + Vector3(cos(a0) * r, 0, sin(a0) * r)]:
			st.add_vertex(v)


func _strip(st: SurfaceTool, a: Vector3, b: Vector3, w: float, col: Color) -> void:
	st.set_color(col)
	var side := (b - a).cross(Vector3(a.x, 0, a.z).normalized() if Vector3(a.x, 0, a.z).length() > 0.01 else Vector3.RIGHT).normalized() * w
	for v: Vector3 in [a - side, b - side, b + side, a - side, b + side, a + side]:
		st.add_vertex(v)


func _cuboid(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	st.set_color(col)
	var h := s * 0.5
	var corners := [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1),
		Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]
	var faces := [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]
	for f: Array in faces:
		var q: Array[Vector3] = []
		for k: int in f:
			q.append(c + corners[k] * h)
		for v: Vector3 in [q[0], q[1], q[2], q[0], q[2], q[3]]:
			st.add_vertex(v)
