# CarryRules — pure carry-weight rules (D-021, D-024): item weight (ammo is weightless), movement speed
# multiplier and sprint permission from carried weight, and the inventory tuning loader.
# Depends on: DataLoader, data/tuning/inventory.json.
class_name CarryRules
extends RefCounted

const TUNING_PATH := "res://data/tuning/inventory.json"
const TUNING_SCHEMA := {
	"carry_capacity": TYPE_FLOAT,
	"overweight_speed_multiplier": TYPE_FLOAT,
	"stuck_ratio": TYPE_FLOAT,
	"stuck_speed_multiplier": TYPE_FLOAT,
	"interact_range": TYPE_FLOAT,
	"starting_items": TYPE_DICTIONARY,
}

static var _tuning: Dictionary = {}


static func load_tuning() -> Dictionary:
	if _tuning.is_empty():
		_tuning = DataLoader.load_validated(TUNING_PATH, TUNING_SCHEMA)
	return _tuning


static func item_weight(def: Dictionary) -> float:
	if def.is_empty() or def.get("category", "") == "ammo":
		return 0.0
	return float(def.weight)


static func speed_multiplier(weight: float, t: Dictionary) -> float:
	var capacity := float(t.carry_capacity)
	if weight <= capacity:
		return 1.0
	if weight >= capacity * float(t.stuck_ratio):
		return float(t.stuck_speed_multiplier)
	return float(t.overweight_speed_multiplier)


static func can_sprint(weight: float, t: Dictionary) -> bool:
	return weight <= float(t.carry_capacity)
