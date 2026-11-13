# Player — one co-op player body.
#   Host:          simulates every player from their intents on the fixed physics tick (authoritative),
#                  runs their weapons (WeaponHolder.host_step) and records their hit capsule history.
#   Owning client: sends intents (move, look, buttons, view tick) each tick, predicts its own movement,
#                  and applies the host's correction using the acknowledged intent sequence number.
#   Other clients: interpolate this player NetClock.INTERP_DELAY behind the newest host snapshot.
# Snapshots travel through the child MultiplayerSynchronizer ("Sync") as net_* properties,
# plus Health:current and Weapons:net_* (on change).
# Hittable interface: health, team, hit_radius, hit_capsule_at(tick).
# Also: carries an InventoryHolder (overweight slows movement, D-021) and, for the local player, finds the
# loot container under the crosshair (10x/sec) and opens it on E. Hunger/thirst live in "Needs" (low = no
# sprint) and timed item use in "ItemUse" (D-046); the host ticks both. Water (D-047): a ray against the water
# surface colliders (layer 32) gives the depth at the feet; wading slows, swimming floats (no sprint, no firing).
# Depends on: MovementRules, CombatRules, CarryRules, DataLoader, NetClock, Health, WeaponHolder, LifeState,
#             InventoryHolder, Viewmodel, CharacterAnimator (Body: other players see an animated survivor model,
#             D-045), data/tuning/player_movement.json, combat.json, inventory.json, data/art/character_models.json.
extends CharacterBody3D

const TUNING_PATH := "res://data/tuning/player_movement.json"
const FLAG_JUMP := 1
const FLAG_SPRINT := 2
const FLAG_CROUCH := 4
const FLAG_INTERACT := 64             # held: revive a downed teammate in range
const ALL_FLAGS := 127                # movement + WeaponHolder FIRE/RELOAD/SLOT2 + INTERACT
const DOWNED_EYE_HEIGHT := 0.45
const INTERACT_MASK := 9              # world + interactables (layer 4); containers are on both
const LOOK_INTERVAL := 0.1
const WATER_MASK := 32
const PITCH_LIMIT := 1.5              # radians, ~86 degrees
const INTERP_DELAY := NetClock.INTERP_DELAY
const SNAP_BUFFER := 16               # remote snapshot ring size
const HISTORY_SIZE := 128             # client prediction history ring (ticks)
const INTENT_QUEUE_SIZE := 8          # host-side buffered intents per player
const MAX_INTENTS_PER_TICK := 2       # host cap so a client can't move faster than real time
const CORRECTION_EPSILON := 0.05      # metres of prediction error ignored

static var tuning: Dictionary = {}

# Replicated host -> clients by $Sync.
var net_position := Vector3.ZERO
var net_yaw := 0.0
var net_pitch := 0.0
var net_crouched := false
var net_ack_seq := 0

var peer_id := 1
var is_local := false
var yaw := 0.0
var pitch := 0.0
var crouched := false
var selected_slot := 0
var team := &"players"
var hit_radius := 0.35

var _gravity := 9.8
var water := MovementRules.Water.DRY
var _clock: NetClock
var _hit_history := PositionHistory.new()
var _spawn_point := Vector3.ZERO
var _shown_life_state := -1
var _revive_range := 2.0
var _carry: Dictionary = {}
var looked_container: Node = null  # local player: loot container under the crosshair, in reach
var looked_talkable: Node = null   # local player: Bonk/Evan (group "talkable") under the crosshair, in reach
var looked_pickup := 0             # local player: id of the dropped item (WorldDrops) under the crosshair, 0 = none
var looked_workbench: Node = null  # local player: the crafting bench (group "workbenches") under the crosshair
var looked_course_box: Node = null  # local player: a disc golf course box (group "course_boxes", D-069) under the crosshair
var looked_sport_spot: Node = null  # local player: a Drop Zone bay / putting start / court post (group "sport_spots", D-074)
var _look_timer := 0.0

