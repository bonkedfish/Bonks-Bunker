# LairDirector — placed enemies and bosses at landmark spawn markers (D-055), main.tscn node "Lairs".
# Landmark scenes carry Marker3D nodes in group "lair_spawns" (unique name; meta "enemy" = EnemyDB id, optional meta
# "requires" = quest-flag list). All peers build the same pool (Lair0..N-1, scenes/zombie.tscn) so every body's
# synchronizer exists everywhere. Host, every check_seconds: a marker with a living player within activate_m gets a
# free pool body (net_enemy = its enemy, full health, at the marker); a live one with everybody beyond deactivate_m
# goes back to the pool. Deaths: mobs count "kills_<enemy>" (or "kills_<kill_count_as>": every raider type counts as
# "raider") on the party's quests and return after respawn_seconds; bosses set "boss_<enemy>_dead" (saved with the
# quest flags, so they never return) and drop their "drops".
# Host: host_noise() alerts active lair enemies like street zombies.
# Group "lair_director". Depends on: scenes/zombie.tscn, EnemyDB, QuestRules, QuestDirector (group "quests"),
# WorldDrops (group "world_drops"), data/tuning/lairs.json, data/tuning/zombies.json (perception_hz, corpse_seconds).
extends Node3D

const ZOMBIE_SCENE := preload("res://scenes/zombie.tscn")
const TUNING_PATH := "res://data/tuning/lairs.json"
const ZOMBIE_TUNING_PATH := "res://data/tuning/zombies.json"

var active_count := 0

var _pool: Array[Node] = []
var _t: Dictionary
var _timer := 0.0
var _by_spawn: Dictionary = {}  # host: marker name -> pool body
var _killed: Dictionary = {}    # host: marker name -> msec when it died
var _quests: Node


func _ready() -> void:
	_t = DataLoader.load_json(TUNING_PATH)
	var zt := DataLoader.load_json(ZOMBIE_TUNING_PATH)
	var def := EnemyDB.get_enemy(str(zt.get("enemy_id", "")))
	if _t.is_empty() or def.is_empty():
		set_physics_process(false)
		return
	_quests = get_tree().get_first_node_in_group("quests")
	for i in int(_t.pool_size):
		var z := ZOMBIE_SCENE.instantiate()
		z.name = "Lair%d" % i
		add_child(z)
		z.setup(def, float(zt.get("perception_hz", 5.0)), float(zt.get("corpse_seconds", 8.0)))
		z.health.died.connect(_on_died.bind(z))
		_pool.append(z)


func host_noise(pos: Vector3, radius: float) -> void:
	if radius <= 0.0:
		return
	for z in _pool:
		if z.net_active and z.global_position.distance_to(pos) <= radius:
			z.hear(pos)


func _physics_process(delta: float) -> void:
	if not (multiplayer.has_multiplayer_peer() and multiplayer.is_server()):
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = float(_t.get("check_seconds", 0.5))
	var players: Array[Vector3] = []
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id > 0 and not p.health.is_dead():
			players.append(p.global_position)
	var flags: Dictionary = _quests.flags if _quests else {}
	var wake := float(_t.activate_m)
	var sleep := float(_t.deactivate_m)
	var now := Time.get_ticks_msec()
	active_count = 0
	for m: Node3D in get_tree().get_nodes_in_group("lair_spawns"):
		var key := str(m.name)
		var near := INF
		for pp in players:
			near = minf(near, pp.distance_to(m.global_position))
		if _by_spawn.has(key):
			var body: Node = _by_spawn[key]
			if not body.net_active:
				_by_spawn.erase(key)  # died and its corpse is gone
			elif near > sleep and not body.health.is_dead():
				body.deactivate()
				_by_spawn.erase(key)
			else:
				active_count += 1
			continue
		if near > wake:
			continue
		var enemy := str(m.get_meta("enemy", ""))
		var def := EnemyDB.get_enemy(enemy)
		if def.is_empty() or not QuestRules.requires_met(m.get_meta("requires") if m.has_meta("requires") else null, flags):
			continue
		if bool(def.get("boss", false)):
			if QuestRules.flag_met(flags, "boss_%s_dead" % enemy):
				continue
		elif _killed.has(key) and now - int(_killed[key]) < int(float(_t.respawn_seconds) * 1000.0):
			continue
		for z in _pool:
			if not z.net_active:
				z.net_enemy = enemy
				z.set_meta("spawn_key", key)
				z.activate(m.global_position, m.global_rotation.y)
				_by_spawn[key] = z
				active_count += 1
				break


func _on_died(_attacker: int, z: Node) -> void:
	if not multiplayer.is_server():
		return
	_killed[str(z.get_meta("spawn_key", ""))] = Time.get_ticks_msec()
	var enemy: String = z.net_enemy
	var def: Dictionary = z.def
	if _quests:
		if bool(def.get("boss", false)):
			_quests.host_set_flag("boss_%s_dead" % enemy)
		else:
			_quests.host_add_count("kills_%s" % str(def.get("kill_count_as", enemy)))
	var drops := get_tree().get_first_node_in_group("world_drops")
	if drops:
		var i := 0
		for item: String in def.get("drops", {}):
			drops.host_add(item, int(def.drops[item]), z.global_position + Vector3(0.5 * i - 0.5, 0.3, 0.6))
			i += 1
