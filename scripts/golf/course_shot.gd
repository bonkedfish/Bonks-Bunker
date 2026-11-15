# CourseShot — simulates one country club shot on the real terrain (D-086), host only, all at once:
#   full swing: GolfBallRules flight (club, power x the lie's power, the swing meter's error) with the ground height
#               under the ball from a ray each step; a segment ray each step bounces it off trees and buildings;
#               roll-out with the lie's friction and the slope pulling it downhill
#   putter:     rolls along the ground at putting.max_speed x power, slowing at the lie's putt_decel, pulled by the
#               slope (terrain normal x g x slope_scale)
# Either one drops into the cup if it passes within cup_r slower than cup_max_speed; landing on the water bed is a
# water hazard; stopping outside the course bounds is out of bounds. Ground rays skip the trees' collider bodies.
# Returns {path: PackedVector3Array (global, sample_hz), end: Vector3, holed, water, out, lie}.
# Depends on: GolfBallRules, CourseLies, the generated cells' Terrain / WaterBed bodies (layer 1 / 16).
class_name CourseShot
extends RefCounted

const GROUND_MASK := 17   # world + water bed
const OBSTACLE_MASK := 1
const BED_LAYER := 16
const G := 9.8

var space: PhysicsDirectSpaceState3D
var t: Dictionary          # GolfBallRules.tuning()
var course: Dictionary     # data/golf/country_club_course.json
var lies: CourseLies
var origin: Transform3D    # the landmark's global transform (lies are landmark-local)
var _skip: Array[RID] = []  # tree collider bodies the ground ray passes through
var _last_ground := 0.0
var _none: Array[RID] = []


func _init(p_space: PhysicsDirectSpaceState3D, p_t: Dictionary, p_course: Dictionary, p_lies: CourseLies, p_origin: Transform3D) -> void:
	space = p_space
	t = p_t
	course = p_course
	lies = p_lies
	origin = p_origin


func lie_at(p: Vector3) -> String:
	var l := origin.affine_inverse() * p
	return lies.lie_at(Vector2(l.x, l.z))


# {pos, normal, water} of the ground under / above p, or {} if there's none loaded there.
func ground(p: Vector3) -> Dictionary:
	var top := Vector3(p.x, maxf(p.y, _last_ground) + 3.0, p.z)
	var bottom := Vector3(p.x, minf(p.y, _last_ground) - 80.0, p.z)
	for i in 4:
		var q := PhysicsRayQueryParameters3D.create(top, bottom, GROUND_MASK, _skip)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return {}
		var body: Object = hit.collider
		if body is CollisionObject3D and (body as Node).name == "Colliders":  # vegetation
			_skip.append((body as CollisionObject3D).get_rid())
			continue
		_last_ground = hit.position.y
		return {"pos": hit.position, "normal": hit.normal,
			"water": body is CollisionObject3D and ((body as CollisionObject3D).collision_layer & BED_LAYER) != 0}
	return {}


