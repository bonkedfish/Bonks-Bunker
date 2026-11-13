# GolfBallRules — pure golf ball rules for Drop Zone (D-074): the range shot (club launch, flight with drag and
# backspin lift, first bounce, roll-out), target scoring at the first landing, and the putting course (ball rolling
# on green / fringe / sand, water, cup capture, power for a distance). Positions are landmark-local; the ground of the
# range and putting course is flat at y 0. Flight objects allocate once per shot. Depends on: DataLoader,
# data/tuning/drop_zone.json.
class_name GolfBallRules
extends RefCounted

const TUNING_PATH := "res://data/tuning/drop_zone.json"
const TUNING_SCHEMA := {"note": TYPE_STRING, "clubs": TYPE_DICTIONARY, "club_order": TYPE_ARRAY, "ball": TYPE_DICTIONARY,
	"range": TYPE_DICTIONARY, "putting": TYPE_DICTIONARY, "pickleball": TYPE_DICTIONARY}
const G := 9.8

enum Lie { GREEN, FRINGE, SAND, WATER, OUT }

static var _tuning: Dictionary = {}


class Shot:
	extends RefCounted
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var time := 0.0
	var landed := false           # touched the ground once
	var land := Vector3.INF       # first touch
	var stopped := false


static func tuning() -> Dictionary:
	if _tuning.is_empty():
		_tuning = DataLoader.load_validated(TUNING_PATH, TUNING_SCHEMA)
	return _tuning


# --- range ----------------------------------------------------------------------------------

static func launch(club: Dictionary, power: float, from: Vector3, yaw: float, t: Dictionary) -> Shot:
	var s := Shot.new()
	var b: Dictionary = t.ball
	var speed := float(club.speed) * pow(clampf(power, 0.02, 1.0), float(b.power_curve))
	var loft := deg_to_rad(float(club.loft_deg))
	s.pos = from + Vector3.UP * float(b.tee_height_m)
	s.vel = Vector3(-sin(yaw) * cos(loft), sin(loft), -cos(yaw) * cos(loft)) * speed
	return s


# One step: flight (drag + decaying backspin lift), first bounce, then rolling to a stop on the flat ground.
static func step(s: Shot, dt: float, t: Dictionary) -> void:
	var b: Dictionary = t.ball
	s.time += dt
	if s.landed and s.pos.y <= 0.0 and s.vel.y <= 0.0:  # rolling
		var h := Vector2(s.vel.x, s.vel.z)
		var roll := h.length()
		if roll < 0.05:
			s.stopped = true
			s.vel = Vector3.ZERO
			return
		h *= maxf(0.0, roll - float(b.roll_friction) * dt) / roll
		s.vel = Vector3(h.x, 0.0, h.y)
		s.pos += s.vel * dt
		s.pos.y = 0.0
		return
	var v := s.vel.length()
	var hdir := Vector2(s.vel.x, s.vel.z)
	var vh := hdir.length()
	hdir = hdir / vh if vh > 0.001 else Vector2.ZERO
	var acc := Vector3(0.0, -G, 0.0) - s.vel * (float(b.drag) * v)
	if v > 0.01 and not s.landed:
		var lift_dir := Vector3(-s.vel.y * hdir.x, vh, -s.vel.y * hdir.y) / v
		acc += lift_dir * (float(b.lift) * exp(-float(b.spin_decay) * s.time) * v * v)
	s.vel += acc * dt
	s.pos += s.vel * dt
	if s.pos.y <= 0.0 and s.vel.y < 0.0:
		if not s.landed:
			s.landed = true
			s.land = Vector3(s.pos.x, 0.0, s.pos.z)
		s.pos.y = 0.0
		s.vel = Vector3(s.vel.x * float(b.roll_keep), -s.vel.y * float(b.bounce), s.vel.z * float(b.roll_keep))
		if s.vel.y < 0.6:
			s.vel.y = 0.0


