# CourseGolf — the Kearney Country Club as a playable 18-hole golf course (D-086), "Golf" node in the country_club
# landmark scene (same path on every peer). Plays with the Drop Zone swing (SportInput "course" mode, GolfView,
# SwingMeter) on the real terrain:
#   Host: E at any tee sign gives that player a card starting on that hole (18 holes, wrapping round). Validates
#         shot intents (has a card, standing by their ball, ball at rest, a club in the bag; power / meter error
#         clamped), simulates the shot at once (CourseShot: flight over the terrain, trees, lies, slope, cup), sends
#         the path to everyone and, when it has stopped on screen, moves the ball: holed / picked up (max_strokes)
#         moves on to the next tee; water or out of bounds = +1, played again from the last spot. After 18 holes the
#         card is done (best round: quest flag "kcc_best_round", lowest). Leaving the course area drops the card.
#   Every peer: `cards` (peer -> {start, played, hole, strokes: Array, ball: Vector3, throws, done, lie}) synced
#         whole; ball playback with a name marker over each resting ball; answers the local player's GolfView /
#         SportInput aim_* questions; adds CourseGolfHud under the HUD.
# Depends on: DataLoader, data/golf/country_club_course.json, GolfBallRules, CourseLies, CourseShot, BallPlayback,
# PlayerColors, DropZone (sender_player / player_by_peer / toast helpers), SportInput (Player "sport"), QuestDirector (group
# "quests"), CourseGolfHud.
class_name CourseGolf
extends Node3D

signal changed

const DATA_PATH := "res://data/golf/country_club_course.json"
const SPOT_LAYER := 8
const LEAVE_MARGIN_M := 60.0
const CourseGolfHud := preload("res://scripts/ui/course_golf_hud.gd")

var cards: Dictionary = {}
var course: Dictionary = {}
var lies: CourseLies

var _t: Dictionary
var _play: BallPlayback
var _in_flight: Dictionary = {}  # host: peer -> [seconds left, result Dictionary, from Vector3]
var _cups: Dictionary = {}  # hole -> Vector3 (global, once the ground under the flag is found)
var _markers: Dictionary = {}  # peer -> Label3D over the resting ball
var _check := 0.0
var _probe_shot: CourseShot = null


func _ready() -> void:
	add_to_group("course_golf")
	course = DataLoader.load_json(DATA_PATH)
	if course.is_empty():
		return
	_t = GolfBallRules.tuning()
	lies = CourseLies.new(course.bounds)
	_play = BallPlayback.new()
	_play.name = "Balls"
	_play.radius = 0.06
	_play.top_level = true  # paths are global
	add_child(_play)
	for i in course.holes.size():
		var h: Dictionary = course.holes[i]
		var body := StaticBody3D.new()
		body.collision_layer = SPOT_LAYER
		body.collision_mask = 0
		body.position = Vector3(float(h.sign[0]), 0.0, float(h.sign[1]))
		body.add_to_group("sport_spots")
		body.set_meta("target", self)
		body.set_meta("index", i)
		body.set_meta("display_name", "Tee off: hole %d (par %d, %d yd) - 18 holes from here" % [i + 1, int(h.par), int(h.yards)])
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.0, 50.0, 1.0)  # stands through the sign whatever the ground height
		shape.shape = box
		body.add_child(shape)
		add_child(body)
	multiplayer.peer_connected.connect(_on_peer_connected)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.add_child.call_deferred(CourseGolfHud.new())


func hole_def(i: int) -> Dictionary:
	return course.holes[i]


func hole_count() -> int:
	return course.holes.size()


func par_total() -> int:
	var total := 0
	for h: Dictionary in course.holes:
		total += int(h.par)
	return total


func local_to_world(x: float, z: float, y := 0.0) -> Vector3:
	return global_transform * Vector3(x, y, z)


func _shot() -> CourseShot:
	return CourseShot.new(get_world_3d().direct_space_state, _t, course, lies, global_transform)


# One shared shot object for the per-frame ground / slope lookups (no allocation each call).
func _probe() -> CourseShot:
	if _probe_shot == null:
		_probe_shot = _shot()
	return _probe_shot


# The cup of a hole (global) with its ground height; Vector3.INF until the ground there has loaded.
func cup_pos(i: int) -> Vector3:
	if _cups.has(i):
		return _cups[i]
	var h: Dictionary = hole_def(i)
	var g := _probe().ground(local_to_world(float(h.cup[0]), float(h.cup[1]), 40.0))
	if g.is_empty():
		return Vector3.INF
	_cups[i] = g.pos
	return g.pos


func is_flying(peer: int) -> bool:
	return _play.is_playing(peer)


