# GroundProps — small landmark props that stand on the real ground rather than at the landmark's flat origin height
# (D-080): the country club's hole flags (with the cup they stand in) and tee signs, spread over a whole golf
# course. Built at runtime as MultiMeshes (flag poles, flags, cups, cup rims, sign posts, sign boards: one draw call
# each) plus a Label3D per sign; every item drops onto the terrain with a ray once its cell has loaded
# (WorldStreamer.cell_loaded, group "world_streamer"), the same way the disc golf baskets do. The ray only sees the
# ground (world + water bed layers) and passes through tree collider bodies and the golf tee E spots, so nothing
# ends up on a tree top or in the air. Visual only: no collision (play is CourseGolf, D-086).
# Data (written by the landmark builder, saved in the landmark scene, landmark-local metres):
#   flags  PackedVector2Array (x, z)      signs  Array of [x, z, yaw_deg, text]
#   bits   Array of [kind, x, z, yaw_rad] - course furniture (D-098): tee_marker, bench, washer (ball washer),
#          yard_post (150 yd), ob_stake; each kind is a few simple parts (BIT_PARTS), one MultiMesh per part
# Depends on: WorldStreamer (group "world_streamer") for cell_loaded.
extends Node3D

const GROUND_MASK := 17  # world + water bed

# kind -> parts [shape "box" size | "cyl" [r, h], colour, offset from the ground point (turned with the yaw)]
const BIT_PARTS := {
	"tee_marker": [["box", Vector3(0.16, 0.16, 0.16), Color(0.15, 0.3, 0.75), Vector3(0, 0.08, 0)]],
	"bench": [["box", Vector3(1.4, 0.06, 0.4), Color(0.45, 0.3, 0.18), Vector3(0, 0.45, 0)],
		["box", Vector3(1.4, 0.35, 0.05), Color(0.45, 0.3, 0.18), Vector3(0, 0.68, -0.2)],
		["box", Vector3(1.2, 0.42, 0.3), Color(0.12, 0.12, 0.12), Vector3(0, 0.21, 0)]],
	"washer": [["cyl", Vector3(0.04, 1.0, 0), Color(0.15, 0.15, 0.15), Vector3(0, 0.5, 0)],
		["box", Vector3(0.18, 0.25, 0.12), Color(0.1, 0.35, 0.18), Vector3(0, 1.05, 0)]],
	"yard_post": [["cyl", Vector3(0.07, 0.5, 0), Color(0.95, 0.95, 0.92), Vector3(0, 0.25, 0)],
		["cyl", Vector3(0.075, 0.08, 0), Color(0.8, 0.12, 0.1), Vector3(0, 0.52, 0)]],
	"ob_stake": [["cyl", Vector3(0.03, 0.9, 0), Color(0.95, 0.95, 0.95), Vector3(0, 0.45, 0)]],
}

@export var flags := PackedVector2Array()
@export var signs: Array = []
@export var bits: Array = []

var _mm: Dictionary = {}       # part -> MultiMesh
var _todo: Array[Vector3i] = []  # (kind 0 = flag / 1 = sign / 2 = bit, index, slot within the bit's kind)
var _labels: Array[Label3D] = []


func _ready() -> void:
	_mm.pole = _multimesh(_cylinder(0.025, 2.4), Color(0.92, 0.92, 0.9), flags.size())
	_mm.flag = _multimesh(_box(Vector3(0.55, 0.38, 0.02)), Color(0.8, 0.08, 0.06), flags.size())
	_mm.cup = _multimesh(_cylinder(0.07, 0.012), Color(0.03, 0.03, 0.03), flags.size())  # the hole, a touch oversize to read
	_mm.rim = _multimesh(_cylinder(0.085, 0.006), Color(0.95, 0.95, 0.95), flags.size())
	_mm.post = _multimesh(_box(Vector3(0.08, 1.0, 0.08)), Color(0.35, 0.25, 0.15), signs.size())
	_mm.board = _multimesh(_box(Vector3(0.9, 0.55, 0.06)), Color(0.1, 0.25, 0.14), signs.size())
	var counts := {}
	for b: Array in bits:
		counts[str(b[0])] = int(counts.get(str(b[0]), 0)) + 1
	for kind: String in counts:
		var parts: Array = BIT_PARTS.get(kind, [])
		for j in parts.size():
			var part: Array = parts[j]
			var size: Vector3 = part[1]
			var mesh := _box(size) if part[0] == "box" else _cylinder(size.x, size.y)
			_mm["%s:%d" % [kind, j]] = _multimesh(mesh, part[2], int(counts[kind]))
	var seen := {}
	for i in bits.size():
		var kind := str(bits[i][0])
		_todo.append(Vector3i(2, i, int(seen.get(kind, 0))))  # z = this bit's slot among its kind
		seen[kind] = int(seen.get(kind, 0)) + 1
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
	var skip: Array[RID] = []
	for i in range(_todo.size() - 1, -1, -1):
		var t := _todo[i]
		var xz: Vector2 = flags[t.y] if t.x == 0 else (Vector2(signs[t.y][0], signs[t.y][1]) if t.x == 1 else Vector2(bits[t.y][1], bits[t.y][2]))
		var top := global_transform * Vector3(xz.x, 60.0, xz.y)
		var hit := _ground(space, top, skip)
		if hit.is_empty():
			continue
		var ground: Vector3 = hit.position
		var local := to_local(ground)
		if t.x == 2:
			var kind := str(bits[t.y][0])
			var b := Basis(Vector3.UP, float(bits[t.y][3]))
			var parts: Array = BIT_PARTS.get(kind, [])
			for j in parts.size():
				_put(_mm["%s:%d" % [kind, j]], t.z, Transform3D(b, local + b * (parts[j][3] as Vector3)))
		elif t.x == 0:
			_put(_mm.cup, t.y, Transform3D(Basis(), local + Vector3(0, 0.004, 0)))
			_put(_mm.rim, t.y, Transform3D(Basis(), local + Vector3(0, 0.001, 0)))
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


# The terrain under `top` (layers world + water bed), passing through the vegetation's collider bodies.
func _ground(space: PhysicsDirectSpaceState3D, top: Vector3, skip: Array[RID]) -> Dictionary:
	for k in 6:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 260.0, GROUND_MASK, skip))
		if hit.is_empty() or not (hit.collider is CollisionObject3D and (hit.collider as Node).name == "Colliders"):
			return hit
		skip.append((hit.collider as CollisionObject3D).get_rid())
	return {}


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
	mi.visibility_range_end = 450.0  # pins show from the tee
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
