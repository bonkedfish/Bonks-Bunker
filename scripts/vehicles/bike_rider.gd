# BikeRider — riding a motorcycle (D-083), Player child "Bike".
#   Host:  host_mount() (from BikeDirector) puts the player on a bike; Player._simulate hands every intent to
#          simulate() while mounted (the host's result is the truth); host_tick() packs `net_state` each tick, drops
#          the rider if they go down or swim; crashes (BikeRules: looping, going over the bars, bad landings, hitting
#          something, a big hit) throw the rider off with damage; stalls / running dry are told to the rider. Bikes ridden
#          into zombies hurt them. Requests from the rider: start (B), get off (F, only when slow), refuel (R, stopped,
#          uses gas cans).
#   Owner: the same simulate() predicts the bike; the gear the rider picked (E / Q, only with the clutch - Shift - held)
#          travels with every intent; reconcile() nudges speed / heading / pitch onto the host's numbers using the
#          prediction history. Mouse look orbits a third-person chase camera (V: first person) that drifts back behind
#          the bike; BikeHud shows speed, gear, revs, clutch, fuel. No weapons: the viewmodel is hidden and Player
#          masks fire / reload.
#   Everyone: draws the bike under the rider (lean, wheelie / stoppie pitch, spinning wheels), sits the rider's body on
#          it (CharacterAnimator.on_bike), plays the engine (BikeSound).
# Replicated by the player's Sync: net_ride ("id|model|scheme", "" = on foot; on change) and net_state (always):
# [speed, heading, pitch, pitch_rate, lean, rpm, gear, flags (1 engine, 2 limiter, 4 clutch in), clutch, fuel].
# Depends on: BikeRules, BikeMesh, BikeSound, BikeHud, BikeDirector (group "bike_director"), Player (parent: head,
# camera, viewmodel, body, health, life, inventory, velocity, yaw / pitch, is_local, peer_id), HUD (group "hud"), Sfx.
class_name BikeRider
extends Node3D

const FLAG_JUMP := 1
const FLAG_SPRINT := 2
const FLAG_CROUCH := 4
const HISTORY := 128  # = Player.HISTORY_SIZE
const CAM_3P := Vector3(0.0, 0.45, 3.6)
const CAM_MASK := 1
const LOOK_LIMIT := 2.6
const RECENTER_AFTER := 1.2
const RECENTER_RATE := 1.8
const ZOMBIE_HIT_COOLDOWN := 0.6

var net_ride := ""
var net_state := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0, 1, 0])

var bike_id := ""
var model := ""
var scheme := 0
var heading := 0.0
var want_gear := 0     # owner: the gear the rider picked (sent with each intent)
var look_rel := 0.0    # owner: camera yaw relative to the bike
var third_person := true

var mounted: bool:
	get:
		return net_ride != ""

var _s: Dictionary = BikeRules.new_state(0.0)
var _b: Dictionary = {}
var _t: Dictionary = {}
var _ride_seen := ""
var _pivot: Node3D
var _wheels: Array[MeshInstance3D] = []
var _sound: BikeSound
var _hud: BikeHud
var _h_speed := PackedFloat32Array()
var _h_heading := PackedFloat32Array()
var _h_pitch := PackedFloat32Array()
var _since_look := 0.0
var _vis_heading := 0.0
var _vis_pitch := 0.0
var _vis_lean := 0.0
var _hits: Dictionary = {}  # host: zombie instance id -> msec of the last hit
var _hint_cd := 0.0
var _heard_gear := 0
var _body_ready := false

@onready var player: Node = get_parent()


func _ready() -> void:
	_t = BikeRules.tuning()
	_h_speed.resize(HISTORY)
	_h_heading.resize(HISTORY)
	_h_pitch.resize(HISTORY)
	($"../Health" as Health).damaged.connect(_on_damaged)


# --- host ----------------------------------------------------------------------------------------

func host_mount(id: String, rec: Dictionary) -> void:
	bike_id = id
	model = str(rec.model)
	scheme = int(rec.scheme)
	_b = BikeRules.bike(model)
	_s = BikeRules.new_state(float(rec.fuel))
	_s.free_rpm = float(_b.idle_rpm) if bool(_s.engine) else 0.0
	heading = float(rec.yaw)
	player.global_position = Vector3(rec.pos[0], rec.pos[1] + 0.05, rec.pos[2])
	player.velocity = Vector3.ZERO
	want_gear = 0
	_pack()
	net_ride = "%s|%s|%d" % [id, model, scheme]
	_note.rpc_id(player.peer_id, "On the %s. Hold Shift (clutch), E for 1st, ease off Shift with W. F gets off." % str(_b.name))