# --- requests -------------------------------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func request_use(index: int) -> void:
	var p := DropZone.sender_player(self)
	if p == null or index < 0 or index >= hole_count():
		return
	var h: Dictionary = hole_def(index)
	if p.global_position.distance_to(local_to_world(float(h.sign[0]), float(h.sign[1]), p.global_position.y - global_position.y)) > 12.0:
		return
	if cards.has(p.peer_id) and not cards[p.peer_id].done:
		_say.rpc_id(p.peer_id, "You're on hole %d - walk off the course to drop your card" % (int(cards[p.peer_id].hole) + 1))
		return
	var tee := _tee_pos(index, p.global_position.y)
	var strokes: Array = []
	strokes.resize(hole_count())
	strokes.fill(0)
	cards[p.peer_id] = {"start": index, "played": 0, "hole": index, "strokes": strokes, "ball": tee, "throws": 0, "done": false,
		"lie": "tee"}
	_sync.rpc(cards)
	_say.rpc_id(p.peer_id, "Kearney Country Club from hole %d, par %d. Click to swing, click for power, click on the line. 3 / wheel: club." % [
		index + 1, par_total()])


@rpc("any_peer", "call_local", "reliable")
func request_shot(club: String, power: float, yaw: float, error := 0.0) -> void:
	var p := DropZone.sender_player(self)
	if p == null or not cards.has(p.peer_id) or _in_flight.has(p.peer_id):
		return
	var c: Dictionary = cards[p.peer_id]
	if c.done or not club in _t.course_clubs:
		return
	var ball: Vector3 = c.ball
	if Vector2(p.global_position.x - ball.x, p.global_position.z - ball.z).length() > float(course.lie_radius_m) \
			or absf(p.global_position.y - ball.y) > 3.0:
		_say.rpc_id(p.peer_id, "Walk up to your ball")
		return
	var cup := cup_pos(int(c.hole))
	var res := _shot().simulate(ball, club, clampf(power, 0.0, 1.0), yaw, clampf(error, -1.5, 1.5),
		cup if cup != Vector3.INF else Vector3(0, -1000, 0))
	_in_flight[p.peer_id] = [_play.duration(res.path, float(_t.ball.sample_hz)) + 0.3, res, ball]
	_show.rpc(p.peer_id, res.path)


func _tee_pos(i: int, fallback_y: float) -> Vector3:
	var h: Dictionary = hole_def(i)
	var at := local_to_world(float(h.tee[0]), float(h.tee[1]), 40.0)
	var g := _shot().ground(at)
	return g.pos if not g.is_empty() else Vector3(at.x, fallback_y, at.z)


# --- host tick ----------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if course.is_empty() or not (multiplayer.has_multiplayer_peer() and multiplayer.is_server()):
		return
	for peer: int in _in_flight.keys():
		var fl: Array = _in_flight[peer]
		fl[0] = float(fl[0]) - delta
		if float(fl[0]) <= 0.0:
			_in_flight.erase(peer)
			_land(peer, fl[1], fl[2])
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	var area := lies.bounds.grow(LEAVE_MARGIN_M)
	for peer: int in cards.keys():
		var p := DropZone.player_by_peer(self, peer)
		var at: Vector3 = to_local(p.global_position) if p else Vector3.INF
		if p == null or not area.has_point(Vector2(at.x, at.z)):
			if p and not cards[peer].done:
				_say.rpc_id(peer, "Left the course - card dropped")
			cards.erase(peer)
			_in_flight.erase(peer)
			_sync.rpc(cards)


func _land(peer: int, res: Dictionary, from: Vector3) -> void:
	if not cards.has(peer):
		return
	var c: Dictionary = cards[peer]
	var hole := int(c.hole)
	c.throws = int(c.throws) + 1
	if res.water or res.out:
		c.throws = int(c.throws) + 1
		c.ball = from
		c.lie = str(lies.lie_at(_flat(to_local(from))))
		_say.rpc_id(peer, ("In the water" if res.water else "Out of bounds") + " - +1, play it again")
	else:
		c.ball = res.end
		c.lie = str(res.lie)
		if not res.holed:
			var cup := cup_pos(hole)
			var left := Vector2(cup.x - res.end.x, cup.z - res.end.z).length() * 1.09361 if cup != Vector3.INF else 0.0
			_say.rpc_id(peer, "%s - %d yd to the pin" % [str(res.lie).capitalize(), roundi(left)])
	if res.holed or int(c.throws) >= int(course.max_strokes):
		c.strokes[hole] = mini(int(c.throws), int(course.max_strokes))
		var par := int(hole_def(hole).par)
		_say.rpc_id(peer, "Hole %d: %s" % [hole + 1, DiscGolfRules.score_name(int(c.strokes[hole]), par) if res.holed else "picked up"])
		c.played = int(c.played) + 1
		c.throws = 0
		if int(c.played) >= hole_count():
			c.done = true
			var total := 0
			for s: Variant in c.strokes:
				total += int(s)
			var quests := get_tree().get_first_node_in_group("quests")
			var best := int(quests.flags.get("kcc_best_round", 0)) if quests else 0
			if quests and (best == 0 or total < best):
				quests.host_add_count("kcc_best_round", total - best)
			_say.rpc_id(peer, "Round done: %d (%s)" % [total, DiscGolfRules.to_par_text(total, par_total())])
		else:
			c.hole = (hole + 1) % hole_count()
			c.ball = _tee_pos(int(c.hole), from.y)
			c.lie = "tee"
			_say.rpc_id(peer, "Hole %d, par %d - %d yd. Head to the tee." % [int(c.hole) + 1, int(hole_def(int(c.hole)).par),
				int(hole_def(int(c.hole)).yards)])
	_sync.rpc(cards)


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _on_peer_connected(peer: int) -> void:
	if multiplayer.is_server():
		_sync.rpc_id(peer, cards)


