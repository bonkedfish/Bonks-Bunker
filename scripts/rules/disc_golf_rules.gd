# DiscGolfRules — pure disc golf scoring and baskets (D-069): what a disc hitting a basket does (caught in the
# chains or tray, spat out, or bounced off the tray / pole), throw validation, score names, course pars, the
# reward tier for a finished round, and the group's throwing order (D-076). Depends on: DataLoader, data/discgolf/courses.json, DiscFlightRules (tuning).
class_name DiscGolfRules
extends RefCounted

enum Basket { NONE, CATCH, SPIT, BOUNCE }

const COURSES_PATH := "res://data/discgolf/courses.json"
const COURSE_SCHEMA := {"name": TYPE_STRING, "landmark": TYPE_STRING, "box": TYPE_ARRAY, "bounds": TYPE_ARRAY, "holes": TYPE_ARRAY}
const HOLE_SCHEMA := {"par": TYPE_FLOAT, "length_ft": TYPE_FLOAT, "tee": TYPE_ARRAY, "basket": TYPE_ARRAY}
const HOLE_OPTIONAL := ["label", "via"]  # shown name ("9½"), dogleg points

static var _courses: Dictionary = {}


static func courses() -> Dictionary:
	if _courses.is_empty():
		var raw := DataLoader.load_json(COURSES_PATH)
		for id: String in raw:
			var c: Variant = raw[id]
			if typeof(c) != TYPE_DICTIONARY or not DataLoader.validate(c, COURSE_SCHEMA, "%s:%s" % [COURSES_PATH, id]):
				continue
			var ok := true
			for h: Variant in c.holes:
				if typeof(h) != TYPE_DICTIONARY:
					ok = false
					continue
				var required: Dictionary = h.duplicate()
				for opt: String in HOLE_OPTIONAL:
					required.erase(opt)
				ok = ok and DataLoader.validate(required, HOLE_SCHEMA, "%s:%s hole" % [COURSES_PATH, id])
			if ok:
				_courses[id] = c
	return _courses


# Hole i's name on signs and cards: its "label" ("9½") or its number.
static func hole_label(course: Dictionary, i: int) -> String:
	return str(course.holes[i].get("label", i + 1))


static func par_total(course: Dictionary) -> int:
	var total := 0
	for h: Dictionary in course.holes:
		total += int(h.par)
	return total


# Disc at rel (relative to the basket's base) moving at speed, previous position prev_rel.
static func basket_contact(rel: Vector3, prev_rel: Vector3, speed: float, t: Dictionary) -> Basket:
	var d := Vector2(rel.x, rel.z).length()
	var r := float(t.catch_radius_m)
	if rel.y >= float(t.tray_low_m) and rel.y <= float(t.chains_high_m) and d <= r:
		var came_from_side := Vector2(prev_rel.x, prev_rel.z).length() > r and prev_rel.y < float(t.chains_low_m)
		if came_from_side and rel.y < float(t.chains_low_m):
			return Basket.BOUNCE  # into the side of the tray
		return Basket.CATCH if speed <= float(t.catch_max_mps) else Basket.SPIT
	if rel.y >= 0.0 and rel.y < float(t.tray_low_m) and d <= float(t.pole_radius_m) + 0.1:
		return Basket.BOUNCE  # the pole
	return Basket.NONE


# Clamped throw: [power 0..1, tilt degrees]; the disc must be a disc the player carries.
static func clamp_throw(power: float, tilt_deg: float, t: Dictionary) -> Vector2:
	var m := float(t.tilt_max_deg)
	return Vector2(clampf(power, 0.0, 1.0), clampf(tilt_deg, -m, m))


static func score_name(strokes: int, par: int) -> String:
	if strokes == 1:
		return "ACE!"
	match strokes - par:
		-3: return "Albatross"
		-2: return "Eagle"
		-1: return "Birdie"
		0: return "Par"
		1: return "Bogey"
		2: return "Double bogey"
		3: return "Triple bogey"
	return "%+d" % (strokes - par)


# "+2", "E", "-1".
static func to_par_text(strokes: int, par: int) -> String:
	return "E" if strokes == par else "%+d" % (strokes - par)


# Reward tables for a finished card: "par" at par or better, else "finish"; plus "ace" when any hole was an ace.
static func reward_tiers(strokes: Array, course: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var total := 0
	var ace := false
	for s: Variant in strokes:
		total += int(s)
		ace = ace or int(s) == 1
	out.append("par" if total <= par_total(course) else "finish")
	if ace:
		out.append("ace")
	return out


# Who throws next (D-076): anyone still on the tee goes first, in tee order; then whoever is furthest from the basket
# ("away"), ties in tee order. state: peer -> {"throws": int, "away": metres to the basket}, only players who can
# throw now. 0 when nobody can.
static func next_thrower(order: Array, state: Dictionary) -> int:
	var tee := 0
	var tee_rank := 1 << 30
	var away := 0
	var away_m := -1.0
	var away_rank := 1 << 30
	for peer: int in state:
		var rank := order.find(peer)
		if rank < 0:
			rank = 1 << 29
		var s: Dictionary = state[peer]
		if int(s.throws) == 0:
			if rank < tee_rank:
				tee = peer
				tee_rank = rank
		else:
			var m := float(s.away)
			if m > away_m + 0.01 or (absf(m - away_m) <= 0.01 and rank < away_rank):
				away = peer
				away_m = m
				away_rank = rank
	return tee if tee != 0 else away


# Tee order for the next hole (D-076): best (lowest) score on the last hole first, ties in random order.
# scores: peer -> strokes. Hole 1 (all 0) comes out random.
static func tee_order(scores: Dictionary, rng: RandomNumberGenerator) -> Array:
	var keyed: Array = []
	for peer: int in scores:
		keyed.append([int(scores[peer]), rng.randf(), peer])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out: Array = []
	for k: Array in keyed:
		out.append(k[2])
	return out
