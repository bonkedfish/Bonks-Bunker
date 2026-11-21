# ScareRules — the pure maths behind the zombie scare features (D-114): which traits a body gets from its style
# seed, whether a player is looking at it, where a flanker heads, how fast the heartbeat goes and how muffled
# hearing gets as a zombie closes in. No scene, rendering or audio here; ZombieScare (host behaviour) and Dread
# (local presentation) call it.
# Depends on: nothing (tuning dictionaries come from data/tuning/scare.json).
class_name ScareRules
extends RefCounted

const ROLE_KEYS := ["screamer", "stumbler", "crawler", "feigner", "lurker", "stalker", "flanker"]

enum Stalk { CREEP, HOLD, CHARGE }


# Traits for one activation. Same seed + same chances = same answer on every peer.
# Returns {screamer, stumbler, crawler, feigner, lurker, stalker, flanker: bool, side: -1|1, speed: float mult,
# twitchy: bool}.
static func roles(style_seed: int, chances: Dictionary, tuning: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = style_seed
	var out := {}
	for k: String in ROLE_KEYS:
		out[k] = rng.randf() < float(chances.get(k, 0.0))
	if out.crawler:
		out.feigner = false  # it's already down
		out.stumbler = false
	if out.lurker:
		out.stalker = false
	var j := 0.0 if chances.is_empty() else float(tuning.get("gait", {}).get("speed_jitter", 0.0))
	out.speed = 1.0 + rng.randf_range(-j, j)
	out.side = 1 if rng.randf() < 0.5 else -1
	out.twitchy = rng.randf() < float(tuning.get("twitch", {}).get("chance", 0.0))
	return out


# True when a player at `eye` facing `look_yaw` (radians, Godot yaw: forward = -Z) has `target` inside cone_deg.
static func is_watched(look_yaw: float, eye: Vector3, target: Vector3, cone_deg: float) -> bool:
	var to := Vector2(target.x - eye.x, target.z - eye.z)
	if to.length_squared() < 0.0001:
		return true
	var fwd := Vector2(-sin(look_yaw), -cos(look_yaw))
	return absf(rad_to_deg(fwd.angle_to(to.normalized()))) <= cone_deg * 0.5


# Stalker at night: charge when close (or after give_up_s), otherwise freeze while watched and creep while not.
static func stalk(dist: float, watched: bool, stalk_time: float, s: Dictionary) -> int:
	if dist <= float(s.get("charge_m", 7.0)) or stalk_time >= float(s.get("give_up_s", 45.0)):
		return Stalk.CHARGE
	return Stalk.HOLD if watched else Stalk.CREEP


# A point beside the target, offset_m to one side of the line from the chaser to it (side = -1 | 1).
static func flank_point(target: Vector3, chaser: Vector3, side: int, offset_m: float) -> Vector3:
	var to := Vector3(target.x - chaser.x, 0.0, target.z - chaser.z)
	if to.length_squared() < 0.0001:
		return target
	var perp := Vector3(-to.z, 0.0, to.x).normalized() * float(side)
	return target + perp * offset_m


# Seconds between heartbeats for the nearest zombie at `dist` (0 = no heartbeat).
static func heartbeat_interval(dist: float, d: Dictionary) -> float:
	var far := float(d.get("heartbeat_far_m", 12.0))
	if dist >= far:
		return 0.0
	var near := float(d.get("heartbeat_near_m", 2.0))
	var k := clampf((far - dist) / maxf(far - near, 0.01), 0.0, 1.0)
	return 60.0 / lerpf(float(d.get("bpm_far", 70.0)), float(d.get("bpm_near", 150.0)), k)


# 0 (clear) .. 1 (fully muffled) for the nearest zombie at `dist`.
static func muffle(dist: float, d: Dictionary) -> float:
	var m := float(d.get("muffle_m", 3.0))
	return clampf(1.0 - dist / maxf(m, 0.01), 0.0, 1.0)


# Low-pass cutoff (Hz) for a muffle amount, falling off exponentially so it sounds even.
static func muffle_cutoff(amount: float, d: Dictionary) -> float:
	var off := float(d.get("muffle_hz_off", 20000.0))
	var near := float(d.get("muffle_hz_near", 900.0))
	return off * pow(near / off, clampf(amount, 0.0, 1.0))


# Camera trauma from a scream heard at `dist`.
static func scream_shake(dist: float, s: Dictionary) -> float:
	var r := float(s.get("shake_radius_m", 30.0))
	return float(s.get("shake", 0.4)) * clampf(1.0 - dist / maxf(r, 0.01), 0.0, 1.0)
