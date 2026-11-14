# BikeRules — pure motorcycle rules (D-083): the bikes from data/vehicles/bikes.json, and one physics tick of a ridden
# bike: clutch (engagement 0..1, eases out over clutch_release_s), a free-revving engine that locks to the rear wheel as
# the clutch comes out, gears with a rev limiter, a torque curve, brakes, rolling / engine braking and drag (top speed
# comes out of the top gear's redline), stalling (clutch out in gear below stall rpm), fuel, lean-steering (turn rate
# from lean and speed, a slow paddle-turn when nearly stopped) and pitch (throttle / clutch-kick wheelies, brake
# stoppies, leaning back / forward, free pitch in the air). Also: when a bike crashes, crash damage, refuelling, and
# which bike (if any) is parked in a map cell for a world.
# State `s` is a Dictionary mutated in place (no allocation per tick): speed (m/s along the heading, < 0 = pushed back),
# rpm, free_rpm, gear (0 = neutral), clutch, lean (rad, + = right), pitch (rad, + = nose up), pitch_rate, yaw_rate
# (d rotation.y / dt), drive (m/s^2 last tick), engine (running), limiter, stalled / out_of_gas (set on the tick it
# happens; the caller clears them), fuel (litres).
# Inputs: throttle / brake 0..1, steer -1..1 (+ = right), rider -1..1 (+ = lean back), clutch_held.
# Pure: no scene or rendering dependencies. Depends on: DataLoader.
class_name BikeRules
extends RefCounted

const PATH := "res://data/vehicles/bikes.json"
const GRAVITY := 9.8
const SCHEMA := {"note": TYPE_STRING, "tuning": TYPE_DICTIONARY, "bikes": TYPE_DICTIONARY}
const BIKE_SCHEMA := {
	"name": TYPE_STRING, "gear_top_kmh": TYPE_ARRAY, "idle_rpm": TYPE_FLOAT, "redline_rpm": TYPE_FLOAT,
	"accel": TYPE_FLOAT, "torque": TYPE_ARRAY, "wheelie": TYPE_FLOAT, "lean_deg": TYPE_FLOAT, "brake": TYPE_FLOAT,
	"tank_l": TYPE_FLOAT, "engine": TYPE_STRING, "spawn_weight": TYPE_FLOAT, "shape": TYPE_DICTIONARY,
	"schemes": TYPE_ARRAY,
}
const TUNING_KEYS := ["clutch_release_s", "stall_rpm_frac", "rev_up_rpm_s", "rev_down_rpm_s", "rolling_mps2",
	"engine_brake_mps2", "low_speed_turn", "lean_rate", "full_lean_mps", "gravity_pitch", "rider_pitch", "air_pitch",
	"pitch_damping", "pitch_spring", "clutch_kick", "stoppie", "loop_deg", "endo_deg", "land_pitch_deg", "land_vy", "impact_mps",
	"crash_safe_mps", "crash_damage_per_mps", "crash_damage_max", "knock_off_damage", "back_push_mps", "idle_lpm",
	"full_lpm", "gas_can_l", "spawn_chance", "dismount_max_mps", "zombie_hit_mps", "zombie_damage_per_mps",
	"zombie_hit_slow", "parked_view_m", "sound_m"]

static var _data: Dictionary = {}


# The whole file, validated once ({} when it is broken).
static func data() -> Dictionary:
	if _data.is_empty():
		var d := DataLoader.load_validated(PATH, SCHEMA)
		if d.is_empty():
			return {}
		for key: String in TUNING_KEYS:
			if typeof(d.tuning.get(key)) != TYPE_FLOAT:
				push_error("BikeRules: tuning '%s' missing or not a number" % key)
				return {}
		for id: String in d.bikes:
			if not DataLoader.validate(d.bikes[id], BIKE_SCHEMA, PATH + ":" + id):
				return {}
		_data = d
	return _data


static func tuning() -> Dictionary:
	return data().get("tuning", {})


static func bike(id: String) -> Dictionary:
	return data().get("bikes", {}).get(id, {})


static func has_bike(id: String) -> bool:
	return data().get("bikes", {}).has(id)


static func new_state(fuel: float) -> Dictionary:
	return {"speed": 0.0, "rpm": 0.0, "free_rpm": 0.0, "gear": 0, "clutch": 1.0, "lean": 0.0, "pitch": 0.0,
		"pitch_rate": 0.0, "yaw_rate": 0.0, "drive": 0.0, "engine": fuel > 0.0, "limiter": false, "stalled": false,
		"out_of_gas": false, "fuel": fuel}


static func gears(b: Dictionary) -> int:
	return (b.gear_top_kmh as Array).size()


# Road speed (m/s) at the redline in gear g (1-based); 0 for neutral.
static func top_mps(b: Dictionary, g: int) -> float:
	var tops: Array = b.gear_top_kmh
	return float(tops[clampi(g, 1, tops.size()) - 1]) / 3.6 if g > 0 else 0.0


