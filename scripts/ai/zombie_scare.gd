# ZombieScare — one zombie's scare traits and host-side scare behaviour (D-114). Owned by Zombie (only for enemy
# IDs listed in data/tuning/scare.json "roles"; raiders and bosses never get one).
#   All peers: traits come from ScareRules.roles(net_style seed), so everyone agrees on who is a crawler or a
#     stumbler without sending more than one int. apply_look() sets the animator up (stumble walk, crawl clips,
#     legs hidden) and the hit-capsule height.
#   Host: host_step() runs before the zombie moves and returns a speed multiplier (0 = stand still and face the
#     target): the spotting scream + sprint (and the call that pulls in others nearby), lurkers waiting against a
#     wall until you're close, night stalkers that freeze while watched and creep while not, feigners lying down
#     and getting back up. chase_point() sends flankers to your side when others are chasing you too.
# Depends on: ScareRules, ZombieBrain, DataLoader, data/tuning/scare.json, DayNight (group "daynight").
class_name ZombieScare
extends RefCounted

const PATH := "res://data/tuning/scare.json"
const WORLD_MASK := 1

enum Pose { NORMAL, DOWN, RISE }

static var tuning: Dictionary = {}
static var roles_off := false  # tests that need plain zombies switch every trait off
static var _chasers: Dictionary = {}  # target instance id -> [frame, count this frame, count last frame]

var roles: Dictionary = {}
var _id := ""
var lurking := false
var lurk_face := Vector3.ZERO
var _scream_left := 0.0
var _sprint_left := 0.0
var _scream_cd := 0.0
var _engaged := false
var _stalk_time := 0.0
var _pose_left := 0.0
var _flank_at := Vector3.ZERO
var _flank_in := 0.0
static var _night := false
static var _night_frame := -1


static func load_tuning() -> Dictionary:
	if tuning.is_empty():
		tuning = DataLoader.load_json(PATH)
	return tuning


# A scare helper for this enemy ID, or null when it gets none.
static func make(enemy_id: String) -> ZombieScare:
	if not load_tuning().get("roles", {}).has(enemy_id):
		return null
	var s := ZombieScare.new()
	s._id = enemy_id
	return s


# All peers: traits for this activation's style seed.
func set_style(style_seed: int) -> void:
	roles = ScareRules.roles(style_seed, {} if roles_off else tuning.roles[_id], tuning)


func is_crawler() -> bool:
	return bool(roles.get("crawler", false))


# Hit-capsule height for this pose (crawling and lying bodies are low).
func height(standing: float, pose: int) -> float:
	if pose == Pose.DOWN:
		return float(tuning.feign.height_m)
	if is_crawler():
		return minf(standing, float(tuning.crawler.height_m))
	return standing


# All peers: the walk / crawl look on the animator (call after every set_model).
func apply_look(body: CharacterAnimator) -> void:
	body.clip_remap.clear()
	body.unhide_bones()
	if is_crawler():
		for k: String in ["idle", "walk", "run", "hit", "attack", "scream"]:
			body.clip_remap[k] = "crawl"
		body.hide_bones(tuning.crawler.hide_bones)
	elif bool(roles.get("stumbler", false)):
		body.clip_remap["walk"] = "stumble"


# --- host ---------------------------------------------------------------------------------

# Host, right after activate(): reset timers; a lurker picks a wall or doorway within search_m to wait against.
func host_activate(z) -> void:
	_scream_left = 0.0
	_sprint_left = 0.0
	_scream_cd = 0.0
	_engaged = false
	_stalk_time = 0.0
	_pose_left = 0.0
	z.health.down_once = bool(roles.get("feigner", false))
	lurking = false
	if not bool(roles.get("lurker", false)):
		return
	var space: PhysicsDirectSpaceState3D = z.get_world_3d().direct_space_state
	var from: Vector3 = z.global_position + Vector3.UP
	var best := INF
	var r := float(tuning.lurk.search_m)
	for i in 8:
		var a := TAU * i / 8.0
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(sin(a), 0.0, cos(a)) * r, WORLD_MASK)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or absf((hit.normal as Vector3).y) > 0.5:
			continue
		var d := from.distance_to(hit.position)
		if d < best:
			best = d
			lurk_face = hit.normal
			z._home = (hit.position as Vector3) + (hit.normal as Vector3) * float(tuning.lurk.wall_gap_m) - Vector3.UP
	if best < INF:
		lurking = true
		z._set_destination(z._home)


