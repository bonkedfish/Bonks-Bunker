# Bonk — the companion NPC (D-031, D-032). One per world, placed in the bunker at load.
#   Host:    perceives zombies (sight + line of sight) and the nearest player at perception_hz, runs
#            CompanionBrain, follows on the navmesh, shoots (infinite reserve, mag + reload) or bats
#            zombies without hurting teammates, teleports to the group if left far behind, and barks.
#            Downed at 0 HP; gets himself up after self_revive_seconds (or a player revives him with E).
#   Clients: render only, interpolated NetClock.INTERP_DELAY behind like zombies.
# Joins groups "players" (zombies target him, players can revive him) and "hittable" (lag-comp hits).
# Talkable (group "talkable", collision layer 4): E opens dialogue via DialogueDirector.
# Depends on: CompanionBrain, DialogueDB, WeaponDB, CombatWorld, DialogueDirector, NetClock, Health,
#             LifeState, PositionHistory, SnapshotBuffer, CharacterAnimator (Body: animated survivor "model",
#             holding his pistol, D-045), data/companions/bonk.json.
# Context barks (host, once a second): first time near each landmark ("landmark_<name>", once per session), a boss
# in view ("boss", once per boss type), a player on chems nearby ("high") or riding the Meepo ("meepo"), with
# per-context cooldowns from bonk.json (context_bark_seconds).
extends CharacterBody3D

const DATA_PATH := "res://data/companions/bonk.json"
const HEIGHT := 1.8
const EYE_HEIGHT := 1.6
const WORLD_MASK := 1
const PERCEPTION_PERIOD := 0.2
const RELOAD_TIME := 1.4
const URGENT_BARKS := ["boss", "downed", "self_revive", "revived_by_player", "player_downed", "friendly_fire", "combat_start", "busy"]
const URGENT_GAP := 1.5
const REPATH_DISTANCE := 1.0  # metres the leader must move before Bonk asks for a new path

var team := &"players"
var hit_radius := 0.35
var peer_id := 0  # not a network player
var display_name := "Bonk"         # talkable NPC interface (D-049)
var dialogue_tree := "bonk_talk"

# Replicated host -> clients.
var net_position := Vector3.ZERO
var net_yaw := 0.0

var def: Dictionary
var brain: CompanionBrain
var _clock: NetClock
var _combat: Node
var _dialogue: Node
var _gun: Dictionary
var _bat: Dictionary
var _history := PositionHistory.new()
var _snapshots := SnapshotBuffer.new()
var _gravity := 9.8
var _perceive_timer := 0.0
var _enemy: Node3D = null
var _leader: Node3D = null
var _known_downed := {}
var _mag := 12
var _reload_left := 0.0
var _bark_timer := 0.0
var _ctx_timer := 0.0
var _ctx_done: Dictionary = {}  # host: one-time context barks already said
var _ctx_last: Dictionary = {}  # host: context -> last time (s)
var _idle_timer := 30.0
var _shown_life_state := -1
var _nav_target := Vector3.INF  # last leader position we pathed to; repath only when they move
var _dodge_left := 0.0  # seconds left stepping out of a player's way (D-035)
var _dodge_target := Vector3.ZERO

@onready var nav: NavigationAgent3D = $Nav
@onready var health: Health = $Health
@onready var life: LifeState = $Life
@onready var collider: CollisionShape3D = $Collider
@onready var body: CharacterAnimator = $Body
@onready var sync: MultiplayerSynchronizer = $Sync


