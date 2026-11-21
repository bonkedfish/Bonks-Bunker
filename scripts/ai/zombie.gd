# Zombie — one pooled zombie body.
#   Host:    perception (sight cone + line of sight at perception_hz; noise via hear()), ZombieBrain decisions,
#            NavigationAgent3D movement, swipe resolution, and hit-capsule history for lag compensation.
#   Clients: render only, interpolated NetClock.INTERP_DELAY behind (same as remote players).
#   All peers: the Body is a CharacterAnimator (D-045) showing one of the enemy's "models" (picked by pool index),
#            animated from movement, net_attacking, death and health drops.
# Pooled by ZombieDirector (street zombies) and LairDirector (placed enemies + bosses, D-055): activate()/deactivate()
# instead of instancing/freeing. Hittable only while active. The enemy type can change per activation: the host
# sets `net_enemy` (replicated) and every peer applies that definition's look (model, scale, tint, boss nameplate).
# Optional definition extras: "ranged" (stops at attack_range and fires a hitscan shot through CombatWorld; swipes
# instead when the target is inside attack_reach), "enrage" (faster + shorter cooldown below a health fraction),
# "bark_prefix" (aggro / enrage / death lines as subtitles), "boss" (group "bosses" for the HUD bar),
# "faction" (D-060: `team`; bodies of another faction are targets like players, so raiders and zombies fight),
# "weapon_slot" (shows that prop, e.g. a raider brute's bat, without the gun animations).
# D-100 open-world types: "armor" (armor_mult(): body shots mostly blocked, head and melee get through - Riot Cop),
# "burst" (the attack is bursting: on its swing or on death it damages players and other bodies around it, then it's
# dead - Bloater), "hearing_mult" + "rush_noise" (hears gunfire farther and runs to it - Runner).
# Safe zones (D-101, SafeZones group "safe_zones"): a body ignores players and noises inside a zone, so a chase ends
# at the edge, and a body that finds itself inside walks back out.
# Scare features (D-114, ZombieScare - only for the enemy IDs in data/tuning/scare.json): `net_style` (replicated
# seed) gives each activation its traits on every peer (stumbler, crawler, screamer, feigner, lurker, stalker,
# flanker, twitchy); `net_pose` (replicated) is NORMAL / DOWN (a feigner lying there) / RISE (getting back up).
# The spotting scream is an RPC (clip + sound + camera shake near it) and calls other zombies nearby through hear().
# Presentation on every peer: Twitch (bone jerks), EyeShine (eyes catching the light at night), a snarl on swings.
# Depends on: ZombieBrain, ZombieScare, Twitch, EyeShine, ZombieTypeRules, EnemyDB, CombatRules, CombatWorld, DialogueDB, PositionHistory,
# SnapshotBuffer, NetClock, Health, CharacterAnimator, Sfx.
extends CharacterBody3D

const HEIGHT := 1.8
const EYE_HEIGHT := 1.6
const WORLD_MASK := 1
const RETARGET_DISTANCE := 0.75
const SWIPE_ARC_DEGREES := 100.0
const BURST_COLOR := Color(0.55, 0.75, 0.15, 0.55)

static var frozen := false  # host: every zombie holds still (ace replay, D-076; set by AceReplay)

var team := &"zombies"
var hit_radius := 0.35
var peer_id := 0  # not a player
var display_name := "Zombie"
var def: Dictionary:  # talk-style interface for DialogueDirector.host_bark (subtitle_range)
	get:
		return _def

# Replicated host -> clients.
var net_enemy := "":  # enemy ID (EnemyDB) this body currently is
	set(value):
		if value != net_enemy:
			net_enemy = value
			if is_node_ready() and value != "":
				_apply_def(EnemyDB.get_enemy(value))
var net_active := false
var net_position := Vector3.ZERO
var net_yaw := 0.0
var net_attacking := false
var net_style := 0:  # scare trait seed for this activation (D-114)
	set(value):
		if value != net_style:
			net_style = value
			if is_node_ready() and _scare:
				_scare.set_style(value)
				_apply_scare_look()
