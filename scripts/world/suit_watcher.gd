# SuitWatcher — the man in the black suit (D-104). Presentation only: never fights, can't be hit, changes nothing.
# Host: every interval_s (data/tuning/suit_watcher.json) picks one living player and tells only that peer to show him
# (RPC _appear); each peer only ever shows him to its own local player, so nobody else sees him. That peer puts him
# distance_m away (preferring behind the camera, on dry open ground with a clear line of sight to the player), keeps
# him facing the player, moves him to a fresh spot every relocate_s while the player isn't looking, and vanishes him
# (with a burst of radio static) when the player gets within near_vanish_m or once show_s is over and he's unseen.
# If no spot works (indoors, crowded) it retries a few times. Every peer has the node (main.gd adds "SuitWatcher",
# same path everywhere for the RPC). Depends on: CharacterAnimator (model "suit_watcher"), DataLoader, Sfx buses.
class_name SuitWatcher
extends Node3D

const PATH := "res://data/tuning/suit_watcher.json"
const MODEL := "suit_watcher"
const GROUND_MASK := 17  # world + water bed
const WATER_BED := 16
const HEAD := 1.65

var showing := false

var _t: Dictionary
var _host_timer := 0.0
var _body: CharacterAnimator
var _left := 0.0
var _reloc := 0.0
var _retries := 0
var _retry_timer := -1.0
var _static: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_t = DataLoader.load_json(PATH)
	_rng.randomize()
	_host_timer = float(_t.get("first_delay_s", 300.0))
	visible = false
	_make_body.call_deferred()  # load the model now, hidden, so his first appearance doesn't hitch


func _make_body() -> void:
	if _body == null:
		_body = CharacterAnimator.new()
		_body.name = "Body"
		add_child(_body)
		_body.set_model(MODEL)


func _process(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_host_timer -= delta
		if _host_timer <= 0.0:
			var range_s: Array = _t.get("interval_s", [600.0, 900.0])
			_host_timer = _rng.randf_range(float(range_s[0]), float(range_s[1]))
			_host_pick()
	if _retry_timer > 0.0:
		_retry_timer -= delta
		if _retry_timer <= 0.0:
			appear_now()
	if showing:
		_tick(delta)


func _host_pick() -> void:
	var peers: Array[int] = []
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id > 0 and not p.health.is_dead():
			peers.append(p.peer_id)
	if not peers.is_empty():
		_appear.rpc_id(peers[_rng.randi() % peers.size()])


@rpc("authority", "call_local", "reliable")
func _appear() -> void:
	_retries = int(_t.get("tries", 3))
	appear_now()


# Local: try to show him now (tests call this directly).
func appear_now() -> bool:
	_retry_timer = -1.0
	var me := get_tree().get_first_node_in_group("local_player") as Node3D
	if me == null or me.health.is_dead():
		return false
	var spot := _find_spot(me, true)
	if spot == Vector3.INF:
		_retries -= 1
		if _retries > 0:
			_retry_timer = float(_t.get("retry_s", 45.0))
		return false
	_make_body()
	global_position = spot
	_face(me, 1.0)
	_left = float(_t.get("show_s", 90.0))
	_reloc = float(_t.get("relocate_s", 20.0))
	showing = true
	visible = true
	return true


func vanish(crackle := true) -> void:
	if not showing:
		return
	showing = false
	visible = false
	if crackle:
		_play_static()


func _tick(delta: float) -> void:
	var me := get_tree().get_first_node_in_group("local_player") as Node3D
	if me == null:
		vanish(false)
		return
	_face(me, delta * 2.0)
	_body.update(delta, false, false, 100.0)
	var d := Vector2(me.global_position.x - global_position.x, me.global_position.z - global_position.z).length()
	if d < float(_t.get("near_vanish_m", 25.0)):
		vanish()
		return
	var seen := _in_view(me)
	_left -= delta
	if _left <= 0.0 and not seen:
		vanish(false)
		return
	_reloc -= delta
	if _reloc <= 0.0:
		_reloc = float(_t.get("relocate_s", 20.0))
		if not seen and d > float(_t.get("relocate_min_m", 40.0)):
			var spot := _find_spot(me, false)
			if spot != Vector3.INF:
				global_position = spot


func _face(me: Node3D, weight: float) -> void:
	var to := me.global_position - global_position
	var yaw := atan2(-to.x, -to.z)  # bodies face -z (same as zombies and players)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(weight, 0.0, 1.0))


# True if he's inside the player's camera view and nothing solid is between them.
func _in_view(me: Node3D) -> bool:
	var cam := get_viewport().get_camera_3d()
	var head := global_position + Vector3.UP * HEAD
	if cam == null or not cam.is_position_in_frustum(head):
		return false
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, head, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# A dry, roofless spot distance_m from the player with a clear line of sight to the player's eyes. behind: prefer the
# half of the circle behind the camera (so he isn't seen appearing). Vector3.INF if none of 16 tries works.
func _find_spot(me: Node3D, behind: bool) -> Vector3:
	var space := get_world_3d().direct_space_state
	var cam := get_viewport().get_camera_3d()
	var fwd := -cam.global_basis.z if cam else -me.global_basis.z
	var base_yaw := atan2(fwd.x, fwd.z)
	var dist: Array = _t.get("distance_m", [60.0, 120.0])
	var eye: Vector3 = me.eye_position() if me.has_method("eye_position") else me.global_position + Vector3.UP * 1.6
	for i in 16:
		var a := base_yaw + (PI + _rng.randf_range(-1.7, 1.7) if behind else _rng.randf_range(0.0, TAU))
		var r := _rng.randf_range(float(dist[0]), float(dist[1]))
		var p := me.global_position + Vector3(sin(a), 0.0, cos(a)) * r
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 80.0, p + Vector3.DOWN * 80.0, GROUND_MASK))
		if hit.is_empty() or (hit.collider is CollisionObject3D and (hit.collider as CollisionObject3D).collision_layer & WATER_BED):
			continue
		var ground: Vector3 = hit.position
		var roof := PhysicsRayQueryParameters3D.create(ground + Vector3.UP * 0.5, ground + Vector3.UP * 40.0, 1)
		if not space.intersect_ray(roof).is_empty():
			continue  # under a roof: outside only
		var los := PhysicsRayQueryParameters3D.create(eye, ground + Vector3.UP * HEAD, 1)
		var los_waist := PhysicsRayQueryParameters3D.create(eye, ground + Vector3.UP * 1.0, 1)
		if not space.intersect_ray(los).is_empty() or not space.intersect_ray(los_waist).is_empty():
			continue  # head and body both in plain sight (not half behind a trunk or a fence)
		return ground
	return Vector3.INF


# A short burst of radio static (generated once, no file), played flat on the SFX bus for the local player.
func _play_static() -> void:
	if _static == null:
		var rate := 22050
		var n := int(rate * 0.45)
		var data := PackedByteArray()
		data.resize(n * 2)
		var lp := 0.0
		for i in n:
			var env := pow(1.0 - float(i) / n, 1.5) * (0.6 + 0.4 * sin(float(i) * 0.013))
			lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), 0.55)
			data.encode_s16(i * 2, int(clampf(lp * env, -1.0, 1.0) * 9000.0))
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = rate
		wav.data = data
		_static = AudioStreamPlayer.new()
		_static.stream = wav
		_static.bus = "SFX"
		_static.volume_db = -10.0
		add_child(_static)
	_static.play()