func host_record() -> Dictionary:
	var p: Vector3 = player.global_position
	return {"model": model, "scheme": scheme, "fuel": snappedf(float(_s.fuel), 0.01), "pos": [p.x, p.y, p.z],
		"yaw": snappedf(heading, 0.001), "tipped": false}


func host_dismount(tipped: bool) -> void:
	if not mounted:
		return
	var side := Vector3(cos(heading), 0.0, -sin(heading))  # the bike's right
	var pos: Vector3 = player.global_position
	if not tipped:  # the bike stays where it was, the rider steps off to its left
		var step := -side * 0.9
		if not player.test_move(player.global_transform, step):
			player.global_position += step
	var dir := get_tree().get_first_node_in_group("bike_director")
	if dir:
		dir.host_park(bike_id, model, scheme, float(_s.fuel), pos, heading, tipped)
	net_ride = ""
	bike_id = ""


func host_tick(_delta: float) -> void:
	if not mounted:
		return
	if player.life.net_state != LifeState.ALIVE or player.water == MovementRules.Water.SWIM:
		host_dismount(true)
		return
	_pack()


func _pack() -> void:
	var flags := (1 if bool(_s.engine) else 0) | (2 if bool(_s.limiter) else 0) | (4 if float(_s.clutch) < 0.5 else 0)
	net_state[0] = float(_s.speed)  # in place: no allocation per tick
	net_state[1] = heading
	net_state[2] = float(_s.pitch)
	net_state[3] = float(_s.pitch_rate)
	net_state[4] = float(_s.lean)
	net_state[5] = float(_s.rpm)
	net_state[6] = float(_s.gear)
	net_state[7] = float(flags)
	net_state[8] = float(_s.clutch)
	net_state[9] = float(_s.fuel)


func _host_crash(why: String, speed: float) -> void:
	var fwd := Vector3(-sin(heading), 0.0, -cos(heading))
	host_dismount(true)
	player.velocity = fwd * speed * 0.6 + Vector3.UP * (2.5 + absf(speed) * 0.1)
	_sfx.rpc("bike_crash")
	var dmg := BikeRules.crash_damage(speed, _t)
	if dmg > 0.0:
		player.health.apply_damage(dmg, 0)
	_note.rpc_id(player.peer_id, "Crashed - %s" % why)


func _on_damaged(amount: float, attacker: int) -> void:
	if multiplayer.is_server() and mounted and attacker != 0 and amount >= float(_t.knock_off_damage):
		_host_crash("knocked off", float(_s.speed))


func _host_hit_zombies(fwd: Vector3) -> void:
	var speed := float(_s.speed)
	if speed < float(_t.zombie_hit_mps):
		return
	var front: Vector3 = player.global_position + fwd * 0.7 + Vector3.UP * 0.8
	var now := Time.get_ticks_msec()
	for z: Node in get_tree().get_nodes_in_group("hittable"):
		if not ("net_enemy" in z) or not z.net_active or not (z is Node3D):
			continue
		if (z as Node3D).global_position.distance_to(front - Vector3.UP * 0.8) > 1.3:
			continue
		var key := z.get_instance_id()
		if now - int(_hits.get(key, -100000)) < int(ZOMBIE_HIT_COOLDOWN * 1000.0):
			continue
		_hits[key] = now
		z.health.apply_damage(speed * float(_t.zombie_damage_per_mps), player.peer_id)
		_s.speed = speed * float(_t.zombie_hit_slow)
		speed = float(_s.speed)


@rpc("any_peer", "call_local", "reliable")
func request_dismount() -> void:
	if not _from_rider() or not mounted:
		return
	if absf(float(_s.speed)) > float(_t.dismount_max_mps):
		_note.rpc_id(player.peer_id, "Slow down to get off")
		return
	host_dismount(false)


@rpc("any_peer", "call_local", "reliable")
func request_start() -> void:
	if not _from_rider() or not mounted or bool(_s.engine):
		return
	if float(_s.fuel) <= 0.0:
		_note.rpc_id(player.peer_id, "Out of gas - R with a gas can")
	elif BikeRules.can_start(_s):
		BikeRules.start(_s, _b)
		_sfx.rpc("bike_start")
	else:
		_note.rpc_id(player.peer_id, "Pull the clutch (Shift) or shift to neutral to start it")