var net_pose := 0:  # ZombieScare.Pose
	set(value):
		if value != net_pose:
			net_pose = value
			if is_node_ready() and value == ZombieScare.Pose.RISE:
				body.one_shot("stand_up", float(ZombieScare.tuning.feign.rise_s))

var brain: ZombieBrain
var _def: Dictionary
var _clock: NetClock
var _history := PositionHistory.new()
var _snapshots := SnapshotBuffer.new()
var _gravity := 9.8
var _perceive_period := 0.2
var _perceive_timer := 0.0
var _corpse_seconds := 1.0
var _target: Node = null
var _sees_target := false
var _last_seen := Vector3.ZERO
var _heard := false
var _noise_pos := Vector3.ZERO
var _home := Vector3.ZERO
var _wander_wait := 0.0
var _shown_active := false
var _height := HEIGHT
var _enraged := false
var _barked_aggro := false
var _burst_done := false
var _life := 0  # host: bumped on every activation, so a corpse timer from an earlier life can't despawn a reused body
var _combat: Node
var _dialogue: Node
var _plate: Label3D
var _safe: Node
var _scare: ZombieScare  # null for enemy IDs without scare traits
var _twitch: Twitch
var _eyes: Node3D
var _eyes_skel: Skeleton3D
var _was_attacking := false
var _face_dir := Vector3.ZERO  # host: face this way this step (scare holds), ZERO = by movement

@onready var nav: NavigationAgent3D = $Nav
@onready var health: Health = $Health
@onready var collider: CollisionShape3D = $Collider
@onready var body: CharacterAnimator = $Body
@onready var sync: MultiplayerSynchronizer = $Sync


func _ready() -> void:
	_clock = get_tree().get_first_node_in_group("net_clock")
	_combat = get_tree().get_first_node_in_group("combat_world")
	_dialogue = get_tree().get_first_node_in_group("dialogue")
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
	sync.synchronized.connect(_on_snapshot)
	health.died.connect(_on_died)
	health.downed.connect(_on_downed)
	_apply_active(false)
	if net_enemy != "" and _def.is_empty():
		_apply_def(EnemyDB.get_enemy(net_enemy))


# Called by ZombieDirector right after add_child, on every peer.
func setup(enemy_def: Dictionary, perception_hz: float, corpse_seconds: float) -> void:
	_perceive_period = 1.0 / maxf(perception_hz, 0.1)
	_corpse_seconds = corpse_seconds
	if enemy_def != _def:  # _ready may already have applied it from a preset net_enemy
		_apply_def(enemy_def)


# Every peer: become this enemy definition (stats on the host, look everywhere).
func _apply_def(enemy_def: Dictionary) -> void:
	if enemy_def.is_empty():
		return
	_def = enemy_def
	brain = ZombieBrain.new(enemy_def)
	health.max_health = enemy_def.max_health
	display_name = str(enemy_def.name)
	team = StringName(str(enemy_def.get("faction", "zombies")))
	_scare = ZombieScare.make(net_enemy)
	if _scare:
		_scare.set_style(net_style)
	var s := float(enemy_def.get("scale", 1.0))
	_height = HEIGHT * s
	hit_radius = 0.35 * s
	body.scale = Vector3.ONE * s
	var models: Array = enemy_def.get("models", [])
	if not models.is_empty() and body.set_model(str(models[str(name).to_int() % models.size()])):
		var slot := int(enemy_def.get("weapon_slot", 0 if bool(enemy_def.get("armed", false)) else -1))
		if slot >= 0:
			body.set_weapon_slot(slot)
		if enemy_def.has("tint"):
			var t: Array = enemy_def.tint
			var overlay := StandardMaterial3D.new()
			overlay.albedo_color = Color(t[0], t[1], t[2], t[3])
			overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			for mi: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
				mi.material_overlay = overlay
		_apply_scare_look()
	var boss := bool(enemy_def.get("boss", false))
	if boss and _plate == null:
		_plate = Label3D.new()
		_plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_plate.pixel_size = 0.005
		_plate.font_size = 48
		_plate.outline_size = 10
		_plate.modulate = Color(1.0, 0.45, 0.35)
		add_child(_plate)
	if _plate:
		_plate.visible = boss
		_plate.text = display_name
		_plate.position = Vector3(0, _height + 0.4, 0)


