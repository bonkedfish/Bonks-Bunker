# DzPutting — Drop Zone's 18-hole putting course (D-074), DropZone child "Putting".
#   Host: E at the start sign gives that player a card (ball on hole 1's tee). Validates putt intents (has a card,
#         standing by their ball, ball at rest), rolls the putt at once (GolfBallRules.roll_putt: green / fringe /
#         sand speeds, water and out of the course = +1 and back to the last spot, the cup catches slow balls),
#         sends the path to everyone, and when it has stopped on screen moves the ball, scores holed / picked-up
#         holes (max_strokes) and moves on to the next tee. After 18 the card is done (best: quest flag
#         "dz_best_putting", lowest). Walking off the course drops the card.
#   Every peer: `cards` (peer -> {hole, strokes: Array, ball: Vector2, throws, done}) synced whole; ball playback /
#         resting balls; puts the local player's SportInput into "putt" mode while they have a card.
# Depends on: DropZone (parent: data, sender_player, toast), GolfBallRules, BallPlayback, SportInput, QuestDirector.
class_name DzPutting
extends Node3D

signal changed

const LEAVE_M := 30.0
const BALL_Y := 0.06

var cards: Dictionary = {}

var _t: Dictionary
var _play: BallPlayback
var _in_flight: Dictionary = {}  # host: peer -> [seconds left, result Dictionary, from Vector2]
var _check := 0.0


func _ready() -> void:
	_t = GolfBallRules.tuning()
	_play = BallPlayback.new()
	_play.radius = 0.045
	_play.color = Color(1.0, 0.85, 0.2)
	add_child(_play)
	multiplayer.peer_connected.connect(_on_peer_connected)


func dz() -> Node:
	return get_parent()


func hole_def(i: int) -> Dictionary:
	return dz().data.putting.holes[i]


func par_total() -> int:
	var total := 0
	for h: Dictionary in dz().data.putting.holes:
		total += int(h.par)
	return total


func is_rolling(peer: int) -> bool:
	return _play.is_playing(peer)


@rpc("any_peer", "call_local", "reliable")
func request_use(_index: int) -> void:
	var p := DropZone.sender_player(self)
	if p == null:
		return
	var s: Array = dz().data.putting.start
	var at: Vector3 = dz().to_local_pos(p.global_position)
	if Vector2(at.x - float(s[0]), at.z - float(s[1])).length() > float(_t.putting.start_radius_m):
		return
	if cards.has(p.peer_id) and not cards[p.peer_id].done:
		_say.rpc_id(p.peer_id, "You're on hole %d" % (int(cards[p.peer_id].hole) + 1))
		return
	var strokes: Array = []
	strokes.resize(dz().data.putting.holes.size())
	strokes.fill(0)
	var tee: Array = hole_def(0).tee
	cards[p.peer_id] = {"hole": 0, "strokes": strokes, "ball": Vector2(tee[0], tee[1]), "throws": 0, "done": false}
	_sync.rpc(cards)
	_say.rpc_id(p.peer_id, "Putting course: 18 holes, par %d. Stand by your ball, hold left click to putt." % par_total())


@rpc("any_peer", "call_local", "reliable")
func request_shot(_club: String, power: float, yaw: float) -> void:
	var p := DropZone.sender_player(self)
	if p == null or not cards.has(p.peer_id) or _in_flight.has(p.peer_id):
		return
	var c: Dictionary = cards[p.peer_id]
	if c.done:
		return
	var at: Vector3 = dz().to_local_pos(p.global_position)
	var ball: Vector2 = c.ball
	if Vector2(at.x, at.z).distance_to(ball) > float(_t.putting.lie_radius_m):
		_say.rpc_id(p.peer_id, "Walk up to your ball")
		return
	var res := GolfBallRules.roll_putt(ball, yaw - dz().global_rotation.y, power, hole_def(int(c.hole)), dz().data.putting.area, _t)
	var path3 := PackedVector3Array()
	for q: Vector2 in res.path:
		path3.append(Vector3(q.x, BALL_Y, q.y))
	_in_flight[p.peer_id] = [_play.duration(path3, float(_t.ball.sample_hz)) + 0.2, res, ball]
	_show.rpc(p.peer_id, path3)


func _physics_process(delta: float) -> void:
	if not (multiplayer.has_multiplayer_peer() and multiplayer.is_server()):
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
	var a: Array = dz().data.putting.area
	var area := Rect2(Vector2(a[0], a[1]), Vector2(float(a[2]) - float(a[0]), float(a[3]) - float(a[1]))).grow(LEAVE_M)
	for peer: int in cards.keys():
		var p := DropZone.player_by_peer(self, peer)
		var at: Vector3 = dz().to_local_pos(p.global_position) if p else Vector3.INF
		if p == null or not area.has_point(Vector2(at.x, at.z)):
			cards.erase(peer)
			_in_flight.erase(peer)
			_sync.rpc(cards)


func _land(peer: int, res: Dictionary, from: Vector2) -> void:
	if not cards.has(peer):
		return
	var c: Dictionary = cards[peer]
	var hole := int(c.hole)
	c.throws = int(c.throws) + 1
	if res.water or res.out:
		c.throws = int(c.throws) + 1
		c.ball = from
		_say.rpc_id(peer, ("In the water" if res.water else "Off the course") + " - +1, play it again")
	else:
		c.ball = res.end
	if res.holed or int(c.throws) >= int(_t.putting.max_strokes):
		c.strokes[hole] = mini(int(c.throws), int(_t.putting.max_strokes))
		var par := int(hole_def(hole).par)
		_say.rpc_id(peer, "Hole %d: %s" % [hole + 1, DiscGolfRules.score_name(int(c.strokes[hole]), par) if res.holed else "picked up"])
		c.hole = hole + 1
		c.throws = 0
		if int(c.hole) >= dz().data.putting.holes.size():
			c.done = true
			var total := 0
			for s: Variant in c.strokes:
				total += int(s)
			var quests := get_tree().get_first_node_in_group("quests")
			var best := int(quests.flags.get("dz_best_putting", 0)) if quests else 0
			if quests and (best == 0 or total < best):
				quests.host_add_count("dz_best_putting", total - best)
			_say.rpc_id(peer, "Putting course done: %d (%s)" % [total, DiscGolfRules.to_par_text(total, par_total())])
		else:
			var tee: Array = hole_def(int(c.hole)).tee
			c.ball = Vector2(tee[0], tee[1])
	_sync.rpc(cards)


func _on_peer_connected(peer: int) -> void:
	if multiplayer.is_server():
		_sync.rpc_id(peer, cards)


@rpc("authority", "call_local", "reliable")
func _sync(new_cards: Dictionary) -> void:
	cards = new_cards
	for peer: int in cards:  # balls rest at their lies
		var c: Dictionary = cards[peer]
		if not _play.is_playing(peer):
			_play.rest(peer, Vector3.INF if c.done else Vector3(c.ball.x, BALL_Y, c.ball.y))
	var me := get_tree().get_first_node_in_group("local_player")
	if me and "sport" in me:
		var mine: Dictionary = cards.get(multiplayer.get_unique_id(), {})
		if not mine.is_empty() and not mine.done:
			me.sport.enter("putt", self)
		else:
			me.sport.leave(self)
	changed.emit()


@rpc("authority", "call_local", "reliable")
func _show(peer: int, path: PackedVector3Array) -> void:
	_play.play(peer, path, float(_t.ball.sample_hz))


@rpc("authority", "call_local", "reliable")
func _say(text: String) -> void:
	DropZone.toast(self, text)
