# DzCourt — one Drop Zone pickleball court (D-074), DropZone child "Court<n>": a player against the CPU.
#   Host: E at the court post starts a game (if the court is free). The player takes the south half (z > 0 in court
#         space), the CPU the north. Runs the ball every physics tick (PickleballRules): serves (the player clicks to
#         serve; the CPU serves after serve_delay_s), bounces, the net, out balls, second bounces, rally scoring to
#         win_points. A click starts a swing (D-089): windup_s later it makes contact, then recovery_s before the
#         next swing can start (clicks meanwhile are ignored, so spamming whiffs). At contact the ball must be on
#         their side, within reach and not theirs to leave; the timing grades the shot (PERFECT: flat and deep,
#         GOOD, EARLY: pulled left and short, LATE: pushed right and floaty) and volleys are checked for faults
#         (two-bounce rule on the serve and the return, no volleys from the kitchen). The ball flies where they
#         look. The CPU runs to the ball, obeys the same volley rules, lobs a player camped at the net, smashes
#         floaters, and misses more against perfect shots. Sends the ball and CPU positions 20x a second
#         (unreliable), the score on change and each hit / point callout (reliable). Walking off ends the game.
#   Every peer: shows the ball (with its shadow and a ring where it will land) and the CPU player, interpolating;
#         the rally count and the last point's callout for the HUD; the local player's timing grade pops up through
#         their SportInput; puts the local player's SportInput into "pickle" mode while it's their game.
# Depends on: DropZone (parent: data, sender_player, toast), PickleballRules, SportInput.
class_name DzCourt
extends Node3D

signal changed

const SEND_HZ := 20.0
const LEAVE_M := 14.0

var index := 0
var player_peer := 0      # 0 = free
var score := Vector2i.ZERO  # (player, CPU)
var serving := 1          # 1 player, -1 CPU
var phase := "idle"       # idle, serve, rally, pause

var _p: Dictionary
var _half := Vector2(3.05, 6.705)
var _ball := PickleballRules.Ball.new()
var _cpu := Vector2.ZERO
var _last_hitter := 0     # 1 player, -1 CPU
var _bounces := 0
var _bounce_side := 0
var _timer := 0.0
var _send := 0.0
var _aim_timer := 0.0
var _goal := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _ball_mesh: MeshInstance3D
var _cpu_mesh: MeshInstance3D
var _shown_ball := Vector3.ZERO
var _shown_cpu := Vector2.ZERO
var rally := 0             # hits this rally (every peer, for the HUD)
var callout := ""          # the last point, e.g. "Kitchen volley! CPU point   3 - 4" (every peer)
var callout_time := 0.0    # seconds it stays up
var _clock := 0.0          # host
var _swing_at := -1.0      # host: contact time of the player's swing in progress
var _swing_yaw := 0.0
var _ready_at := 0.0       # host: the player can start a new swing from here
var _shots := 0            # host: hits this rally (0 before the serve)
var _player_grade := ""    # host: the player's last shot grade (the CPU smashes LATE floaters)
var _shadow: MeshInstance3D
var _ring: MeshInstance3D
var _land_timer := 0.0


func _ready() -> void:
	_p = PickleballRules.tuning()
	_half = PickleballRules.half_size(dz().data.court_size)
	var c: Array = dz().data.courts[index].c
	position = Vector3(float(c[0]), 0.0, float(c[1]))
	_rng.randomize()
	_ball_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = float(_p.ball_r) * 1.6
	sm.height = sm.radius * 2.0
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.95, 0.85, 0.15)
	sm.material = bm
	_ball_mesh.mesh = sm
	_ball_mesh.visible = false
	add_child(_ball_mesh)
	_cpu_mesh = MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.3
	cm.height = 1.75
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.75, 0.3, 0.2)
	cm.material = cmat
	_cpu_mesh.mesh = cm
	_cpu_mesh.visible = false
	add_child(_cpu_mesh)
	_shadow = _flat_mesh(CylinderMesh.new(), Color(0, 0, 0, 0.45))
	(_shadow.mesh as CylinderMesh).top_radius = 0.09
	(_shadow.mesh as CylinderMesh).bottom_radius = 0.09
	(_shadow.mesh as CylinderMesh).height = 0.004
	var torus := TorusMesh.new()
	torus.inner_radius = 0.2
	torus.outer_radius = 0.26
	torus.rings = 16
	torus.ring_segments = 4
	_ring = _flat_mesh(torus, Color(1.0, 0.85, 0.2, 0.8))
	multiplayer.peer_connected.connect(_on_peer_connected)


