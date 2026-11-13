# DzRange — the Drop Zone target game at the 32 bays (D-074), DropZone child "Range".
#   Host: E at a bay screen gives that player a game of `balls` balls in that bay (one player per bay). Validates
#         shot intents (in a game, balls left, standing in the bay, no ball in the air), simulates the whole shot at
#         once (GolfBallRules: flight, first bounce, roll-out; the side and far nets stop it), sends the path to
#         everyone, and when it has landed on screen scores the first landing on the targets (bullseye doubles), tells
#         the player and syncs the board. The last ball ends the game (best score: quest flag "dz_best_range").
#         Walking away from the bay forfeits.
#   Every peer: `games` (peer -> {bay, balls, score, last}), synced whole on change; ball playback; puts the local
#         player's SportInput into "range" mode while they have a game.
# Depends on: DropZone (parent: data, sender_player, toast), GolfBallRules, BallPlayback, SportInput (Player "sport"),
# QuestDirector (group "quests").
class_name DzRange
extends Node3D

signal changed

const LEAVE_M := 6.0

var games: Dictionary = {}

var _t: Dictionary
var _play: BallPlayback
var _in_flight: Dictionary = {}  # host: peer -> [seconds left, points, target index]
var _check := 0.0


func _ready() -> void:
	_t = GolfBallRules.tuning()
	_play = BallPlayback.new()
	_play.radius = 0.05
	add_child(_play)
	multiplayer.peer_connected.connect(_on_peer_connected)


func dz() -> Node:
	return get_parent()


func bay_spot(i: int) -> Vector3:
	var b: Dictionary = dz().data.bays[i]
	return Vector3(float(b.x), float(b.y), float(b.z))


func is_flying(peer: int) -> bool:
	return _play.is_playing(peer)


# --- requests -------------------------------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func request_use(index: int) -> void:
	var p := DropZone.sender_player(self)
	if p == null or index < 0 or index >= dz().data.bays.size():
		return
	var at: Vector3 = dz().to_local_pos(p.global_position)
	if at.distance_to(bay_spot(index)) > 9.0:
		return
	if games.has(p.peer_id):
		_say.rpc_id(p.peer_id, "You already have a game going in bay %d" % (int(games[p.peer_id].bay) + 1))
		return
	for g: Dictionary in games.values():
		if int(g.bay) == index:
			_say.rpc_id(p.peer_id, "Bay %d is taken" % (index + 1))
			return
	games[p.peer_id] = {"bay": index, "balls": int(_t.range.balls), "score": 0, "last": -1}
	_sync.rpc(games)
	_say.rpc_id(p.peer_id, "Bay %d: %d balls. Hold left click to swing, 3 = next club. Land it on a target!" % [index + 1, int(_t.range.balls)])


@rpc("any_peer", "call_local", "reliable")
func request_shot(club_id: String, power: float, yaw: float) -> void:
	var p := DropZone.sender_player(self)
	if p == null or not games.has(p.peer_id) or _in_flight.has(p.peer_id) or not _t.clubs.has(club_id):
		return
	var g: Dictionary = games[p.peer_id]
	if int(g.balls) <= 0:
		return
	var tee := bay_spot(int(g.bay))
	var at: Vector3 = dz().to_local_pos(p.global_position)
	if Vector2(at.x - tee.x, at.z - tee.z).length() > float(_t.range.bay_radius_m) or absf(at.y - tee.y) > 1.5:
		_say.rpc_id(p.peer_id, "Step up to the mat in your bay")
		return
	var local_yaw: float = yaw - dz().global_rotation.y
	var shot := GolfBallRules.launch(_t.clubs[club_id], power, Vector3(tee.x, 0.0, tee.z), local_yaw, _t)
	var path := _simulate(shot, tee.y)
	var score := GolfBallRules.target_score(shot.land if shot.landed else Vector3.INF, dz().data.targets, _t)
	g.balls = int(g.balls) - 1
	_in_flight[p.peer_id] = [_play.duration(path, float(_t.ball.sample_hz)) + 0.2, score.x, score.y]
	_show.rpc(p.peer_id, path)