# Torque fraction at rpm fraction x (0..1 of the redline), linear between the data points.
static func torque(b: Dictionary, x: float) -> float:
	var pts: Array = b.torque
	if x <= float(pts[0][0]):
		return float(pts[0][1])
	for i in range(1, pts.size()):
		if x <= float(pts[i][0]):
			var a: Array = pts[i - 1]
			var c: Array = pts[i]
			return lerpf(float(a[1]), float(c[1]), (x - float(a[0])) / maxf(float(c[0]) - float(a[0]), 0.0001))
	return float(pts[pts.size() - 1][1])


# Sequential box: N <-> 1 <-> 2 ... Only with the clutch pulled in (D-083: manual with clutch). True when it shifted.
static func shift(s: Dictionary, b: Dictionary, want: int) -> bool:
	var g := int(s.gear)
	var w := clampi(want, 0, gears(b))
	if w == g or float(s.clutch) > 0.5:
		return false
	s.gear = g + signi(w - g)  # one step per tick
	return true


static func step(s: Dictionary, b: Dictionary, t: Dictionary, throttle: float, brake: float, steer: float,
		rider: float, clutch_held: bool, on_floor: bool, dt: float) -> void:
	var g := int(s.gear)
	var redline := float(b.redline_rpm)
	var idle := float(b.idle_rpm)
	var running := bool(s.engine)
	var thr := throttle if running else 0.0
	var v1 := top_mps(b, 1)
	var vg := top_mps(b, g)
	var wheel := absf(float(s.speed)) / vg * redline if g > 0 else 0.0
	# Clutch: in at once, out over clutch_release_s; on the gas below idle-speed it slips longer (a launch), with no
	# gas it bites at the normal pace (so dumping it from a standstill stalls).
	var rate := 1.0 / float(t.clutch_release_s)
	if g > 0 and thr > 0.1:
		rate *= clampf(wheel / idle, 0.2, 1.0)
	s.clutch = 0.0 if clutch_held else minf(float(s.clutch) + rate * dt, 1.0)
	var e := float(s.clutch) if g > 0 else 0.0
	# Engine: revs freely toward the throttle; the clutch blends it onto the rear wheel.
	var target := idle + thr * (redline - idle) if running else 0.0
	var free := float(s.free_rpm)
	free = move_toward(free, target, (float(t.rev_up_rpm_s) if target > free else float(t.rev_down_rpm_s)) * dt)
	var rpm := lerpf(free, wheel, e) if g > 0 else free
	if e >= 1.0 and running:
		free = wheel  # locked to the wheel: a later clutch pull starts from here
	s.limiter = false
	var drive := 0.0
	if running and g > 0:
		drive = thr * torque(b, clampf(rpm / redline, 0.0, 1.0)) * float(b.accel) * (v1 / vg) * e
		if rpm >= redline:
			drive = 0.0
			s.limiter = true
			rpm = redline
			free = minf(free, redline)
	s.free_rpm = free
	var engine_brake := 0.0
	if g > 0 and e > 0.5 and thr < 0.05:
		engine_brake = float(t.engine_brake_mps2) * clampf(rpm / redline, 0.0, 1.0) * (v1 / vg) * e
	var vtop := top_mps(b, gears(b))
	var drag_k := float(b.accel) * (v1 / vtop) * torque(b, 1.0) / (vtop * vtop) * 0.85  # top gear just reaches its redline
	var speed := float(s.speed)
	if on_floor:
		speed += drive * dt
		if speed > 0.0:
			var dec := brake * float(b.brake) + float(t.rolling_mps2) + engine_brake + drag_k * speed * speed
			speed = maxf(speed - dec * dt, 0.0)
		if brake > 0.5 and speed <= 0.3 and (g == 0 or e < 0.5 or not running):
			speed = move_toward(speed, -float(t.back_push_mps), 3.0 * dt)  # paddle it backwards
		elif speed < 0.0 and brake <= 0.5:
			speed = move_toward(speed, 0.0, 3.0 * dt)
	else:
		speed -= signf(speed) * drag_k * speed * speed * dt
	s.speed = speed
	# Stall: clutch out, in gear, wheel too slow for the engine.
	if running and g > 0 and e >= 1.0 and wheel < idle * float(t.stall_rpm_frac) and speed >= 0.0:
		s.engine = false
		s.stalled = true
		running = false
	s.rpm = rpm if running else 0.0
	s.drive = drive
	# Lean + turn rate.
	var v := absf(speed)
	var full := clampf(v / float(t.full_lean_mps), 0.0, 1.0)
	s.lean = move_toward(float(s.lean), steer * deg_to_rad(float(b.lean_deg)) * full, float(t.lean_rate) * dt)
	var turn := lerpf(steer * float(t.low_speed_turn), GRAVITY * tan(float(s.lean)) / maxf(v, 0.1),
		clampf((v - 2.0) / 4.0, 0.0, 1.0))
	if speed < 0.0:
		turn = -turn * 0.5
	s.yaw_rate = -turn if on_floor else 0.0
	# Pitch.
	var p := float(s.pitch)
	var w := float(s.pitch_rate)
	var grav := float(t.gravity_pitch)
	var spring := float(t.pitch_spring)  # with gravity: a steady throttle holds a steady wheelie / stoppie angle
	if on_floor:
		var kick := float(t.clutch_kick) * maxf(free - wheel, 0.0) / 1000.0 * thr if g > 0 and e > 0.0 and e < 1.0 else 0.0
		var up := float(b.wheelie) * drive + kick + maxf(rider, 0.0) * float(t.rider_pitch)
		var down := float(t.stoppie) * brake * float(b.brake) * clampf(v / 5.0, 0.0, 1.0) * (1.0 + maxf(-rider, 0.0) * 0.6) \
			+ maxf(-rider, 0.0) * float(t.rider_pitch)
		if p > 0.0 or (p == 0.0 and up > grav):  # wheelie: rear wheel down
			w += (up - grav * cos(p) - spring * p - brake * float(b.brake) * 0.6 - float(t.pitch_damping) * w) * dt
			p += w * dt
			if p < 0.0:
				p = 0.0
				w = 0.0
		elif p < 0.0 or (p == 0.0 and down > grav):  # stoppie: front wheel down
			w += (-down + grav * cos(p) - spring * p - float(t.pitch_damping) * w) * dt
			p += w * dt
			if p > 0.0:
				p = 0.0
				w = 0.0
		else:
			p = 0.0
			w = 0.0
	else:
		w += (rider * float(t.air_pitch) - 0.4 * w) * dt
		p += w * dt
	s.pitch = p
	s.pitch_rate = w
	# Fuel.
	if running:
		s.fuel = maxf(float(s.fuel) - (float(t.idle_lpm) + float(t.full_lpm) * thr * clampf(rpm / redline, 0.0, 1.0)) * dt / 60.0, 0.0)
		if float(s.fuel) <= 0.0:
			s.engine = false
			s.out_of_gas = true


