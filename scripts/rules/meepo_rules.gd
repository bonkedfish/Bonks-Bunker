# MeepoRules — pure rules for the Meepo electric longboard (D-057): who may hop on, the movement tuning while riding,
# battery drain / recharge, and knock-offs. Depends on: DataLoader (data/tuning/meepo.json).
class_name MeepoRules
extends RefCounted

const PATH := "res://data/tuning/meepo.json"

static var _t: Dictionary = {}


static func tuning() -> Dictionary:
	if _t.is_empty():
		_t = DataLoader.load_json(PATH)
	return _t


static func can_ride(has_board: bool, battery: float, alive: bool, swimming: bool, t: Dictionary) -> bool:
	return has_board and alive and not swimming and battery >= float(t.get("min_battery", 2.0))


# Movement tuning while riding: walk speed becomes ride_speed, sprint becomes boost_speed (D-068), gentler
# acceleration, no crouch speed change.
static func ride_movement(base: Dictionary, t: Dictionary) -> Dictionary:
	var m := base.duplicate()
	m.walk_speed = float(t.ride_speed)
	m.sprint_speed = float(t.get("boost_speed", t.ride_speed))
	m.crouch_speed = float(t.ride_speed)
	m.ground_accel = float(t.ride_accel)
	return m


# boosting: rolling faster than cruise (sprint held) drains boost_drain_mult times faster.
static func battery_after(battery: float, rolling: bool, charging: bool, delta: float, t: Dictionary, boosting := false) -> float:
	if rolling:
		battery -= float(t.battery_drain_per_s) * delta * (float(t.get("boost_drain_mult", 1.0)) if boosting else 1.0)
	elif charging:
		battery += float(t.recharge_per_s) * delta
	return clampf(battery, 0.0, 100.0)


static func knocked_off(damage: float, t: Dictionary) -> bool:
	return damage >= float(t.get("knockoff_damage", 15.0))
