# EffectRules — timed effects (D-052, compounding since D-082): chems and booze from data/effects/effects.json.
# `active` = { effect_id: {left, hold, peak} }. Each dose adds its "seconds" to `left`, up to max_doses worth; the
# dose LEVEL is left / seconds, so an effect weakens as it wears off. Strength = the level below 1 (fading out), else
# 1 + gain x (level - 1), capped at max_doses. Reaching hold_from doses starts a hold: the level stays put for
# hold_seconds before it starts wearing off (booze: 8+ drinks keeps you wasted for a couple of minutes). When an
# effect runs out, its "after" effect starts at after_scale x the peak level (a weak, slow comedown).
# mods() / look() / vomit() turn the strengths into numbers: multiplicative mods scale as 1 + (base - 1) x strength;
# "look" values are per strength, or [per, from] = per x (strength - from) once above `from`.
# Pure: no scene or rendering dependencies. Depends on: DataLoader.
class_name EffectRules
extends RefCounted

const PATH := "res://data/effects/effects.json"
const MOD_KEYS := ["damage_taken", "move_speed", "hunger_drain", "thirst_drain"]
const LOOK_KEYS := ["sway_deg", "drift_deg_s", "stumble", "double_px", "blur", "lurch", "impair"]
const MOD_MIN := 0.25
const MOD_MAX := 4.0

static var _defs: Dictionary = {}


static func defs() -> Dictionary:
	if _defs.is_empty():
		_defs = DataLoader.load_json(PATH).get("effects", {})
		for id: String in _defs:
			var e: Dictionary = _defs[id]
			if not e.has("name") or not e.has("seconds"):
				push_error("EffectRules: effect '%s' needs name and seconds" % id)
			if e.has("after") and not _defs.has(str(e.after)):
				push_error("EffectRules: effect '%s' has unknown after '%s'" % [id, e.after])
			for k: String in e.get("look", {}):
				if not k in LOOK_KEYS:
					push_error("EffectRules: effect '%s' has unknown look key '%s'" % [id, k])
	return _defs


static func has_effect(id: String) -> bool:
	return defs().has(id)


static func max_doses(e: Dictionary) -> float:
	return float(e.get("max_doses", 3.0))


# Dose level of one active entry (0 .. max_doses).
static func level(entry: Dictionary, e: Dictionary) -> float:
	return float(entry.left) / maxf(float(e.seconds), 0.001)


# Strength from a dose level: fades out below 1 dose, then grows by `gain` per extra dose.
static func strength(lv: float, e: Dictionary) -> float:
	if lv < 1.0:
		return maxf(lv, 0.0)
	return 1.0 + float(e.get("gain", 0.5)) * (minf(lv, max_doses(e)) - 1.0)


# Takes `doses` of effect `id`. Returns the new active set.
static func add(active: Dictionary, id: String, doses: float, d: Dictionary) -> Dictionary:
	var out := active.duplicate(true)
	if not d.has(id) or doses <= 0.0:
		return out
	var e: Dictionary = d[id]
	var entry: Dictionary = out.get(id, {"left": 0.0, "hold": 0.0, "peak": 0.0})
	var cap := float(e.seconds) * max_doses(e)
	entry.left = minf(float(entry.left) + float(e.seconds) * doses, cap)
	var lv := level(entry, e)
	entry.peak = maxf(float(entry.peak), lv)
	if e.has("hold_from") and lv >= float(e.hold_from):
		entry.hold = float(e.get("hold_seconds", 0.0))
	out[id] = entry
	return out


# Counts down; a held effect keeps its level until the hold ends. Expired effects start their "after" effect.
static func tick(active: Dictionary, delta: float, d: Dictionary) -> Dictionary:
	var out := {}
	var started: Dictionary = {}  # after id -> doses
	for id: String in active:
		var entry: Dictionary = active[id].duplicate()
		var held := minf(float(entry.hold), delta)  # the hold uses up time first; the rest wears the dose off
		entry.hold = float(entry.hold) - held
		entry.left = float(entry.left) - (delta - held)
		if float(entry.left) > 0.0:
			out[id] = entry
		elif d.has(id) and d[id].has("after"):
			var after := str(d[id].after)
			started[after] = maxf(float(started.get(after, 0.0)), float(entry.peak) * float(d[id].get("after_scale", 0.5)))
	for id: String in started:
		if not out.has(id):
			out = add(out, id, clampf(float(started[id]), 0.5, max_doses(d[id])), d)
	return out


# { effect id: strength } for the active set.
static func strengths(active: Dictionary, d: Dictionary) -> Dictionary:
	var out := {}
	for id: String in active:
		if d.has(id):
			out[id] = strength(level(active[id], d[id]), d[id])
	return out


# { damage_taken, move_speed, hunger_drain, thirst_drain, heal_per_second, fov_add } from strengths.
static func mods(str_by_id: Dictionary, d: Dictionary) -> Dictionary:
	var m := {"heal_per_second": 0.0, "fov_add": 0.0}
	for k: String in MOD_KEYS:
		m[k] = 1.0
	for id: String in str_by_id:
		if not d.has(id):
			continue
		var s := float(str_by_id[id])
		var e: Dictionary = d[id]
		var em: Dictionary = e.get("mods", {})
		for k: String in MOD_KEYS:
			m[k] *= clampf(1.0 + (float(em.get(k, 1.0)) - 1.0) * s, MOD_MIN, MOD_MAX)
		m.heal_per_second += float(e.get("heal_per_second", 0.0)) * s
		m.fov_add += float(e.get("fov_add", 0.0)) * minf(s, 3.0)
	for k: String in MOD_KEYS:
		m[k] = clampf(float(m[k]), MOD_MIN, MOD_MAX)
	return m


# How messed up you look and move: { sway_deg, drift_deg_s, stumble, double_px, blur, lurch, impair } (summed;
# impair, stumble, blur and lurch capped at 1).
static func look(str_by_id: Dictionary, d: Dictionary) -> Dictionary:
	var out := {}
	for k: String in LOOK_KEYS:
		out[k] = 0.0
	for id: String in str_by_id:
		var lk: Dictionary = d.get(id, {}).get("look", {})
		var s := float(str_by_id[id])
		for k: String in lk:
			var v: Variant = lk[k]
			if typeof(v) == TYPE_ARRAY:
				out[k] += float(v[0]) * maxf(s - float(v[1]), 0.0)
			else:
				out[k] += float(v) * s
	for k: String in ["impair", "stumble", "blur", "lurch"]:
		out[k] = minf(float(out[k]), 1.0)
	return out


# The vomit block of the first effect strong enough to make you throw up ({} when none): {from, every_s, food,
# water, stop_s}.
static func vomit(str_by_id: Dictionary, d: Dictionary) -> Dictionary:
	for id: String in str_by_id:
		var v: Dictionary = d.get(id, {}).get("vomit", {})
		if not v.is_empty() and float(str_by_id[id]) >= float(v.get("from", 99.0)):
			return v
	return {}
