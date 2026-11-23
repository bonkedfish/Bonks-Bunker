# DiscFlightRules — pure disc flight (D-069): launch a disc from speed / glide / turn / fade numbers, power (0..1),
# aim (yaw, pitch), tilt (+ = left edge down, curves left) and a throw style (D-117, data/discgolf/throw_styles.json:
# backhand, forehand, putt, tomahawk, roller - each scales power / lift / turn / fade, adds pitch and tilt, and may
# keep turning the disc over (flip) or roll it along the ground on landing: roll_step()), then step it on a fixed dt.
# Lift scales with the disc's own launch speed (so distance grows smoothly with power) and with glide; drag slows it;
# above turn_start of its full speed it rolls right (turn < 0), below fade_start (and once it has slowed to
# fade_after_slow of its launch speed) it rolls left (fade) — mirrored for
# forehand — and the roll tilts the lift sideways, which is the curve. Tree crowns: canopy_hit() (ellipsoid test).
# Wind (D-076): Flight.wind (m/s) — drag works on the speed through the air, so the disc drifts with it; next_wind()
# rolls the next shift, wind_from() names where it comes from. Ground, trunks and the basket are the caller's job (DiscGolfDirector with physics rays, DiscGolfRules for baskets).
# Catalog (D-119): bag_order() sorts the discs fastest first; each disc's plastic tier (base | premium, "plastics" in
# the tuning) sets how far a release slips (slip()) and how fast it beats in (wear_after()); worn() turns a disc's
# numbers into its beat-in flight (more turn, less fade).
# One Flight object per throw; step() allocates nothing. Depends on: DataLoader, data/discgolf/discs.json,
# data/discgolf/throw_styles.json, data/tuning/disc_golf.json.
class_name DiscFlightRules
extends RefCounted

const DISCS_PATH := "res://data/discgolf/discs.json"
const TUNING_PATH := "res://data/tuning/disc_golf.json"
const STYLES_PATH := "res://data/discgolf/throw_styles.json"
const DISC_SCHEMA := {"speed": TYPE_FLOAT, "glide": TYPE_FLOAT, "turn": TYPE_FLOAT, "fade": TYPE_FLOAT,
	"full_speed_mps": TYPE_FLOAT, "color": TYPE_ARRAY}
const DISC_OPTIONAL := ["shape", "plastic", "stamp", "tier"]  # looks only (DiscMesh, D-117); tier = plastic (D-119)
const STYLE_SCHEMA := {"name": TYPE_STRING, "hand": TYPE_FLOAT, "power_mult": TYPE_FLOAT, "pitch_add_deg": TYPE_FLOAT,
	"roll_add_deg": TYPE_FLOAT, "lift_mult": TYPE_FLOAT, "turn_mult": TYPE_FLOAT, "fade_mult": TYPE_FLOAT,
	"flip_rate_deg": TYPE_FLOAT, "max_roll_deg": TYPE_FLOAT, "ground_roll": TYPE_BOOL, "spin": TYPE_FLOAT, "anim": TYPE_DICTIONARY}
const ROLLER_SCHEMA := {"roll_min_deg": TYPE_FLOAT, "roll_keep": TYPE_FLOAT, "roll_friction": TYPE_FLOAT,
	"roll_curve_deg": TYPE_FLOAT, "fall_mps": TYPE_FLOAT}
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
	"ace_slowmo_s": TYPE_FLOAT, "impaired_throw": TYPE_DICTIONARY, "water_penalty": TYPE_FLOAT, "rewards": TYPE_DICTIONARY,
	"plastics": TYPE_DICTIONARY, "wear": TYPE_DICTIONARY, "starter_discs": TYPE_ARRAY}
const G := 9.8
const MPH := 0.44704  # m/s
const COMPASS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

static var _discs: Dictionary = {}
static var _tuning: Dictionary = {}
static var _styles: Dictionary = {}
static var _style_order: PackedStringArray = []
static var _styles_fp: Dictionary = {}
static var _bag_order: PackedStringArray = []


