# GolfView — the golf camera and aim guides for the local player (D-086), made by SportInput under itself.
# While the player is addressing their ball (game.aim_ready()) or the ball is in the air, a camera behind the ball
# looking down the aim line (player.yaw, so the mouse aims) replaces the first-person camera; walking away from the
# ball gives the first-person camera back. Other players / Bonk standing between the camera and the ball are hidden
# on this screen while it's up. Guides (one ImmediateMesh, rebuilt only when the aim, club or ball moves):
#   full swing: the full-power arc for the club from this lie and a ring where it first lands
#   putter / putting course: a line along the ground out to the cup's distance, with slope ticks (downhill side)
# Visual only, local only. Depends on: SportInput (club_id, mode, game's aim_* methods), GolfBallRules.
class_name GolfView
extends Node3D

const ARC_POINTS := 48
const RING_POINTS := 24

var _cam: Camera3D
var _mesh: ImmediateMesh
var _guide: MeshInstance3D
var _key := Vector4.INF  # yaw, club hash, ball x, ball z of the guide that's built
var _active := false
var _snap := false
var _hidden: Array[Node3D] = []


func _ready() -> void:
	top_level = true
	_cam = Camera3D.new()
	_cam.fov = 62.0
	_cam.far = 900.0
	add_child(_cam)
	_mesh = ImmediateMesh.new()
	_guide = MeshInstance3D.new()
	_guide.mesh = _mesh
	_guide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	_guide.material_override = mat
	add_child(_guide)
	_guide.top_level = true


func stop(player: Node) -> void:
	if _active:
		_active = false
		player.camera.make_current()
	_guide.visible = false
	_unhide()


func update_view(player: Node, sp: SportInput, delta: float) -> void:
	var game: Node = sp.game
	var ball: Vector3 = game.aim_ball()
	var flying: bool = game.aim_flying()
	var want: bool = ball != Vector3.INF and (game.aim_ready() or flying or sp.meter.busy())
	if want != _active:
		_active = want
		if want:
			_snap = true
			_cam.make_current()
		else:
			player.camera.make_current()
	_guide.visible = want and not flying
	if not want:
		_unhide()
		return
	var sw: Dictionary = GolfBallRules.tuning().swing
	var putter: bool = sp.mode == "putt" or sp.club_id() == "putter"
	var yaw: float = player.yaw
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var back := float(sw.putt_cam_back_m if putter else sw.cam_back_m)
	var up := float(sw.putt_cam_up_m if putter else sw.cam_up_m)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var eye := ball - fwd * back + Vector3.UP * up + right * (0.0 if putter else 1.1)  # a little off the line: the arc reads as a curve
	var look := ball + fwd * (3.0 if putter else 18.0) + Vector3.UP * (0.2 if putter else 0.0)
	if flying:
		var fp: Vector3 = game.aim_flight_pos()
		if fp != Vector3.INF:
			look = fp
	if _snap or _cam.global_position.distance_to(eye) > 30.0:
		_cam.global_position = eye
	else:
		_cam.global_position = _cam.global_position.lerp(eye, 1.0 - exp(-10.0 * delta))
	_snap = false
	if _cam.global_position.distance_to(look) > 0.1:
		_cam.look_at(look, Vector3.UP)
	_hide_blockers(player, eye, ball)
	if flying:
		return
	var key := Vector4(snappedf(yaw, 0.002), float(sp.club_id().hash() % 100000), snappedf(ball.x, 0.05), snappedf(ball.z, 0.05))
	if key == _key:
		return
	_key = key
	_mesh.clear_surfaces()
	if putter:
		_putt_line(game, ball, fwd)
	else:
		_arc(game, sp.club_id(), ball, yaw)


func _arc(game: Node, club_id: String, ball: Vector3, yaw: float) -> void:
	var t := GolfBallRules.tuning()
	if not t.clubs.has(club_id):
		return
	var s := GolfBallRules.launch(t.clubs[club_id], float(game.aim_power_mult()), ball, yaw, t)
	var dt := 1.0 / float(t.ball.step_hz)
	_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var n := 0
	while not s.landed and s.time < float(t.ball.max_flight_s):
		GolfBallRules.step(s, dt, t, ball.y)
		n += 1
		if n % 4 == 0:
			_mesh.surface_set_color(Color(1.0, 1.0, 1.0, 0.8))
			_mesh.surface_add_vertex(s.pos)
	_mesh.surface_set_color(Color(1.0, 1.0, 1.0, 0.8))
	_mesh.surface_add_vertex(s.pos)
	_mesh.surface_end()
	var land: Vector3 = game.aim_ground(s.pos)
	var dist := Vector2(land.x - ball.x, land.z - ball.z).length()
	_ring(land + Vector3.UP * 0.15, clampf(dist * 0.04, 2.0, 8.0), Color(1.0, 0.85, 0.2, 0.9))  # big enough to see far off


func _putt_line(game: Node, ball: Vector3, fwd: Vector3) -> void:
	var cup: Vector3 = game.aim_cup()
	var dist := 6.0 if cup == Vector3.INF else maxf(1.5, Vector2(cup.x - ball.x, cup.z - ball.z).length())
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var steps := clampi(ceili(dist / 0.5), 3, ARC_POINTS)
	var prev := ball + Vector3.UP * 0.03
	for i in range(1, steps + 1):
		var p: Vector3 = game.aim_ground(ball + fwd * (dist * i / steps)) + Vector3.UP * 0.03
		if i % 2 == 1:
			_mesh.surface_set_color(Color(1.0, 1.0, 1.0, 0.85))
			_mesh.surface_add_vertex(prev)
			_mesh.surface_add_vertex(p)
		prev = p
	var slope: Vector2 = game.aim_slope()
	if slope.length() > 0.01:  # ticks pointing downhill along the line: longer = steeper
		var dir := Vector3(slope.x, 0.0, slope.y).normalized() * clampf(slope.length() * 2.0, 0.15, 0.8)
		for i in range(1, 5):
			var p: Vector3 = game.aim_ground(ball + fwd * (dist * i / 5.0)) + Vector3.UP * 0.05
			_mesh.surface_set_color(Color(0.4, 0.8, 1.0, 0.9))
			_mesh.surface_add_vertex(p)
			_mesh.surface_add_vertex(p + dir)
	_mesh.surface_end()
	if cup != Vector3.INF:
		_ring(cup + Vector3.UP * 0.04, 0.25, Color(1.0, 0.85, 0.2, 0.9))


func _ring(at: Vector3, r: float, col: Color) -> void:
	_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in RING_POINTS + 1:
		var a := TAU * i / RING_POINTS
		_mesh.surface_set_color(col)
		_mesh.surface_add_vertex(at + Vector3(cos(a) * r, 0.0, sin(a) * r))
	_mesh.surface_end()


# Hides bodies (teammates, Bonk) standing between the camera and the ball, shows them again once they're clear.
func _hide_blockers(player: Node, eye: Vector3, ball: Vector3) -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if p == player or not p is Node3D:
			continue
		var at: Vector3 = (p as Node3D).global_position + Vector3.UP
		var q := Geometry3D.get_closest_point_to_segment(at, eye, ball + Vector3.UP)
		var blocks := q.distance_to(at) < 1.3
		if blocks and (p as Node3D).visible:
			(p as Node3D).visible = false
			_hidden.append(p)
		elif not blocks and p in _hidden:
			(p as Node3D).visible = true
			_hidden.erase(p)


func _unhide() -> void:
	for p in _hidden:
		if is_instance_valid(p):
			p.visible = true
	_hidden.clear()