func _ready() -> void:
	def = DataLoader.load_json(DATA_PATH)
	brain = CompanionBrain.new(def)
	_gun = WeaponDB.get_weapon(str(def.get("weapon", "pistol_9mm")))
	_bat = WeaponDB.get_weapon(str(def.get("melee_weapon", "bat_baseball")))
	_mag = int(_gun.get("mag_size", 12.0))
	_clock = get_tree().get_first_node_in_group("net_clock")
	_combat = get_tree().get_first_node_in_group("combat_world")
	_dialogue = get_tree().get_first_node_in_group("dialogue")
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
	add_to_group("players")
	add_to_group("hittable")
	health.max_health = float(def.get("max_health", 150.0))
	health.reset()
	life.set_bleed_out_seconds(float(def.get("self_revive_seconds", 20.0)))
	health.died.connect(_on_downed)
	health.damaged.connect(_on_damaged)
	life.bled_out.connect(_on_get_up.bind("self_revive"))
	life.revived.connect(_on_get_up.bind("revived_by_player"))
	sync.synchronized.connect(_on_snapshot)
	if body.set_model(str(def.get("model", ""))):
		body.set_weapon_slot(0)
	_idle_timer = randf_range(float(def.get("idle_bark_min", 25.0)), float(def.get("idle_bark_max", 55.0)))
	if not multiplayer.is_server():
		global_position = net_position  # spawned by the host's NpcSpawner with its current position
		return
	# Host: start next to the players' spawn markers (inside Bonk's bunker).
	var spawns := get_tree().get_first_node_in_group("player_spawns")
	if spawns and spawns.get_child_count() > 0:
		global_position = spawns.get_child(0).global_position + Vector3(1.2, 0.0, 1.5)
	net_position = global_position


func eye_position() -> Vector3:
	return global_position + Vector3.UP * EYE_HEIGHT


func hit_capsule_at(tick: float) -> Vector4:
	var s := _history.sample(tick)
	if s.w < 0.0:
		return Vector4(global_position.x, global_position.y, global_position.z, HEIGHT)
	return s


# Host: a short line as a subtitle for everyone nearby. Urgent contexts skip the cooldown.
func bark(context: String) -> void:
	if not (multiplayer.has_multiplayer_peer() and multiplayer.is_server()) or _dialogue == null:
		return
	var urgent := context in URGENT_BARKS
	if _bark_timer > 0.0 and not (urgent and _bark_timer <= float(def.get("bark_cooldown", 6.0)) - URGENT_GAP):
		return
	var lines := DialogueDB.barks(context)
	if lines.is_empty():
		return
	_bark_timer = float(def.get("bark_cooldown", 6.0))
	_dialogue.host_bark(self, str(lines[randi() % lines.size()]))