class Flight:
	extends RefCounted
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var roll := 0.0        # radians, + = left edge down (curves left)
	var hand := 1.0        # 1 backhand-side spin, -1 forehand-side (mirrors turn and fade)
	var v0 := 1.0          # launch speed
	var v_full := 1.0      # this disc's full-power speed
	var lift_max := 0.0
	var k_drag := 0.0
	var turn := 0.0
	var fade := 0.0
	var time := 0.0
	var wind := Vector3.ZERO  # m/s, horizontal, the way the air moves
	var flip := 0.0        # rad/s the style keeps turning it over (tomahawk)
	var max_roll := 1.4    # rad
	var ground_roll := false  # rolls on its edge after landing (roller)
	var rolling := false
	var roll_min := 0.4    # rad: steeper than this on landing = it rolls
	var roll_keep := 0.75
	var roll_friction := 1.6
	var roll_curve := 0.5  # rad/s
	var fall_mps := 1.8
	var roll_v0 := 1.0     # speed when it started rolling


static func discs() -> Dictionary:
	if _discs.is_empty():
		var raw := DataLoader.load_json(DISCS_PATH)
		for id: String in raw:
			if typeof(raw[id]) != TYPE_DICTIONARY:
				continue
			var required: Dictionary = raw[id].duplicate()
			for opt: String in DISC_OPTIONAL:
				required.erase(opt)
			if DataLoader.validate(required, DISC_SCHEMA, "%s:%s" % [DISCS_PATH, id]):
				_discs[id] = raw[id]
	return _discs


# Throw styles by id (D-117), validated; roller-only keys are checked when ground_roll is on.
static func styles() -> Dictionary:
	if _styles.is_empty():
		var raw := DataLoader.load_json(STYLES_PATH)
		for id: String in raw.get("styles", {}):
			var st: Variant = raw.styles[id]
			if typeof(st) != TYPE_DICTIONARY:
				continue
			var required: Dictionary = st.duplicate()
			for k: String in ROLLER_SCHEMA:
				required.erase(k)
			var ok := DataLoader.validate(required, STYLE_SCHEMA, "%s:%s" % [STYLES_PATH, id])
			if ok and bool(st.ground_roll):
				var roller := {}
				for k: String in ROLLER_SCHEMA:
					if st.has(k):
						roller[k] = st[k]
				ok = DataLoader.validate(roller, ROLLER_SCHEMA, "%s:%s" % [STYLES_PATH, id])
			if ok:
				_styles[id] = st
		for id: Variant in raw.get("order", []):
			if _styles.has(str(id)):
				_style_order.append(str(id))
		_styles_fp = raw.get("fp", {})
	return _styles


# First-person scaling of the swing's torso twist / lean (presentation, D-117).
static func styles_fp() -> Dictionary:
	styles()
	return _styles_fp


# Style ids in the order F cycles through them.
static func style_order() -> PackedStringArray:
	styles()
	return _style_order


# A style by id; unknown ids (an old client, a typo) get the backhand.
static func style(id: String) -> Dictionary:
	var all := styles()
	return all.get(id, all.get("backhand", {}))


static func tuning() -> Dictionary:
	if _tuning.is_empty():
		_tuning = DataLoader.load_validated(TUNING_PATH, TUNING_SCHEMA)
	return _tuning


static func is_disc(id: String) -> bool:
	return discs().has(id)


# Every disc id, fastest first (drivers .. putters), then by id - the order 3 steps through the discs you carry.
static func bag_order() -> PackedStringArray:
	if _bag_order.is_empty():
		var ids := discs().keys()
		ids.sort_custom(func(a: String, b: String) -> bool:
			var sa := float(_discs[a].speed)
			var sb := float(_discs[b].speed)
			return sa > sb if sa != sb else a < b)
		_bag_order = PackedStringArray(ids)
	return _bag_order


# The plastic tier's numbers (D-119): {name, slip_deg, wear_per_throw, wear_per_tree}; unknown tiers are base.
static func plastic(disc: Dictionary, t: Dictionary) -> Dictionary:
	var all: Dictionary = t.get("plastics", {})
	return all.get(str(disc.get("tier", "base")), all.get("base", {}))


# A disc's numbers once it has beaten in (wear 0 new .. 1 fully worn): turn more negative, less fade. A copy.
static func worn(disc: Dictionary, wear: float, t: Dictionary) -> Dictionary:
	var w := clampf(wear, 0.0, 1.0)
	if w <= 0.0:
		return disc
	var out := disc.duplicate()
	var wt: Dictionary = t.get("wear", {})
	out.turn = float(disc.turn) + float(wt.get("turn_add", -1.5)) * w
	out.fade = float(disc.fade) * (1.0 - float(wt.get("fade_cut", 0.5)) * w)
	return out


