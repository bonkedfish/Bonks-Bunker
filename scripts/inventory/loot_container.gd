# LootContainer — a searchable, shared container (D-023, D-026).
# The host rolls its loot table the first time anyone opens it and keeps the remaining `contents`
# (keyed by `container_id`, which is what saves will store). Players open it (E while looking at it),
# take one stack or everything; the host validates range/alive/availability and pushes the updated
# contents to everyone who has it open. `net_remaining` replicates so prompts can show "(empty)".
# `streamed` (D-056): a loot spot inside a generated map cell — no Sync child, no mesh, comes and goes with the cell;
# on the host it reads its saved contents from SaveDirector.world when it loads and writes them back when it unloads.
# Group "loot_containers". Depends on: LootDB, LootRules, CarryRules (interact range), LootUI (group "loot_ui"),
# SaveFormat + SaveDirector (group "save_director", streamed spots only).
extends StaticBody3D

@export var container_id := ""
@export var display_name := "Cabinet"
@export var loot_table := "house_cabinet"
@export var size := Vector3(0.9, 1.0, 0.5)
@export var color := Color(0.45, 0.4, 0.35)
@export var streamed := false

var net_remaining := -1  # -1 = never opened; replicated
var contents: Dictionary = {}  # host: item_id -> count still inside

var _rolled := false
var _viewers: Dictionary = {}  # host: peer_id -> true
var _range := 2.5


func _ready() -> void:
	add_to_group("loot_containers")
	_range = CarryRules.load_tuning().get("interact_range", 2.5)
	var mesh := get_node_or_null("Mesh") as MeshInstance3D
	if mesh:
		var box := BoxMesh.new()
		box.size = size
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.85
		box.material = mat
		mesh.mesh = box
		mesh.position.y = size.y * 0.5
	var shape := BoxShape3D.new()
	shape.size = size
	$Collider.shape = shape
	$Collider.position.y = size.y * 0.5
	if streamed and _is_host():
		var saves := get_tree().get_first_node_in_group("save_director")
		if saves and saves.world.get("containers", {}).has(container_id):
			host_load_state(SaveFormat.clean_items(saves.world.containers[container_id]))


func _exit_tree() -> void:
	if not streamed or not _is_host() or not _rolled:
		return
	var saves := get_tree().get_first_node_in_group("save_director")
	if saves and saves.world.has("containers"):
		saves.world.containers[container_id] = contents.duplicate()


func _is_host() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


# --- requests (any peer -> host) -------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func request_open() -> void:
	var player := _validated_player()
	if player == null:
		return
	if not _rolled:
		_rolled = true
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		contents = LootRules.roll(LootDB.get_table(loot_table), rng)
		_update_remaining()
	_viewers[player.peer_id] = true
	_show_contents.rpc_id(player.peer_id, contents)


# n <= 0 takes the whole stack.
@rpc("any_peer", "call_local", "reliable")
func request_take(item_id: String, n: int) -> void:
	var player := _validated_player()
	if player == null or not _viewers.has(player.peer_id):
		return
	_move_to(player, item_id, n)
	_broadcast()


@rpc("any_peer", "call_local", "reliable")
func request_take_all() -> void:
	var player := _validated_player()
	if player == null or not _viewers.has(player.peer_id):
		return
	for id: String in contents.keys():
		_move_to(player, id, 0)
	_broadcast()


@rpc("any_peer", "call_local", "reliable")
func request_close() -> void:
	if multiplayer.is_server():
		_viewers.erase(_sender())


# --- host: saves (D-037) ---------------------------------------------------------------

# null = never opened (it rolls fresh the first time someone opens it), else what's still inside.
func host_save_state() -> Variant:
	if not _rolled:
		return null
	return contents.duplicate()


func host_load_state(items: Dictionary) -> void:
	_rolled = true
	contents = items
	_update_remaining()


# --- host ----------------------------------------------------------------------

func _move_to(player: Node, item_id: String, n: int) -> void:
	var available := int(contents.get(item_id, 0))
	var take := available if n <= 0 else mini(n, available)
	if take <= 0:
		return
	if available - take <= 0:
		contents.erase(item_id)
	else:
		contents[item_id] = available - take
	player.inventory.host_add(item_id, take)
	_update_remaining()


func _broadcast() -> void:
	var peers := multiplayer.get_peers()
	for peer: int in _viewers.keys():
		if peer == 1 or peer in peers:
			_show_contents.rpc_id(peer, contents)
		else:
			_viewers.erase(peer)


func _update_remaining() -> void:
	var total := 0
	for id: String in contents:
		total += int(contents[id])
	net_remaining = total


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()


# The requesting player's body, only if they're alive and within reach of this container.
func _validated_player() -> Node:
	if not multiplayer.is_server():
		return null
	var peer := _sender()
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == peer:
			if p.health.is_dead() or p.global_position.distance_to(global_position) > _range + 1.0:
				return null
			return p
	return null


# --- host -> one peer ----------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _show_contents(items: Dictionary) -> void:
	var ui := get_tree().get_first_node_in_group("loot_ui")
	if ui:
		ui.show_container(self, items)