# B: the engine restarts with fuel, and the clutch in or in neutral.
static func can_start(s: Dictionary) -> bool:
	return not bool(s.engine) and float(s.fuel) > 0.0 and (int(s.gear) == 0 or float(s.clutch) < 0.5)


static func start(s: Dictionary, b: Dictionary) -> void:
	s.engine = true
	s.free_rpm = float(b.idle_rpm)


# Crash reasons ("" = none).
static func pitch_crash(s: Dictionary, t: Dictionary) -> String:
	if float(s.pitch) > deg_to_rad(float(t.loop_deg)):
		return "looped it"
	if float(s.pitch) < -deg_to_rad(float(t.endo_deg)):
		return "went over the bars"
	return ""


static func landing_crash(pitch: float, vy: float, t: Dictionary) -> String:
	if vy < -float(t.land_vy):
		return "landed too hard"
	if absf(pitch) > deg_to_rad(float(t.land_pitch_deg)):
		return "landed crooked"
	return ""


static func impact_crash(speed_before: float, speed_after: float, t: Dictionary) -> String:
	return "hit something" if speed_before - speed_after > float(t.impact_mps) else ""


static func crash_damage(speed: float, t: Dictionary) -> float:
	return clampf((absf(speed) - float(t.crash_safe_mps)) * float(t.crash_damage_per_mps), 0.0, float(t.crash_damage_max))


# [new fuel, gas cans used] filling from `cans` gas cans.
static func refuel(fuel: float, cans: int, b: Dictionary, t: Dictionary) -> Array:
	var used := 0
	var tank := float(b.tank_l)
	while used < cans and fuel < tank - 0.05:
		fuel = minf(fuel + float(t.gas_can_l), tank)
		used += 1
	return [fuel, used]


# The bike parked in map cell `cell` of the world with seed `world_seed`, or {} for none:
# {model, scheme, fuel, marker (index into marker_count road markers), yaw, offset [x, z]}. Same answer every time.
static func cell_bike(world_seed: int, cell: Vector2i, marker_count: int) -> Dictionary:
	var d := data()
	if d.is_empty() or marker_count <= 0:
		return {}
	var t: Dictionary = d.tuning
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, cell.x, cell.y, "bike"])
	if rng.randf() >= float(t.spawn_chance):
		return {}
	var total := 0.0
	for id: String in d.bikes:
		total += float(d.bikes[id].spawn_weight)
	var pick := rng.randf() * total
	var model := ""
	for id: String in d.bikes:
		model = id
		pick -= float(d.bikes[id].spawn_weight)
		if pick <= 0.0:
			break
	var b: Dictionary = d.bikes[model]
	var fs: Array = t.get("fuel_spawn", [0.2, 0.6])
	return {"model": model, "scheme": rng.randi() % (b.schemes as Array).size(),
		"fuel": snappedf(float(b.tank_l) * rng.randf_range(float(fs[0]), float(fs[1])), 0.1),
		"marker": rng.randi() % marker_count, "yaw": rng.randf() * TAU,
		"offset": [rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5)]}