@rpc("any_peer", "call_local", "reliable")
func request_refuel() -> void:
	if not _from_rider() or not mounted:
		return
	if absf(float(_s.speed)) > 1.0:
		_note.rpc_id(player.peer_id, "Stop to refuel")
		return
	var cans: int = player.inventory.count("gas_can")
	if cans <= 0:
		_note.rpc_id(player.peer_id, "No gas can")
		return
	var r := BikeRules.refuel(float(_s.fuel), cans, _b, _t)
	if int(r[1]) <= 0:
		_note.rpc_id(player.peer_id, "The tank is full")
		return
	player.inventory.host_remove("gas_can", int(r[1]))
	_s.fuel = float(r[0])
	_sfx.rpc("bike_refuel")
	_note.rpc_id(player.peer_id, "Filled up with %d gas can%s: %d%%" % [int(r[1]), "" if int(r[1]) == 1 else "s",
		roundi(100.0 * float(_s.fuel) / float(_b.tank_l))])


func _from_rider() -> bool:
	if not multiplayer.is_server():
		return false
	var sender := multiplayer.get_remote_sender_id()
	return sender == player.peer_id or (sender == 0 and player.is_local) or (sender == 1 and player.is_local)


func _exit_tree() -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server() and mounted and is_inside_tree():
		host_dismount(false)


# --- host + owner: one tick of riding -------------------------------------------------------------

func simulate(move: Vector2, flags: int, gear: int) -> void:
	if _b.is_empty():
		return
	var dt := get_physics_process_delta_time()
	var host := multiplayer.is_server()
	var throttle := clampf(-move.y, 0.0, 1.0)
	var brake := clampf(move.y, 0.0, 1.0)
	var steer := clampf(move.x, -1.0, 1.0)
	var rider := (1.0 if flags & FLAG_JUMP else 0.0) - (1.0 if flags & FLAG_CROUCH else 0.0)
	if BikeRules.shift(_s, _b, gear) and player.is_local:
		Sfx.play_local("bike_shift")
	var on_floor: bool = player.is_on_floor()
	var vy: float = player.velocity.y
	var before := float(_s.speed)
	BikeRules.step(_s, _b, _t, throttle, brake, steer, rider, (flags & FLAG_SPRINT) != 0, on_floor, dt)
	heading = wrapf(heading + float(_s.yaw_rate) * dt, -PI, PI)
	player.rotation.y = heading
	player.head.rotation.y = wrapf(player.yaw - heading, -PI, PI)
	var fwd := Vector3(-sin(heading), 0.0, -cos(heading))
	if not on_floor:
		vy -= player._gravity * dt
	player.velocity = fwd * float(_s.speed) + Vector3.UP * vy
	player.move_and_slide()
	var after: float = Vector3(player.velocity.x, 0.0, player.velocity.z).dot(fwd)
	var hit_zombie := false
	for i in player.get_slide_collision_count():
		var c: Object = player.get_slide_collision(i).get_collider()
		if c is Node and (c as Node).is_in_group("hittable") and not (c as Node).is_in_group("players"):
			hit_zombie = true
	if float(_s.speed) > 0.0:
		_s.speed = clampf(after, 0.0, float(_s.speed))  # walls and kerbs take speed away
	elif float(_s.speed) < 0.0:
		_s.speed = clampf(after, float(_s.speed), 0.0)
	var why := ""
	if not on_floor and player.is_on_floor():  # landed: the lifted wheel comes down
		why = BikeRules.landing_crash(float(_s.pitch), vy, _t)
		_s.pitch = clampf(float(_s.pitch), 0.0, 0.5) * 0.5
		_s.pitch_rate = 0.0
	if not host:
		_s.stalled = false
		_s.out_of_gas = false
		return
	if why == "" and not hit_zombie:
		why = BikeRules.impact_crash(before, after, _t)
	if why == "":
		why = BikeRules.pitch_crash(_s, _t)
	if why != "":
		_host_crash(why, before)
		return
	_host_hit_zombies(fwd)
	if bool(_s.stalled):
		_s.stalled = false
		_sfx.rpc("bike_stall")
		_note.rpc_id(player.peer_id, "Stalled - B restarts it (clutch in or neutral)")
	if bool(_s.out_of_gas):
		_s.out_of_gas = false
		_sfx.rpc("bike_stall")
		_note.rpc_id(player.peer_id, "Out of gas - R refuels from a gas can")


# --- owner: prediction bookkeeping ----------------------------------------------------------------

# The look yaw the owner sends: the bike's heading plus where the camera is turned.
func look_yaw() -> float:
	return wrapf(heading + look_rel, -PI, PI)


