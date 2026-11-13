# DiscFlightRules — pure disc flight (D-069): launch a disc from speed / glide / turn / fade numbers, power (0..1),
# aim (yaw, pitch), tilt (+ = left edge down, curves left) and backhand / forehand, then step it on a fixed dt.
# Lift scales with the disc's own launch speed (so distance grows smoothly with power) and with glide; drag slows it;
# above turn_start of its full speed it rolls right (turn < 0), below fade_start (and once it has slowed to
# fade_after_slow of its launch speed) it rolls left (fade) — mirrored for
# forehand — and the roll tilts the lift sideways, which is the curve. Tree crowns: canopy_hit() (ellipsoid test).
# Wind (D-076): Flight.wind (m/s) — drag works on the speed through the air, so the disc drifts with it; next_wind()
# rolls the next shift, wind_from() names where it comes from. Ground, trunks and the basket are the caller's job (DiscGolfDirector with physics rays, DiscGolfRules for baskets).
# One Flight object per throw; step() allocates nothing. Depends on: DataLoader, data/discgolf/discs.json,
# data/tuning/disc_golf.json.
class_name DiscFlightRules
extends RefCounted

const DISCS_PATH := "res://data/discgolf/discs.json"
const TUNING_PATH := "res://data/tuning/disc_golf.json"
const DISC_SCHEMA := {"speed": TYPE_FLOAT, "glide": TYPE_FLOAT, "turn": TYPE_FLOAT, "fade": TYPE_FLOAT,
	"full_speed_mps": TYPE_FLOAT, "color": TYPE_ARRAY}
const TUNING_SCHEMA := {"note": TYPE_STRING, "lift_base": TYPE_FLOAT, "lift_glide": TYPE_FLOAT,
	"lift_power": TYPE_FLOAT, "drag": TYPE_FLOAT, "drag_speed": TYPE_FLOAT, "turn_start": TYPE_FLOAT,
	"turn_rate_deg": TYPE_FLOAT, "fade_start": TYPE_FLOAT, "fade_rate_deg": TYPE_FLOAT, "fade_after_slow": TYPE_FLOAT, "max_roll_deg": TYPE_FLOAT,
	"launch_height_m": TYPE_FLOAT, "aim_height_m": TYPE_FLOAT, "launch_pitch_add_deg": TYPE_FLOAT, "pitch_min_deg": TYPE_FLOAT,
	"pitch_max_deg": TYPE_FLOAT, "tilt_max_deg": TYPE_FLOAT, "tilt_step_deg": TYPE_FLOAT, "charge_seconds": TYPE_FLOAT,
	"step_hz": TYPE_FLOAT, "sample_hz": TYPE_FLOAT, "max_flight_s": TYPE_FLOAT, "restitution": TYPE_FLOAT,
	"slide_friction": TYPE_FLOAT, "max_slide_s": TYPE_FLOAT, "canopy_hits_per_m": TYPE_FLOAT,
	"canopy_bare_density": TYPE_FLOAT, "canopy_slow": TYPE_ARRAY, "catch_radius_m": TYPE_FLOAT,
	"tray_low_m": TYPE_FLOAT, "chains_low_m": TYPE_FLOAT, "chains_high_m": TYPE_FLOAT, "catch_max_mps": TYPE_FLOAT,
	"pole_radius_m": TYPE_FLOAT, "start_radius_m": TYPE_FLOAT, "box_use_m": TYPE_FLOAT, "lie_radius_m": TYPE_FLOAT,
	"tee_radius_m": TYPE_FLOAT, "max_strokes": TYPE_FLOAT, "leave_m": TYPE_FLOAT, "wind_max_mph": TYPE_FLOAT,
	"wind_shift_s": TYPE_ARRAY, "wind_turn_max_deg": TYPE_FLOAT, "wind_effect": TYPE_FLOAT, "ace_slowmo": TYPE_FLOAT,
	"ace_slowmo_s": TYPE_FLOAT, "rewards": TYPE_DICTIONARY}
const G := 9.8
const MPH := 0.44704  # m/s
const COMPASS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

static var _discs: Dictionary = {}
static var _tuning: Dictionary = {}


class Flight:
	extends RefCounted
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var roll := 0.0        # radians, + = left edge down (curves left)
	var hand := 1.0        # 1 backhand, -1 forehand (mirrors turn and fade)
	var v0 := 1.0          # launch speed
	var v_full := 1.0      # this disc's full-power speed
	var lift_max := 0.0
	var k_drag := 0.0
	var turn := 0.0
	var fade := 0.0
	var time := 0.0
	var wind := Vector3.ZERO  # m/s, horizontal, the way the air moves


static func discs() -> Dictionary:
	if _discs.is_empty():
		var raw := DataLoader.load_json(DISCS_PATH)
		for id: String in raw:
			if typeof(raw[id]) == TYPE_DICTIONARY and DataLoader.validate(raw[id], DISC_SCHEMA, "%s:%s" % [DISCS_PATH, id]):
				_discs[id] = raw[id]
	return _discs


static func tuning() -> Dictionary:
	if _tuning.is_empty():
		_tuning = DataLoader.load_validated(TUNING_PATH, TUNING_SCHEMA)
	return _tuning


static func is_disc(id: String) -> bool:
	return discs().has(id)


# Launch pitch (radians) for a camera pitch (radians).
static func launch_pitch(camera_pitch: float, t: Dictionary) -> float:
	return deg_to_rad(clampf(rad_to_deg(camera_pitch) + float(t.launch_pitch_add_deg), float(t.pitch_min_deg), float(t.pitch_max_deg)))