# --- every peer ---------------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _sync(new_cards: Dictionary) -> void:
	cards = new_cards
	for peer: int in _markers.keys():
		if not cards.has(peer) or cards[peer].done:
			_markers[peer].queue_free()
			_markers.erase(peer)
			_play.rest(peer, Vector3.INF)
	for peer: int in cards:
		var c: Dictionary = cards[peer]
		if c.done:
			continue
		if not _play.is_playing(peer):
			_play.rest(peer, c.ball)
		_marker(peer).global_position = (c.ball as Vector3) + Vector3.UP * 1.4
	var me := get_tree().get_first_node_in_group("local_player")
	if me and "sport" in me:
		var mine: Dictionary = cards.get(multiplayer.get_unique_id(), {})
		if not mine.is_empty() and not mine.done:
			me.sport.enter("course", self)
		else:
			me.sport.leave(self)
	changed.emit()


func _marker(peer: int) -> Label3D:
	if not _markers.has(peer):
		var nl := Label3D.new()
		nl.top_level = true
		nl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		nl.no_depth_test = true
		nl.fixed_size = true
		nl.pixel_size = 0.0012
		nl.font_size = 24
		nl.outline_size = 6
		nl.visibility_range_end = 450.0
		add_child(nl)
		_markers[peer] = nl
	var l: Label3D = _markers[peer]
	for p in get_tree().get_nodes_in_group("players"):
		if "net_name" in p and p.peer_id == peer:
			l.text = "v  %s" % (str(p.net_name) if str(p.net_name) != "" else "Ball")
			l.modulate = PlayerColors.color(int(p.get("net_color")))
	return l


@rpc("authority", "call_local", "reliable")
func _show(peer: int, path: PackedVector3Array) -> void:
	_play.play(peer, path, float(_t.ball.sample_hz))


@rpc("authority", "call_local", "reliable")
func _say(text: String) -> void:
	DropZone.toast(self, text)


# --- the local player's golf view (SportInput / GolfView) -----------------------------------------

func my_card() -> Dictionary:
	var c: Dictionary = cards.get(multiplayer.get_unique_id(), {})
	return {} if c.is_empty() or c.done else c


func aim_ball() -> Vector3:
	var c := my_card()
	return Vector3.INF if c.is_empty() else c.ball


func aim_ready() -> bool:
	var me := get_tree().get_first_node_in_group("local_player")
	var ball := aim_ball()
	if me == null or ball == Vector3.INF or aim_flying() or me.bike.mounted:
		return false
	return Vector2(me.global_position.x - ball.x, me.global_position.z - ball.z).length() <= float(course.lie_radius_m) \
		and absf(me.global_position.y - ball.y) <= 3.0


func aim_flying() -> bool:
	return is_flying(multiplayer.get_unique_id())


func aim_flight_pos() -> Vector3:
	return _play.world_pos(multiplayer.get_unique_id())


func aim_cup() -> Vector3:
	var c := my_card()
	return Vector3.INF if c.is_empty() else cup_pos(int(c.hole))


func aim_clubs() -> Array:
	return _t.course_clubs


func aim_power_mult() -> float:
	var c := my_card()
	return float(course.lies.get(str(c.get("lie", "rough")), course.lies.rough).power) if not c.is_empty() else 1.0


func aim_on_green() -> bool:
	return str(my_card().get("lie", "")) == "green"


func aim_slope() -> Vector2:
	var ball := aim_ball()
	if ball == Vector3.INF:
		return Vector2.ZERO
	var g := _probe().ground(ball + Vector3.UP)
	if g.is_empty():
		return Vector2.ZERO
	var n: Vector3 = g.normal
	return Vector2(n.x, n.z) * (9.8 * float(course.slope_scale))


func aim_ground(p: Vector3) -> Vector3:
	var g := _probe().ground(p + Vector3.UP * 2.0)
	return p if g.is_empty() else g.pos
