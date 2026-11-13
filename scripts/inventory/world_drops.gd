# WorldDrops — "Drops" node in main.tscn (group "world_drops") (D-046): items players drop land in the world as
# pickups anyone can take, and are saved with the world.
#   Host:    owns the list (id -> item, count, position), validates drop/pickup requests (alive, owns the items,
#            in reach), moves items between inventories and the world, enforces the per-cell loose-loot cap
#            (oldest removed), sends spawns/despawns to every peer and the full list to peers that join.
#   All:     show each drop as a small coloured box (pooled bodies on the interactables layer, so the player's
#            look ray finds them; they don't block movement).
# Depends on: DropRules, ItemDB, CarryRules (interact range), InventoryHolder, WorldStreamer (group
# "world_streamer", for cells).
class_name WorldDrops
extends Node3D

const LAYER := 8  # layer 4 = interactables (bit value 8)
const GROUND_MASK := 17  # world + water bed

var drops: Dictionary = {}  # id -> [item_id, count, Vector3]  (all peers)

var _next_id := 1
var _pool: Array[StaticBody3D] = []
var _bodies: Dictionary = {}  # id -> StaticBody3D
var _meshes: Dictionary = {}  # category -> BoxMesh with its material
var _shape: BoxShape3D
var _range := 2.5


func _ready() -> void:
	add_to_group("world_drops")
	_range = float(CarryRules.load_tuning().get("interact_range", 2.5))
	var t := DropRules.tuning()
	var s := float(t.pickup_size_m)
	_shape = BoxShape3D.new()
	_shape.size = Vector3(s, s, s)
	for cat: String in t.colors:
		var c: Array = t.colors[cat]
		var mesh := BoxMesh.new()
		mesh.size = Vector3(s * 0.8, s * 0.55, s * 0.6)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(c[0], c[1], c[2])
		mat.roughness = 0.8
		mesh.material = mat
		_meshes[cat] = mesh
	multiplayer.peer_connected.connect(_on_peer_connected)


func display_name(id: int) -> String:
	if not drops.has(id):
		return ""
	var d: Array = drops[id]
	var item_name := str(ItemDB.get_item(d[0]).get("name", d[0]))
	return item_name if int(d[1]) == 1 else "%s x%d" % [item_name, int(d[1])]


# --- requests (any peer -> host) -------------------------------------------------------

# n <= 0 drops the whole stack.
@rpc("any_peer", "call_local", "reliable")
func request_drop(item_id: String, n: int) -> void:
	var player := _sender_player()
	if player == null or not ItemDB.has_item(item_id):
		return
	var count := DropRules.drop_count(player.inventory.count(item_id), n)
	if count <= 0:
		return
	count = player.inventory.host_remove(item_id, count)
	var fwd: Vector3 = -player.global_basis.z
	fwd.y = 0.0
	var spread := float(DropRules.tuning().drop_spread_m)
	var jitter := Vector3(randf_range(-spread, spread), 0.0, randf_range(-spread, spread))  # piles spread out
	host_add(item_id, count, _ground(player.global_position + fwd.normalized() * float(DropRules.tuning().drop_distance_m) + jitter))


@rpc("any_peer", "call_local", "reliable")
func request_pickup(id: int) -> void:
	var player := _sender_player()
	if player == null or not drops.has(id):
		return
	var d: Array = drops[id]
	if player.global_position.distance_to(d[2]) > _range + 1.0:
		return
	player.inventory.host_add(str(d[0]), int(d[1]))
	_remove.rpc(id)


# --- host --------------------------------------------------------------------------------

func host_add(item_id: String, count: int, pos: Vector3) -> void:
	if count <= 0:
		return
	var id := _next_id
	_next_id += 1
	_spawn.rpc(id, item_id, count, pos)
	_enforce_cap(pos)


# Oldest first: [[item_id, count, x, y, z], ...]
func host_save_state() -> Array:
	var ids: Array = drops.keys()
	ids.sort()
	var out: Array = []
	for id: int in ids:
		var d: Array = drops[id]
		out.append([d[0], d[1], snappedf(d[2].x, 0.01), snappedf(d[2].y, 0.01), snappedf(d[2].z, 0.01)])
	return out


func host_load_state(entries: Array) -> void:
	for e: Array in entries:
		host_add(str(e[0]), int(e[1]), Vector3(e[2], e[3], e[4]))


func _enforce_cap(pos: Vector3) -> void:
	var streamer := get_tree().get_first_node_in_group("world_streamer")
	if streamer == null or streamer.grid == null:
		return
	var cell: Vector2i = streamer.grid.cell_of(pos)
	var ids: Array = []
	for id: int in drops:
		if streamer.grid.cell_of(drops[id][2]) == cell:
			ids.append(id)
	for id: int in DropRules.over_cap(ids, int(DropRules.tuning().per_cell_cap)):
		_remove.rpc(id)


func _ground(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.5, p + Vector3.DOWN * 4.0, GROUND_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else p


func _sender_player() -> Node:
	if not multiplayer.is_server():
		return null
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == peer:
			return null if p.health.is_dead() else p
	return null


func _on_peer_connected(peer: int) -> void:
	if not multiplayer.is_server():
		return
	for id: int in drops:
		var d: Array = drops[id]
		_spawn.rpc_id(peer, id, d[0], d[1], d[2])


# --- host -> peers -------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _spawn(id: int, item_id: String, count: int, pos: Vector3) -> void:
	drops[id] = [item_id, count, pos]
	var body: StaticBody3D = _pool.pop_back() if not _pool.is_empty() else _new_body()
	var mesh: BoxMesh = _meshes.get(str(ItemDB.get_item(item_id).get("category", "junk")), _meshes.junk)
	(body.get_child(0) as MeshInstance3D).mesh = mesh
	body.set_meta("drop_id", id)
	body.position = pos + Vector3.UP * mesh.size.y * 0.5
	body.rotation.y = float(id) * 2.39996  # golden-angle spin so piles don't line up
	body.visible = true
	(body.get_child(1) as CollisionShape3D).disabled = false
	_bodies[id] = body


@rpc("authority", "call_local", "reliable")
func _remove(id: int) -> void:
	drops.erase(id)
	var body: StaticBody3D = _bodies.get(id)
	if body == null:
		return
	_bodies.erase(id)
	body.visible = false
	(body.get_child(1) as CollisionShape3D).set_deferred("disabled", true)
	_pool.append(body)


func _new_body() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER
	body.collision_mask = 0
	body.add_to_group("pickups")
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	var shape := CollisionShape3D.new()
	shape.shape = _shape
	body.add_child(shape)
	add_child(body)
	return body