func _flat_mesh(mesh: PrimitiveMesh, col: Color) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


func dz() -> Node:
	return get_parent()


# Court-space position of a world point.
func court_pos(world: Vector3) -> Vector3:
	return dz().to_local_pos(world) - position


@rpc("any_peer", "call_local", "reliable")
func request_use(_i: int) -> void:
	var p := DropZone.sender_player(self)
	if p == null or court_pos(p.global_position).length() > float(_p.join_radius_m) + _half.y:
		return
	if player_peer != 0:
		if player_peer != p.peer_id:
			_say.rpc_id(p.peer_id, "Court %d is taken" % (index + 1))
		return
	player_peer = p.peer_id
	score = Vector2i.ZERO
	serving = 1
	_cpu = Vector2(0.0, -_half.y - 0.5)
	_start_point()
	_state.rpc(player_peer, score, serving, phase)
	_say.rpc_id(p.peer_id, "Pickleball vs the CPU, to %d. Stand on the near side; click to serve and to hit." % int(_p.win_points))


@rpc("any_peer", "call_local", "reliable")
func request_hit(yaw: float) -> void:
	var p := DropZone.sender_player(self)
	if p == null or p.peer_id != player_peer:
		return
	var me := court_pos(p.global_position) + Vector3.UP * 1.0
	if phase == "serve" and serving == 1:
		_ball.pos = Vector3(me.x, 0.9, maxf(me.z, _half.y * 0.6))
		_hit(1, yaw, true)
		phase = "rally"
		return
	if phase != "rally" or _clock < _ready_at:  # mid-swing or recovering: spam does nothing
		return
	_swing_at = _clock + float(_p.windup_s)
	_swing_yaw = yaw
	_ready_at = _swing_at + float(_p.recovery_s)


# The player's swing reaches the contact point: grade it, check the volley rules, hit or whiff.
func _contact() -> void:
	var p := DropZone.player_by_peer(self, player_peer)
	if p == null:
		return
	var me := court_pos(p.global_position) + Vector3.UP * 1.0
	var grade := "WHIFF"
	if _last_hitter != 1 and PickleballRules.side_of(_ball.pos) == 1:
		grade = PickleballRules.swing_grade(_ball.pos - me, _ball.vel, _p, float(_p.reach_slack_m))
	_fx.rpc(1, grade, rally)
	if grade == "WHIFF":
		return
	var fault := PickleballRules.volley_fault(_bounce_side == 1 and _bounces > 0, _shots, me.z, _p)
	if fault != "":
		_point(-1, fault)
		return
	_hit(1, _swing_yaw, false, grade)


# Launches the ball from its spot toward the other side: `who` 1 player (aimed by yaw, shaped by the timing
# grade), -1 CPU (a lob over a net camper, a smash on a floater, else a rally ball).
func _hit(who: int, yaw: float, serve: bool, grade := "GOOD") -> void:
	var far := -who * _half.y
	var depth := _rng.randf_range(0.45, 0.85)
	var apex: Array = _p.hit_speed_apex_m
	var h := _rng.randf_range(float(apex[0]), float(apex[1]))
	var target := Vector2.ZERO
	if who == 1:
		_player_grade = grade
		match grade:
			"PERFECT":
				depth = _rng.randf_range(0.8, 0.92)
				h = float(_p.perfect_apex_m)
			"EARLY":
				yaw += deg_to_rad(float(_p.mistime_yaw_deg))
				depth = _rng.randf_range(0.35, 0.6)
			"LATE":
				yaw -= deg_to_rad(float(_p.mistime_yaw_deg))
				h = float(_p.late_apex_m)
		var dir := Vector2(-sin(yaw - dz().global_rotation.y), -cos(yaw - dz().global_rotation.y))
		var t := (far * depth - _ball.pos.z) / dir.y if dir.y < -0.05 else 4.0
		target = Vector2(_ball.pos.x, _ball.pos.z) + dir * clampf(t, 1.0, 16.0)
	else:
		var pz := _player_court_pos()
		target = Vector2(_rng.randf_range(-_half.x * 0.85, _half.x * 0.85), far * depth)
		if not serve and PickleballRules.cpu_should_lob(pz.z, _p):  # over the head of a net camper
			target = Vector2(_rng.randf_range(-_half.x * 0.6, _half.x * 0.6), far * _rng.randf_range(0.85, 0.95))
			h = float(_p.lob_apex_m)
			grade = "LOB"
		elif not serve and _player_grade == "LATE":  # put the floater away, away from the player
			target = Vector2(-signf(pz.x if pz.x != 0.0 else 1.0) * _half.x * 0.8, far * 0.8)
			h = float(_p.perfect_apex_m)
			grade = "SMASH"
	if serve:  # diagonal service box, past the kitchen
		target.y = signf(far) * _rng.randf_range(3.2, _half.y - 0.6)
		h = float(_p.serve_apex_m)
	_ball.vel = PickleballRules.aim(_ball.pos, target, h, _p)
	_last_hitter = who
	_bounces = 0
	_bounce_side = 0
	_shots += 1
	rally += 1
	if who == -1:
		_fx.rpc(-1, grade, rally)


