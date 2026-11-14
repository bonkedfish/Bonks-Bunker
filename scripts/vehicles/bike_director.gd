# BikeDirector — "Bikes" node made by Main (group "bike_director") (D-083): the motorcycles parked around the world.
#   Host: when a map cell loads, the cell's own parked bike appears (BikeRules.cell_bike: at most one per cell, the
#         same bikes for the same world, on one of the cell's road markers) unless someone already moved it; bikes
#         players left (records: model, scheme, fuel, position, yaw, tipped) show again when their cell loads.
#         Cells unloading hide their bikes. E on a bike -> host_mount hands it to that player's BikeRider; getting off
#         or crashing -> host_park puts it back as a record. Saves moved bikes + which cell bikes were taken.
#   All:  _show / _hide build and free the ParkedBike nodes ("B_<id>"); players who join get every shown bike.
# Depends on: BikeRules, ParkedBike, BikeRider (Player child "Bike"), WorldStreamer (group "world_streamer": cells,
# road markers), Player (group "players"), HUD (group "hud": toasts).
class_name BikeDirector
extends Node3D

const MOUNT_RANGE := 4.0

var _seed := 0
var _taken: Dictionary = {}   # host: cell bike id -> true (somebody moved it; never respawns there)
var _parked: Dictionary = {}  # host: id -> {model, scheme, fuel, pos [x, y, z], yaw, tipped, moved}
var _shown: Dictionary = {}   # all peers: id -> ParkedBike
var _streamer: Node
var _view_m := 120.0


func _ready() -> void:
	add_to_group("bike_director")
	_view_m = float(BikeRules.tuning().get("parked_view_m", 120.0))
	multiplayer.peer_connected.connect(_on_peer_connected)
	_streamer = get_tree().get_first_node_in_group("world_streamer")
	if _streamer:
		_streamer.cell_loaded.connect(_on_cell_loaded)
		_streamer.cell_unloaded.connect(_on_cell_unloaded)


# --- host: save / load ---------------------------------------------------------------------------

func host_load(saved: Dictionary, world_slug: String) -> void:
	_seed = hash(world_slug)
	_taken.clear()
	for id in saved.get("taken", []):
		_taken[str(id)] = true
	_parked.clear()
	var recs: Dictionary = saved.get("parked", {})
	for id: String in recs:
		var r: Dictionary = recs[id]
		if typeof(r.get("pos")) == TYPE_ARRAY and BikeRules.has_bike(str(r.get("model", ""))):
			_parked[id] = {"model": str(r.model), "scheme": int(r.get("scheme", 0)), "fuel": float(r.get("fuel", 0.0)),
				"pos": r.pos, "yaw": float(r.get("yaw", 0.0)), "tipped": bool(r.get("tipped", false)), "moved": true}
	if _streamer:
		for c: Vector2i in _streamer.near_loaded:
			_on_cell_loaded(c)


func host_save() -> Dictionary:
	var parked := {}
	for id: String in _parked:
		var r: Dictionary = _parked[id]
		if bool(r.moved):
			parked[id] = {"model": r.model, "scheme": r.scheme, "fuel": snappedf(float(r.fuel), 0.01), "pos": r.pos,
				"yaw": snappedf(float(r.yaw), 0.001), "tipped": r.tipped}
	for p in get_tree().get_nodes_in_group("players"):  # bikes being ridden are saved where their rider is
		if "bike" in p and p.bike.mounted:
			parked[p.bike.bike_id] = p.bike.host_record()
	return {"taken": _taken.keys(), "parked": parked}


# --- host: cells ---------------------------------------------------------------------------------

func _on_cell_loaded(c: Vector2i) -> void:
	if not multiplayer.is_server() or _streamer == null:
		return
	var id := "c%d_%d" % [c.x, c.y]
	if not _taken.has(id) and not _parked.has(id) and not _ridden(id):
		var markers: Array[Node] = _streamer.spawn_points(c)
		var spawn := BikeRules.cell_bike(_seed, c, markers.size())
		if not spawn.is_empty():
			var at: Vector3 = (markers[int(spawn.marker)] as Node3D).global_position
			var off: Array = spawn.offset
			_parked[id] = {"model": spawn.model, "scheme": spawn.scheme, "fuel": spawn.fuel,
				"pos": [at.x + float(off[0]), at.y - 0.1, at.z + float(off[1])], "yaw": spawn.yaw, "tipped": false,
				"moved": false}
	for bid: String in _parked:
		if not _shown.has(bid) and _cell_of(_parked[bid]) == c:
			_show_rec(bid)