func _physics_process(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_host_step(delta)
	elif multiplayer.has_multiplayer_peer() and not _snapshots.is_empty():
		var s := _snapshots.sample(Time.get_ticks_msec() / 1000.0 - NetClock.INTERP_DELAY)
		global_position = Vector3(s.x, s.y, s.z)
		rotation.y = s.w
	_update_life_visuals()
	body.update(delta, false, life.net_state != LifeState.ALIVE, health.current, true, false)


# --- host ----------------------------------------------------------------------

func _host_step(delta: float) -> void:
	life.host_tick(delta)
	_bark_timer = maxf(_bark_timer - delta, 0.0)
	if health.is_dead():
		_move(delta, Vector3.ZERO, Vector3.ZERO)
		_publish()
		return
	_context_barks(delta)

	_perceive_timer -= delta
	if _perceive_timer <= 0.0:
		_perceive_timer = PERCEPTION_PERIOD
		_perceive()
	var enemy_ok: bool = is_instance_valid(_enemy) and not _enemy.health.is_dead()
	var leader_ok: bool = is_instance_valid(_leader)
	var enemy_dist: float = global_position.distance_to(_enemy.global_position) if enemy_ok else INF
	var leader_dist: float = global_position.distance_to(_leader.global_position) if leader_ok else 0.0
	if leader_ok and leader_dist > float(def.teleport_distance):
		_teleport_near(_leader)
		leader_dist = 0.0

	brain.tick(delta, enemy_ok, enemy_dist, leader_dist)
	if brain.combat_started:
		bark("combat_start")

	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_mag = int(_gun.get("mag_size", 12.0))
	if brain.wants_fire and enemy_ok and _reload_left <= 0.0:
		_shoot(_enemy)
	if brain.wants_melee and enemy_ok:
		var to: Vector3 = (_enemy.global_position - global_position).normalized()
		if _combat.host_melee(self, _bat, eye_position(), to, float(_clock.tick), false):
			bark("kill")

	var move_dir := Vector3.ZERO
	if _dodge_left <= 0.0:
		_check_dodge()
	if _dodge_left > 0.0:
		_dodge_left -= delta
		var to_spot := _dodge_target - global_position
		to_spot.y = 0.0
		if to_spot.length_squared() < 0.04:
			_dodge_left = 0.0
		else:
			move_dir = to_spot.normalized() * float(def.walk_speed)
	elif brain.wants_move and leader_ok:
		if _nav_target.distance_squared_to(_leader.global_position) > REPATH_DISTANCE * REPATH_DISTANCE:
			_nav_target = _leader.global_position
			nav.target_position = _nav_target
		var to_next := nav.get_next_path_position() - global_position
		to_next.y = 0.0
		if to_next.length_squared() > 0.0001:
			var speed := float(def.run_speed if brain.move_fast else def.walk_speed)
			move_dir = to_next.normalized() * speed
	var face := move_dir
	if brain.state == CompanionBrain.State.COMBAT and enemy_ok:
		face = _enemy.global_position - global_position
	_move(delta, move_dir, face)

	if brain.state == CompanionBrain.State.FOLLOW:
		_idle_timer -= delta
		if _idle_timer <= 0.0:
			_idle_timer = randf_range(float(def.idle_bark_min), float(def.idle_bark_max))
			bark("idle")
	_publish()


# A player walking into Bonk: pick the first sidestep spot that is on the navmesh, at his level, and not
# behind a wall, and walk there for up to dodge_max_seconds. Runs every host tick; allocates only on a dodge.
func _context_barks(delta: float) -> void:
	_ctx_timer -= delta
	if _ctx_timer > 0.0:
		return
	_ctx_timer = 1.0
	var lms := get_parent().get_parent().get_node_or_null("Landmarks") if get_parent() else null
	if lms:
		for lm: Node3D in lms.get_children():
			var key := "landmark_" + str(lm.name)
			if not _ctx_done.has(key) and global_position.distance_to(lm.global_position) < float(def.get("landmark_bark_m", 70.0)) \
					and not DialogueDB.barks(key).is_empty():
				_ctx_done[key] = true
				bark(key)
				return
	for b in get_tree().get_nodes_in_group("bosses"):
		var key := "boss_" + str(b.net_enemy)
		if not _ctx_done.has(key) and not b.health.is_dead() and global_position.distance_to(b.global_position) < 30.0:
			_ctx_done[key] = true
			bark("boss")
			return
	var now := Time.get_ticks_msec() / 1000.0
	var gap := float(def.get("context_bark_seconds", 150.0))
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id <= 0 or p.global_position.distance_to(global_position) > 12.0:
			continue
		if "riding" in p and p.riding and now - _ctx_last.get("meepo", -INF) > gap:
			_ctx_last["meepo"] = now
			bark("meepo")
			return
		if not p.effects.net_effects.is_empty() and now - _ctx_last.get("high", -INF) > gap:
			_ctx_last["high"] = now
			bark("high")
			return


func _check_dodge() -> void:
	var trigger := float(def.get("dodge_trigger_distance", 1.4))
	var min_speed := float(def.get("dodge_min_player_speed", 1.0))
	for p in get_tree().get_nodes_in_group("players"):
		if p == self or p.peer_id <= 0 or p.health.is_dead():
			continue
		var pv: Vector3 = p.velocity
		if not CompanionBrain.player_walking_into(global_position - p.global_position, pv, trigger, min_speed):
			continue
		var map := nav.get_navigation_map()
		var space := get_world_3d().direct_space_state
		var knee := global_position + Vector3.UP * 0.4  # navmesh points sit ~0.4 m above the floor too
		for i in 3:
			var spot := CompanionBrain.dodge_spot(global_position, p.global_position, pv, i, float(def.get("dodge_step", 1.5)))
			var on_mesh := NavigationServer3D.map_get_closest_point(map, spot)
			if Vector2(on_mesh.x - spot.x, on_mesh.z - spot.z).length() > 0.4 or absf(on_mesh.y - spot.y) > 0.8:
				continue
			var ray := PhysicsRayQueryParameters3D.create(knee, on_mesh, WORLD_MASK)  # catches walls, curbs, ledges
			if not space.intersect_ray(ray).is_empty():
				continue
			_dodge_target = spot
			_dodge_left = float(def.get("dodge_max_seconds", 1.0))
			return
		return


func _shoot(target: Node3D) -> void:
	if _mag <= 0:
		_reload_left = RELOAD_TIME
		bark("reload")
		return
	_mag -= 1
	var eye := eye_position()
	var aim: Vector3 = target.global_position + Vector3.UP * 1.1
	var spread := tan(deg_to_rad(float(def.aim_spread_degrees)))
	var dir := ((aim - eye).normalized() + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()
	if _combat.host_fire(self, _gun, eye, dir, float(_clock.tick), false):
		if randf() < 0.6:
			bark("kill")


func _perceive() -> void:
	var space := get_world_3d().direct_space_state
	var eye := eye_position()
	var best: Node3D = null
	var best_dist := float(def.sight_range)
	for t in get_tree().get_nodes_in_group("hittable"):
		if t.team != &"zombies" or t.health.is_dead():
			continue
		var d: float = global_position.distance_to(t.global_position)
		if d > best_dist:
			continue
		var query := PhysicsRayQueryParameters3D.create(eye, t.global_position + Vector3.UP * 1.2, WORLD_MASK)
		if not space.intersect_ray(query).is_empty():
			continue
		best = t
		best_dist = d
	_enemy = best

	_leader = null
	var lead_dist := INF
	for p in get_tree().get_nodes_in_group("players"):
		if p == self or p.peer_id <= 0:
			continue
		var downed: bool = p.life.is_downed()
		if downed and not _known_downed.has(p.peer_id):
			bark("player_downed")
		if downed:
			_known_downed[p.peer_id] = true
		else:
			_known_downed.erase(p.peer_id)
		if p.health.is_dead():
			continue
		var d: float = global_position.distance_to(p.global_position)
		if d < lead_dist:
			lead_dist = d
			_leader = p


func _teleport_near(leader: Node3D) -> void:
	var behind: Vector3 = leader.global_position + leader.global_basis.z * 2.0
	var on_mesh := NavigationServer3D.map_get_closest_point(nav.get_navigation_map(), behind)
	global_position = on_mesh if on_mesh.distance_to(behind) < 3.0 else behind  # navmesh may not be baked yet
	velocity = Vector3.ZERO
	_nav_target = Vector3.INF


func _move(delta: float, horizontal: Vector3, face: Vector3) -> void:
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	move_and_slide()
	face.y = 0.0
	if face.length_squared() > 0.0001:
		rotation.y = rotate_toward(rotation.y, atan2(-face.x, -face.z), float(def.get("turn_speed", 8.0)) * delta)


func _publish() -> void:
	_history.record(_clock.tick, global_position, HEIGHT)
	net_position = global_position
	net_yaw = rotation.y


func _on_downed(_attacker_peer: int) -> void:
	if multiplayer.is_server():
		life.host_go_down()
		bark("downed")


func _on_get_up(context: String) -> void:
	health.current = float(def.get("revive_health", 60.0))
	life.host_set_alive()
	bark(context)


func _on_damaged(_amount: float, attacker_peer: int) -> void:
	if attacker_peer > 0 and not health.is_dead():
		bark("friendly_fire")


# --- visuals (all peers) -------------------------------------------------------------

func _on_snapshot() -> void:
	_snapshots.push(Time.get_ticks_msec() / 1000.0, net_position, net_yaw)


func _update_life_visuals() -> void:
	var state: int = life.net_state
	if state == _shown_life_state:
		return
	_shown_life_state = state
	collider.set_deferred("disabled", state != LifeState.ALIVE)
