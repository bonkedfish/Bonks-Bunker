# CombatRules — pure combat math: aim direction, ray vs. capsule hit test, melee arc test,
# friendly-fire damage scaling, and the combat tuning loader. No nodes, no rendering.
# Targets are vertical capsules described by a base (feet) position, radius and height.
# Depends on: DataLoader, data/tuning/combat.json.
class_name CombatRules
extends RefCounted

const TUNING_PATH := "res://data/tuning/combat.json"
const TUNING_SCHEMA := {
	"player_max_health": TYPE_FLOAT,
	"friendly_fire_multiplier": TYPE_FLOAT,
	"respawn_seconds": TYPE_FLOAT,
	"bleed_out_seconds": TYPE_FLOAT,
	"revive_seconds": TYPE_FLOAT,
	"revive_range": TYPE_FLOAT,
	"revive_health": TYPE_FLOAT,
	"max_rewind_seconds": TYPE_FLOAT,
	"switch_time": TYPE_FLOAT,
	"dummy_max_health": TYPE_FLOAT,
	"dummy_reset_seconds": TYPE_FLOAT,
	"loadout": TYPE_ARRAY,
}

static var _tuning: Dictionary = {}


static func load_tuning() -> Dictionary:
	if _tuning.is_empty():
		_tuning = DataLoader.load_validated(TUNING_PATH, TUNING_SCHEMA)
	return _tuning


# Camera forward for a yaw (around Y) and pitch (around local X); -Z is forward.
static func aim_direction(yaw: float, pitch: float) -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.RIGHT, pitch).rotated(Vector3.UP, yaw)


# Distance along the ray to where it enters the capsule, or -1.0 for a miss.
static func ray_vs_capsule(origin: Vector3, dir: Vector3, max_dist: float,
		base: Vector3, radius: float, height: float) -> float:
	var a := base + Vector3.UP * radius
	var b := base + Vector3.UP * maxf(height - radius, radius)
	var pts := Geometry3D.get_closest_points_between_segments(origin, origin + dir * max_dist, a, b)
	var miss := pts[0].distance_to(pts[1])
	if miss > radius:
		return -1.0
	var along := (pts[0] - origin).dot(dir)
	return maxf(along - sqrt(radius * radius - miss * miss), 0.0)


# True if any part of the capsule is within reach and inside the swing cone around `forward`.
static func melee_hits_capsule(eye: Vector3, forward: Vector3, reach: float, arc_degrees: float,
		base: Vector3, radius: float, height: float) -> bool:
	var a := base + Vector3.UP * radius
	var b := base + Vector3.UP * maxf(height - radius, radius)
	var to_target := Geometry3D.get_closest_point_to_segment(eye, a, b) - eye
	var dist := to_target.length()
	if dist - radius > reach:
		return false
	if dist <= radius:
		return true
	return rad_to_deg(forward.angle_to(to_target)) <= arc_degrees * 0.5


static func scaled_damage(damage: float, same_team: bool, friendly_fire_multiplier: float) -> float:
	return damage * friendly_fire_multiplier if same_team else damage