# --- host: pool lifecycle --------------------------------------------------------

func activate(pos: Vector3, yaw := 0.0) -> void:
	global_position = pos
	rotation.y = yaw
	_home = pos
	velocity = Vector3.ZERO
	health.reset()
	brain.reset()
	_enraged = false
	_barked_aggro = false
	_burst_done = false
	_life += 1
	health.down_once = false
	net_pose = ZombieScare.Pose.NORMAL
	net_style = randi() & 0x7fffffff
	_snapshots.clear()
	_history.clear()  # else rewound shots could still hit where this pooled body stood last time
	_target = null
	_sees_target = false
	_heard = false
	_perceive_timer = randf() * _perceive_period  # stagger perception across zombies
	_wander_wait = randf() * float(_def.wander_pause)
	nav.target_position = pos
	net_position = pos
	net_yaw = rotation.y
	net_attacking = false
	net_active = true
	add_to_group("hittable")
	if bool(_def.get("boss", false)):
		add_to_group("bosses")
	_apply_active(true)
	if _scare:
		_scare.host_activate(self)


func deactivate() -> void:
	net_active = false
	net_attacking = false
	remove_from_group("hittable")
	if is_in_group("bosses"):
		remove_from_group("bosses")
	_apply_active(false)


func hear(pos: Vector3) -> void:
	if not net_active or health.is_dead():
		return
	if brain.state == ZombieBrain.State.CHASE or brain.state == ZombieBrain.State.ATTACK:
		return
	if _safe == null:
		_safe = get_tree().get_first_node_in_group("safe_zones")  # Main adds it after the pools are built
	if _safe and _safe.contains(pos):
		return
	_noise_pos = pos
	_heard = true


# Share of a hit that gets through this body's armor (1 = no armor). hit_frac: 0 feet .. 1 top of the head.
func armor_mult(hit_frac: float, melee: bool) -> float:
	return ZombieTypeRules.armor_mult(_def.get("armor", {}), hit_frac, melee)


# Noise radius multiplier for this type (Runners hear gunfire from farther away).
func hearing_mult() -> float:
	return float(_def.get("hearing_mult", 1.0))


func hit_capsule_at(tick: float) -> Vector4:
	var s := _history.sample(tick)
	if s.w < 0.0:
		return Vector4(global_position.x, global_position.y, global_position.z, _hit_height())
	return s


# Standing height, or lower for a crawler / a body lying down.
func _hit_height() -> float:
	return _scare.height(_height, net_pose) if _scare else _height


func has_scare() -> bool:
	return _scare != null


# --- per tick --------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		if net_active and not health.is_dead() and not frozen:
			_host_step(delta)
	elif net_active and not _snapshots.is_empty():
		var s := _snapshots.sample(Time.get_ticks_msec() / 1000.0 - NetClock.INTERP_DELAY)
		global_position = Vector3(s.x, s.y, s.z)
		rotation.y = s.w
	_update_visuals(delta)