# Whole shot from the bay (tee level y0: the ground is y 0, an upper-bay shot starts y0 higher).
func _simulate(s: GolfBallRules.Shot, y0: float) -> PackedVector3Array:
	var dt := 1.0 / float(_t.ball.step_hz)
	var every := maxi(1, roundi(float(_t.ball.step_hz) / float(_t.ball.sample_hz)))
	var n: Dictionary = dz().data.nets
	var face := float(dz().data.bay_face_x)
	var back := s.pos.x - 1.0  # mishit backwards into the bay: stop
	s.pos.y += y0
	var path := PackedVector3Array([s.pos])
	var steps := 0
	while not s.stopped and s.time < float(_t.ball.max_flight_s):
		GolfBallRules.step(s, dt, _t)
		if s.pos.y < 0.0:
			s.pos.y = 0.0
		var hit_net := s.pos.z < float(n.north_z) or s.pos.z > float(n.south_z) or s.pos.x > float(n.far_x) or s.pos.x < back
		if hit_net and s.pos.y < float(n.height):  # the net stops it; it drops straight down
			s.pos = Vector3(clampf(s.pos.x, minf(back, face), float(n.far_x) - 0.1), s.pos.y,
				clampf(s.pos.z, float(n.north_z) + 0.1, float(n.south_z) - 0.1))
			s.vel = Vector3(0.0, minf(s.vel.y, 0.0), 0.0)
		steps += 1
		if steps % every == 0:
			path.append(s.pos)
	path.append(s.pos)
	return path


# --- host tick ----------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not (multiplayer.has_multiplayer_peer() and multiplayer.is_server()):
		return
	for peer: int in _in_flight.keys():
		var fl: Array = _in_flight[peer]
		fl[0] = float(fl[0]) - delta
		if float(fl[0]) <= 0.0:
			_in_flight.erase(peer)
			_land(peer, int(fl[1]), int(fl[2]))
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	for peer: int in games.keys():  # walked off, or left the game
		var p := DropZone.player_by_peer(self, peer)
		if p == null or (dz().to_local_pos(p.global_position)).distance_to(bay_spot(int(games[peer].bay))) > LEAVE_M:
			games.erase(peer)
			_in_flight.erase(peer)
			_sync.rpc(games)


func _land(peer: int, points: int, target: int) -> void:
	if not games.has(peer):
		return
	var g: Dictionary = games[peer]
	g.score = int(g.score) + points
	g.last = points
	var what := "Miss" if target < 0 else "+%d  %s%s" % [points, str(dz().data.targets[target].color).capitalize(),
		"  BULLSEYE" if points > int(dz().data.targets[target].points) else ""]
	_say.rpc_id(peer, "%s   (score %d, %d balls left)" % [what, int(g.score), int(g.balls)])
	if int(g.balls) <= 0:
		var score := int(g.score)
		games.erase(peer)
		var quests := get_tree().get_first_node_in_group("quests")
		var best := int(quests.flags.get("dz_best_range", 0)) if quests else 0
		if quests and score > best:
			quests.host_add_count("dz_best_range", score - best)
		_say.rpc_id(peer, "Game over: %d points%s" % [score, "  - new Drop Zone record!" if score > best and best > 0 else ""])
	_sync.rpc(games)


func _on_peer_connected(peer: int) -> void:
	if multiplayer.is_server():
		_sync.rpc_id(peer, games)


# --- every peer ---------------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _sync(new_games: Dictionary) -> void:
	games = new_games
	var me := get_tree().get_first_node_in_group("local_player")
	if me and "sport" in me:
		if games.has(multiplayer.get_unique_id()):
			me.sport.enter("range", self)
		else:
			me.sport.leave(self)
	changed.emit()


@rpc("authority", "call_local", "reliable")
func _show(peer: int, path: PackedVector3Array) -> void:
	_play.play(peer, path, float(_t.ball.sample_hz))


@rpc("authority", "call_local", "reliable")
func _say(text: String) -> void:
	DropZone.toast(self, text)
