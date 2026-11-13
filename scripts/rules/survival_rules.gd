# SurvivalRules — hunger/thirst and item-use math (D-046). Pure: no nodes, no rendering.
# Needs run 0 (empty) .. max_need (full). Tuning in data/tuning/survival.json; item effects in items.json "use":
# { seconds, heal?, food?, water? }. Depends on: DataLoader.
class_name SurvivalRules
extends RefCounted

const PATH := "res://data/tuning/survival.json"
const SCHEMA := {
	"max_need": TYPE_FLOAT, "hunger_minutes_to_empty": TYPE_FLOAT, "thirst_minutes_to_empty": TYPE_FLOAT,
	"low_threshold": TYPE_FLOAT, "low_heal_multiplier": TYPE_FLOAT, "low_blocks_sprint": TYPE_BOOL,
	"empty_damage_per_second": TYPE_FLOAT, "respawn_need_floor": TYPE_FLOAT, "cancel_move_speed": TYPE_FLOAT,
}

static var _tuning: Dictionary = {}


static func tuning() -> Dictionary:
	if _tuning.is_empty():
		_tuning = DataLoader.load_validated(PATH, SCHEMA)
	return _tuning


# Needs after `delta` seconds: Vector2(hunger, thirst). mult scales each meter's drain (effects, D-052).
static func drain(needs: Vector2, delta: float, t: Dictionary, mult := Vector2.ONE) -> Vector2:
	var m := float(t.max_need)
	var h := needs.x - m / (float(t.hunger_minutes_to_empty) * 60.0) * delta * mult.x
	var w := needs.y - m / (float(t.thirst_minutes_to_empty) * 60.0) * delta * mult.y
	return Vector2(clampf(h, 0.0, m), clampf(w, 0.0, m))


static func is_low(needs: Vector2, t: Dictionary) -> bool:
	return minf(needs.x, needs.y) <= float(t.low_threshold)


# Damage per second from an empty meter (either one).
static func starving_damage(needs: Vector2, t: Dictionary) -> float:
	return float(t.empty_damage_per_second) if minf(needs.x, needs.y) <= 0.0 else 0.0


static func can_sprint(needs: Vector2, t: Dictionary) -> bool:
	return not (bool(t.low_blocks_sprint) and is_low(needs, t))


static func heal_multiplier(needs: Vector2, t: Dictionary) -> float:
	return float(t.low_heal_multiplier) if is_low(needs, t) else 1.0


# The item's "use" block, or {} if it can't be used.
static func use_def(item: Dictionary) -> Dictionary:
	var u: Variant = item.get("use", {})
	if typeof(u) != TYPE_DICTIONARY or not u.has("seconds"):
		return {}
	return u


# Result of finishing a use: { health, needs } given current health/max and needs.
static func apply_use(use: Dictionary, health: float, max_health: float, needs: Vector2, t: Dictionary) -> Dictionary:
	var m := float(t.max_need)
	var heal := float(use.get("heal", 0.0)) * heal_multiplier(needs, t)
	var out_needs := Vector2(minf(needs.x + float(use.get("food", 0.0)), m), minf(needs.y + float(use.get("water", 0.0)), m))
	return {"health": minf(health + heal, max_health), "needs": out_needs}


# Which owned item a quick-use key picks: "heal" -> the aid item that heals most; "eat" -> the food/water that
# best fills the lower meter (or the other meter if nothing fills the lower one). "" if nothing fits.
static func quick_pick(kind: String, owned: Dictionary, items: Dictionary, needs: Vector2) -> String:
	if kind == "heal":
		return _best(owned, items, "heal")
	var first := "food" if needs.x <= needs.y else "water"
	var pick := _best(owned, items, first)
	return pick if pick != "" else _best(owned, items, "water" if first == "food" else "food")


static func _best(owned: Dictionary, items: Dictionary, effect: String) -> String:
	var best := ""
	var best_amount := 0.0
	for id: String in owned:
		if int(owned[id]) <= 0 or not items.has(id):
			continue
		var amount := float(use_def(items[id]).get(effect, 0.0))
		if amount > best_amount:
			best = id
			best_amount = amount
	return best