func _host_step(delta: float) -> void:
	_perceive_timer -= delta
	if _perceive_timer <= 0.0:
		_perceive_timer += _perceive_period
		_perceive()

	var target_ok := _sees_target and is_instance_valid(_target)
	var target_dist := global_position.distance_to(_target.global_position) if target_ok else INF
	var heard_now := _heard
	_heard = false
	brain.tick(delta, target_ok, target_dist, heard_now, nav.is_navigation_finished())

	var enrage: Dictionary = _def.get("enrage", {})
	if not _enraged and not enrage.is_empty() and health.current <= health.max_health * float(enrage.get("below", 0.0)):
		_enraged = true
		brain.cooldown_mult = float(enrage.get("cooldown_mult", 1.0))
		_bark("enrage")
	if not _barked_aggro and brain.state == ZombieBrain.State.CHASE:
		_barked_aggro = true
		_bark("aggro")

	var mult := _scare.host_step(self, delta, target_ok, target_dist) if _scare else 1.0
	var busy := _scare != null and _scare.busy(net_pose)
	_face_dir = Vector3.ZERO
	if mult == 0.0 and net_pose == ZombieScare.Pose.NORMAL:
		if target_ok:
			_face_dir = _target.global_position - global_position  # screaming, stalking, lurking: watch you
		elif _scare and _scare.lurking:
			_face_dir = _scare.lurk_face
	var speed := float(_def.walk_speed) * mult
	match brain.state:
		ZombieBrain.State.CHASE:
			speed = float(_def.chase_speed) * (float(enrage.get("speed_mult", 1.0)) if _enraged else 1.0) * mult
			if target_ok and _scare:
				_set_destination(_scare.chase_point(self, _target, target_dist))
			else:
				_set_destination(_target.global_position if target_ok else _last_seen)
		ZombieBrain.State.INVESTIGATE:
			if bool(_def.get("rush_noise", false)):
				speed = float(_def.chase_speed) * mult
			if heard_now:
				_set_destination(_noise_pos)
		ZombieBrain.State.WANDER:
			if _scare and _scare.lurking:
				pass  # waiting at its wall
			elif nav.is_navigation_finished():
				_wander_wait -= delta
				if _wander_wait <= 0.0:
					_wander_wait = float(_def.wander_pause)
					_set_destination(_random_wander_point())
		ZombieBrain.State.ATTACK:
			speed = 0.0

	if brain.attack_landed and not busy:
		if _def.has("burst"):
			_burst()
			return
		if _def.has("ranged") and target_dist > float(_def.attack_reach):
			_resolve_shot()
		else:
			_resolve_swipe()
	_move(delta, speed)

	_history.record(_clock.tick, global_position, _hit_height())
	net_position = global_position
	net_yaw = rotation.y
	net_attacking = brain.state == ZombieBrain.State.ATTACK


func _perceive() -> void:
	if _safe == null:
		_safe = get_tree().get_first_node_in_group("safe_zones")
	if _safe and _safe.contains(global_position):  # wandered or was carried into a safe zone: walk back out
		_home = _safe.exit_point(global_position)
		brain.reset()
		_sees_target = false
		_set_destination(_home)
		return
	var eye := global_position + Vector3.UP * EYE_HEIGHT
	var forward := -global_basis.z
	var half_fov := deg_to_rad(float(_def.sight_fov_degrees)) * 0.5
	var close := float(_def.close_sense_range)
	var best: Node = null
	var best_dist := float(_def.sight_range)
	var space := get_world_3d().direct_space_state
	for group: StringName in [&"players", &"hittable"]:
		for p in get_tree().get_nodes_in_group(group):
			if p == self or p.health.is_dead():
				continue
			if group == &"hittable" and not ("net_enemy" in p and p.team != team):
				continue  # players were checked above; other enemy bodies only when they're another faction
			if group == &"players" and _safe and _safe.contains(p.global_position):
				continue  # nobody gets chased into a safe zone
			var to: Vector3 = p.global_position - global_position
			to.y = 0.0
			var d := to.length()
			if d > best_dist:
				continue
			if d > close and forward.angle_to(to) > half_fov:
				continue
			var their_eye: Vector3 = p.eye_position() if p.has_method("eye_position") else p.global_position + Vector3.UP * EYE_HEIGHT
			var query := PhysicsRayQueryParameters3D.create(eye, their_eye, WORLD_MASK)
			if not space.intersect_ray(query).is_empty():
				continue
			best = p
			best_dist = d
	_sees_target = best != null
	if best:
		_target = best
		_last_seen = best.global_position