func _on_cell_unloaded(c: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	for bid: String in _parked.keys():
		if _cell_of(_parked[bid]) == c:
			if _shown.has(bid):
				_hide.rpc(bid)
			if not bool(_parked[bid].moved):
				_parked.erase(bid)  # an untouched cell bike comes back from the world seed next time


func _cell_of(r: Dictionary) -> Vector2i:
	var p: Array = r.pos
	return _streamer.grid.cell_of(Vector3(p[0], p[1], p[2]))


func _ridden(id: String) -> bool:
	for p in get_tree().get_nodes_in_group("players"):
		if "bike" in p and p.bike.mounted and p.bike.bike_id == id:
			return true
	return false


# --- host: riding --------------------------------------------------------------------------------

func host_mount(peer: int, id: String) -> void:
	if not multiplayer.is_server() or not _parked.has(id):
		return
	var p := _player(peer)
	if p == null or p.bike.mounted or p.life.net_state != LifeState.ALIVE or p.water == MovementRules.Water.SWIM:
		return
	var r: Dictionary = _parked[id]
	var pos := Vector3(r.pos[0], r.pos[1], r.pos[2])
	if p.global_position.distance_to(pos) > MOUNT_RANGE:
		return
	_parked.erase(id)
	if id.begins_with("c"):
		_taken[id] = true
	_hide.rpc(id)
	p.meepo.net_riding = false
	p.bike.host_mount(id, r)


# A bike someone got off / crashed: back in the world as a record (always kept in the save).
func host_park(id: String, model: String, scheme: int, fuel: float, pos: Vector3, yaw: float, tipped: bool) -> void:
	if not multiplayer.is_server():
		return
	if id.begins_with("c"):
		_taken[id] = true
	_parked[id] = {"model": model, "scheme": scheme, "fuel": fuel, "pos": [pos.x, pos.y, pos.z], "yaw": yaw,
		"tipped": tipped, "moved": true}
	_show_rec(id)


# Tests: a bike right here (returns its id).
func host_spawn_test(model: String, scheme: int, fuel: float, pos: Vector3, yaw: float) -> String:
	var id := "t%d" % (Time.get_ticks_usec() % 1000000)
	host_park(id, model, scheme, fuel, pos, yaw, false)
	return id


func _show_rec(id: String) -> void:
	var r: Dictionary = _parked[id]
	_show.rpc(id, str(r.model), int(r.scheme), float(r.fuel), Vector3(r.pos[0], r.pos[1], r.pos[2]), float(r.yaw),
		bool(r.tipped))


func _on_peer_connected(peer: int) -> void:
	if not multiplayer.is_server():
		return
	for id: String in _shown:
		if _parked.has(id):
			var r: Dictionary = _parked[id]
			_show.rpc_id(peer, id, str(r.model), int(r.scheme), float(r.fuel), Vector3(r.pos[0], r.pos[1], r.pos[2]),
				float(r.yaw), bool(r.tipped))


# --- every peer ----------------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _show(id: String, model: String, scheme: int, fuel: float, pos: Vector3, yaw: float, tipped: bool) -> void:
	if not BikeRules.has_bike(model):
		return
	if _shown.has(id):
		_drop(_shown[id])
	var pb := ParkedBike.new()
	pb.setup(id, model, scheme, fuel, tipped, _view_m)
	add_child(pb)
	pb.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	_shown[id] = pb


@rpc("authority", "call_local", "reliable")
func _hide(id: String) -> void:
	if _shown.has(id):
		_drop(_shown[id])
		_shown.erase(id)


# Frees a parked bike node at the end of the frame (it may be running its own request_use right now); renamed first so
# a new "B_<id>" can take its place at once.
func _drop(pb: Node) -> void:
	pb.name = str(pb.name) + "_gone"
	pb.queue_free()


func _player(peer: int) -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if "peer_id" in p and p.peer_id == peer:
			return p
	return null
