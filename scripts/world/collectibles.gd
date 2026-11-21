# CollectibleManager — the fifteen collectible sets (D-107): cones, golf balls and tees, playing cards, plungers,
# gnomes, bowling pins, rubber ducks, flip phones, VHS tapes, trophies, model cars, plates, mannequin heads and
# lunchboxes. Main child "Collectibles", group "collectibles"; same path on every peer.
# Every spot in data/encounters/collectibles.json is hand placed (map x / z, or a landmark plus an offset). A spot
# builds when its cell loads, drops onto the ground, and offers an E prompt; the host checks range, puts the item
# in that player's inventory and marks the spot taken for the whole party (saved in the world, so a world keeps
# what it has lost). Picking one up tells everybody, so the pickup disappears on every screen.
# The bunker shelf: once the party owns a type, one of it stands on the rack in Bonk's bunker, so the collection
# is somewhere you can look at it. counts() is what a UI or a quest would read.
# Depends on: PropKits, EncounterSite (prop building), ItemDB, WorldStreamer (group "world_streamer"),
# HUD (group "hud"), SaveDirector (host_save_state / host_load_state).
class_name CollectibleManager
extends Node3D

const PATH := "res://data/encounters/collectibles.json"
const GROUND_MASK := 17

var types: Dictionary = {}   # item id -> {name, kit}
var spots: Dictionary = {}   # spot key -> {item, at, landmark?, yaw}
var taken: Dictionary = {}   # spot key -> true (saved)

var _built: Dictionary = {}  # spot key -> Node3D
var _by_cell: Dictionary = {}
var _pending: Array = []
var _streamer: Node
var _shelf: Node3D
var _shelf_shown: Dictionary = {}
var _retry := 2.0
var _shelf_timer := 4.0


func _ready() -> void:
	add_to_group("collectibles")
	var raw := DataLoader.load_json(PATH)
	types = raw.get("types", {})
	var i := 0
	for s: Dictionary in raw.get("spots", []):
		var key := "%s_%d" % [str(s.get("item", "x")), i]
		spots[key] = s
		i += 1
	_streamer = get_tree().get_first_node_in_group("world_streamer")
	if _streamer == null:
		return
	_streamer.cell_loaded.connect(_on_cell_loaded)
	_streamer.cell_unloaded.connect(_on_cell_unloaded)
	for key: String in spots:
		if spots[key].has("landmark"):
			_pending.append(key)
		else:
			var at: Array = spots[key].at
			var cell: Vector2i = _streamer.grid.cell_of(Vector3(at[0], 0.0, at[1]))
			var list: Array = _by_cell.get(cell, [])
			list.append(key)
			_by_cell[cell] = list
	for cell: Vector2i in _streamer.near_loaded:
		_on_cell_loaded(cell)


func _process(delta: float) -> void:
	_shelf_timer -= delta
	if _shelf_timer <= 0.0:
		_shelf_timer = 5.0
		_update_shelf()
	if _pending.is_empty():
		return
	_retry -= delta
	if _retry > 0.0:
		return
	_retry = 3.0
	for i in range(_pending.size() - 1, -1, -1):
		var key: String = _pending[i]
		var lm := get_tree().root.find_child(str(spots[key].landmark), true, false) as Node3D
		if lm == null:
			continue
		_pending.remove_at(i)
		var at: Array = spots[key].at
		_build(key, lm.global_transform * Vector3(at[0], at[1], at[2]), false)


# How many of each collectible type the party has between them (the shelf and any UI read this).
func counts() -> Dictionary:
	var out := {}
	for item: String in types:
		var n := 0
		for p in get_tree().get_nodes_in_group("players"):
			if p.peer_id > 0:
				n += p.inventory.count(item)
		out[item] = n
	return out


func _on_cell_loaded(cell: Vector2i) -> void:
	for key: String in _by_cell.get(cell, []):
		if not _built.has(key) and not taken.has(key):
			var at: Array = spots[key].at
			_build(key, Vector3(at[0], 0.0, at[1]), true)


func _on_cell_unloaded(cell: Vector2i) -> void:
	for key: String in _by_cell.get(cell, []):
		if _built.has(key):
			(_built[key] as Node).queue_free()
			_built.erase(key)