# Host, each physics step (after the brain ticked). Returns the speed multiplier for this step.
func host_step(z, delta: float, target_ok: bool, target_dist: float) -> float:
	_scream_cd = maxf(_scream_cd - delta, 0.0)
	match z.net_pose:
		Pose.DOWN:
			z.brain.reset()
			_pose_left -= delta
			if _pose_left <= 0.0:
				_pose_left = float(tuning.feign.rise_s)
				z.net_pose = Pose.RISE
			return 0.0
		Pose.RISE:
			z.brain.reset()
			_pose_left -= delta
			if _pose_left <= 0.0:
				z.net_pose = Pose.NORMAL
				z.health.current = z.health.max_health * float(tuning.feign.revive_fraction)
				z.hear(z._last_seen if z._last_seen != Vector3.ZERO else z.global_position)
			return 0.0
	var chasing: bool = z.brain.state == ZombieBrain.State.CHASE or z.brain.state == ZombieBrain.State.ATTACK
	if _scream_left > 0.0:
		_scream_left -= delta
		if _scream_left <= 0.0:
			_sprint_left = float(tuning.scream.sprint_seconds)
		return 0.0
	if lurking:
		if chasing and target_dist <= float(tuning.lurk.wake_m):
			lurking = false  # ambush
		else:
			return 0.0 if chasing or z.nav.is_navigation_finished() else _gait()
	if chasing and target_ok and bool(roles.get("stalker", false)) and _is_night(z) and z._target.is_in_group("players"):
		var st: Dictionary = tuning.stalk
		var act := ScareRules.stalk(target_dist, ScareRules.is_watched(float(z._target.net_yaw),
			z._target.global_position, z.global_position, float(st.look_cone_degrees)), _stalk_time, st)
		if act != ScareRules.Stalk.CHARGE:
			_stalk_time += delta
			_engaged = false
			return 0.0 if act == ScareRules.Stalk.HOLD else float(st.creep_mult) * float(z._def.walk_speed) / maxf(float(z._def.chase_speed), 0.01)
	if not chasing:
		_engaged = false
		_stalk_time = 0.0
		return _gait()
	if not _engaged:
		_engaged = true
		if bool(roles.get("screamer", false)) and _scream_cd <= 0.0 and target_dist > float(tuning.scream.min_distance_m):
			_scream_cd = float(tuning.scream.cooldown_s)
			_scream_left = float(tuning.scream.seconds)
			z.host_scream()
			return 0.0
	if _sprint_left > 0.0:
		_sprint_left -= delta
		return _gait() * float(tuning.scream.sprint_mult)
	return _gait()


# Host: true while screaming, lying or getting up (no swings then).
func busy(pose: int) -> bool:
	return _scream_left > 0.0 or pose != Pose.NORMAL


# Host: the feigner drops instead of dying (Health.downed).
func host_downed(z) -> void:
	var f: Dictionary = tuning.feign
	_pose_left = randf_range(float(f.down_min_s), float(f.down_max_s))
	_scream_left = 0.0
	_sprint_left = 0.0
	lurking = false
	z.net_pose = Pose.DOWN


# Host: where a chaser heads. Flankers swing to one side of you while others are chasing you too.
func chase_point(z, target: Node3D, target_dist: float) -> Vector3:
	var key := target.get_instance_id()
	var frame := Engine.get_physics_frames()
	if not _chasers.has(key):
		_chasers[key] = [frame, 0, 0]
	var e: Array = _chasers[key]
	if int(e[0]) != frame:  # new physics frame: last frame's count becomes the one we read
		e[2] = e[1]
		e[1] = 0
		e[0] = frame
	e[1] = int(e[1]) + 1
	var f: Dictionary = tuning.flank
	if bool(roles.get("flanker", false)) and int(e[2]) >= int(f.min_chasers) and target_dist > float(f.until_m):
		_flank_in -= z.get_physics_process_delta_time()
		if _flank_in <= 0.0:  # re-aim twice a second, so the path isn't recomputed every step
			_flank_in = 0.5
			_flank_at = ScareRules.flank_point(target.global_position, z.global_position, int(roles.side), float(f.offset_m))
		return _flank_at
	return target.global_position


func _gait() -> float:
	var m := float(roles.get("speed", 1.0))
	return m * float(tuning.crawler.speed_mult) if is_crawler() else m


func _is_night(z) -> bool:
	var frame := Engine.get_physics_frames()
	if frame - _night_frame >= 30 or _night_frame < 0:  # looked up twice a second, shared by every zombie
		_night_frame = frame
		var dn: Node = z.get_tree().get_first_node_in_group("daynight")
		_night = dn != null and dn.is_night()
	return _night