func _resolve_swipe() -> void:
	if not is_instance_valid(_target) or _target.health.is_dead():
		return
	var eye := global_position + Vector3.UP * EYE_HEIGHT
	if CombatRules.melee_hits_capsule(eye, -global_basis.z, float(_def.attack_reach), SWIPE_ARC_DEGREES,
			_target.global_position, _target.hit_radius, HEIGHT):
		_target.health.apply_damage(float(_def.attack_damage), peer_id)


# Ranged enemies: one hitscan shot at the target's chest with some spread, through CombatWorld (tracer, noise,
# walls block it, never hits other zombies).
func _resolve_shot() -> void:
	if not is_instance_valid(_target) or _target.health.is_dead() or _combat == null:
		return
	var r: Dictionary = _def.ranged
	var eye := global_position + Vector3.UP * EYE_HEIGHT * (_height / HEIGHT)
	var dir: Vector3 = (_target.global_position + Vector3.UP * 1.0 - eye).normalized()
	var spread := tan(deg_to_rad(float(r.get("spread_degrees", 3.0))))
	dir = (dir + Vector3(randf_range(-spread, spread), randf_range(-spread, spread), randf_range(-spread, spread))).normalized()
	_combat.host_fire(self, r, eye, dir, float(_clock.tick), false)


# Host: a boss line as a subtitle for players nearby (lines: DialogueDB barks "<bark_prefix><context>").
func _bark(context: String) -> void:
	if not _def.has("bark_prefix") or _dialogue == null:
		return
	var lines := DialogueDB.barks(str(_def.bark_prefix) + context)
	if not lines.is_empty():
		_dialogue.host_bark(self, str(lines[randi() % lines.size()]))


func _move(delta: float, speed: float) -> void:
	var horizontal := Vector3.ZERO
	var face := Vector3.ZERO
	if speed > 0.0 and not nav.is_navigation_finished():
		var to := nav.get_next_path_position() - global_position
		to.y = 0.0
		if to.length_squared() > 0.0001:
			horizontal = to.normalized() * speed
			face = horizontal
	if brain.state == ZombieBrain.State.ATTACK and is_instance_valid(_target):
		face = _target.global_position - global_position
		face.y = 0.0
	elif _face_dir != Vector3.ZERO:
		face = Vector3(_face_dir.x, 0.0, _face_dir.z)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta
	move_and_slide()
	if face.length_squared() > 0.0001:
		rotation.y = rotate_toward(rotation.y, atan2(-face.x, -face.z), float(_def.turn_speed) * delta)


func _set_destination(pos: Vector3) -> void:
	if nav.target_position.distance_to(pos) > RETARGET_DISTANCE or nav.is_navigation_finished():
		nav.target_position = pos


func _random_wander_point() -> Vector3:
	var r := float(_def.wander_radius)
	var p := _home + Vector3(randf_range(-r, r), 0.0, randf_range(-r, r))
	if _safe and _safe.contains(p):
		p = _home
	return NavigationServer3D.map_get_closest_point(nav.get_navigation_map(), p)


# Host: a Bloater bursts - damage falls off with distance for every living player and body around it (zombies and
# raiders too), then it is dead. Runs once per activation, on its own swing or on its death (deferred, so a chain of
# bursts doesn't recurse inside Health.died).
func _burst() -> void:
	if _burst_done or not net_active:
		return
	_burst_done = true
	var b: Dictionary = _def.burst
	var centre := global_position + Vector3.UP * 0.9
	var seen := {}
	for group: StringName in [&"players", &"hittable"]:
		for t in get_tree().get_nodes_in_group(group):
			if t == self or seen.has(t) or t.health.is_dead():
				continue
			seen[t] = true
			var dmg := ZombieTypeRules.burst_damage(b, (t.global_position + Vector3.UP * 0.9).distance_to(centre))
			if dmg > 0.0:
				t.health.apply_damage(dmg, peer_id)
	_fx_burst.rpc(centre, float(b.radius_m))
	if not health.is_dead():
		health.apply_damage(health.current, peer_id)