# Owning client: prediction history, indexed by seq % HISTORY_SIZE.
var _seq := 0
var _history := PackedVector3Array()

# Host: ring buffer of received intents (parallel arrays, no per-tick allocation).
var _q_move := PackedVector2Array()
var _q_flags := PackedInt32Array()
var _q_yaw := PackedFloat32Array()
var _q_pitch := PackedFloat32Array()
var _q_view := PackedFloat64Array()
var _q_seq := PackedInt32Array()
var _q_next := 0
var _q_count := 0
var _last_queued_seq := 0
var _last_processed_seq := 0

# Remote clients: ring buffer of snapshots, _s_newest = index of latest.
var _s_time := PackedFloat64Array()
var _s_pos := PackedVector3Array()
var _s_yaw := PackedFloat32Array()
var _s_pitch := PackedFloat32Array()
var _s_newest := 0
var _s_count := 0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var viewmodel: Node3D = $Head/Camera3D/Viewmodel
@onready var body: CharacterAnimator = $Body
@onready var collider: CollisionShape3D = $Collider
@onready var sync: MultiplayerSynchronizer = $Sync
@onready var health: Health = $Health
@onready var weapons: WeaponHolder = $Weapons
@onready var life: LifeState = $Life
@onready var inventory: InventoryHolder = $Inventory
@onready var needs: PlayerNeeds = $Needs
@onready var item_use: ItemUse = $ItemUse
@onready var effects: ActiveEffects = $Effects
@onready var meepo: MeepoRider = $Meepo
@onready var disc: DiscThrower = $Disc
@onready var sport: SportInput = $Sport

var riding: bool:  # on the Meepo (D-057)
	get:
		return meepo.net_riding


func _enter_tree() -> void:
	peer_id = name.to_int()


func _ready() -> void:
	if tuning.is_empty():
		tuning = DataLoader.load_validated(TUNING_PATH, MovementRules.SCHEMA)
	if tuning.is_empty():
		set_physics_process(false)
		return
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
	_clock = get_tree().get_first_node_in_group("net_clock")
	is_local = peer_id == multiplayer.get_unique_id()
	add_to_group("hittable")
	add_to_group("players")
	if is_local:
		add_to_group("local_player")
	camera.current = is_local
	body.visible = not is_local
	viewmodel.visible = is_local
	var model := _model_id()
	if is_local:
		viewmodel.set_arms_model(model)
	else:
		body.set_model(model)
	viewmodel.show_slot(0)
	weapons.viewmodel = viewmodel
	weapons.inventory = inventory
	_carry = CarryRules.load_tuning()

	var combat_tuning := CombatRules.load_tuning()
	health.max_health = combat_tuning.get("player_max_health", 100.0)
	_revive_range = combat_tuning.get("revive_range", 2.0)

	_history.resize(HISTORY_SIZE)
	_q_move.resize(INTENT_QUEUE_SIZE)
	_q_flags.resize(INTENT_QUEUE_SIZE)
	_q_yaw.resize(INTENT_QUEUE_SIZE)
	_q_pitch.resize(INTENT_QUEUE_SIZE)
	_q_view.resize(INTENT_QUEUE_SIZE)
	_q_seq.resize(INTENT_QUEUE_SIZE)
	_s_time.resize(SNAP_BUFFER)
	_s_pos.resize(SNAP_BUFFER)
	_s_yaw.resize(SNAP_BUFFER)
	_s_pitch.resize(SNAP_BUFFER)

	_set_crouched(false)
	if multiplayer.is_server():
		health.reset()
		health.died.connect(_on_died)
		life.revived.connect(_on_revived)
		life.bled_out.connect(_on_bled_out)
		_spawn_point = global_position
		_give_starting_items(combat_tuning)
	else:
		global_position = net_position
		sync.synchronized.connect(_on_snapshot)


