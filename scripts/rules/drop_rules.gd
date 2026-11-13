# DropRules — pure rules for items dropped into the world (D-046): which drops a cell's loose-loot cap removes
# (oldest first) and whether a drop request is allowed. Tuning in data/tuning/drops.json.
# Depends on: DataLoader.
class_name DropRules
extends RefCounted

const TUNING_PATH := "res://data/tuning/drops.json"

static var _tuning: Dictionary = {}


static func tuning() -> Dictionary:
	if _tuning.is_empty():
		_tuning = DataLoader.load_json(TUNING_PATH)
	return _tuning


# ids = drop ids in one cell; ids grow over time, so the smallest are the oldest. Returns the ids to remove.
static func over_cap(ids: Array, cap: int) -> Array:
	if ids.size() <= cap:
		return []
	var sorted := ids.duplicate()
	sorted.sort()
	return sorted.slice(0, sorted.size() - cap)


# How many of item `id` a player holding `owned` may drop when asking for n (n <= 0 = the whole stack).
static func drop_count(owned: int, n: int) -> int:
	if owned <= 0:
		return 0
	return owned if n <= 0 else mini(n, owned)
