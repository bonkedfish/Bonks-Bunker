# VendorCamp — John Pork's concession tent at the start of a disc golf course (D-082), built by DiscCourse from the
# course's "camp" {at, face} in data/discgolf/courses.json. Front is local -Z (turned to look at `face`): a red and
# white pop-up canopy with a "JOHN PORK'S" banner, a draped table with a hot dog roller and drinks, two coolers, a
# chalkboard menu, a trash can; John Pork (ResidentNpc "john_pork") behind the table; the course records board on the
# right (a Label3D in group "record_boards", meta course_id, text from DiscGolfDirector.records via
# DiscRecordsRules); a MeepoDock on the left. The tent mesh is built once and shared (vertex colours, one draw call);
# one StaticBody holds the posts, table, coolers, signs. Depends on: DiscRecordsRules, DiscGolfDirector (group
# "disc_golf": records), MeepoDock, scenes/resident_npc.tscn.
class_name VendorCamp
extends Node3D

const NPC_SCENE := preload("res://scenes/resident_npc.tscn")
const HALF := 1.6        # canopy half-width
const EAVE := 2.15       # canopy edge height
const PEAK := 2.75
const BOARD_SIZE := Vector2(2.3, 1.7)

static var _mesh: ArrayMesh

var course_id := ""
var board: Label3D


# Builds everything for `course` (id `id`). Returns the collision RIDs (course rays skip them).
func build(id: String, course: Dictionary) -> Array[RID]:
	course_id = id
	_make_mesh()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.visibility_range_end = 160.0
	add_child(mi)
	var body := StaticBody3D.new()
	add_child(body)
	for p: Vector2 in [Vector2(-HALF, -HALF), Vector2(HALF, -HALF), Vector2(-HALF, HALF), Vector2(HALF, HALF)]:
		_shape(body, Vector3(p.x, EAVE * 0.5, p.y), Vector3(0.08, EAVE, 0.08))
	_shape(body, Vector3(0, 0.38, -1.0), Vector3(2.6, 0.76, 0.7))      # table
	_shape(body, Vector3(-1.05, 0.25, 0.55), Vector3(0.75, 0.5, 0.48))  # coolers
	_shape(body, Vector3(1.05, 0.25, 0.55), Vector3(0.75, 0.5, 0.48))
	_shape(body, Vector3(-2.0, 0.55, -2.1), Vector3(0.75, 1.1, 0.5))   # menu sign
	_shape(body, Vector3(2.75, 1.1, -0.7), Vector3(BOARD_SIZE.x, 2.2, 0.16))  # records board
	_shape(body, Vector3(2.0, 0.45, -2.2), Vector3(0.5, 0.9, 0.5))     # trash can
	var banner := _label("JOHN PORK'S", 56, Color(1.0, 0.96, 0.9))
	banner.position = Vector3(0, EAVE - 0.11, -HALF - 0.02)
	banner.rotation.y = PI
	banner.visibility_range_end = 70.0
	add_child(banner)
	var under := _label("DISC-SIDE CONCESSIONS", 34, Color(0.55, 0.08, 0.1))
	under.outline_size = 0
	under.position = Vector3(0, 0.45, -1.35)
	under.rotation.y = PI
	under.visibility_range_end = 30.0
	add_child(under)
	var menu := _label("COLD BEER\nSELTZERS - SHOTS\nWATER - HOT DOGS\nPORK RINDS\nPARTY FAVORS\n\nSCRAP ONLY\ncheap!", 30,
		Color(0.95, 0.95, 0.9))
	menu.position = Vector3(-2.0, 0.6, -2.29)
	menu.rotation = Vector3(-0.2, PI, 0)
	menu.visibility_range_end = 20.0
	add_child(menu)
	board = _label("", 30, Color(0.95, 0.93, 0.82))
	board.pixel_size = 0.0021
	# Text hangs down from the panel's top-left corner as seen from the front (turned round, so its +X is camp -X).
	board.position = Vector3(2.75 + BOARD_SIZE.x * 0.5 - 0.1, 0.55 + BOARD_SIZE.y - 0.08, -0.76)
	board.rotation.y = PI
	board.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	board.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	board.visibility_range_end = 25.0
	board.add_to_group("record_boards")
	board.set_meta("course_id", id)
	add_child(board)
	var dg := get_tree().get_first_node_in_group("disc_golf") if is_inside_tree() else null
	board.text = DiscRecordsRules.board_text(dg.records.get(id, {}) if dg else {}, course)
	var npc: Node3D = NPC_SCENE.instantiate()
	npc.set("npc_id", "john_pork")
	npc.position = Vector3(0, 0, -0.1)
	npc.rotation.y = 0.0
	add_child(npc)
	var dock := MeepoDock.new()
	dock.position = Vector3(-2.75, 0, -0.5)
	add_child(dock)
	return [body.get_rid(), dock.get_rid(), (npc as CollisionObject3D).get_rid()]  # the ground snap ray skips them all