# A new flight from `from` toward yaw (radians, 0 = -Z like the player) at launch pitch (radians).
static func launch(disc: Dictionary, power: float, from: Vector3, yaw: float, pitch: float, tilt_deg: float,
		forehand: bool, t: Dictionary) -> Flight:
	var f := Flight.new()
	power = clampf(power, 0.03, 1.0)
	f.v_full = float(disc.full_speed_mps)
	f.v0 = f.v_full * power
	f.pos = from
	var dir := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	f.vel = dir * f.v0
	f.roll = deg_to_rad(clampf(tilt_deg, -float(t.tilt_max_deg), float(t.tilt_max_deg)))
	f.hand = -1.0 if forehand else 1.0
	f.lift_max = G * (float(t.lift_base) + float(t.lift_glide) * float(disc.glide)) * (1.0 - float(t.lift_power) + float(t.lift_power) * power)
	f.k_drag = float(t.drag) / (1.0 + float(t.drag_speed) * float(disc.speed))
	f.turn = float(disc.turn)
	f.fade = float(disc.fade)
	return f


# One step of free flight (no collisions).
static func step(f: Flight, dt: float, t: Dictionary) -> void:
	var v := f.vel.length()
	var vh := Vector2(f.vel.x, f.vel.z)
	var fwd := vh / vh.length() if vh.length() > 0.0001 else Vector2(0.0, -1.0)
	var left := Vector2(fwd.y, -fwd.x)
	var sr := v / f.v_full
	var turn_start := float(t.turn_start)
	var fade_start := float(t.fade_start)
	if sr > turn_start:
		f.roll += deg_to_rad(float(t.turn_rate_deg)) * f.turn * (sr - turn_start) / (1.0 - turn_start) * dt * f.hand
	if sr < fade_start and v < f.v0 * float(t.fade_after_slow):  # fades once slow AND it has lost speed (putts fly straight)
		f.roll += deg_to_rad(float(t.fade_rate_deg)) * f.fade * (fade_start - sr) / fade_start * dt * f.hand
	var max_roll := deg_to_rad(float(t.max_roll_deg))
	f.roll = clampf(f.roll, -max_roll, max_roll)
	var ratio := minf(v / f.v0, 1.2)
	var lift := f.lift_max * ratio * ratio
	var side := lift * sin(f.roll)
	var air := f.vel - f.wind
	var acc := Vector3(side * left.x, lift * cos(f.roll) - G, side * left.y) - air * (f.k_drag * air.length())
	f.vel += acc * dt
	f.pos += f.vel * dt
	f.time += dt


# True if pos is inside the crown of a tree standing at base with height h (bare trees: thinner crowns).
static func in_canopy(pos: Vector3, base: Vector3, h: float, bare: bool) -> bool:
	var c := base + Vector3.UP * (0.75 if bare else 0.7) * h
	var rh := (0.32 if bare else 0.42) * h
	var rv := 0.35 * h
	var d := pos - c
	return (d.x * d.x + d.z * d.z) / (rh * rh) + (d.y * d.y) / (rv * rv) <= 1.0


# Chance that a step of `metres` through a crown clips a branch.
static func canopy_hit_chance(metres: float, bare: bool, t: Dictionary) -> float:
	return clampf(metres * float(t.canopy_hits_per_m) * (float(t.canopy_bare_density) if bare else 1.0), 0.0, 1.0)


# Carry over flat open ground (metres from the launch point to where it comes down to `to_height` above the ground)
# at a power. The HUD's "power to reach the basket" mark uses to_height = aim_height_m (the chains).
static func flat_distance(disc: Dictionary, power: float, t: Dictionary, to_height := 0.0) -> float:
	var f := launch(disc, power, Vector3(0.0, float(t.launch_height_m), 0.0), 0.0, launch_pitch(0.0, t), 0.0, false, t)
	var dt := 1.0 / float(t.step_hz)
	while (f.pos.y > to_height or f.vel.y > 0.0) and f.time < float(t.max_flight_s):
		step(f, dt, t)
	return Vector2(f.pos.x, f.pos.z).length()


# Table of flat_distance down to the chains at power 0, 0.05 .. 1 (21 entries).
static func reach_table(disc: Dictionary, t: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in 21:
		out.append(0.0 if i == 0 else flat_distance(disc, i / 20.0, t, float(t.aim_height_m)))
	return out


# Power that carries `metres` on flat ground (from a reach_table), clamped to 1.
static func power_for(table: PackedFloat32Array, metres: float) -> float:
	for i in range(1, table.size()):
		if table[i] >= metres:
			return (i - 1 + inverse_lerp(table[i - 1], table[i], metres)) / 20.0
	return 1.0


# The wind after a shift (D-076), m/s in map x / z, the way it blows. From calm: a random speed up to wind_max_mph and
# a random direction; otherwise the speed moves by up to 40% of the max and the direction turns by up to
# wind_turn_max_deg.
static func next_wind(prev: Vector2, rng: RandomNumberGenerator, t: Dictionary) -> Vector2:
	var top := float(t.wind_max_mph) * MPH
	if prev.length() < 0.05:
		return Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, top)
	var speed := clampf(prev.length() + rng.randf_range(-0.4, 0.4) * top, 0.0, top)
	return Vector2.from_angle(prev.angle() + deg_to_rad(rng.randf_range(-1.0, 1.0) * float(t.wind_turn_max_deg))) * speed


# Compass point the wind comes FROM ("NW"), or "calm". Map -z is north, +x east.
static func wind_from(w: Vector2) -> String:
	if w.length() < 0.05:
		return "calm"
	var bearing := fposmod(rad_to_deg(atan2(-w.x, w.y)), 360.0)
	return COMPASS[roundi(bearing / 45.0) % 8]
