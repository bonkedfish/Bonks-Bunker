# ZombieDirector — owns the zombie pool and spawning on the streamed map (D-019, D-039).
# All peers build the same pool (Zombie0..N-1, pool_size) at load, so every zombie's synchronizer exists everywhere.
# Host, every spawn_interval: zombies standing in a cell the host no longer has loaded are put back in the
#       pool; then one zombie is activated in a cell within near range of some player that has fewer than
#       cell_cap zombies (the cap counts everyone's zombies together), at one of that cell's road markers
#       ≥ min_spawn_distance from every living player and either out of their sight or ≥ far_spawn_distance away.
# Host: host_noise(pos, radius) alerts active zombies in range (gunshots, bat swings).
# No spawns inside a disc golf course during a round (DiscGolfDirector.blocks_spawn, group "disc_golf").
# Group "zombie_director". Depends on: scenes/zombie.tscn, EnemyDB, DataLoader, data/tuning/zombies.json,
# WorldStreamer (group "world_streamer": loaded cells, their ZombieSpawns markers).
extends Node3D

const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const TUNING_PATH := "res://data/tuning/zombies.json"
const SCHEMA := {
	"enemy_id": TYPE_STRING, "pool_size": TYPE_FLOAT, "cell_cap": TYPE_FLOAT, "spawn_interval": TYPE_FLOAT,
	"min_spawn_distance": TYPE_FLOAT, "far_spawn_distance": TYPE_FLOAT,
	"perception_hz": TYPE_FLOAT, "corpse_seconds": TYPE_FLOAT,
}
const WORLD_MASK := 1

var active_count := 0

var _pool: Array[Node] = []
var _tuning: Dictionary
var _spawn_timer := 0.0
var _streamer: Node
var _counts: Dictionary = {}  # host, per spawn tick: Vector2i cell -> active zombies in it


func _ready() -> void:
	add_to_group("zombie_director")
	_tuning = DataLoader.load_validated(TUNING_PATH, SCHEMA)
	var def := EnemyDB.get_enemy(str(_tuning.get("enemy_id", "")))
	if _tuning.is_empty() or def.is_empty():
		set_physics_process(false)
		return
	for i in int(_tuning.pool_size):
		var z := ZOMBIE_SCENE.instantiate()
		z.name = "Zombie%d" % i
		add_child(z)
		z.setup(def, float(_tuning.perception_hz), float(_tuning.corpse_seconds))
		_pool.append(z)


func _physics_process(delta: float) -> void:
	active_count = 0
	for z in _pool:
		if z.net_active:
			active_count += 1
	if not (multiplayer.has_multiplayer_peer() and multiplayer.is_server()):
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = float(_tuning.spawn_interval)
	if _streamer == null:
		_streamer = get_tree().get_first_node_in_group("world_streamer")
	if _streamer == null or not _streamer.has_index():
		return
	_counts.clear()
	var active := 0
	for z in _pool:
		if not z.net_active:
			continue
		var c: Vector2i = _streamer.grid.cell_of(z.global_position)
		if not _streamer.is_loaded(c):
			z.deactivate()  # its ground is gone on the host: back to the pool
			continue
		_counts[c] = int(_counts.get(c, 0)) + 1
		active += 1
	if active >= _pool.size():
		return
	var point := _pick_spawn_point()
	if point == Vector3.INF:
		return
	for z in _pool:
		if not z.net_active:
			z.activate(point)
			return


func host_noise(pos: Vector3, radius: float) -> void:
	if radius <= 0.0:
		return
	for z in _pool:
		if z.net_active and z.global_position.distance_to(pos) <= radius:
			z.hear(pos)


# A random cell near some player that is under cell_cap, then a random valid marker in it.
# Vector3.INF if nothing is valid right now.
func _pick_spawn_point() -> Vector3:
	var cells: Array = _streamer.want_near.keys()
	if cells.is_empty():
		return Vector3.INF
	var players := get_tree().get_nodes_in_group("players")
	var space := get_world_3d().direct_space_state
	var cap := int(_tuning.cell_cap)
	var start := randi() % cells.size()
	for i in cells.size():
		var c: Vector2i = cells[(start + i) % cells.size()]
		if int(_counts.get(c, 0)) >= cap:
			continue
		var markers: Array[Node] = _streamer.spawn_points(c)
		if markers.is_empty():
			continue
		var m0 := randi() % markers.size()
		for j in markers.size():
			var point: Vector3 = markers[(m0 + j) % markers.size()].global_position
			if _spawn_ok(point, players, space):
				return point
	return Vector3.INF


func _spawn_ok(point: Vector3, players: Array, space: PhysicsDirectSpaceState3D) -> bool:
	var min_d := float(_tuning.min_spawn_distance)
	var far_d := float(_tuning.far_spawn_distance)
	for dg in get_tree().get_nodes_in_group("disc_golf"):  # no zombies in a park during a disc golf round (D-069)
		if dg.blocks_spawn(point):
			return false
	for p in players:
		if p.health.is_dead():
			continue
		var d: float = p.global_position.distance_to(point)
		if d < min_d:
			return false
		if d >= far_d:
			continue
		var query := PhysicsRayQueryParameters3D.create(p.eye_position(), point + Vector3.UP * 1.5, WORLD_MASK)
		if space.intersect_ray(query).is_empty():
			return false  # a player could see it appear
	return true
