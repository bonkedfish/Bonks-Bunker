# GunFeelRules — pure math for how a gun handles (D-122, arcade-plus): the recoil kick a shot gives the view (a small
# per-gun pattern that repeats, so it can be learned), how the kick and the spread bloom recover, the spread a shot
# really gets (base + bloom, tighter aiming down sights), when a reload's sound cues fall, and one step of an ejected
# casing's flight. No nodes, no rendering, no allocation in the per-shot / per-frame calls.
# Numbers: each gun's "feel" / "reload_cues" in data/weapons/weapons.json, shared ones in data/weapons/gun_feel.json.
# Depends on: DataLoader (tuning only).
class_name GunFeelRules
extends RefCounted

const TUNING_PATH := "res://data/weapons/gun_feel.json"

static var _tuning: Dictionary = {}


static func tuning() -> Dictionary:
	if _tuning.is_empty():
		_tuning = DataLoader.load_json(TUNING_PATH)
	return _tuning


# View kick for the shot_index-th shot of a burst (0 = first): Vector2(pitch up, yaw right) in degrees.
# feel.kick = [pitch, yaw] scale, feel.pattern = [[pitch mult, yaw mult], ...] repeating.
static func kick(feel: Dictionary, shot_index: int) -> Vector2:
	var k: Array = feel.get("kick", [0.0, 0.0])
	var pat: Array = feel.get("pattern", [])
	if pat.is_empty():
		return Vector2(float(k[0]), 0.0)
	var p: Array = pat[shot_index % pat.size()]
	return Vector2(float(k[0]) * float(p[0]), float(k[1]) * float(p[1]))


# Moves an accumulated kick (degrees) back toward zero at rate_deg_s; returns what's left.
static func recover(offset: Vector2, rate_deg_s: float, dt: float) -> Vector2:
	var l := offset.length()
	var step := rate_deg_s * dt
	return Vector2.ZERO if l <= step else offset * ((l - step) / l)


# Spread bloom (degrees) after one more shot: feel.bloom = [per shot, max, recover per second].
static func bloom_after_shot(bloom: float, feel: Dictionary) -> float:
	var b: Array = feel.get("bloom", [0.0, 0.0, 0.0])
	return minf(bloom + float(b[0]), float(b[1]))


static func bloom_recover(bloom: float, feel: Dictionary, dt: float) -> float:
	var b: Array = feel.get("bloom", [0.0, 0.0, 0.0])
	return maxf(bloom - float(b[2]) * dt, 0.0)


# The cone (degrees) a shot really gets: the gun's spread_deg plus bloom, times ads_spread while aiming.
static func shot_spread(base_deg: float, bloom: float, aiming: bool, feel: Dictionary) -> float:
	var s := base_deg + bloom
	return s * float(feel.get("ads_spread", 1.0)) if aiming else s


# Magnification while aiming down sights: a scope's / the gun's zoom, else the feel's ads_zoom.
static func ads_zoom(weapon: Dictionary) -> float:
	return maxf(float(weapon.get("zoom", 1.0)), float(weapon.get("feel", {}).get("ads_zoom", 1.0)))


# Index of the next reload cue to play now (cues = [[fraction of reload_time, sound event], ...] in order) given
# how many already played and the reload's progress 0..1; -1 = none due.
static func due_cue(cues: Array, played: int, progress: float) -> int:
	if played < cues.size() and progress >= float(cues[played][0]):
		return played
	return -1


# Reload progress 0..1 from the time since it started.
static func reload_progress(elapsed: float, reload_time: float) -> float:
	return clampf(elapsed / maxf(reload_time, 0.01), 0.0, 1.0)


# One step of an ejected casing (in place): gravity, a damped bounce on floor_y, spin slows on the ground.
# Returns false once it has come to rest.
static func casing_step(pos: PackedVector3Array, vel: PackedVector3Array, i: int, floor_y: float, dt: float,
		gravity: float, bounce: float) -> bool:
	var v := vel[i]
	v.y -= gravity * dt
	var p := pos[i] + v * dt
	if p.y <= floor_y:
		p.y = floor_y
		if absf(v.y) < 0.6:
			vel[i] = Vector3.ZERO
			pos[i] = p
			return false
		v = Vector3(v.x * 0.5, -v.y * bounce, v.z * 0.5)
	pos[i] = p
	vel[i] = v
	return true
