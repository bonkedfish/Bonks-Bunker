# WorldStreamer — "World" node in main.tscn (group "world_streamer") (D-039). Loads the generated map cells
# listed in world/generated/cells/index.json around the people that matter on this peer:
#   host:   every body in group "players" (players + Bonk), because the host simulates all of them
#   client: its own player (it predicts its own movement)
#   nobody yet (menu): the spawn hint (the bunker)
# Full-detail cells within near_radius are loaded on a background thread and added one per frame; the
# cell a body is standing in is loaded immediately if it's missing (so nobody falls through the world).
# Cells beyond near_radius + unload_margin are freed. Low-detail shells cover every other cell out to the
# graphics tier's view distance (hidden where the full cell is loaded).
# Generated cells contain no networked nodes, so each peer streams on its own. Landmarks stay resident.
# Perf: a cell add (or blocking load) slower than slow_ms is printed and kept in slow_events for tests.
# Depends on: CellGrid, DataLoader, Graphics autoload, data/map/streaming.json, the cell index.
extends Node3D

signal cell_loaded(cell: Vector2i)
signal cell_unloaded(cell: Vector2i)

const CONFIG_PATH := "res://data/map/streaming.json"

var grid: CellGrid
var near_loaded: Dictionary = {}  # Vector2i -> Node3D
var want_near: Dictionary = {}  # Vector2i -> true: cells within near_radius of someone (zombies spawn only here)
var spawn_hint := Vector3.ZERO

var _index: Dictionary = {}
var _cfg: Dictionary = {}
var _keep_near: Dictionary = {}
var _want_far: Dictionary = {}
var _far_loaded: Dictionary = {}  # Vector2i -> Node3D
var _pending: Dictionary = {}  # path -> [Vector2i, is_far]
var _ready_queue: Array = []  # [Vector2i, is_far, PackedScene]
var _cells_root: Node3D
var _far_root: Node3D
var _timer := 0.0
var _positions := PackedVector3Array()
var slow_events := PackedStringArray()


func _ready() -> void:
	add_to_group("world_streamer")
	_cfg = DataLoader.load_json(CONFIG_PATH)
	_index = DataLoader.load_json(str(_cfg.get("index_path", "")))
	if _index.is_empty():
		push_error("WorldStreamer: no cell index - run the map pipeline (tools/map_import)")
		set_process(false)
		return
	var org: Array = _index.get("origin", [])
	grid = CellGrid.new(float(_index.cell_size), int(_index.get("cells_x", _index.get("cells_per_side", 8))),
		int(_index.get("cells_z", _index.get("cells_per_side", 8))), Vector2(org[0], org[1]) if org.size() == 2 else Vector2.INF)
	var hint: Array = _index.get("spawn_hint", [0, 0, 0])
	spawn_hint = Vector3(hint[0], hint[1], hint[2])
	_cells_root = Node3D.new()
	_cells_root.name = "Cells"
	add_child(_cells_root)
	_far_root = Node3D.new()
	_far_root.name = "FarCells"
	add_child(_far_root)
	# Boot: the cells around the spawn load now, synchronously, so the first frame has ground.
	var boot := {}
	grid.add_square(boot, grid.cell_of(spawn_hint), int(_cfg.get("near_radius", 1.0)))
	for c: Vector2i in boot:
		_add_cell(c, false, load(_path(c, false)) as PackedScene)
	_update()


func has_index() -> bool:
	return not _index.is_empty()


func is_loaded(c: Vector2i) -> bool:
	return near_loaded.has(c)


# Zombie spawn markers in a loaded cell (empty if not loaded).
func spawn_points(c: Vector2i) -> Array[Node]:
	var cell: Node3D = near_loaded.get(c)
	if cell == null:
		return []
	var holder := cell.get_node_or_null("ZombieSpawns")
	if holder == null:
		return []
	return holder.get_children()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = float(_cfg.get("update_seconds", 0.25))
		_update()
	_poll_pending()
	for i in int(_cfg.get("instantiations_per_frame", 1.0)):
		if _ready_queue.is_empty():
			break
		var item: Array = _ready_queue.pop_front()
		_add_cell(item[0], item[1], item[2])