# Points for a first landing at `land` (local): [points, target index] (index -1 = no target).
static func target_score(land: Vector3, targets: Array, t: Dictionary) -> Vector2i:
	var r: Dictionary = t.range
	for i in targets.size():
		var tg: Dictionary = targets[i]
		var d := Vector2(land.x - float(tg.x), land.z - float(tg.z)).length()
		if d <= float(tg.r):
			var pts := int(tg.points)
			if d <= float(tg.r) * float(r.bullseye_frac):
				pts = int(pts * float(r.bullseye_mult))
			return Vector2i(pts, i)
	return Vector2i(0, -1)


# Flat carry (first landing distance) of a club at a power, for the HUD's target marks.
static func carry(club: Dictionary, power: float, t: Dictionary) -> float:
	var s := launch(club, power, Vector3.ZERO, 0.0, t)
	var dt := 1.0 / float(t.ball.step_hz)
	while not s.landed and s.time < float(t.ball.max_flight_s):
		step(s, dt, t)
	return -s.land.z if s.landed else 0.0


# --- putting ----------------------------------------------------------------------------------

# Surface under a point of the putting course (local x, z) for a hole: its green ellipse, bunker, water, the rest of
# the course area (fringe), or out of the area.
static func lie_at(p: Vector2, hole: Dictionary, area: Array) -> Lie:
	if p.x < float(area[0]) or p.y < float(area[1]) or p.x > float(area[2]) or p.y > float(area[3]):
		return Lie.OUT
	if hole.has("water") and p.distance_to(_v2(hole.water.c)) <= float(hole.water.r):
		return Lie.WATER
	if hole.has("bunker") and p.distance_to(_v2(hole.bunker.c)) <= float(hole.bunker.r):
		return Lie.SAND
	var g: Dictionary = hole.green
	var q := (p - _v2(g.c)).rotated(-float(g.rot))
	if pow(q.x / float(g.a), 2.0) + pow(q.y / float(g.b), 2.0) <= 1.0:
		return Lie.GREEN
	return Lie.FRINGE


static func decel(lie: Lie, t: Dictionary) -> float:
	var p: Dictionary = t.putting
	match lie:
		Lie.GREEN:
			return float(p.decel_green)
		Lie.SAND:
			return float(p.decel_sand)
	return float(p.decel_fringe)


# Power (0..1) that rolls a putt `metres` on the green.
static func putt_power(metres: float, t: Dictionary) -> float:
	var p: Dictionary = t.putting
	return clampf(sqrt(2.0 * float(p.decel_green) * maxf(metres, 0.0)) / float(p.max_speed), 0.0, 1.0)


# Rolls one putt to the end: returns {path: PackedVector2Array (sample_hz), end: Vector2, holed, water, out}.
static func roll_putt(from: Vector2, yaw: float, power: float, hole: Dictionary, area: Array, t: Dictionary) -> Dictionary:
	var p: Dictionary = t.putting
	var dt := 1.0 / float(t.ball.step_hz)
	var every := maxi(1, roundi(float(t.ball.step_hz) / float(t.ball.sample_hz)))
	var vel := Vector2(-sin(yaw), -cos(yaw)) * clampf(power, 0.0, 1.0) * float(p.max_speed)
	var pos := from
	var cup := _v2(hole.cup)
	var path := PackedVector2Array([pos])
	var out := {"holed": false, "water": false, "out": false}
	var steps := 0
	while vel.length() > 0.02 and steps < 2000:
		var lie := lie_at(pos, hole, area)
		if lie == Lie.WATER or lie == Lie.OUT:
			out[("water" if lie == Lie.WATER else "out")] = true
			break
		if pos.distance_to(cup) <= float(p.cup_r) and vel.length() <= float(p.cup_max_speed):
			out.holed = true
			pos = cup
			break
		var v := vel.length()
		vel *= maxf(0.0, v - decel(lie, t) * dt) / v
		pos += vel * dt
		steps += 1
		if steps % every == 0:
			path.append(pos)
	path.append(pos)
	out.path = path
	out.end = pos
	return out


static func _v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))
