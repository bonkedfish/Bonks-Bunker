# MeepoDock — a Meepo charging dock you can put your board in (D-082). It is an E use spot (group "sport_spots":
# metas target / index / display_name, the same as the Drop Zone bays): E docks the local player's board — it stands
# in one of the dock's SLOTS, charged straight away (D-065: instant) — and E again takes it back. While a player's
# board is docked they can't ride. One slot per player. Still in group "meepo_chargers", so standing near it with a
# board also charges it as before. Host decides (request_use); `slots` (peer per slot, 0 = free) goes to every peer
# on change and to players who join. A slot frees itself when its player leaves the game or no longer has a board.
# Front is local -Z. Mesh built in code, shared by every dock. Depends on: MeepoRider (each player's "meepo":
# host_dock / host_undock / docked_at / has_board / net_riding / net_battery), Player (group "players"), HUD (group
# "hud": toasts).
class_name MeepoDock
extends StaticBody3D

const SLOTS := 4
const LAYER := 9          # world + interactables
const WIDTH := 1.6
const SLOT_GAP := 0.36
const CHECK_SECONDS := 0.5

var slots: Array = [0, 0, 0, 0]

var _boards: Array[MeshInstance3D] = []
var _check := 0.0
var _prompt := ""

static var _stand_mesh: ArrayMesh
static var _board_mesh: ArrayMesh


func _ready() -> void:
	add_to_group("meepo_docks")
	add_to_group("no_merge")  # a hand-built landmark's StaticMeshMerger must leave its boards alone
	add_to_group("meepo_chargers")
	add_to_group("sport_spots")
	collision_layer = LAYER
	collision_mask = 0
	set_meta("target", self)
	set_meta("index", 0)
	set_meta("display_name", "Meepo Charging Dock")
	_make_meshes()
	var stand := MeshInstance3D.new()
	stand.mesh = _stand_mesh
	stand.visibility_range_end = 90.0
	add_child(stand)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH, 1.15, 0.5)
	shape.shape = box
	shape.position = Vector3(0, 0.575, 0)
	add_child(shape)
	for i in SLOTS:
		var b := MeshInstance3D.new()
		b.mesh = _board_mesh
		b.position = Vector3(_slot_x(i), 0.12, -0.12)
		b.visible = false
		b.visibility_range_end = 60.0
		add_child(b)
		_boards.append(b)
	var label := Label3D.new()
	label.text = "MEEPO CHARGING DOCK"
	label.font_size = 40
	label.pixel_size = 0.004
	label.outline_size = 8
	label.modulate = Color(0.55, 0.95, 1.0)
	label.position = Vector3(0, 1.32, -0.05)
	label.visibility_range_end = 25.0
	label.rotation.y = PI  # read from the front (-Z)
	add_child(label)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


static func _slot_x(i: int) -> float:
	return (i - (SLOTS - 1) * 0.5) * SLOT_GAP


func slot_of(peer: int) -> int:
	return slots.find(peer)


# --- host ------------------------------------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func request_use(_index: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
	var p := _player(peer)
	if p == null or not "meepo" in p or p.global_position.distance_to(global_position) > 4.0:
		return
	var m: Node = p.meepo
	var mine := slot_of(peer)
	if mine >= 0:
		slots[mine] = 0
		m.host_undock()
		_sync.rpc(slots)
		_say.rpc_id(peer, "Took your Meepo back (%d%%)" % roundi(float(m.net_battery)))
		return
	if not m.has_board():
		_say.rpc_id(peer, "You don't have a Meepo to dock")
		return
	if m.net_riding:
		_say.rpc_id(peer, "Hop off first (B), then dock it")
		return
	if m.docked_at() != null:
		_say.rpc_id(peer, "Your Meepo is already in another dock")
		return
	var free := slot_of(0)
	if free < 0:
		_say.rpc_id(peer, "The dock is full")
		return
	slots[free] = peer
	m.host_dock(self)
	_sync.rpc(slots)
	_say.rpc_id(peer, "Meepo docked - fully charged. E to take it back.")


