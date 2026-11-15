# SportInput — the local player's controls for the Drop Zone games (D-074) and golf (D-086), Player child "Sport".
# A game node puts its player into a mode with enter() (from its synced state) and out with leave():
#   "range" / "putt" / "course" (golf, D-086): the 3-click swing meter (SwingMeter): left click starts the swing,
#            left click sets the power, left click on the line sets the accuracy. Mouse aims (the GolfView camera
#            sits behind the ball, with the shot arc / putt line). 3 or the mouse wheel changes club (range and
#            course; the course picks a club for the distance - the putter on the green - when the ball stops).
#   "pickle": left click swings (or serves) toward where you look; a swing needs the windup + recovery time
#            before the next (D-089: the host enforces it, this only stops sending clicks it would ignore).
#   "pool":  (D-084, a PoolTable) on your shot hold left click to charge, release to shoot where you look; with ball in
#            hand the table takes the click (places the cue ball) instead.
# Right click cancels a swing / charge. Sends only intents to the game node (request_shot / request_hit); the host
# decides. While a mode is on, the weapon is hidden and doesn't fire (Player checks `mode`), and the disc is put away.
# Golf game nodes answer: aim_ball() (global ball, INF = none), aim_ready() (can swing now), aim_cup(), aim_clubs(),
# aim_power_mult() (the lie), aim_slope() (m/s2 downhill), aim_ground(Vector3) (point on the ground below / above),
# aim_flying() and aim_flight_pos() (the ball while it's in the air).
# HUD reads mode / club_id() / charge / meter / last_grade. Depends on: GolfBallRules (tuning), SwingMeter, GolfView,
# PickleballRules (swing timing), Player (parent: is_local, yaw, viewmodel, disc, health), the game nodes (DzRange, DzPutting, DzCourt, CourseGolf).
class_name SportInput
extends Node

const GOLF := ["range", "putt", "course"]

var mode := ""
var game: Node = null
var club_index := 0
var charge := 0.0
var charging := false
var meter := SwingMeter.new()
var last_grade := ""
var grade_time := 0.0  # seconds the last grade has left on screen

var pickle_ready_at := 0.0  # seconds (engine clock) when the next pickleball swing can start
var _view: GolfView = null
var _last_ball := Vector3.INF

@onready var player: Node = get_parent()


func enter(new_mode: String, node: Node) -> void:
	if mode == new_mode and game == node:
		return
	mode = new_mode
	game = node
	charging = false
	charge = 0.0
	club_index = 0
	_last_ball = Vector3.INF
	meter.cancel()
	if player.disc.active:
		player.disc._set_active(false)
	player.viewmodel.visible = false
	if is_golf():
		var sw: Dictionary = GolfBallRules.tuning().swing
		var putt := mode == "putt"
		meter.setup(float(sw.putt_up_s if putt else sw.up_s), float(sw.putt_down_s if putt else sw.down_s), sw)
		if player.is_local and _view == null:
			_view = GolfView.new()
			_view.name = "GolfView"
			add_child(_view)


func leave(node: Node) -> void:
	if game != node:
		return
	mode = ""
	game = null
	charging = false
	charge = 0.0
	meter.cancel()
	player.viewmodel.visible = not player.disc.active
	if _view:
		_view.stop(player)


func is_golf() -> bool:
	return mode in GOLF


func clubs() -> Array:
	if is_golf() and game and game.has_method("aim_clubs"):
		return game.aim_clubs()
	return GolfBallRules.tuning().club_order


func club_id() -> String:
	var order := clubs()
	return str(order[club_index % order.size()]) if not order.is_empty() else ""


func _unhandled_input(event: InputEvent) -> void:
	if not player.is_local or mode == "" or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if is_golf():
		_golf_input(event)
	elif mode == "pickle" and event.is_action_pressed("fire"):
		var now := Time.get_ticks_msec() / 1000.0
		if now >= pickle_ready_at or game.phase == "serve":
			var pb := PickleballRules.tuning()
			if game.phase != "serve":
				pickle_ready_at = now + float(pb.windup_s) + float(pb.recovery_s)
			game.request_hit.rpc_id(1, player.yaw)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		charging = false
		charge = 0.0


func _golf_input(event: InputEvent) -> void:
	if event.is_action_pressed("fire"):
		if meter.busy() or game.aim_ready():
			meter.click()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		meter.cancel()
	elif not meter.busy() and mode != "putt":
		var step := 0
		if event.is_action_pressed("disc_mode") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			step = 1
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			step = -1
		if step != 0:
			club_index = posmod(club_index + step, clubs().size())
			get_viewport().set_input_as_handled()


# 0..1: how far the pickleball swing has recovered (1 = ready).
func pickle_ready() -> float:
	var pb := PickleballRules.tuning()
	var total := float(pb.windup_s) + float(pb.recovery_s)
	return clampf(1.0 - (pickle_ready_at - Time.get_ticks_msec() / 1000.0) / total, 0.0, 1.0)


func _process(delta: float) -> void:
	grade_time = maxf(0.0, grade_time - delta)
	if not player.is_local or game == null:
		return
	if is_golf():
		_golf_process(delta)
		return
	if mode != "pool":
		return
	if not game.my_turn() or game.placing():
		charging = false
		charge = 0.0
		return
	var can: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not player.health.is_dead()
	if can and Input.is_action_pressed("fire"):
		charging = true
		charge = minf(1.0, charge + delta / float(PoolRules.tuning().charge_seconds))
	elif charging:
		charging = false
		if can:
			game.request_shot.rpc_id(1, club_id(), charge, player.yaw)
		charge = 0.0


func _golf_process(delta: float) -> void:
	var ball: Vector3 = game.aim_ball()
	if ball != _last_ball and not game.aim_flying():
		_last_ball = ball
		if ball != Vector3.INF:
			_pick_club(ball)
	if meter.busy() and (player.health.is_dead() or not game.aim_ready()):
		meter.cancel()
	meter.update(delta)
	charge = meter.power if meter.phase != SwingMeter.Phase.POWER else meter.value
	if meter.phase == SwingMeter.Phase.DONE:
		last_grade = meter.grade
		grade_time = float(GolfBallRules.tuning().swing.grade_show_s)
		game.request_shot.rpc_id(1, club_id(), meter.power, player.yaw, meter.error)
		meter.cancel()
	if _view:
		_view.update_view(player, self, delta)


# Course: the putter on the green, otherwise the shortest club that carries to the cup at full power.
func _pick_club(ball: Vector3) -> void:
	var order := clubs()
	if mode != "course" or order.is_empty():
		return
	var cup: Vector3 = game.aim_cup()
	if cup == Vector3.INF:
		return
	if game.aim_on_green():
		club_index = order.find("putter")
		return
	var dist := Vector2(cup.x - ball.x, cup.z - ball.z).length()
	var t := GolfBallRules.tuning()
	var pick := 0
	for i in order.size():
		var id := str(order[i])
		if t.clubs.has(id) and GolfBallRules.carry(t.clubs[id], game.aim_power_mult(), t) >= dist:
			pick = i
	club_index = pick
