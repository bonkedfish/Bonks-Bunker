# DiscCourse — one disc golf course in the world (D-069), the landmark scene scenes/disc_course.tscn placed by
# LandmarkLoader (data/map/landmarks.json "centennial_dgc"). Builds from data/discgolf/courses.json at load:
# a realistic basket per hole (D-117, BasketMesh: link-by-link chains up close, glowing band (D-076), hole number,
# a mulch ring where the course has one), the tee pad and hole sign (TeeBox: hole map, par, length) in the course's
# "look" from data/discgolf/course_looks.json, and the course box at hole 1 (E: start / join a round), and
# John Pork's VendorCamp (tent, vendor, records board, Meepo dock) where the course has a "camp" (D-082).
# Course data is in map coordinates; each piece drops onto the ground with a ray when its cell has loaded.
# Group "disc_courses". Course box body: group "course_boxes" (display_name, course_id) on the interactable layer.
# Every node it makes gets a fixed name (Anchor<n>, Camp) so paths match on every peer: the vendor and the dock
# are used over the network (D-091; before, a client's E on John Pork reached nobody on the host).
# Visual + colliders only; rounds live in DiscGolfDirector. Depends on: DiscGolfRules, VendorCamp, WorldStreamer
# (group "world_streamer": cell_loaded), BasketMesh, TeeBox, data/discgolf/course_looks.json.
class_name DiscCourse
extends Node3D

const GROUND_MASK := 1
const BOX_LAYER := 9  # world + interactables
const LOOKS_PATH := "res://data/discgolf/course_looks.json"
const BasketMesh := preload("res://scripts/discgolf/basket_mesh.gd")
const TeeBox := preload("res://scripts/discgolf/tee_box.gd")

@export var course_id := "centennial"  # replaced by the course whose "landmark" is this node's name

var course: Dictionary = {}

var _baskets: Array[Node3D] = []
var _tees: Array[Node3D] = []
var _box: Node3D
var camp: VendorCamp
var _anchor_count := 0
var _unsnapped: Array[Node3D] = []
var _rids: Array[RID] = []

static var _box_mesh: ArrayMesh
static var _looks: Dictionary = {}

var _look: Dictionary = {}  # this course's pieces (D-117)
var _wear := 0.5


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
	if _looks.is_empty():
		_looks = DataLoader.load_json(LOOKS_PATH)
	_look = course.get("look", {})
	_wear = float(_look.get("wear", 0.5))
	var holes: Array = course.holes
	for i in holes.size():
		var h: Dictionary = holes[i]
		var tee := _map(h.tee)
		var basket := _map(h.basket)
		var dir := (basket - tee).normalized()
		_baskets.append(_add_basket(basket, DiscGolfRules.hole_label(course, i)))
		_tees.append(_add_tee(tee, dir, DiscGolfRules.hole_label(course, i), h))
	_box = _add_box(_map(course.box))
	if course.has("camp"):
		_add_camp(course.camp)
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
	n.name = "Anchor%d" % _anchor_count  # built in the same order on every peer
	_anchor_count += 1
	n.position = local
	add_child(n)
	_unsnapped.append(n)
	return n