func _shape(body: StaticBody3D, centre: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = centre
	body.add_child(cs)


func _label(text: String, font_size: int, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.004
	l.modulate = col
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.9)
	return l


# --- the shared tent mesh --------------------------------------------------------------------------

static func _make_mesh() -> void:
	if _mesh != null:
		return
	var red := Color(0.78, 0.12, 0.12)
	var white := Color(0.93, 0.92, 0.88)
	var pole := Color(0.55, 0.57, 0.6)
	var cloth := Color(0.95, 0.72, 0.76)
	var dark := Color(0.15, 0.15, 0.16)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Vector2 in [Vector2(-HALF, -HALF), Vector2(HALF, -HALF), Vector2(-HALF, HALF), Vector2(HALF, HALF)]:
		_box(st, Vector3(p.x, EAVE * 0.5, p.y), Vector3(0.06, EAVE, 0.06), pole)
	# Roof: four sloped panels, red front / back, white sides.
	var c := [Vector3(-HALF, EAVE, -HALF), Vector3(HALF, EAVE, -HALF), Vector3(HALF, EAVE, HALF), Vector3(-HALF, EAVE, HALF)]
	var top := Vector3(0, PEAK, 0)
	for i in 4:
		_tri(st, c[i], top, c[(i + 1) % 4], red if i % 2 == 0 else white)
	# Valance flaps round the edge.
	for i in 4:
		var a: Vector3 = c[i]
		var b: Vector3 = c[(i + 1) % 4]
		_quad(st, a, b, b - Vector3(0, 0.24, 0), a - Vector3(0, 0.24, 0), red if i % 2 == 0 else white)
	# Table with a long cloth, legs hidden under it.
	_box(st, Vector3(0, 0.75, -1.0), Vector3(2.6, 0.04, 0.72), white)
	_box(st, Vector3(0, 0.37, -1.33), Vector3(2.58, 0.74, 0.02), cloth)
	_box(st, Vector3(-1.29, 0.37, -1.0), Vector3(0.02, 0.74, 0.7), cloth)
	_box(st, Vector3(1.29, 0.37, -1.0), Vector3(0.02, 0.74, 0.7), cloth)
	# On the table: hot dog roller, a row of cans, a cash box.
	_box(st, Vector3(-0.75, 0.84, -1.0), Vector3(0.6, 0.14, 0.4), Color(0.7, 0.7, 0.72))
	for i in 5:
		_box(st, Vector3(-0.98 + i * 0.115, 0.93, -1.0), Vector3(0.06, 0.05, 0.34), Color(0.75, 0.42, 0.25))
	for i in 6:
		var cols := [Color(0.85, 0.75, 0.3), Color(0.2, 0.45, 0.8), Color(0.8, 0.2, 0.3)]
		_box(st, Vector3(0.05 + i * 0.13, 0.83, -1.15), Vector3(0.07, 0.12, 0.07), cols[i % 3])
	_box(st, Vector3(0.95, 0.82, -0.9), Vector3(0.3, 0.1, 0.22), Color(0.25, 0.3, 0.25))
	# Coolers.
	_box(st, Vector3(-1.05, 0.22, 0.55), Vector3(0.72, 0.44, 0.45), Color(0.15, 0.4, 0.75))
	_box(st, Vector3(-1.05, 0.47, 0.55), Vector3(0.74, 0.06, 0.47), white)
	_box(st, Vector3(1.05, 0.22, 0.55), Vector3(0.72, 0.44, 0.45), red)
	_box(st, Vector3(1.05, 0.47, 0.55), Vector3(0.74, 0.06, 0.47), white)
	# Chalkboard A-frame menu, leaning back.
	_box(st, Vector3(-2.0, 0.55, -2.25), Vector3(0.7, 1.05, 0.04), dark)
	_box(st, Vector3(-2.0, 0.55, -1.95), Vector3(0.7, 1.05, 0.04), dark)
	_box(st, Vector3(-2.0, 1.08, -2.1), Vector3(0.74, 0.04, 0.34), Color(0.45, 0.32, 0.2))
	# Records board: two posts and a dark green panel with a wooden frame.
	for x: float in [2.75 - BOARD_SIZE.x * 0.5 + 0.08, 2.75 + BOARD_SIZE.x * 0.5 - 0.08]:
		_box(st, Vector3(x, 1.1, -0.7), Vector3(0.1, 2.2, 0.1), Color(0.4, 0.3, 0.2))
	_box(st, Vector3(2.75, 0.55 + BOARD_SIZE.y * 0.5, -0.72), Vector3(BOARD_SIZE.x, BOARD_SIZE.y, 0.06), Color(0.1, 0.24, 0.15))
	_box(st, Vector3(2.75, 0.55 + BOARD_SIZE.y + 0.05, -0.72), Vector3(BOARD_SIZE.x + 0.1, 0.1, 0.1), Color(0.45, 0.32, 0.2))
	# Trash can.
	_box(st, Vector3(2.0, 0.45, -2.2), Vector3(0.48, 0.9, 0.48), Color(0.25, 0.32, 0.25))
	st.generate_normals()
	_mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.75
	m.cull_mode = BaseMaterial3D.CULL_DISABLED  # canopy and flaps are single faces
	_mesh.surface_set_material(0, m)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	st.set_color(col)
	for v: Vector3 in [a, b, c]:
		st.add_vertex(v)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(st, a, b, c, col)
	_tri(st, a, c, d, col)


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var p := [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1),
		Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]
	var faces := [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]
	for f: Array in faces:
		var q: Array[Vector3] = []
		for k: int in f:
			q.append(c + p[k] * h)
		_quad(st, q[0], q[1], q[2], q[3], col)
