# ZombieTypeRules — pure rules for the open-world zombie types (D-100): which type spawns at a distance from the
# bunker, how much of a hit gets through armor (Riot Cop), and how hard a Bloater's burst hits at a distance.
# No nodes, no rendering. Depends on: nothing (callers pass the tuning / enemy definition Dictionaries).
class_name ZombieTypeRules
extends RefCounted


# bands: [[from_m, {enemy_id: weight, ...}], ...] sorted by from_m. The last band whose from_m <= dist_m is used.
# `mult` (D-110) scales each type's weight - at night the specials get commoner and plain shamblers rarer - and
# `amount` 0..1 fades that in, so dusk is halfway between the day table and the night one.
# Returns "" if there are no bands or the band has no positive weight.
static func pick_type(bands: Array, dist_m: float, rng: RandomNumberGenerator, mult := {}, amount := 0.0) -> String:
	var weights: Dictionary = {}
	for band: Array in bands:
		if dist_m >= float(band[0]):
			weights = band[1]
	var scaled: Dictionary = {}
	var total := 0.0
	for id: String in weights:
		var w := maxf(float(weights[id]), 0.0) * lerpf(1.0, float(mult.get(id, 1.0)), clampf(amount, 0.0, 1.0))
		scaled[id] = w
		total += w
	if total <= 0.0:
		return ""
	var pick := rng.randf() * total
	for id: String in scaled:
		pick -= float(scaled[id])
		if pick <= 0.0:
			return id
	return str(scaled.keys().back())


# Share of a hit's damage that gets through. armor: {body_mult, head_mult, melee_mult, head_from} (empty = no armor).
# hit_frac: where the hit landed up the body (0 = feet, 1 = top of the head). Melee ignores where it landed.
static func armor_mult(armor: Dictionary, hit_frac: float, melee: bool) -> float:
	if armor.is_empty():
		return 1.0
	if melee:
		return float(armor.get("melee_mult", 1.0))
	if hit_frac >= float(armor.get("head_from", 0.75)):
		return float(armor.get("head_mult", 1.0))
	return float(armor.get("body_mult", 1.0))


# Damage at dist_m from a burst {radius_m, damage, edge_frac}: full at the centre, edge_frac of it at the radius,
# nothing beyond.
static func burst_damage(burst: Dictionary, dist_m: float) -> float:
	var r := float(burst.get("radius_m", 0.0))
	if r <= 0.0 or dist_m > r:
		return 0.0
	var edge := float(burst.get("edge_frac", 0.35))
	return float(burst.get("damage", 0.0)) * lerpf(1.0, edge, clampf(dist_m / r, 0.0, 1.0))
