# PoolRules — pure pool / billiards rules (D-084), from data/pool/pool.json. Table frame: x along the length (head /
# break end -x), y across, origin at the centre, metres. Balls: index 0 = cue, 1-7 solids, 8 = the 8-ball, 9-15
# stripes; positions in a PackedVector2Array of 16, pocketed balls sit at OUT.
#   rack(): a fresh 8-ball rack (8 in the middle, a solid and a stripe in the back corners) + the cue on the head spot.
#   Shot: new_shot() then advance() a slice at a time (the host spreads it over frames) until done: rolling friction,
#   ball-ball and cushion bounces, pockets; records the first ball the cue hits, what dropped (in order), clack /
#   pocket sound events and positions every frame_dt for playback.
#   aim_probe(): where the cue ball would first touch a ball or cushion going straight (aim line + ghost ball).
#   judge(): simple 8-ball on a game state {seats [peer, peer], groups ["", ""], turn, break_shot, ball_in_hand,
#   over, winner, msg}: fouls (scratch, no hit, wrong group first) -> ball in hand; own ball down keeps the turn;
#   groups from the first ball after the break; the 8 last wins, early or on a foul loses, on the break re-spots.
#   With one seat taken (practice) there are no groups or losing: clear the table to re-rack.
# Pure: no scene or rendering dependencies. Depends on: DataLoader.
class_name PoolRules
extends RefCounted

const PATH := "res://data/pool/pool.json"
const OUT := Vector2(99.0, 99.0)
const BALLS := 16
const MAX_EVENTS := 48
const SCHEMA := {
	"note": TYPE_STRING, "length": TYPE_FLOAT, "width": TYPE_FLOAT, "surface_h": TYPE_FLOAT, "ball_r": TYPE_FLOAT,
	"corner_r": TYPE_FLOAT, "side_r": TYPE_FLOAT, "corner_gap": TYPE_FLOAT, "side_gap": TYPE_FLOAT, "decel": TYPE_FLOAT,
	"drag": TYPE_FLOAT, "ball_e": TYPE_FLOAT, "rail_e": TYPE_FLOAT, "sim_dt": TYPE_FLOAT, "frame_dt": TYPE_FLOAT,
	"max_time": TYPE_FLOAT, "max_speed": TYPE_FLOAT, "min_speed": TYPE_FLOAT, "stop_speed": TYPE_FLOAT,
	"charge_seconds": TYPE_FLOAT, "shoot_range": TYPE_FLOAT, "leave_m": TYPE_FLOAT, "sim_budget_ms": TYPE_FLOAT,
	"colors": TYPE_ARRAY,
}

static var _t: Dictionary = {}


static func tuning() -> Dictionary:
	if _t.is_empty():
		_t = DataLoader.load_validated(PATH, SCHEMA)
	return _t


static func head_spot(t: Dictionary) -> Vector2:
	return Vector2(-float(t.length) * 0.25, 0.0)


static func foot_spot(t: Dictionary) -> Vector2:
	return Vector2(float(t.length) * 0.25, 0.0)


static func pockets(t: Dictionary) -> PackedVector2Array:
	var hx := float(t.length) * 0.5 + 0.01
	var hy := float(t.width) * 0.5 + 0.01
	return PackedVector2Array([Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(-hx, hy), Vector2(hx, hy),
		Vector2(0.0, -hy - 0.02), Vector2(0.0, hy + 0.02)])


static func is_solid(b: int) -> bool:
	return b >= 1 and b <= 7


static func is_stripe(b: int) -> bool:
	return b >= 9 and b <= 15


static func group_of(b: int) -> String:
	return "solids" if is_solid(b) else ("stripes" if is_stripe(b) else "")