func _update() -> void:
	_gather_positions()
	var near_r := int(_cfg.get("near_radius", 1.0))
	want_near.clear()
	_keep_near.clear()
	_want_far.clear()
	for p in _positions:
		var c := grid.cell_of(p)
		grid.add_square(want_near, c, near_r)
		grid.add_square(_keep_near, c, near_r + int(_cfg.get("unload_margin", 1.0)))
		if grid.in_bounds(c) and not near_loaded.has(c):
			_load_now(c)  # someone is standing here: no waiting
	var far_r := ceili(Graphics.get_view_distance() / grid.cell_size)
	grid.add_square(_want_far, grid.cell_of(_positions[0]), far_r)

	for c: Vector2i in want_near:
		if not near_loaded.has(c):
			_request(c, false)
	for c: Vector2i in near_loaded.keys():
		if not _keep_near.has(c):
			near_loaded[c].queue_free()
			near_loaded.erase(c)
			cell_unloaded.emit(c)
	for c: Vector2i in _want_far:
		if not _far_loaded.has(c):
			_request(c, true)
	for c: Vector2i in _far_loaded.keys():
		if not _want_far.has(c):
			_far_loaded[c].queue_free()
			_far_loaded.erase(c)
		else:
			_far_loaded[c].visible = not near_loaded.has(c)


func _gather_positions() -> void:
	_positions.clear()
	if multiplayer.is_server():
		for p in get_tree().get_nodes_in_group("players"):
			_positions.append(p.global_position)
	else:
		var me := get_tree().get_first_node_in_group("local_player")
		if me:
			_positions.append(me.global_position)
	if _positions.is_empty():
		_positions.append(spawn_hint)


func _request(c: Vector2i, far: bool) -> void:
	var path := _path(c, far)
	if path == "" or _pending.has(path) or _queued(c, far):
		return
	if ResourceLoader.load_threaded_request(path, "PackedScene") == OK:
		_pending[path] = [c, far]


func _poll_pending() -> void:
	for path: String in _pending.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		var info: Array = _pending[path]
		_pending.erase(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_ready_queue.append([info[0], info[1], ResourceLoader.load_threaded_get(path)])
		else:
			push_warning("WorldStreamer: failed to load %s" % path)


func _load_now(c: Vector2i) -> void:
	var t0 := Time.get_ticks_usec()
	var path := _path(c, false)
	var scene: PackedScene
	if _pending.has(path):
		scene = ResourceLoader.load_threaded_get(path)  # blocks until the thread finishes
		_pending.erase(path)
	else:
		scene = load(path) as PackedScene
	_add_cell(c, false, scene)
	_note_slow("blocking load", c, false, t0)


func _add_cell(c: Vector2i, far: bool, scene: PackedScene) -> void:
	var loaded := _far_loaded if far else near_loaded
	if scene == null or loaded.has(c):
		return
	if not far and not _keep_near.has(c) and not _keep_near.is_empty():
		return  # nobody needs it any more
	var t0 := Time.get_ticks_usec()
	var node := scene.instantiate() as Node3D
	(_far_root if far else _cells_root).add_child(node)
	loaded[c] = node
	if far:
		node.visible = not near_loaded.has(c)
	else:
		if _far_loaded.has(c):
			_far_loaded[c].visible = false
		cell_loaded.emit(c)
	_note_slow("add", c, far, t0)


func _note_slow(what: String, c: Vector2i, far: bool, t0: int) -> void:
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	if ms < float(_cfg.get("slow_ms", 12.0)):
		return
	var line := "%.1f s: %s %s cell %s took %.1f ms" % [Time.get_ticks_msec() / 1000.0, what, "far" if far else "near", c, ms]
	print("WorldStreamer: " + line)
	if slow_events.size() < 100:
		slow_events.append(line)


func _queued(c: Vector2i, far: bool) -> bool:
	for item in _ready_queue:
		if item[0] == c and item[1] == far:
			return true
	return false


func _path(c: Vector2i, far: bool) -> String:
	var entry: Dictionary = _index.cells.get(grid.key(c), {})
	return str(entry.get("far" if far else "near", ""))