func look(dx: float, dy: float) -> void:
	look_rel = clampf(look_rel - dx, -LOOK_LIMIT, LOOK_LIMIT)
	player.pitch = clampf(player.pitch - dy, -1.2, 1.2)
	player.head.rotation.x = player.pitch
	player.yaw = look_yaw()
	_since_look = 0.0


func record(seq: int) -> void:
	var i := seq % HISTORY
	_h_speed[i] = float(_s.speed)
	_h_heading[i] = heading
	_h_pitch[i] = float(_s.pitch)


# Host numbers for intent `ack` vs what this client predicted after it: shift the present by the difference.
func reconcile(ack: int, seq: int) -> void:
	if not mounted or _b.is_empty() or ack <= 0 or seq - ack >= HISTORY:
		return
	var i := ack % HISTORY
	var ds := net_state[0] - _h_speed[i]
	var dh := angle_difference(_h_heading[i], net_state[1])
	var dp := net_state[2] - _h_pitch[i]
	if absf(ds) > 0.4:
		_s.speed = float(_s.speed) + ds
		for k in HISTORY:
			_h_speed[k] += ds
	if absf(dh) > 0.03:
		heading = wrapf(heading + dh, -PI, PI)
		for k in HISTORY:
			_h_heading[k] += dh
	if absf(dp) > 0.08:
		_s.pitch = float(_s.pitch) + dp
		for k in HISTORY:
			_h_pitch[k] += dp
	_s.engine = (int(net_state[7]) & 1) != 0  # starting / stalling is the host's call
	_s.fuel = net_state[9]


# --- owner input ---------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not mounted or not player.is_local or player.cutscene or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var handled := true
	if event.is_action_pressed("bike_shift_up") or event.is_action_pressed("bike_shift_down"):
		var up := event.is_action_pressed("bike_shift_up")
		if Input.is_action_pressed("sprint"):
			want_gear = clampi(want_gear + (1 if up else -1), 0, BikeRules.gears(_b))
		else:
			_hint("Pull the clutch first: hold Shift, then E / Q")
	elif event.is_action_pressed("bike_dismount"):
		request_dismount.rpc_id(1)
	elif event.is_action_pressed("ride"):
		request_start.rpc_id(1)
	elif event.is_action_pressed("reload"):
		request_refuel.rpc_id(1)
	elif event.is_action_pressed("bike_camera"):
		third_person = not third_person
	elif event.is_action_pressed("interact") or event.is_action_pressed("weapon_1") or event.is_action_pressed("weapon_2"):
		pass  # no looting, talking or weapons from the saddle
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _hint(text: String) -> void:
	if _hint_cd > 0.0:
		return
	_hint_cd = 3.0
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_toast(text, 2.5)


# --- every peer: look and sound --------------------------------------------------------------------

func _process(delta: float) -> void:
	_hint_cd = maxf(_hint_cd - delta, 0.0)
	if net_ride != _ride_seen:
		_apply_ride()
	if not mounted:
		return
	var local_sim: bool = multiplayer.is_server() or player.is_local
	var speed := float(_s.speed) if local_sim else net_state[0]
	var k := 1.0 - exp(-15.0 * delta)
	if local_sim:
		_vis_heading = heading
		_vis_pitch = float(_s.pitch)
		_vis_lean = float(_s.lean)
	else:  # other players' bikes: ease toward the host's numbers
		_vis_heading = lerp_angle(_vis_heading, net_state[1], k)
		_vis_pitch = lerpf(_vis_pitch, net_state[2], k)
		_vis_lean = lerpf(_vis_lean, net_state[4], k)
		player.rotation.y = _vis_heading
		player.head.rotation.y = wrapf(player.net_yaw - _vis_heading, -PI, PI)
	var gear_now := int(_s.gear) if local_sim else int(net_state[6])
	if gear_now != _heard_gear:  # other riders' shifts (the rider hears their own from simulate)
		_heard_gear = gear_now
		if not player.is_local:
			Sfx.play_at("bike_shift", player.global_position)
	var axle: Array[Vector3] = BikeMesh.axles(model)
	var pt := Vector3(0, 0, axle[0].z if _vis_pitch >= 0.0 else axle[1].z)  # wheelie: rear contact, stoppie: front
	var pitch_xf := Transform3D(Basis.IDENTITY, pt) * Transform3D(Basis(Vector3.RIGHT, _vis_pitch), Vector3.ZERO) \
		* Transform3D(Basis.IDENTITY, -pt)
	_pivot.transform = Transform3D(Basis(Vector3.BACK, -_vis_lean), Vector3.ZERO) * pitch_xf
	for w in _wheels:
		w.rotation.x -= speed / float(_b.shape.wheel_r) * delta
	player.body.transform = _pivot.transform * Transform3D(Basis.IDENTITY, Vector3(0, float(_b.shape.get("rider_y", 0.3)), 0.1))
	var flags := int(net_state[7])
	var rpm := float(_s.rpm) if local_sim else net_state[5]
	var engine_on := bool(_s.engine) if local_sim else (flags & 1) != 0
	var limiter := bool(_s.limiter) if local_sim else (flags & 2) != 0
	_sound.update(rpm, engine_on, limiter, delta)
	if player.is_local:
		_owner_view(delta, speed)
		if _hud:
			_hud.show_state(absf(speed), int(_s.gear), rpm, float(_b.redline_rpm), float(_s.clutch) < 0.5, float(_s.fuel),
				float(_b.tank_l), engine_on, limiter)


