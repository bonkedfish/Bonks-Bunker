# GroundProps — small landmark props that stand on the real ground rather than at the landmark's flat origin height
# (D-080): the country club's hole flags and tee signs, spread over a whole golf course. Built at runtime as four
# MultiMeshes (flag poles, flags, sign posts, sign boards: four draw calls) plus a Label3D per sign; every item drops
# onto the ground with a ray once its cell has loaded (WorldStreamer.cell_loaded, group "world_streamer"), the same
# way the disc golf baskets do. Visual only: no collision, no gameplay (the course is not playable, D-079).
# Data (written by the landmark builder, saved in the landmark scene, landmark-local metres):
#   flags  PackedVector2Array (x, z)      signs  Array of [x, z, yaw_deg, text]
# Depends on: WorldStreamer (group "world_streamer") for cell_loaded.
extends Node3D

@export var flags := PackedVector2Array()
@export var signs: Array = []

var _mm: Dictionary = {}       # part -> MultiMesh
var _todo: Array[Vector3i] = []  # (kind 0 = flag / 1 = sign, index, unused)
var _labels: Array[Label3D] = []


func _ready() -> void:
	_mm.pole = _multimesh(_cylinder(0.025, 2.4), Color(0.92, 0.92, 0.9), flags.size())
	_mm.flag = _multimesh(_box(Vector3(0.55, 0.38, 0.02)), Color(0.8, 0.08, 0.06), flags.size())
	_mm.post = _multimesh(_box(Vector3(0.08, 1.0, 0.08)), Color(0.35, 0.25, 0.15), signs.size())
	_mm.board = _multimesh(_box(Vector3(0.9, 0.55, 0.06)), Color(0.1, 0.25, 0.14), signs.size())
	for i in flags.size():
		_todo.append(Vector3i(0, i, 0))
	for i in signs.size():
		_todo.append(Vector3i(1, i, 0))
		var l := Label3D.new()
		l.text = str(signs[i][3])
		l.font_size = 28
		l.pixel_size = 0.01
		l.modulate = Color(0.95, 0.95, 0.9)
		l.visibility_range_end = 30.0
		l.visible = false
		add_child(l)
		_labels.append(l)
	var streamer := get_tree().get_first_node_in_group("world_streamer")
	if streamer and streamer.has_signal("cell_loaded"):
		streamer.cell_loaded.connect(func(_c: Vector2i) -> void: _snap.call_deferred())
	_snap.call_deferred()


func _snap() -> void:
	if not is_inside_tree() or _todo.is_empty():
		return
	var space := get_world_3d().direct_space_state
	for i in range(_todo.size() - 1, -1, -1):
		var t := _todo[i]
		var xz: Vector2 = flags[t.y] if t.x == 0 else Vector2(signs[t.y][0], signs[t.y][1])
		var top := global_transform * Vector3(xz.x, 60.0, xz.y)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 260.0))
		if hit.is_empty():
			continue
		var ground: Vector3 = hit.position
		var local := to_local(ground)
		if t.x == 0:
			_put(_mm.pole, t.y, Transform3D(Basis(), local + Vector3(0, 1.2, 0)))
			_put(_mm.flag, t.y, Transform3D(Basis(), local + Vector3(0.29, 2.18, 0)))
		else:
			var b := Basis(Vector3.UP, deg_to_rad(float(signs[t.y][2])))
			_put(_mm.post, t.y, Transform3D(b, local + Vector3(0, 0.5, 0)))
			_put(_mm.board, t.y, Transform3D(b, local + Vector3(0, 1.1, 0)))
			var l := _labels[t.y]
			l.transform = Transform3D(b, local + b * Vector3(0, 1.1, 0.04))
			l.visible = true
		_todo.remove_at(i)


func _put(mm: MultiMesh, i: int, xf: Transform3D) -> void:
	mm.set_instance_transform(i, xf)


func _multimesh(mesh: Mesh, color: Color, count: int) -> MultiMesh:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	mesh.surface_set_material(0, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:  # hidden (zero scale) until snapped
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 220.0
	add_child(mi)
	return mm


func _box(size: Vector3) -> ArrayMesh:
	var b := BoxMesh.new()
	b.size = size
	return _to_array(b)


func _cylinder(r: float, h: float) -> ArrayMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 6
	c.rings = 1
	return _to_array(c)


func _to_array(p: PrimitiveMesh) -> ArrayMesh:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, p.get_mesh_arrays())
	return m