# How the release slips in the hand (host-rolled): Vector2(yaw error in radians, tilt error in degrees).
static func slip(disc: Dictionary, t: Dictionary, rng: RandomNumberGenerator) -> Vector2:
	var deg := float(plastic(disc, t).get("slip_deg", 0.0))
	return Vector2(deg_to_rad(rng.randfn(0.0, deg)), rng.randfn(0.0, deg * 2.0))


# Wear after one throw that clipped `tree_hits` tree crowns.
static func wear_after(wear: float, disc: Dictionary, tree_hits: int, t: Dictionary) -> float:
	var pl := plastic(disc, t)
	return clampf(wear + float(pl.get("wear_per_throw", 0.0)) + float(pl.get("wear_per_tree", 0.0)) * tree_hits, 0.0, 1.0)


# Launch pitch (radians) for a camera pitch (radians).
static func launch_pitch(camera_pitch: float, t: Dictionary) -> float:
	return deg_to_rad(clampf(rad_to_deg(camera_pitch) + float(t.launch_pitch_add_deg), float(t.pitch_min_deg), float(t.pitch_max_deg)))


# A new flight from `from` toward yaw (radians, 0 = -Z like the player) at launch pitch (radians).
# `throw_style` = one of styles() (D-117); an empty one throws a plain backhand.
static func launch(disc: Dictionary, power: float, from: Vector3, yaw: float, pitch: float, tilt_deg: float,
		throw_style: Dictionary, t: Dictionary) -> Flight:
	var f := Flight.new()
	power = clampf(power, 0.03, 1.0)
	f.v_full = float(disc.full_speed_mps)
	f.v0 = f.v_full * power * float(throw_style.get("power_mult", 1.0))
	f.pos = from
	pitch += deg_to_rad(float(throw_style.get("pitch_add_deg", 0.0)))
	var dir := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	f.vel = dir * f.v0
	var roll_add := float(throw_style.get("roll_add_deg", 0.0))
	f.roll = deg_to_rad(clampf(tilt_deg, -float(t.tilt_max_deg), float(t.tilt_max_deg)) + roll_add)
	f.hand = float(throw_style.get("hand", 1.0))
	f.lift_max = G * (float(t.lift_base) + float(t.lift_glide) * float(disc.glide)) * (1.0 - float(t.lift_power) + float(t.lift_power) * power) \
		* float(throw_style.get("lift_mult", 1.0))
	f.k_drag = float(t.drag) / (1.0 + float(t.drag_speed) * float(disc.speed))
	f.turn = float(disc.turn) * float(throw_style.get("turn_mult", 1.0))
	f.fade = float(disc.fade) * float(throw_style.get("fade_mult", 1.0))
	f.flip = deg_to_rad(float(throw_style.get("flip_rate_deg", 0.0))) * signf(roll_add)
	f.max_roll = deg_to_rad(float(throw_style.get("max_roll_deg", t.max_roll_deg)))
	f.ground_roll = bool(throw_style.get("ground_roll", false))
	if f.ground_roll:
		f.roll_min = deg_to_rad(float(throw_style.roll_min_deg))
		f.roll_keep = float(throw_style.roll_keep)
		f.roll_friction = float(throw_style.roll_friction)
		f.roll_curve = deg_to_rad(float(throw_style.roll_curve_deg))
		f.fall_mps = float(throw_style.fall_mps)
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
	f.roll += f.flip * dt
	f.roll = clampf(f.roll, -f.max_roll, f.max_roll)
	var ratio := minf(v / f.v0, 1.2)
	var lift := f.lift_max * ratio * ratio
	var side := lift * sin(f.roll)
	var air := f.vel - f.wind
	var acc := Vector3(side * left.x, lift * cos(f.roll) - G, side * left.y) - air * (f.k_drag * air.length())
	f.vel += acc * dt
	f.pos += f.vel * dt
	f.time += dt


# Landing on its edge (roller, D-117): true if this flight starts rolling now; it then keeps roll_keep of its
# horizontal speed and stands up on its edge.
static func start_rolling(f: Flight) -> bool:
	var vh := Vector2(f.vel.x, f.vel.z)
	if not f.ground_roll or f.rolling or absf(f.roll) < f.roll_min or vh.length() * f.roll_keep < f.fall_mps * 2.0:
		return false
	f.rolling = true
	vh *= f.roll_keep
	f.vel = Vector3(vh.x, 0.0, vh.y)
	f.roll_v0 = vh.length()
	f.roll = signf(f.roll) * deg_to_rad(80.0)
	return true