@rpc("authority", "call_local", "unreliable")
func _fx_burst(at: Vector3, radius: float) -> void:
	Sfx.play_at("zombie_burst", at)
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BURST_COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = mat
	mi.mesh = sphere
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(mi)
	mi.global_position = at
	mi.scale = Vector3.ONE * 0.3
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE * radius * 0.8, 0.35).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.6)
	tw.chain().tween_callback(mi.queue_free)


# Host: the spotting scream - everyone near sees and hears it, and zombies within call_radius_m come running.
func host_scream() -> void:
	_fx_scream.rpc(global_position + Vector3.UP * _hit_height() * 0.85)
	var to: Vector3 = _target.global_position if is_instance_valid(_target) else global_position
	var r := float(ZombieScare.tuning.scream.call_radius_m)
	for n in get_tree().get_nodes_in_group("hittable"):
		if n != self and "net_enemy" in n and n.team == team and n.net_active \
				and n.global_position.distance_squared_to(global_position) < r * r:
			n.hear(to)


@rpc("authority", "call_local", "unreliable")
func _fx_scream(at: Vector3) -> void:
	body.one_shot("scream", float(ZombieScare.tuning.scream.seconds))
	Sfx.play_at("zombie_scream", at)
	var dread := get_tree().get_first_node_in_group("dread")
	if dread:
		dread.heard_scream(at)


func _on_downed() -> void:
	net_attacking = false
	if multiplayer.is_server() and _scare:
		_scare.host_downed(self)


func _on_died(_attacker_peer: int) -> void:
	net_attacking = false
	if multiplayer.is_server():
		if _def.has("burst") and not _burst_done:
			_burst.call_deferred()
		_bark("death")
		get_tree().create_timer(_corpse_seconds).timeout.connect(_corpse_gone.bind(_life))


func _corpse_gone(life: int) -> void:
	if life == _life:
		deactivate()


# --- visuals (all peers) -----------------------------------------------------------

func _on_snapshot() -> void:
	if net_active:
		_snapshots.push(Time.get_ticks_msec() / 1000.0, net_position, net_yaw)


func _update_visuals(delta: float) -> void:
	if net_active != _shown_active:
		if net_active and not multiplayer.is_server():
			_snapshots.clear()
			global_position = net_position
			rotation.y = net_yaw
		_apply_active(net_active)
	if net_active:
		var down := health.is_dead() or net_pose == ZombieScare.Pose.DOWN
		body.update(delta, net_attacking, down, health.current, bool(_def.get("armed", false)))
		if _scare:
			_scare_visuals(delta, down)


# All peers: the stumble / crawl look, twitchy bones and night eyes for this activation's traits.
func _apply_scare_look() -> void:
	if _scare == null:
		body.clip_remap.clear()
		body.unhide_bones()
		_twitch = null
		_eyes = null
		_eyes_skel = null
		return
	_scare.apply_look(body)
	var skel := body.skeleton()
	_twitch = Twitch.make(skel, ZombieScare.tuning.twitch) if skel and bool(_scare.roles.get("twitchy", false)) else null
	if skel != _eyes_skel:  # a new model: its eyes go on the new head (the old ones were freed with the old model)
		_eyes_skel = skel
		_eyes = EyeShine.attach(skel, ZombieScare.tuning.eyes) if skel else null


func _scare_visuals(delta: float, down: bool) -> void:
	if net_attacking and not _was_attacking:
		Sfx.play_at("zombie_attack", global_position + Vector3.UP * _hit_height() * 0.8)
	_was_attacking = net_attacking
	if _eyes:
		_eyes.visible = not down
	if _twitch and body.advanced and not down and not net_attacking:
		var cam := get_viewport().get_camera_3d()
		if cam and cam.global_position.distance_squared_to(global_position) < _twitch.range_sq:
			_twitch.apply(body.skeleton(), delta)


func _apply_active(on: bool) -> void:
	_shown_active = on
	visible = on
	collider.set_deferred("disabled", not on)