func _add_basket(local: Vector3, number: String) -> Node3D:
	var a := _anchor(local)
	var style: Dictionary = _looks.get("baskets", {}).get(str(_look.get("basket", "mach2")), {})
	var metal: Dictionary = _looks.get("metal", {})
	var near := float(style.get("near_m", 28.0))
	var near_mi := MeshInstance3D.new()  # every chain link up close, simple strips from further away (D-117)
	near_mi.mesh = BasketMesh.mesh(style, metal, _looks.get("link", {}), _wear, true)
	near_mi.visibility_range_end = near
	a.add_child(near_mi)
	var far_mi := MeshInstance3D.new()
	far_mi.mesh = BasketMesh.mesh(style, metal, _looks.get("link", {}), _wear, false)
	far_mi.visibility_range_begin = near
	far_mi.visibility_range_end = float(style.get("far_m", 220.0))
	far_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	a.add_child(far_mi)
	var ring: Dictionary = _looks.get("rings", {}).get(str(_look.get("ring", "")), {})
	if not ring.is_empty():  # the landscaped circle round the pole (Centennial)
		var meshes := TeeBox.ring_meshes(ring)
		for m: Mesh in meshes:
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.position.y = -0.04 if m is CylinderMesh else 0.0
			mi.visibility_range_end = 90.0
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	label.position = Vector3(0, float(style.get("band_bottom", 1.32)) + 0.06, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visibility_range_end = 60.0
	a.add_child(label)
	return a


# Tee pad down the fairway from the tee spot, and the hole sign behind it beside the pad, its face toward players
# coming up to the tee (D-117).
func _add_tee(local: Vector3, dir: Vector3, number: String, h: Dictionary) -> Node3D:
	var a := _anchor(local)
	var yaw := atan2(-dir.x, -dir.z)  # pad's -Z down the fairway
	var tee_style: Dictionary = _looks.get("tees", {}).get(str(_look.get("tee", "asphalt")), {})
	var size: Array = tee_style.get("size", [1.5, 3.6])
	var length := float(size[1])
	var pad := MeshInstance3D.new()
	pad.mesh = TeeBox.pad_mesh(tee_style)
	pad.rotation.y = yaw
	pad.position = Vector3(0, float(tee_style.get("top_m", 0.05)) - 0.15, 0) - dir * (length * 0.5 - 1.2)
	pad.visibility_range_end = 220.0
	a.add_child(pad)
	var sign_style: Dictionary = _looks.get("signs", {}).get(str(_look.get("sign", "post")), {})
	var pts := PackedVector2Array([Vector2(float(h.tee[0]), float(h.tee[1]))])
	for v: Variant in h.get("via", []):
		pts.append(Vector2(float(v[0]), float(v[1])))
	pts.append(Vector2(float(h.basket[0]), float(h.basket[1])))
	var built: Array = TeeBox.sign_mesh(sign_style, pts, _wear, hash(str(course_id) + number))
	var board := MeshInstance3D.new()
	board.mesh = built[0]
	var right := dir.cross(Vector3.UP).normalized()
	board.position = -dir * (length - 1.2 + 0.7) + right * (float(size[0]) * 0.5 + 0.7)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(course_id) + number)
	board.rotation = Vector3(deg_to_rad(rng.randf_range(-3.0, 1.0) * _wear), yaw, deg_to_rad(rng.randf_range(-5.0, 5.0) * _wear))
	board.visibility_range_end = 120.0
	a.add_child(board)
	var tc: Array = sign_style.get("text_color", [0.95, 0.92, 0.8])
	var label := _label("HOLE %s\nPAR %d\n%d FT" % [number, int(h.par), int(h.length_ft)], 34,
		Color(tc[0], tc[1], tc[2]).lerp(Color(0.7, 0.7, 0.68), _wear * 0.3))
	label.pixel_size = 0.0022
	label.outline_size = 4
	label.width = float(built[2]) / label.pixel_size
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.position = built[1] + Vector3(0, 0, 0.003)
	label.visibility_range_end = 30.0
	board.add_child(label)
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


# John Pork's tent, its front turned to the camp's "face" point (D-082).
func _add_camp(def: Dictionary) -> void:
	var at := _map(def.at)
	var face := _map(def.get("face", course.box))
	var a := _anchor(at)
	camp = VendorCamp.new()
	camp.name = "Camp"
	camp.rotation.y = atan2(-(face.x - at.x), -(face.z - at.z))  # its -Z toward `face`
	a.add_child(camp)
	_rids.append_array(camp.build(course_id, course))


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
	if _box_mesh != null:
		return
	var st := SurfaceTool.new()
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
