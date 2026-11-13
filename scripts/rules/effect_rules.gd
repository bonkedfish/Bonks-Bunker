# EffectRules — timed effects (D-052): Fallout-chem style buffs with side effects, from data/effects/effects.json.
# `active` = { effect_id: seconds_left }. add() starts/restarts one; tick() counts down and starts each expired
# effect's "after" effect (comedowns); mods() multiplies every active effect's mods together (missing = 1.0) and sums
# heal_per_second and fov_add. Pure: no scene or rendering dependencies. Depends on: DataLoader.
class_name EffectRules
extends RefCounted

const PATH := "res://data/effects/effects.json"
const MOD_KEYS := ["damage_taken", "move_speed", "hunger_drain", "thirst_drain"]

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
	return _defs


static func has_effect(id: String) -> bool:
	return defs().has(id)


static func add(active: Dictionary, id: String, d: Dictionary) -> Dictionary:
	var out := active.duplicate()
	if d.has(id):
		out[id] = float(d[id].seconds)
	return out


static func tick(active: Dictionary, delta: float, d: Dictionary) -> Dictionary:
	var out := {}
	var started: Array = []
	for id: String in active:
		var left := float(active[id]) - delta
		if left > 0.0:
			out[id] = left
		elif d.has(id) and d[id].has("after"):
			started.append(str(d[id].after))
	for id: String in started:
		if not out.has(id):
			out[id] = float(d[id].seconds)
	return out


# { damage_taken, move_speed, hunger_drain, thirst_drain, heal_per_second, fov_add } for the active set.
static func mods(ids: Array, d: Dictionary) -> Dictionary:
	var m := {"heal_per_second": 0.0, "fov_add": 0.0}
	for k: String in MOD_KEYS:
		m[k] = 1.0
	for id: String in ids:
		if not d.has(id):
			continue
		var e: Dictionary = d[id]
		var em: Dictionary = e.get("mods", {})
		for k: String in MOD_KEYS:
			m[k] *= float(em.get(k, 1.0))
		m.heal_per_second += float(e.get("heal_per_second", 0.0))
		m.fov_add += float(e.get("fov_add", 0.0))
	return m
