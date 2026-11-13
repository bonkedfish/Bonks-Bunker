# ItemDB — item definitions from data/items/items.json, looked up by string ID and validated.
# Categories: weapon, ammo, aid, food, junk. Pure: no scene or rendering dependencies. Depends on: DataLoader.
class_name ItemDB
extends RefCounted

const PATH := "res://data/items/items.json"
const CATEGORIES := ["weapon", "ammo", "aid", "food", "chem", "gear", "junk", "quest"]
const SCHEMA := {"name": TYPE_STRING, "category": TYPE_STRING, "weight": TYPE_FLOAT, "value": TYPE_FLOAT}

static var _items: Dictionary = {}
static var _loaded := false


static func has_item(id: String) -> bool:
	_ensure_loaded()
	return _items.has(id)


static func get_item(id: String) -> Dictionary:
	_ensure_loaded()
	if not _items.has(id):
		push_error("ItemDB: unknown item id '%s'" % id)
		return {}
	return _items[id]


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var raw := DataLoader.load_json(PATH)
	for id: String in raw:
		var entry: Variant = raw[id]
		if typeof(entry) != TYPE_DICTIONARY:
			push_error("ItemDB: %s:%s is not an object" % [PATH, id])
			continue
		var required: Dictionary = entry.duplicate()
		required.erase("use")  # optional { seconds, heal?, food?, water?, effect? } (SurvivalRules D-046, EffectRules D-052)
		if not DataLoader.validate(required, SCHEMA, "%s:%s" % [PATH, id]):
			continue
		if not entry.category in CATEGORIES:
			push_error("ItemDB: %s:%s has unknown category '%s'" % [PATH, id, entry.category])
			continue
		_items[id] = entry
