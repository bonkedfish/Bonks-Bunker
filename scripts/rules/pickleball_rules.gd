# PickleballRules — pure pickleball for the Drop Zone courts (D-074). Court-relative coordinates: x across
# (±half width), z along (±half length), the net at z = 0; the player's side is z > 0, the CPU's z < 0.
# step() moves the ball (gravity, bounce with skid) and reports bounces and net hits; aim() gives the launch velocity
# that lands a ball on a spot with a chosen apex; in_court(); the CPU's move target and miss chance; rally scoring
# to win_points (win by win_by). D-089: swing timing grades (swing_grade: PERFECT / GOOD / EARLY / LATE / WHIFF from
# where the ball is when the swing makes contact), the volley faults (two-bounce rule for the serve and the return,
# no volleys from the kitchen), when the CPU lobs a player camped at the net, the predicted landing spot.
# Tuning: data/tuning/drop_zone.json "pickleball". Depends on: GolfBallRules (tuning).
class_name PickleballRules
extends RefCounted

enum Event { NONE, BOUNCE, NET }


class Ball:
	extends RefCounted
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO


static func tuning() -> Dictionary:
	return GolfBallRules.tuning().get("pickleball", {})


static func half_size(court_size: Array) -> Vector2:
	return Vector2(float(court_size[0]) * 0.5, float(court_size[1]) * 0.5)


static func step(b: Ball, dt: float, p: Dictionary) -> Event:
	var before := b.pos
	b.vel.y -= float(p.g) * dt
	b.pos += b.vel * dt
	if signf(before.z) != signf(b.pos.z) and b.pos.y < float(p.net_h) and before.z != 0.0:
		b.pos = Vector3(b.pos.x, b.pos.y, signf(before.z) * 0.05)
		b.vel = Vector3(b.vel.x * 0.2, minf(b.vel.y, 0.0), -b.vel.z * 0.1)
		return Event.NET
	var r := float(p.ball_r)
	if b.pos.y <= r and b.vel.y < 0.0:
		b.pos.y = r
		b.vel = Vector3(b.vel.x * float(p.skid_keep), -b.vel.y * float(p.bounce), b.vel.z * float(p.skid_keep))
		return Event.BOUNCE
	return Event.NONE


# Launch velocity from `from` that peaks at `apex` (metres above the ground) and comes down on `to` (x, z).
static func aim(from: Vector3, to: Vector2, apex: float, p: Dictionary) -> Vector3:
	var g := float(p.g)
	var top := maxf(apex, from.y + 0.2)
	var vy := sqrt(2.0 * g * (top - from.y))
	var t_up := vy / g
	var t_down := sqrt(2.0 * maxf(top - float(p.ball_r), 0.01) / g)
	var flat := (to - Vector2(from.x, from.z)) / (t_up + t_down)
	return Vector3(flat.x, vy, flat.y)


static func in_court(pos: Vector3, half: Vector2) -> bool:
	return absf(pos.x) <= half.x + 0.04 and absf(pos.z) <= half.y + 0.04


# Side a court position is on: 1 = player (z > 0), -1 = CPU.
static func side_of(pos: Vector3) -> int:
	return 1 if pos.z > 0.0 else -1


# Where the CPU should stand for the ball coming its way: under the top of the ball's hop after its first bounce
# (a short look-ahead on a copy of the ball). Home: the middle of its baseline.
static func cpu_target(b: Ball, p: Dictionary, half: Vector2) -> Vector2:
	if b.vel.z >= 0.0:
		return Vector2(0.0, -half.y * 0.75)
	var c := Ball.new()
	c.pos = b.pos
	c.vel = b.vel
	var bounced := false
	for i in 180:  # 3 s at 60 Hz
		var ev := step(c, 1.0 / 60.0, p)
		if ev == Event.BOUNCE:
			bounced = true
		elif bounced and c.vel.y <= 0.0:
			break
	return Vector2(clampf(c.pos.x, -half.x - 1.5, half.x + 1.5), clampf(c.pos.z, -half.y - 2.5, -0.8))


static func cpu_miss_chance(ball_speed: float, p: Dictionary) -> float:
	return clampf(float(p.ai_miss) + ball_speed * float(p.ai_miss_per_mps), 0.0, 0.6)


static func game_won(mine: int, theirs: int, p: Dictionary) -> bool:
	return mine >= int(p.win_points) and mine - theirs >= int(p.win_by)


# --- D-089: timed swings, faults, lobs ---------------------------------------------------------------

# Grade of a swing at its contact moment. `rel` = ball - the player's contact point (court space, 3D), `vel` = the
# ball's velocity. Further than reach_m + slack (the host's allowance for the client's delay) = WHIFF. Otherwise by the time to the ball's closest approach (flat): still coming
# by more than good_s = EARLY, already past by more than good_s = LATE, within perfect_s = PERFECT, else GOOD.
static func swing_grade(rel: Vector3, vel: Vector3, p: Dictionary, slack := 0.0) -> String:
	if rel.length() > float(p.reach_m) + slack:
		return "WHIFF"
	var r := Vector2(rel.x, rel.z)
	var v := Vector2(vel.x, vel.z)
	var tc := -r.dot(v) / v.length_squared() if v.length_squared() > 0.01 else 0.0  # + = still coming
	if absf(tc) <= float(p.perfect_s):
		return "PERFECT"
	if absf(tc) <= float(p.good_s):
		return "GOOD"
	return "EARLY" if tc > 0.0 else "LATE"


# Why a volley (hit before the ball bounced on the hitter's side) is a fault, or "" if it's fine. shot = how many
# hits the rally has had (0 = the serve, so 1 = the return): those two must bounce first. hitter_z = the hitter's
# court z (distance from the net is |z|).
static func volley_fault(bounced: bool, shot: int, hitter_z: float, p: Dictionary) -> String:
	if bounced:
		return ""
	if shot < 2:
		return "Two-bounce rule"
	if absf(hitter_z) < float(p.kitchen_m):
		return "Kitchen volley"
	return ""


# The CPU lobs over a player standing this close to the net.
static func cpu_should_lob(player_z: float, p: Dictionary) -> bool:
	return absf(player_z) < float(p.net_camp_m)


# Where the ball will first come down (court x, z), INF if not within 3 s. Copies the ball.
static func landing(b: Ball, p: Dictionary) -> Vector3:
	var c := Ball.new()
	c.pos = b.pos
	c.vel = b.vel
	for i in 180:
		if step(c, 1.0 / 60.0, p) == Event.BOUNCE:
			return c.pos
	return Vector3.INF