# Fresh rack: apex on the foot spot pointing at the cue, 8 in the middle of row 3, a solid and a stripe in the back
# corners, the rest shuffled by `seed`.
static func rack(seed: int, t: Dictionary) -> PackedVector2Array:
	var r := float(t.ball_r)
	var gap := r * 2.0 + 0.0008
	var spots: Array[Vector2] = []
	for row in 5:
		for k in row + 1:
			spots.append(foot_spot(t) + Vector2(row * gap * 0.866, (k - row * 0.5) * gap))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var solids: Array = [1, 2, 3, 4, 5, 6, 7]
	var stripes: Array = [9, 10, 11, 12, 13, 14, 15]
	var order: Array = []  # ball for each spot index
	order.resize(15)
	order[4] = 8  # middle of row 3
	var corner_solid_left := rng.randf() < 0.5
	var s0: int = solids.pop_at(rng.randi() % solids.size())
	var p0: int = stripes.pop_at(rng.randi() % stripes.size())
	order[10] = s0 if corner_solid_left else p0  # back row corners
	order[14] = p0 if corner_solid_left else s0
	var rest: Array = solids + stripes
	for i in range(rest.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp: Variant = rest[i]
		rest[i] = rest[j]
		rest[j] = tmp
	for i in 15:
		if order[i] == null:
			order[i] = rest.pop_back()
	var pos := PackedVector2Array()
	pos.resize(BALLS)
	pos[0] = head_spot(t)
	for i in 15:
		pos[int(order[i])] = spots[i]
	return pos


# --- the shot ----------------------------------------------------------------------------------------

static func new_shot(pos: PackedVector2Array, cue_vel: Vector2) -> Dictionary:
	var vel := PackedVector2Array()
	vel.resize(BALLS)
	vel[0] = cue_vel
	return {"pos": pos.duplicate(), "vel": vel, "time": 0.0, "next_frame": 0.0, "first_hit": -1, "pocketed": [],
		"frames": PackedVector2Array(), "events": [], "rails": 0, "done": false}


# Runs up to `steps` physics steps. True when every ball has stopped (or max_time ran out).
static func advance(s: Dictionary, t: Dictionary, steps: int) -> bool:
	var pos: PackedVector2Array = s.pos
	var vel: PackedVector2Array = s.vel
	var dt := float(t.sim_dt)
	var r := float(t.ball_r)
	var d2 := (r * 2.0) * (r * 2.0)
	var hx := float(t.length) * 0.5 - r
	var hy := float(t.width) * 0.5 - r
	var decel := float(t.decel)
	var drag := float(t.drag)
	var stop := float(t.stop_speed)
	var be := float(t.ball_e)
	var re := float(t.rail_e)
	var pk := pockets(t)
	var frames: PackedVector2Array = s.frames
	for n in steps:
		if float(s.time) >= float(s.next_frame):
			frames.append_array(pos)
			s.next_frame = float(s.next_frame) + float(t.frame_dt)
		var moving := false
		for i in BALLS:
			var v := vel[i]
			if v == Vector2.ZERO:
				continue
			var sp := v.length()
			var ns := sp - (decel + drag * sp) * dt
			if ns <= stop:
				vel[i] = Vector2.ZERO
				continue
			moving = true
			vel[i] = v * (ns / sp)
			pos[i] += vel[i] * dt
		if not moving:
			frames.append_array(pos)
			s.done = true
			break
		for i in BALLS:  # ball - ball
			if pos[i] == OUT:
				continue
			for j in range(i + 1, BALLS):
				if pos[j] == OUT or (vel[i] == Vector2.ZERO and vel[j] == Vector2.ZERO):
					continue
				var d := pos[j] - pos[i]
				var dd := d.length_squared()
				if dd >= d2 or dd < 1e-12:
					continue
				var dist := sqrt(dd)
				var nrm := d / dist
				var rel := (vel[i] - vel[j]).dot(nrm)
				var push := nrm * (r * 2.0 - dist) * 0.5
				pos[i] -= push
				pos[j] += push
				if rel <= 0.0:
					continue
				var imp := nrm * rel * (1.0 + be) * 0.5
				vel[i] -= imp
				vel[j] += imp
				if int(s.first_hit) < 0 and (i == 0 or j == 0):
					s.first_hit = j if i == 0 else i
				_event(s, "clack", rel)
		for i in BALLS:  # cushions + pockets
			if pos[i] == OUT or vel[i] == Vector2.ZERO:
				continue
			var p := pos[i]
			var near_corner := absf(p.x) > hx + r - float(t.corner_gap) and absf(p.y) > hy + r - float(t.corner_gap)
			var near_side := absf(p.x) < float(t.side_gap)
			var dropped := -1
			for k in pk.size():
				if p.distance_to(pk[k]) < (float(t.corner_r) if k < 4 else float(t.side_r)):
					dropped = k
			if dropped < 0 and near_corner and (absf(p.x) > hx + r + 0.03 or absf(p.y) > hy + r + 0.03):
				dropped = 0
			if dropped < 0 and near_side and absf(p.y) > hy + r + 0.04:
				dropped = 4
			if dropped >= 0:
				pos[i] = OUT
				vel[i] = Vector2.ZERO
				s.pocketed.append(i)
				_event(s, "pocket", 1.0)
				continue
			if not near_corner and absf(p.x) > hx:
				p.x = signf(p.x) * hx
				vel[i] = Vector2(-vel[i].x * re, vel[i].y)
				_rail(s, i, absf(vel[i].x))
			if not near_corner and not near_side and absf(p.y) > hy:
				p.y = signf(p.y) * hy
				vel[i] = Vector2(vel[i].x, -vel[i].y * re)
				_rail(s, i, absf(vel[i].y))
			pos[i] = p
		s.time = float(s.time) + dt
		if float(s.time) > float(t.max_time):
			for i in BALLS:
				vel[i] = Vector2.ZERO
			frames.append_array(pos)
			s.done = true
			break
	s.pos = pos
	s.vel = vel
	s.frames = frames
	return bool(s.done)


static func _rail(s: Dictionary, i: int, speed: float) -> void:
	if int(s.first_hit) >= 0 or i != 0:
		s.rails = int(s.rails) + 1
	_event(s, "rail", speed)


static func _event(s: Dictionary, kind: String, strength: float) -> void:
	var ev: Array = s.events
	if ev.size() < MAX_EVENTS and strength > 0.15:
		ev.append([snappedf(float(s.time), 0.01), kind, snappedf(minf(strength, 6.0), 0.01)])


# The whole shot at once (tests; the host uses advance() over several frames).
static func run_shot(pos: PackedVector2Array, cue_vel: Vector2, t: Dictionary) -> Dictionary:
	var s := new_shot(pos, cue_vel)
	while not advance(s, t, 4096):
		pass
	return s


# Where the cue ball going along `dir` first touches something: {end (cue centre then), hit (ball index, -1 = cushion),
# out (the object ball's direction after the hit, or ZERO)}.
static func aim_probe(pos: PackedVector2Array, dir: Vector2, t: Dictionary) -> Dictionary:
	var r := float(t.ball_r)
	var c := pos[0]
	var best := INF
	var hit := -1
	for i in range(1, BALLS):
		if pos[i] == OUT:
			continue
		var m := pos[i] - c
		var along := m.dot(dir)
		if along <= 0.0:
			continue
		var side2 := m.length_squared() - along * along
		var rr := (r * 2.0) * (r * 2.0)
		if side2 > rr:
			continue
		var dist := along - sqrt(rr - side2)
		if dist < best:
			best = dist
			hit = i
	var hx := float(t.length) * 0.5 - r
	var hy := float(t.width) * 0.5 - r
	var wall := INF
	if dir.x != 0.0:
		wall = minf(wall, ((hx if dir.x > 0.0 else -hx) - c.x) / dir.x)
	if dir.y != 0.0:
		wall = minf(wall, ((hy if dir.y > 0.0 else -hy) - c.y) / dir.y)
	if wall < best:
		return {"end": c + dir * maxf(wall, 0.0), "hit": -1, "out": Vector2.ZERO}
	var end := c + dir * maxf(best, 0.0)
	return {"end": end, "hit": hit, "out": (pos[hit] - end).normalized()}


# Can the cue ball be put down at p (ball in hand)?
static func valid_place(pos: PackedVector2Array, p: Vector2, t: Dictionary) -> bool:
	var r := float(t.ball_r)
	if absf(p.x) > float(t.length) * 0.5 - r or absf(p.y) > float(t.width) * 0.5 - r:
		return false
	for i in range(1, BALLS):
		if pos[i] != OUT and pos[i].distance_to(p) < r * 2.05:
			return false
	return true


# --- 8-ball -------------------------------------------------------------------------------------------

static func new_game(seats: Array) -> Dictionary:
	return {"seats": seats.duplicate(), "groups": ["", ""], "turn": 0, "break_shot": true, "ball_in_hand": false,
		"over": false, "winner": -1, "msg": "Break!"}


static func players(g: Dictionary) -> int:
	return (1 if int(g.seats[0]) != 0 else 0) + (1 if int(g.seats[1]) != 0 else 0)


# Applies a finished shot `s` (from advance) to game `g` and the ball positions (both updated in place).
# `before` = positions before the shot. `names` = [seat 0 name, seat 1 name] for the message.
static func judge(g: Dictionary, s: Dictionary, before: PackedVector2Array, t: Dictionary, names: Array) -> void:
	var pos: PackedVector2Array = s.pos
	var me := int(g.turn)
	var them := 1 - me if players(g) == 2 else me
	var dropped: Array = s.pocketed
	var first := int(s.first_hit)
	var scratch := dropped.has(0)
	var groups: Array = g.groups
	var solo := players(g) < 2
	var mine := str(groups[me])
	var cleared_before := mine != "" and _left(before, mine) == 0
	var foul := scratch or first < 0
	var why := "scratch" if scratch else ("hit nothing" if first < 0 else "")
	if not foul and not solo and not bool(g.break_shot):
		if mine == "" and first == 8:
			foul = true
			why = "hit the 8 first"
		elif mine != "" and not cleared_before and group_of(first) != mine:
			foul = true
			why = "hit the wrong ball first"
		elif mine != "" and cleared_before and first != 8:
			foul = true
			why = "had to hit the 8"
	var name: String = str(names[me])
	if scratch:
		pos[0] = head_spot(t)
		pos[0] = _clear_spot(pos, 0, t)
	if dropped.has(8) and bool(g.break_shot):
		pos[8] = foot_spot(t)
		pos[8] = _clear_spot(pos, 8, t)
	s.pos = pos
	if dropped.has(8) and not bool(g.break_shot) and solo and _left(pos, "solids") + _left(pos, "stripes") > 0:
		pos[8] = foot_spot(t)  # practice: the 8 comes back until the rest are down
		pos[8] = _clear_spot(pos, 8, t)
		s.pos = pos
	elif dropped.has(8) and not bool(g.break_shot):
		if solo:
			g.over = true
			g.winner = me
			g.msg = "Table cleared - racking up"
			return
		elif foul or not cleared_before:
			g.over = true
			g.winner = them
			g.msg = "%s sank the 8 %s - %s wins!" % [name, "on a foul" if foul else "too early", str(names[them])]
			return
		else:
			g.over = true
			g.winner = me
			g.msg = "%s sinks the 8 - %s wins!" % [name, name]
			return
	if solo and _left(pos, "solids") + _left(pos, "stripes") == 0:
		g.over = true
		g.winner = me
		g.msg = "Table cleared - racking up"
		return
	var own_down := false
	for b: int in dropped:
		if b == 0 or b == 8:
			continue
		if not solo and not bool(g.break_shot) and str(groups[me]) == "" and not foul:
			groups[me] = group_of(b)
			groups[them] = "stripes" if group_of(b) == "solids" else "solids"
		if str(groups[me]) == "" or group_of(b) == str(groups[me]):
			own_down = true
	g.groups = groups
	g.break_shot = false
	g.ball_in_hand = foul
	if foul:
		g.turn = them
		g.msg = "Foul (%s) - %s, ball in hand" % [why, str(names[them])] if not solo else "Foul (%s) - ball in hand" % why
	elif own_down:
		g.msg = "%s keeps shooting" % name if not solo else "Nice"
	else:
		g.turn = them
		g.msg = "%s's shot" % str(names[them]) if not solo else ""


static func _left(pos: PackedVector2Array, group: String) -> int:
	var n := 0
	for b in range(1, BALLS):
		if pos[b] != OUT and group_of(b) == group:
			n += 1
	return n


# Ball b's spot nudged along -x (cue) / +x (8) until it isn't touching another ball.
static func _clear_spot(pos: PackedVector2Array, b: int, t: Dictionary) -> Vector2:
	var r := float(t.ball_r)
	var p := pos[b]
	for step in 40:
		var ok := true
		for i in BALLS:
			if i != b and pos[i] != OUT and pos[i].distance_to(p) < r * 2.05:
				ok = false
		if ok:
			break
		p += Vector2(r * 2.1 * (1.0 if b == 8 else -1.0), 0.0)
	return p