func _build(key: String, at: Vector3, drop: bool) -> void:
	if taken.has(key):
		return
	var item := str(spots[key].item)
	var kit := str((types.get(item, {}) as Dictionary).get("kit", "rubber_duck"))
	var pos := at
	if drop:
		var hit := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(at + Vector3.UP * 60.0, at + Vector3.DOWN * 60.0, GROUND_MASK))
		if hit.is_empty():
			return
		pos = hit.position
	var site := EncounterSite.new()
	site.name = "Pick_%s" % key
	add_child(site)
	site.global_position = pos
	site.rotation.y = deg_to_rad(float(spots[key].get("yaw", 0.0)))
	site.build(_slot_of(key), item, {
		"props": [{"kit": kit, "at": [0, 0, 0], "yaw": 0, "collide": false}],
		"uses": [{"label": "Take the %s" % str((types.get(item, {}) as Dictionary).get("name", item)),
			"at": [0, 0.4, 0], "size": [0.9, 0.9, 0.9]}]}, hash(key), self)
	_built[key] = site


func _slot_of(key: String) -> int:
	return int(abs(hash(key))) % 100000


@rpc("any_peer", "call_local", "reliable")
func request_use(index: int) -> void:
	if not multiplayer.is_server():
		return
	var slot := floori(index / 100.0)
	for key: String in spots:
		if taken.has(key) or _slot_of(key) != slot or not _built.has(key):
			continue
		var player := _player()
		if player == null or player.global_position.distance_to((_built[key] as Node3D).global_position) > 6.0:
			return
		player.inventory.host_add(str(spots[key].item), 1)
		_picked.rpc(key, player.peer_id)
		return


func host_save_state() -> Dictionary:
	return {"taken": taken.duplicate()}


func host_load_state(saved: Variant) -> void:
	taken.clear()
	if typeof(saved) == TYPE_DICTIONARY:
		for key: String in (saved as Dictionary).get("taken", {}):
			taken[key] = true
	for key: String in taken.keys():
		if _built.has(key):
			(_built[key] as Node).queue_free()
			_built.erase(key)


# One of each type the party owns, standing on a rack in the bunker.
func _update_shelf() -> void:
	var have := counts()
	var wanted := {}
	for item: String in have:
		if int(have[item]) > 0:
			wanted[item] = true
	if wanted.hash() == _shelf_shown.hash() and _shelf != null:
		return
	var home := get_tree().root.find_child("bonk_bunker", true, false) as Node3D
	if home == null:
		return
	if _shelf:
		_shelf.name = "ShelfOld"  # queue_free is deferred; without this the new shelf is renamed Shelf2
		_shelf.queue_free()
	_shelf_shown = wanted
	var raw := DataLoader.load_json(PATH)
	var anchor: Array = raw.get("shelf", {}).get("at", [0, 0, 0])
	var site := EncounterSite.new()
	site.name = "Shelf"
	add_child(site)
	_shelf = site
	site.global_position = home.global_transform * Vector3(anchor[0], anchor[1], anchor[2])
	site.rotation.y = home.rotation.y + deg_to_rad(float(raw.get("shelf", {}).get("yaw", 0.0)))
	var props: Array = [{"box": [0, 0.45, 0, 2.6, 0.06, 0.4], "mat": "wood"},
		{"box": [0, 0.95, 0, 2.6, 0.06, 0.4], "mat": "wood"},
		{"box": [-1.28, 0.7, 0, 0.06, 1.0, 0.4], "mat": "wood"},
		{"box": [1.28, 0.7, 0, 0.06, 1.0, 0.4], "mat": "wood"}]
	var i := 0
	for item: String in types:
		if not wanted.has(item):
			continue
		var row := floori(i / 8.0)  # two shelves of eight: all 15 types fit without a third row
		var col := i % 8
		props.append({"kit": str(types[item].get("kit", "rubber_duck")),
			"at": [-1.12 + col * 0.32, 0.48 + row * 0.5, 0.0], "yaw": 20 * (i % 3), "collide": false})
		i += 1
	site.build(0, "shelf", {"props": props}, 1, self)


func _player() -> Node:
	var id := multiplayer.get_remote_sender_id()
	var peer := id if id != 0 else multiplayer.get_unique_id()
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == peer and not p.health.is_dead():
			return p
	return null


@rpc("authority", "call_local", "reliable")
func _picked(key: String, peer: int) -> void:
	taken[key] = true
	if _built.has(key):
		(_built[key] as Node).queue_free()
		_built.erase(key)
	if peer == multiplayer.get_unique_id():
		var hud := get_tree().get_first_node_in_group("hud")
		var item := str((spots.get(key, {}) as Dictionary).get("item", ""))
		if hud:
			hud.show_toast("Collected: %s" % str((types.get(item, {}) as Dictionary).get("name", item)), 2.5)
