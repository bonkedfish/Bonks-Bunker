# EncounterRules — pure rules for the random encounter director (D-105): the in-game clock, whether a definition
# may fire right now (cooldowns, quest flags, hour window, weather, distance from the bunker, placement), and the
# weighted pick among the ones that may. No nodes, no rendering; the caller passes plain dictionaries.
# A definition: {weight, rarity, cooldown_s, once, placement, requires, hours [from, to], weather, min_bunker_m,
#                max_bunker_m}. `state`: {last: {id: seconds}, done: {id: true}}.
class_name EncounterRules
extends RefCounted


# In-game hour 0-24 from the world's play time. day_start_hour is the hour a brand-new world starts at.
static func hour_of(play_seconds: float, minutes_per_real_minute: float, day_start_hour: float) -> float:
	var hours := play_seconds / 60.0 * (minutes_per_real_minute / 60.0)
	return fposmod(day_start_hour + hours, 24.0)


# True if `hour` is inside [from, to], which may wrap past midnight (22 -> 4). An empty window is always true.
static func hour_in(window: Array, hour: float) -> bool:
	if window.size() != 2:
		return true
	var from := float(window[0])
	var to := float(window[1])
	if is_equal_approx(from, to):
		return true
	return (hour >= from and hour < to) if from < to else (hour >= from or hour < to)


# Why `def` can't fire now, or "" if it can.
static func blocked_reason(def: Dictionary, now: float, state: Dictionary, flags: Dictionary, hour: float,
		weather: String, bunker_m: float, placement: String) -> String:
	var id := str(def.get("id", ""))
	if bool(def.get("once", false)) and bool((state.get("done", {}) as Dictionary).get(id, false)):
		return "already happened"
	var last := float((state.get("last", {}) as Dictionary).get(id, -1.0e12))
	var left := last + float(def.get("cooldown_s", 600.0)) - now
	if left > 0.0:
		return "cooling down %.0f s" % left
	if placement != "" and str(def.get("placement", "road")) != placement:
		return "wrong spot"
	if not QuestRules.requires_met(def.get("requires"), flags):
		return "quest flags"
	if not hour_in(def.get("hours", []), hour):
		return "wrong hour"
	var w: Array = def.get("weather", [])
	if not w.is_empty() and not (weather in w):
		return "wrong weather"
	if bunker_m < float(def.get("min_bunker_m", 0.0)):
		return "too close to the bunker"
	if bunker_m > float(def.get("max_bunker_m", 1.0e9)):
		return "too far from the bunker"
	return ""


# The weight a definition contributes (0 = can't fire).
static func weight_of(def: Dictionary, rarity_weight: Dictionary) -> float:
	return maxf(float(def.get("weight", 1.0)), 0.0) * float(rarity_weight.get(str(def.get("rarity", "common")), 1.0))


# One id from `defs` (id -> definition), weighted; "" if none can fire. `reasons` is filled with id -> why not.
static func pick(defs: Dictionary, rng: RandomNumberGenerator, now: float, state: Dictionary, flags: Dictionary,
		hour: float, weather: String, bunker_m: float, placement: String, rarity_weight: Dictionary,
		reasons: Dictionary = {}) -> String:
	var ids: Array = []
	var weights: Array = []
	var total := 0.0
	for id: String in defs:
		var def: Dictionary = defs[id]
		var why := blocked_reason(def, now, state, flags, hour, weather, bunker_m, placement)
		if why != "":
			reasons[id] = why
			continue
		var w := weight_of(def, rarity_weight)
		if w <= 0.0:
			reasons[id] = "no weight"
			continue
		ids.append(id)
		weights.append(w)
		total += w
	if total <= 0.0:
		return ""
	var pick_at := rng.randf() * total
	for i in ids.size():
		pick_at -= float(weights[i])
		if pick_at <= 0.0:
			return str(ids[i])
	return str(ids.back())


# Records that `id` fired at `now` (and, for a once-only encounter, that it is done).
static func mark_fired(state: Dictionary, id: String, now: float, once: bool) -> void:
	(state.last as Dictionary)[id] = now
	if once:
		(state.done as Dictionary)[id] = true


static func new_state() -> Dictionary:
	return {"last": {}, "done": {}}


# A saved state dictionary cleaned up into the shape above.
static func clean_state(saved: Variant) -> Dictionary:
	var out := new_state()
	if typeof(saved) != TYPE_DICTIONARY:
		return out
	for key: String in ["last", "done"]:
		var sub: Variant = (saved as Dictionary).get(key, {})
		if typeof(sub) != TYPE_DICTIONARY:
			continue
		for id: String in sub:
			if key == "last":
				out[key][id] = float(sub[id])
			else:
				out[key][id] = true
	return out