func _unhandled_input(event: InputEvent) -> void:
	if not is_local or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action_pressed("interact"):
		_try_open_container()  # an open loot window consumes E first, so this never reopens it
		return
	var motion := event as InputEventMouseMotion
	if motion:
		var sens: float = tuning.mouse_sensitivity
		yaw = wrapf(yaw - motion.relative.x * sens, -PI, PI)
		pitch = clampf(pitch - motion.relative.y * sens, -PITCH_LIMIT, PITCH_LIMIT)
		rotation.y = yaw
		head.rotation.x = pitch


func _physics_process(delta: float) -> void:
	var dead := health.is_dead()
	if multiplayer.is_server():
		if is_local:
			var flags := _read_local_flags()
			if not dead:
				_simulate(_read_local_move(), flags, yaw, pitch)
			weapons.host_step(_dry_flags(flags), yaw, pitch, float(_clock.tick), delta, dead)
			_host_try_revive(flags, delta)
		else:
			_process_queued_intents(delta)
		life.host_tick(delta)
		needs.host_tick(delta, life.net_state == LifeState.ALIVE)
		item_use.host_tick(delta)
		effects.host_tick(delta, life.net_state == LifeState.ALIVE)
		meepo.host_tick(delta)
		_hit_history.record(_clock.tick, global_position, _current_height())
		net_position = global_position
		net_yaw = yaw
		net_pitch = pitch
		net_crouched = crouched
		net_ack_seq = _last_processed_seq
	elif is_local:
		var move := Vector2.ZERO if dead else _read_local_move()
		var flags := _read_local_flags() if not dead else (WeaponHolder.FLAG_SLOT2 if selected_slot == 1 else 0)
		_seq += 1
		_send_intent.rpc_id(1, _seq, move, flags, yaw, pitch, _clock.view_tick())
		if not dead:
			_simulate(move, flags, yaw, pitch)
		_history[_seq % HISTORY_SIZE] = global_position
		weapons.client_step(_dry_flags(flags), selected_slot, delta, dead)
	else:
		_interpolate_remote()
	if is_local:
		_update_look(delta)
	else:
		body.set_weapon_slot(weapons.net_slot)
		body.riding = meepo.net_riding
		body.update(delta, false, life.net_state != LifeState.ALIVE, health.current, weapons.net_slot == 0, crouched)
	_update_life_visuals()


# Survivor model for this player (by peer id until character creation exists).
func _model_id() -> String:
	var list: Array = DataLoader.load_json(CharacterAnimator.DATA_PATH).get("player_models", [])
	return str(list[absi(peer_id) % list.size()]) if not list.is_empty() else ""


# --- hittable ------------------------------------------------------------------

func hit_capsule_at(tick: float) -> Vector4:
	var s := _hit_history.sample(tick)
	if s.w < 0.0:
		return Vector4(global_position.x, global_position.y, global_position.z, _current_height())
	return s


func eye_position() -> Vector3:
	return head.global_position


func muzzle_position() -> Vector3:
	return viewmodel.muzzle.global_position


func _current_height() -> float:
	return tuning.crouch_height if crouched else tuning.stand_height


# --- downed / revive / respawn (D-015) ------------------------------------------------

func _update_life_visuals() -> void:
	var state := life.net_state
	if state == _shown_life_state:
		return
	_shown_life_state = state
	var alive := state == LifeState.ALIVE
	collider.set_deferred("disabled", not alive)
	body.visible = state != LifeState.DEAD and not is_local
	if is_local:
		viewmodel.visible = alive
	if state == LifeState.DOWNED:
		head.position.y = DOWNED_EYE_HEIGHT
	else:
		_set_crouched(crouched)