func _player_court_pos() -> Vector3:
	var p := DropZone.player_by_peer(self, player_peer)
	return court_pos(p.global_position) if p else Vector3(0, 0, _half.y)


func _start_point() -> void:
	phase = "serve"
	_timer = float(_p.serve_delay_s)
	_last_hitter = 0
	_bounces = 0
	_shots = 0
	rally = 0
	_swing_at = -1.0
	_ready_at = 0.0
	_player_grade = ""
	_ball.vel = Vector3.ZERO
	_ball.pos = Vector3(0.0, -5.0, 0.0) if serving == 1 else Vector3(_cpu.x, 0.9, -_half.y + 0.4)


func _physics_process(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server() and player_peer != 0:
		_host_tick(delta)
	_show(delta)


func _host_tick(delta: float) -> void:
	_clock += delta
	var p := DropZone.player_by_peer(self, player_peer)
	if p == null or court_pos(p.global_position).length() > LEAVE_M + _half.y:
		player_peer = 0
		phase = "idle"
		_state.rpc(0, score, serving, phase)
		return
	match phase:
		"serve":
			if serving == -1:
				_timer -= delta
				if _timer <= 0.0:
					_ball.pos = Vector3(_cpu.x, 0.9, -_half.y + 0.4)
					_hit(-1, 0.0, true)
					phase = "rally"
		"pause":
			_timer -= delta
			if _timer <= 0.0:
				if PickleballRules.game_won(score.x, score.y, _p) or PickleballRules.game_won(score.y, score.x, _p):
					var won := score.x > score.y
					_say.rpc_id(player_peer, "%s %d-%d" % ["You win!" if won else "The CPU wins", score.x, score.y])
					player_peer = 0
					phase = "idle"
					_state.rpc(0, score, serving, phase)
					return
				_start_point()
				_state.rpc(player_peer, score, serving, phase)
		"rally":
			_rally(delta)
	# CPU footwork.
	_aim_timer -= delta
	if _aim_timer <= 0.0:  # the look-ahead runs 10x a second, not every tick
		_aim_timer = 0.1
		_goal = PickleballRules.cpu_target(_ball, _p, _half) if phase == "rally" else Vector2(0.0, -_half.y - 0.3)
	_cpu = _cpu.move_toward(_goal, float(_p.ai_speed) * delta)
	_send -= delta
	if _send <= 0.0:
		_send = 1.0 / SEND_HZ
		_ball_state.rpc(_ball.pos, _ball.vel, _cpu)


func _rally(delta: float) -> void:
	if _swing_at >= 0.0 and _clock >= _swing_at:
		_swing_at = -1.0
		_contact()
		if phase != "rally":
			return
	var ev := PickleballRules.step(_ball, delta, _p)
	if ev == PickleballRules.Event.NET:
		_point(-_last_hitter, "Into the net")
		return
	if ev == PickleballRules.Event.BOUNCE:
		var side := PickleballRules.side_of(_ball.pos)
		if _bounces == 0 and (side == _last_hitter or not PickleballRules.in_court(_ball.pos, _half)):
			_point(-_last_hitter, "Out")
			return
		if side == _bounce_side:
			_bounces += 1
		else:
			_bounce_side = side
			_bounces = 1
		if _bounces >= 2:  # nobody got to it
			_point(-side, "")
			return
	if absf(_ball.pos.z) > _half.y + 4.0 or absf(_ball.pos.x) > _half.x + 4.0:
		_point(-PickleballRules.side_of(_ball.pos) if _bounces > 0 else -_last_hitter, "Out")
		return
	# CPU return: its side, in reach; volleys only where the rules allow them (not the serve / return, not from the
	# kitchen).
	var bounced := _bounces > 0 and _bounce_side == -1
	if _last_hitter == 1 and PickleballRules.side_of(_ball.pos) == -1 and PickleballRules.volley_fault(bounced, _shots, _cpu.y, _p) == "":
		if Vector2(_cpu.x - _ball.pos.x, _cpu.y - _ball.pos.z).length() <= float(_p.ai_reach_m) and _ball.pos.y < 2.2:
			var miss := PickleballRules.cpu_miss_chance(_ball.vel.length(), _p)
			if _player_grade == "PERFECT":
				miss += float(_p.ai_miss_perfect)
			if _rng.randf() < miss:
				_ball.vel = Vector3(_rng.randf_range(-2, 2), 1.5, 3.0)  # framed it into the net
				_last_hitter = -1
			else:
				_hit(-1, 0.0, false)


func _point(to: int, why: String) -> void:
	if to == 1:
		score.x += 1
	else:
		score.y += 1
	serving = to
	phase = "pause"
	_timer = float(_p.point_pause_s)
	_swing_at = -1.0
	_state.rpc(player_peer, score, serving, phase)
	var called := Vector2i(score.x, score.y) if to == 1 else Vector2i(score.y, score.x)  # the server's score first
	_callout.rpc("%s%s   %d - %d" % [(why + "! ") if why != "" else "", "Your point" if to == 1 else "CPU point", called.x, called.y])


func _on_peer_connected(peer: int) -> void:
	if multiplayer.is_server():
		_state.rpc_id(peer, player_peer, score, serving, phase)


# --- every peer -----------------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _state(peer: int, new_score: Vector2i, new_serving: int, new_phase: String) -> void:
	player_peer = peer
	score = new_score
	serving = new_serving
	phase = new_phase
	_ball_mesh.visible = peer != 0
	_cpu_mesh.visible = peer != 0
	var me := get_tree().get_first_node_in_group("local_player")
	if me and "sport" in me:
		if peer == multiplayer.get_unique_id():
			me.sport.enter("pickle", self)
		else:
			me.sport.leave(self)
	changed.emit()


# A hit (who 1 player / -1 CPU) or the player's whiff: the rally count for everyone, the grade for the player.
@rpc("authority", "call_local", "reliable")
func _fx(who: int, grade: String, count: int) -> void:
	rally = count
	var me := get_tree().get_first_node_in_group("local_player")
	if me and "sport" in me and player_peer == multiplayer.get_unique_id() and me.sport.game == self:
		if who == 1 or grade in ["LOB", "SMASH"]:
			me.sport.last_grade = grade if who == 1 else "CPU " + grade
			me.sport.grade_time = float(GolfBallRules.tuning().swing.grade_show_s)
	changed.emit()


@rpc("authority", "call_local", "reliable")
func _callout(text: String) -> void:
	callout = text
	callout_time = float(_p.callout_s)
	changed.emit()


@rpc("authority", "call_remote", "unreliable_ordered")
func _ball_state(pos: Vector3, vel: Vector3, cpu: Vector2) -> void:
	_ball.pos = pos
	_ball.vel = vel
	_cpu = cpu


func _show(delta: float) -> void:
	callout_time = maxf(0.0, callout_time - delta)
	_shadow.visible = _ball_mesh.visible and _ball.pos.y > 0.0
	if not _ball_mesh.visible:
		_ring.visible = false
		return
	if not multiplayer.is_server() and phase == "rally":  # clients run the ball on between updates
		_ball.pos += _ball.vel * delta
		_ball.vel.y -= float(_p.g) * delta
		if _ball.pos.y < float(_p.ball_r):
			_ball.pos.y = float(_p.ball_r)
	_shown_ball = _shown_ball.lerp(_ball.pos, minf(1.0, delta * 25.0))
	_shown_cpu = _shown_cpu.lerp(_cpu, minf(1.0, delta * 12.0))
	_ball_mesh.position = _shown_ball
	_cpu_mesh.position = Vector3(_shown_cpu.x, 0.9, _shown_cpu.y)
	_shadow.position = Vector3(_shown_ball.x, 0.012, _shown_ball.z)
	var s := clampf(1.3 - _shown_ball.y * 0.15, 0.5, 1.3)  # smaller and lighter the higher it is
	_shadow.scale = Vector3(s, 1.0, s)
	_land_timer -= delta
	if _land_timer <= 0.0:  # where it comes down: 10x a second
		_land_timer = 0.1
		var land := PickleballRules.landing(_ball, _p) if phase == "rally" else Vector3.INF
		_ring.visible = land != Vector3.INF
		if _ring.visible:
			_ring.position = Vector3(land.x, 0.015, land.z)


@rpc("authority", "call_local", "reliable")
func _say(text: String) -> void:
	DropZone.toast(self, text, 2.0)