func simulate(from: Vector3, club_id: String, power: float, yaw: float, error: float, cup: Vector3) -> Dictionary:
	_last_ground = from.y
	var lie := lie_at(from)
	var lie_data: Dictionary = course.lies.get(lie, course.lies.rough)
	if club_id == "putter":
		return _putt(from, power, yaw, error, cup)
	var s := GolfBallRules.launch(t.clubs[club_id], power * float(lie_data.power), from, yaw, t, error)
	s.pos = from + Vector3.UP * float(t.ball.tee_height_m if lie == "tee" else 0.02)
	var dt := 1.0 / float(t.ball.step_hz)
	var every := maxi(1, roundi(float(t.ball.step_hz) / float(t.ball.sample_hz)))
	var path := PackedVector3Array([s.pos])
	var out := {"holed": false, "water": false, "out": false}
	var g := ground(s.pos)
	var gy: float = g.pos.y if not g.is_empty() else from.y
	var steps := 0
	while not s.stopped and s.time < float(t.ball.max_flight_s) + 20.0:
		var prev := s.pos
		var rolling := s.landed and s.pos.y <= gy + 0.001 and s.vel.y <= 0.0
		if rolling and not g.is_empty():
			var n: Vector3 = g.normal
			s.vel += Vector3(n.x, 0.0, n.z) * (G * float(course.slope_scale) * dt)
			if steps % 6 == 0:
				s.roll_mult = float(course.lies.get(lie_at(s.pos), course.lies.rough).roll)
		GolfBallRules.step(s, dt, t, gy)
		var seg := space.intersect_ray(PhysicsRayQueryParameters3D.create(prev, s.pos, OBSTACLE_MASK, _none))
		if not seg.is_empty() and (seg.normal as Vector3).y < 0.5:  # a tree or a wall: knocked back down
			s.pos = seg.position + (seg.normal as Vector3) * 0.05
			s.vel = s.vel.bounce(seg.normal) * 0.3
		if s.pos.y - gy < 25.0 or steps % 8 == 0:
			g = ground(s.pos)
			if not g.is_empty():
				gy = g.pos.y
				if s.pos.y < gy or (rolling and s.pos.y - gy < 0.3):  # rolling follows the ground down slopes
					s.pos.y = gy
		if s.landed and not g.is_empty() and g.water and s.pos.y <= gy + 0.05:
			out.water = true
			break
		if s.landed and _in_cup(s.pos, s.vel, cup):
			out.holed = true
			s.pos = cup
			break
		steps += 1
		if steps % every == 0:
			path.append(s.pos)
	path.append(s.pos)
	return _end(out, path, s.pos)


func _putt(from: Vector3, power: float, yaw: float, error: float, cup: Vector3) -> Dictionary:
	var p: Dictionary = t.putting
	yaw -= deg_to_rad(clampf(error, -1.5, 1.5) * float(t.swing.putt_yaw_deg))
	var vel := Vector3(-sin(yaw), 0.0, -cos(yaw)) * clampf(power, 0.0, 1.0) * float(p.max_speed)
	var pos := from
	var dt := 1.0 / float(t.ball.step_hz)
	var every := maxi(1, roundi(float(t.ball.step_hz) / float(t.ball.sample_hz)))
	var path := PackedVector3Array([pos])
	var out := {"holed": false, "water": false, "out": false}
	var decel := float(course.lies.green.putt_decel)
	var steps := 0
	while vel.length() > 0.02 and steps < 3000:
		var g := ground(pos)
		if g.is_empty():
			break
		if g.water:
			out.water = true
			break
		pos.y = g.pos.y
		if steps % 6 == 0:
			decel = float(course.lies.get(lie_at(pos), course.lies.rough).putt_decel)
		var n: Vector3 = g.normal
		vel += Vector3(n.x, 0.0, n.z) * (G * float(course.slope_scale) * dt)
		var v := vel.length()
		if v < 0.0001:
			break
		vel *= maxf(0.0, v - decel * dt) / v
		if _in_cup(pos, vel, cup):
			out.holed = true
			pos = cup
			break
		var prev := pos
		pos += vel * dt
		var seg := space.intersect_ray(PhysicsRayQueryParameters3D.create(prev + Vector3.UP * 0.05, pos + Vector3.UP * 0.05,
			OBSTACLE_MASK, _none))
		if not seg.is_empty() and (seg.normal as Vector3).y < 0.5:
			pos = prev
			vel = vel.bounce(seg.normal) * 0.3
		steps += 1
		if steps % every == 0:
			path.append(pos)
	path.append(pos)
	return _end(out, path, pos)


func _end(out: Dictionary, path: PackedVector3Array, at: Vector3) -> Dictionary:
	out.path = path
	out.end = at
	out.lie = lie_at(at)
	if not out.holed and not out.water and out.lie == "out":
		out.out = true
	return out


func _in_cup(pos: Vector3, vel: Vector3, cup: Vector3) -> bool:
	return Vector2(pos.x - cup.x, pos.z - cup.z).length() <= float(course.cup_r) and absf(pos.y - cup.y) < 0.4 \
		and Vector2(vel.x, vel.z).length() <= float(course.cup_max_speed)