# Host: a living player holding interact revives the nearest downed teammate in range.
func _host_try_revive(flags: int, delta: float) -> void:
	if (flags & FLAG_INTERACT) == 0 or health.is_dead():
		return
	var best: Node = null
	var best_dist := _revive_range
	for p in get_tree().get_nodes_in_group("players"):
		if p == self or not p.life.is_downed():
			continue
		var d := global_position.distance_to(p.global_position)
		if d <= best_dist:
			best = p
			best_dist = d
	if best:
		best.life.host_revive_step(delta)


func _on_died(_attacker_peer: int) -> void:
	life.host_go_down()


func _on_revived() -> void:
	health.current = CombatRules.load_tuning().get("revive_health", 30.0)
	life.host_set_alive()


# --- inventory / looting ------------------------------------------------------------

func _give_starting_items(combat_tuning: Dictionary) -> void:
	for id in combat_tuning.get("loadout", []):
		inventory.host_add(str(id), 1)
	var start: Dictionary = _carry.get("starting_items", {})
	for id: String in start:
		inventory.host_add(id, int(start[id]))


func _update_look(delta: float) -> void:
	_look_timer -= delta
	if _look_timer > 0.0:
		return
	_look_timer = LOOK_INTERVAL
	looked_container = null
	looked_talkable = null
	looked_pickup = 0
	looked_workbench = null
	looked_course_box = null
	looked_sport_spot = null
	if health.is_dead():
		return
	var from := camera.global_position
	var to := from - camera.global_basis.z * float(_carry.get("interact_range", 2.5))
	var query := PhysicsRayQueryParameters3D.create(from, to, INTERACT_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider is Node:
		if hit.collider.is_in_group("loot_containers"):
			looked_container = hit.collider
		elif hit.collider.is_in_group("talkable") and not ("health" in hit.collider and hit.collider.health.is_dead()):
			looked_talkable = hit.collider
		elif hit.collider.is_in_group("pickups"):
			looked_pickup = int(hit.collider.get_meta("drop_id", 0))
		elif hit.collider.is_in_group("workbenches"):
			looked_workbench = hit.collider
		elif hit.collider.is_in_group("course_boxes"):
			looked_course_box = hit.collider
		elif hit.collider.is_in_group("sport_spots"):
			looked_sport_spot = hit.collider


# E: reviving a downed teammate in range wins; otherwise open the container / talk to the NPC / pick up the dropped
# item / use the workbench / start a disc golf round at the course box / use a Drop Zone spot under the crosshair.
func _try_open_container() -> void:
	if health.is_dead() or _downed_teammate_near():
		return
	if looked_container:
		looked_container.request_open.rpc_id(1)
	elif looked_talkable:
		var dialogue := get_tree().get_first_node_in_group("dialogue")
		if dialogue:
			dialogue.request_talk.rpc_id(1, looked_talkable.get_path())
	elif looked_pickup > 0:
		var drops := get_tree().get_first_node_in_group("world_drops")
		if drops:
			drops.request_pickup.rpc_id(1, looked_pickup)
	elif looked_workbench:
		var ui := get_tree().get_first_node_in_group("crafting_ui")
		if ui:
			ui.open(looked_workbench)
	elif looked_course_box:
		var dg := get_tree().get_first_node_in_group("disc_golf")
		if dg:
			dg.request_start.rpc_id(1, str(looked_course_box.get_meta("course_id", "")))
	elif looked_sport_spot:
		var target: Node = looked_sport_spot.get_meta("target")
		target.request_use.rpc_id(1, int(looked_sport_spot.get_meta("index", 0)))


func _downed_teammate_near() -> bool:
	for p in get_tree().get_nodes_in_group("players"):
		if p != self and p.life.is_downed() and global_position.distance_to(p.global_position) <= _revive_range:
			return true
	return false


func _on_bled_out() -> void:
	get_tree().create_timer(CombatRules.load_tuning().get("respawn_seconds", 5.0)).timeout.connect(_respawn)


func _respawn() -> void:
	global_position = _spawn_point
	velocity = Vector3.ZERO
	health.reset()
	needs.host_respawned()
	effects.host_clear()
	life.host_set_alive()  # inventory and magazines are kept (D-027)


# --- shared simulation -------------------------------------------------------

func _simulate(move: Vector2, flags: int, look_yaw: float, look_pitch: float) -> void:
	yaw = look_yaw
	pitch = clampf(look_pitch, -PITCH_LIMIT, PITCH_LIMIT)
	rotation.y = yaw
	head.rotation.x = pitch
	var depth := _water_depth()
	water = MovementRules.water_mode(depth, tuning)
	var dt := get_physics_process_delta_time()
	if water == MovementRules.Water.SWIM:
		if crouched and _has_headroom():
			_set_crouched(false)
		velocity = MovementRules.swim_velocity(velocity, MovementRules.wish_direction(move, yaw),
			(flags & FLAG_JUMP) != 0, (flags & FLAG_CROUCH) != 0, depth, tuning, dt)
		move_and_slide()
		return
	var want_crouch := (flags & FLAG_CROUCH) != 0 and not meepo.net_riding
	if want_crouch != crouched and (want_crouch or _has_headroom()):
		_set_crouched(want_crouch)
	var carried := inventory.weight
	var wading := water == MovementRules.Water.WADE
	velocity = MovementRules.step_velocity(
		velocity, MovementRules.wish_direction(move, yaw),
		(flags & FLAG_SPRINT) != 0 and not wading and CarryRules.can_sprint(carried, _carry) and needs.can_sprint(), crouched,
		(flags & FLAG_JUMP) != 0, is_on_floor(), _gravity, meepo.movement(tuning) if meepo.net_riding else tuning, dt,
		CarryRules.speed_multiplier(carried, _carry) * (float(tuning.wade_speed_mult) if wading else 1.0) * effects.speed_mult())
	move_and_slide()


# Metres of water above the feet (0 when dry), from the water surface colliders.
func _water_depth() -> float:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 6.0, global_position, WATER_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y - global_position.y if not hit.is_empty() else 0.0


# No firing while swimming or riding the Meepo.
func _dry_flags(flags: int) -> int:
	return flags & ~WeaponHolder.FLAG_FIRE if water == MovementRules.Water.SWIM or meepo.net_riding else flags


func _set_crouched(value: bool) -> void:
	crouched = value
	var stand: float = tuning.stand_height
	var height: float = tuning.crouch_height if value else stand
	(collider.shape as CapsuleShape3D).height = height
	collider.position.y = height * 0.5
	head.position.y = height - float(tuning.eye_offset)


func _has_headroom() -> bool:
	var rise: float = tuning.stand_height - tuning.crouch_height
	return not test_move(global_transform, Vector3.UP * rise)


# --- owning client -------------------------------------------------------------

func _read_local_move() -> Vector2:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


func _read_local_flags() -> int:
	var flags := 0
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Input.is_action_just_pressed("weapon_1"):
			_select_slot(0)
		if Input.is_action_just_pressed("weapon_2"):
			_select_slot(1)
		if Input.is_action_just_pressed("jump"):
			flags |= FLAG_JUMP
		if Input.is_action_pressed("sprint"):
			flags |= FLAG_SPRINT
		if Input.is_action_pressed("crouch"):
			flags |= FLAG_CROUCH
		if Input.is_action_pressed("fire") and not disc.active and sport.mode == "":  # disc / Drop Zone game: left click is theirs
			flags |= WeaponHolder.FLAG_FIRE
		if Input.is_action_pressed("reload"):
			flags |= WeaponHolder.FLAG_RELOAD
		if Input.is_action_pressed("interact"):
			flags |= FLAG_INTERACT
	if selected_slot == 1:
		flags |= WeaponHolder.FLAG_SLOT2
	return flags


func _select_slot(slot: int) -> void:
	if slot == selected_slot or weapons.weapon_in_slot(slot).is_empty():
		return
	selected_slot = slot
	viewmodel.show_slot(slot)


func _on_snapshot() -> void:
	if is_local:
		_reconcile()
	else:
		_s_newest = (_s_newest + 1) % SNAP_BUFFER
		_s_count = mini(_s_count + 1, SNAP_BUFFER)
		_s_time[_s_newest] = Time.get_ticks_msec() / 1000.0
		_s_pos[_s_newest] = net_position
		_s_yaw[_s_newest] = net_yaw
		_s_pitch[_s_newest] = net_pitch
		if net_crouched != crouched:
			_set_crouched(net_crouched)


# Compare where the host put us after intent N with where we predicted we'd be after intent N,
# then shift the present (and the remaining history) by the difference.
func _reconcile() -> void:
	if net_ack_seq <= 0 or _seq - net_ack_seq >= HISTORY_SIZE:
		return
	var error := net_position - _history[net_ack_seq % HISTORY_SIZE]
	if error.length() <= CORRECTION_EPSILON:
		return
	global_position += error
	for i in HISTORY_SIZE:
		_history[i] += error


# --- host ----------------------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _send_intent(seq: int, move: Vector2, flags: int, look_yaw: float, look_pitch: float, view_tick: float) -> void:
	# Never trust the client: only its own body, only newer intents, sane values.
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != peer_id:
		return
	if seq <= _last_queued_seq or not move.is_finite() or not is_finite(look_yaw) \
			or not is_finite(look_pitch) or not is_finite(view_tick):
		return
	_last_queued_seq = seq
	if move.length_squared() > 1.0:
		move = move.normalized()
	_q_move[_q_next] = move
	_q_flags[_q_next] = flags & ALL_FLAGS
	_q_yaw[_q_next] = wrapf(look_yaw, -PI, PI)
	_q_pitch[_q_next] = look_pitch
	_q_view[_q_next] = view_tick
	_q_seq[_q_next] = seq
	_q_next = (_q_next + 1) % INTENT_QUEUE_SIZE
	_q_count = mini(_q_count + 1, INTENT_QUEUE_SIZE)


func _process_queued_intents(delta: float) -> void:
	var n := mini(_q_count, MAX_INTENTS_PER_TICK)
	for i in n:
		var idx := (_q_next - _q_count + INTENT_QUEUE_SIZE) % INTENT_QUEUE_SIZE
		var dead := health.is_dead()
		if not dead:
			_simulate(_q_move[idx], _q_flags[idx], _q_yaw[idx], _q_pitch[idx])
		weapons.host_step(_dry_flags(_q_flags[idx]), _q_yaw[idx], clampf(_q_pitch[idx], -PITCH_LIMIT, PITCH_LIMIT),
			_q_view[idx], delta, dead)
		_host_try_revive(_q_flags[idx], delta)
		_last_processed_seq = _q_seq[idx]
		_q_count -= 1


# --- remote view -----------------------------------------------------------------

func _interpolate_remote() -> void:
	if _s_count == 0:
		return
	var render_time := Time.get_ticks_msec() / 1000.0 - INTERP_DELAY
	var newer := _s_newest
	for i in range(1, _s_count):
		var older := (_s_newest - i + SNAP_BUFFER) % SNAP_BUFFER
		if _s_time[older] <= render_time:
			var span := _s_time[newer] - _s_time[older]
			var t := 1.0 if span <= 0.0 else clampf((render_time - _s_time[older]) / span, 0.0, 1.0)
			_apply_view(_s_pos[older].lerp(_s_pos[newer], t),
				lerp_angle(_s_yaw[older], _s_yaw[newer], t),
				lerpf(_s_pitch[older], _s_pitch[newer], t))
			return
		newer = older
	_apply_view(_s_pos[newer], _s_yaw[newer], _s_pitch[newer])


func _apply_view(pos: Vector3, view_yaw: float, view_pitch: float) -> void:
	global_position = pos
	rotation.y = view_yaw
	head.rotation.x = view_pitch