# Host: frees the slot of a player who no longer has a board (dropped or traded it).
func host_release(peer: int) -> void:
	var i := slot_of(peer)
	if i >= 0:
		slots[i] = 0
		_sync.rpc(slots)


func _on_peer_connected(peer: int) -> void:
	if multiplayer.is_server():
		_sync.rpc_id(peer, slots)


func _on_peer_disconnected(peer: int) -> void:
	if multiplayer.is_server():
		host_release(peer)


# --- every peer ---------------------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _sync(new_slots: Array) -> void:
	slots = new_slots.duplicate()
	for i in SLOTS:
		_boards[i].visible = int(slots[i]) != 0


@rpc("authority", "call_local", "reliable")
func _say(text: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_toast(text, 2.5)


# The E prompt for the local player (HUD shows "E <display_name>").
func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = CHECK_SECONDS
	var me := get_tree().get_first_node_in_group("local_player")
	var text := "Meepo Charging Dock"
	if me and "meepo" in me:
		var m: Node = me.meepo
		if slot_of(multiplayer.get_unique_id()) >= 0:
			text = "Take your Meepo (charged)"
		elif m.net_riding:
			text = "Meepo Charging Dock - hop off (B) to dock"
		elif m.has_board():
			text = "Dock your Meepo (%d%%)" % roundi(float(m.net_battery))
	if text != _prompt:
		_prompt = text
		set_meta("display_name", text)


func _player(peer: int) -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if "peer_id" in p and p.peer_id == peer:
			return p
	return null


# --- meshes (built once) -------------------------------------------------------------------------------

static func _make_meshes() -> void:
	if _stand_mesh != null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := Color(0.16, 0.18, 0.2)
	var trim := Color(0.1, 0.45, 0.55)
	_cuboid(st, Vector3(0, 0.05, 0), Vector3(WIDTH, 0.1, 0.5), body)              # base
	_cuboid(st, Vector3(0, 0.6, 0.18), Vector3(WIDTH, 1.1, 0.12), body)            # back panel
	_cuboid(st, Vector3(0, 1.17, 0.12), Vector3(WIDTH + 0.06, 0.06, 0.26), trim)   # top cap
	for i in SLOTS + 1:  # dividers between the slots
		var x := (i - SLOTS * 0.5) * SLOT_GAP
		_cuboid(st, Vector3(x, 0.35, -0.05), Vector3(0.04, 0.5, 0.34), trim)
	for i in SLOTS:  # charge lights over each slot
		_cuboid(st, Vector3(_slot_x(i), 1.0, 0.115), Vector3(0.1, 0.05, 0.02), Color(0.2, 0.95, 0.4))
	st.generate_normals()
	_stand_mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.6
	m.metallic = 0.3
	_stand_mesh.surface_set_material(0, m)
	st = SurfaceTool.new()  # a board standing on its tail in the slot
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cuboid(st, Vector3(0, 0.475, 0), Vector3(0.26, 0.95, 0.03), Color(0.12, 0.12, 0.13))
	_cuboid(st, Vector3(0, 0.5, -0.02), Vector3(0.12, 0.3, 0.012), Color(0.2, 0.9, 1.0))
	for zy: float in [0.15, 0.8]:
		_cuboid(st, Vector3(0, zy, 0.05), Vector3(0.3, 0.09, 0.09), Color(0.85, 0.35, 0.1))
	st.generate_normals()
	_board_mesh = st.commit()
	var bm := StandardMaterial3D.new()
	bm.vertex_color_use_as_albedo = true
	bm.roughness = 0.7
	bm.emission_enabled = true
	bm.emission = Color(0.05, 0.25, 0.3)
	_board_mesh.surface_set_material(0, bm)


static func _cuboid(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
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
