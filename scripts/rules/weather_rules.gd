# WeatherRules — the weather's rules (D-099), pure (no nodes): which state comes next and for how long, what each
# state means (rain / storm / fog levels), how levels blend, how much a lightning strike hurts at a distance, how
# much less zombies hear, how much a storm adds to the disc golf wind. Tuning: data/tuning/weather.json.
# Depends on: DataLoader.
class_name WeatherRules
extends RefCounted

const DATA_PATH := "res://data/tuning/weather.json"
const STATES := ["clear", "fog", "rain", "storm"]

static var _t: Dictionary = {}


static func tuning() -> Dictionary:
	if _t.is_empty():
		_t = DataLoader.load_json(DATA_PATH)
	return _t


# The next state by weight, never the current one.
static func pick_next(current: String, rng: RandomNumberGenerator, t: Dictionary) -> String:
	var total := 0.0
	for s: String in t.states:
		if s != current:
			total += float(t.states[s].weight)
	var r := rng.randf() * total
	for s: String in t.states:
		if s == current:
			continue
		r -= float(t.states[s].weight)
		if r <= 0.0:
			return s
	return "clear"


static func duration_s(state: String, rng: RandomNumberGenerator, t: Dictionary) -> float:
	var m: Array = t.states[state].minutes
	return rng.randf_range(float(m[0]), float(m[1])) * 60.0


# (rain, storm, fog) a state settles at.
static func levels(state: String, t: Dictionary) -> Vector3:
	var s: Dictionary = t.states.get(state, t.states.clear)
	return Vector3(float(s.rain), float(s.storm), float(s.fog))


# Moves `now` toward `target` at full change per blend_seconds.
static func blend(now: Vector3, target: Vector3, delta: float, t: Dictionary) -> Vector3:
	var step := delta / maxf(float(t.blend_seconds), 0.01)  # each level on its own
	return Vector3(move_toward(now.x, target.x, step), move_toward(now.y, target.y, step), move_toward(now.z, target.z, step))


# Multiplier on zombies' noise radius for the current levels (the strongest effect wins).
static func hearing_mult(lv: Vector3, t: Dictionary) -> float:
	var h: Dictionary = t.hearing
	return minf(minf(lerpf(1.0, float(h.rain), lv.x), lerpf(1.0, float(h.storm), lv.y)), lerpf(1.0, float(h.fog), lv.z))


# Damage from a strike `d` metres away (0 outside radius_m, full at the centre, linear between).
static func strike_damage(d: float, t: Dictionary) -> float:
	var l: Dictionary = t.lightning
	return float(l.damage) * clampf(1.0 - d / float(l.radius_m), 0.0, 1.0)


# Disc golf wind in a storm: stronger by storm_wind_add_mps (scaled by the storm level), capped.
static func storm_wind(wind: Vector2, storm: float, rng: RandomNumberGenerator, t: Dictionary) -> Vector2:
	if storm <= 0.01:
		return wind
	var dir := wind.normalized() if wind.length() > 0.01 else Vector2.from_angle(rng.randf() * TAU)
	return dir * minf(wind.length() + float(t.storm_wind_add_mps) * storm, float(t.storm_wind_max_mps))
