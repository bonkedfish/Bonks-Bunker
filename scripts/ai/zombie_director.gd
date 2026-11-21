# ZombieDirector — owns the zombie pool and spawning on the streamed map (D-019, D-039).
# All peers build the same pool (Zombie0..N-1, pool_size) at load, so every zombie's synchronizer exists everywhere.
# Host, every spawn_interval: zombies standing in a cell the host no longer has loaded are put back in the
#       pool; then one zombie is activated in a cell within near range of some player that has fewer than
#       cell_cap zombies (the cap counts everyone's zombies together), at one of that cell's road markers
#       ≥ min_spawn_distance from every living player and either out of their sight or ≥ far_spawn_distance away.
# Host: host_noise(pos, radius) alerts active zombies in range (gunshots, bat swings; scaled by each type's hearing).
# No spawns inside a disc golf course during a round (DiscGolfDirector.blocks_spawn, group "disc_golf") or ever
# inside a safe zone (SafeZones, group "safe_zones", D-101).
# Types (D-100): the spawn point's distance from the bunker (landmark home_landmark) picks the type from
# types_by_distance (ZombieTypeRules.pick_type); a pooled body already of that type is reused first (switching type
# reloads the model on every peer).
# Night (D-110): the per-cell cap is multiplied by night_cell_cap_mult and the type weights by night_weight_mult,
# faded in with DayNight.night(), so after dark there are twice as many and far more of them are specials.
# pool_size is still the hard ceiling on how many can be awake at once. A dead zombie with a drop_table rolls it and leaves the loot (WorldDrops).
# Group "zombie_director". Depends on: scenes/zombie.tscn, EnemyDB, LootDB, LootRules, ZombieTypeRules, DataLoader,
# data/tuning/zombies.json, WorldStreamer (group "world_streamer": loaded cells, their ZombieSpawns markers),
# WorldDrops (group "world_drops").
extends Node3D

const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const TUNING_PATH := "res://data/tuning/zombies.json"
const SCHEMA := {
	"enemy_id": TYPE_STRING, "pool_size": TYPE_FLOAT, "cell_cap": TYPE_FLOAT, "spawn_interval": TYPE_FLOAT,
	"min_spawn_distance": TYPE_FLOAT, "far_spawn_distance": TYPE_FLOAT,
	"perception_hz": TYPE_FLOAT, "corpse_seconds": TYPE_FLOAT,
	"home_landmark": TYPE_STRING, "types_note": TYPE_STRING, "types_by_distance": TYPE_ARRAY,
	"night_note": TYPE_STRING, "night_cell_cap_mult": TYPE_FLOAT, "night_weight_mult": TYPE_DICTIONARY,
}
const WORLD_MASK := 1

var active_count := 0

var _clock: Node

var _pool: Array[Node] = []
var _tuning: Dictionary
var _spawn_timer := 0.0
var _streamer: Node
var _counts: Dictionary = {}  # host, per spawn tick: Vector2i cell -> active zombies in it
var _home: Node3D  # the bunker landmark (types get harder farther from it)
var _home_search_at := 0  # msec: next time to look for it (a tree search, so not every spawn tick)
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("zombie_director")
	_tuning = DataLoader.load_validated(TUNING_PATH, SCHEMA)
	var def := EnemyDB.get_enemy(str(_tuning.get("enemy_id", "")))
	if _tuning.is_empty() or def.is_empty():
		set_physics_process(false)
		return
	_rng.randomize()
	for i in int(_tuning.pool_size):
		var z := ZOMBIE_SCENE.instantiate()
		z.name = "Zombie%d" % i
		z.net_enemy = str(_tuning.enemy_id)  # before add_child: applied once in _ready, no model reload
		add_child(z)
		z.setup(def, float(_tuning.perception_hz), float(_tuning.corpse_seconds))
		z.health.died.connect(_on_zombie_died.bind(z))
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
	var type := _type_at(point)
	var body: Node = null
	for z in _pool:
		if not z.net_active:
			if z.net_enemy == type:
				body = z
				break
			if body == null:
				body = z
	if body:
		body.net_enemy = type
		body.activate(point)


# The enemy type for a spawn at `point`: by its distance from the bunker (D-100).
func _type_at(point: Vector3) -> String:
	if (_home == null or not is_instance_valid(_home)) and Time.get_ticks_msec() >= _home_search_at:
		_home_search_at = Time.get_ticks_msec() + 10000
		_home = get_tree().root.find_child(str(_tuning.get("home_landmark", "")), true, false) as Node3D
	var from := _home.global_position if _home else Vector3.ZERO
	var dist := Vector2(point.x - from.x, point.z - from.z).length()
	var type := ZombieTypeRules.pick_type(_tuning.get("types_by_distance", []), dist, _rng,
		_tuning.get("night_weight_mult", {}), _night())
	return type if type != "" and not EnemyDB.get_enemy(type).is_empty() else str(_tuning.enemy_id)


# How far into night it is, 0..1 (D-110): it raises the per-cell cap and shifts the mix toward the special types.
func _night() -> float:
	if _clock == null or not is_instance_valid(_clock):
		_clock = get_tree().get_first_node_in_group("daynight")
	return float(_clock.night()) if _clock else 0.0


# Host: a dead zombie with a drop_table leaves what it rolls on the ground.
func _on_zombie_died(_attacker: int, z: Node) -> void:
	if not multiplayer.is_server():
		return
	var table := str(z.def.get("drop_table", ""))
	if table == "":
		return
	var drops := get_tree().get_first_node_in_group("world_drops")
	if drops == null:
		return
	var got := LootRules.roll(LootDB.get_table(table), _rng)
	var i := 0
	for item: String in got:
		drops.host_add(item, int(got[item]), z.global_position + Vector3(0.5 * i - 0.25, 0.3, 0.5))
		i += 1


func host_noise(pos: Vector3, radius: float) -> void:
	var weather := get_tree().get_first_node_in_group("weather")
	if weather:
		radius *= weather.hearing_mult()  # rain and storms drown noise out (D-099)
	if radius <= 0.0:
		return
	for z in _pool:
		if z.net_active and z.global_position.distance_to(pos) <= radius * z.hearing_mult():
			z.hear(pos)


# A random cell near some player that is under cell_cap, then a random valid marker in it.
# Vector3.INF if nothing is valid right now.
func _pick_spawn_point() -> Vector3:
	var cells: Array = _streamer.want_near.keys()
	if cells.is_empty():
		return Vector3.INF
	var players := get_tree().get_nodes_in_group("players")
	var space := get_world_3d().direct_space_state
	var cap := int(float(_tuning.cell_cap) * lerpf(1.0, float(_tuning.get("night_cell_cap_mult", 1.0)), _night()))
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
	var safe := get_tree().get_first_node_in_group("safe_zones")
	if safe and safe.contains(point):  # never near the courses (D-101)
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