# One step rolling on its edge over ground with this normal (D-117): rolling friction and the slope change its speed,
# it curves the way it leans (more as it slows) and leans further over. Returns false once it falls flat (it lies
# where it is; the caller moves it, follows the ground and stops it on obstacles).
static func roll_step(f: Flight, normal: Vector3, dt: float) -> bool:
	var vh := Vector2(f.vel.x, f.vel.z)
	var speed := vh.length()
	if speed < f.fall_mps:
		return false
	var dir := vh / speed
	var g_along := Vector3(0.0, -G, 0.0) - normal * (-G * normal.y)  # gravity along the slope
	speed += Vector2(g_along.x, g_along.z).dot(dir) * dt - f.roll_friction * dt
	if speed < f.fall_mps:
		f.roll = 0.0
		return false
	var slow := clampf(1.0 - speed / maxf(f.roll_v0, 0.01), 0.0, 1.0)
	dir = dir.rotated(-f.roll_curve * (0.25 + slow) * signf(f.roll) * dt)  # + roll (left edge down) curves left
	f.vel = Vector3(dir.x * speed, 0.0, dir.y * speed)
	f.roll = signf(f.roll) * deg_to_rad(lerpf(80.0, 88.0, slow))
	f.time += dt
	return true


enum Canopy { NONE, LEAVES, WOOD }
const DISC_RADIUS_M := 0.105


# What a disc touches in a tree drawn by TreeMesh (D-091). `local` is the disc's position in the tree's own units
# (height 1, trunk base at the origin: the instance transform's inverse); `shape` is the mesh's "tree_shape"
# {limbs: [[a, b, r0, r1]], blobs: [[centre, radius]]}; `pad` = the disc's radius in those units. WOOD = a branch
# (the trunk is a physics collider), LEAVES = inside a leaf clump, NONE = the air between them.
static func canopy_contact(local: Vector3, shape: Dictionary, pad: float) -> int:
	for limb: Array in shape.get("limbs", []):
		var a: Vector3 = limb[0]
		var ab: Vector3 = (limb[1] as Vector3) - a
		var k := clampf((local - a).dot(ab) / maxf(ab.length_squared(), 1e-8), 0.0, 1.0)
		if local.distance_to(a + ab * k) <= lerpf(float(limb[2]), float(limb[3]), k) + pad:
			return Canopy.WOOD
	for blob: Array in shape.get("blobs", []):
		if local.distance_to(blob[0]) <= float(blob[1]) + pad:
			return Canopy.LEAVES
	return Canopy.NONE


# Horizontal reach of a tree_shape from its trunk, in its own units (for bucketing trees by area).
static func canopy_reach(shape: Dictionary) -> float:
	var r := 0.0
	for limb: Array in shape.get("limbs", []):
		r = maxf(r, Vector2((limb[1] as Vector3).x, (limb[1] as Vector3).z).length() + float(limb[2]))
	for blob: Array in shape.get("blobs", []):
		r = maxf(r, Vector2((blob[0] as Vector3).x, (blob[0] as Vector3).z).length() + float(blob[1]))
	return r


# Old cells without a tree_shape: true if pos is inside the crown of a tree standing at base with height h (bare
# trees: thinner crowns).
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
static func flat_distance(disc: Dictionary, power: float, t: Dictionary, to_height := 0.0, throw_style := {}) -> float:
	var f := launch(disc, power, Vector3(0.0, float(t.launch_height_m), 0.0), 0.0, launch_pitch(0.0, t), 0.0, throw_style, t)
	var dt := 1.0 / float(t.step_hz)
	while (f.pos.y > to_height or f.vel.y > 0.0) and f.time < float(t.max_flight_s):
		step(f, dt, t)
	return Vector2(f.pos.x, f.pos.z).length()


# Table of flat_distance down to the chains at power 0, 0.05 .. 1 (21 entries).
static func reach_table(disc: Dictionary, t: Dictionary, throw_style := {}) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in 21:
		out.append(0.0 if i == 0 else flat_distance(disc, i / 20.0, t, float(t.aim_height_m), throw_style))
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