func _owner_view(delta: float, speed: float) -> void:
	_since_look += delta
	if third_person and _since_look > RECENTER_AFTER and absf(speed) > 3.0:
		look_rel = move_toward(look_rel, 0.0, RECENTER_RATE * delta)
		player.yaw = look_yaw()
	player.head.rotation.y = look_rel
	var cam: Camera3D = player.camera
	if third_person:
		var want: Vector3 = player.head.global_transform * CAM_3P
		var from: Vector3 = player.head.global_position
		var q := PhysicsRayQueryParameters3D.create(from, want, CAM_MASK, [player.get_rid()])
		var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
		var dist := CAM_3P.length()
		if not hit.is_empty():
			dist = maxf(from.distance_to(hit.position) - 0.25, 0.4)
		cam.position = CAM_3P.normalized() * dist
		if not _body_ready:
			_body_ready = player.body.set_model(player._model_id())
		player.body.visible = true
		player.body.update(delta, false, false, player.health.current, false, false)
	else:
		cam.position = Vector3.ZERO
		player.body.visible = false


# Mount / dismount on this peer, from net_ride.
func _apply_ride() -> void:
	_ride_seen = net_ride
	var on := net_ride != ""
	if on:
		var parts := net_ride.split("|")
		bike_id = parts[0]
		model = parts[1]
		scheme = int(parts[2])
		_b = BikeRules.bike(model)
		if not multiplayer.is_server():
			_s = BikeRules.new_state(net_state[9])
			_s.engine = (int(net_state[7]) & 1) != 0
			_s.free_rpm = float(_b.idle_rpm) if bool(_s.engine) else 0.0
			heading = net_state[1]
			want_gear = int(net_state[6])
		_vis_heading = heading
		_build_visual()
		_heard_gear = int(net_state[6])
	else:
		if _pivot:
			_pivot.queue_free()
			_pivot = null
			_wheels.clear()
			_sound = null
		player.body.transform = Transform3D.IDENTITY
	player.body.on_bike = on
	if player.is_local:
		player.viewmodel.visible = not on
		if on:
			look_rel = 0.0
			_hud = BikeHud.new()
			var hud := get_tree().get_first_node_in_group("hud")
			if hud:
				hud.add_child(_hud)
		else:
			if _hud:
				_hud.queue_free()
				_hud = null
			player.head.rotation.y = 0.0
			player.rotation.y = player.yaw
			player.camera.position = Vector3.ZERO
			player.body.visible = false
			player.show_held_weapon()


func _build_visual() -> void:
	if _pivot:
		_pivot.queue_free()
	_wheels.clear()
	_pivot = Node3D.new()
	add_child(_pivot)
	var mi := MeshInstance3D.new()
	mi.mesh = BikeMesh.body(model, scheme)
	mi.visibility_range_end = 250.0
	_pivot.add_child(mi)
	for a: Vector3 in BikeMesh.axles(model):
		var holder := Node3D.new()
		holder.position = a
		_pivot.add_child(holder)
		var w := MeshInstance3D.new()
		w.mesh = BikeMesh.wheel(model)
		w.visibility_range_end = 250.0
		holder.add_child(w)
		_wheels.append(w)
	_sound = BikeSound.new()
	_pivot.add_child(_sound)
	_sound.setup(str(_b.engine), float(_b.redline_rpm), float(_t.sound_m))


@rpc("authority", "call_local", "reliable")
func _note(text: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_toast(text, 3.0)


@rpc("authority", "call_local", "unreliable")
func _sfx(id: String) -> void:
	if player.is_local:
		Sfx.play_local(id)
	else:
		Sfx.play_at(id, player.global_position + Vector3.UP * 0.6)
