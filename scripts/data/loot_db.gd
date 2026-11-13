# LootDB — loot tables from data/loot/loot_tables.json, looked up by string ID and validated.
# A table: rolls_min/rolls_max, entries [{item, weight, min, max}]; item "" means "nothing" for that roll.
# Every non-empty item must exist in ItemDB. Pure. Depends on: DataLoader, ItemDB.
class_name LootDB
extends RefCounted

const PATH := "res://data/loot/loot_tables.json"
const TABLE_SCHEMA := {"rolls_min": TYPE_FLOAT, "rolls_max": TYPE_FLOAT, "entries": TYPE_ARRAY}
const ENTRY_SCHEMA := {"item": TYPE_STRING, "weight": TYPE_FLOAT, "min": TYPE_FLOAT, "max": TYPE_FLOAT}

static var _tables: Dictionary = {}
static var _loaded := false


static func get_table(id: String) -> Dictionary:
	if not _loaded:
		_load()
	if not _tables.has(id):
		push_error("LootDB: unknown loot table '%s'" % id)
		return {}
	return _tables[id]


static func _load() -> void:
	_loaded = true
	var raw := DataLoader.load_json(PATH)
	for id: String in raw:
		var table: Variant = raw[id]
		var label := "%s:%s" % [PATH, id]
		if typeof(table) != TYPE_DICTIONARY or not DataLoader.validate(table, TABLE_SCHEMA, label):
			continue
		var ok := true
		for entry: Variant in table.entries:
			if typeof(entry) != TYPE_DICTIONARY or not DataLoader.validate(entry, ENTRY_SCHEMA, label + " entry"):
				ok = false
			elif entry.item != "" and not ItemDB.has_item(entry.item):
				push_error("LootDB: %s references unknown item '%s'" % [label, entry.item])
				ok = false
		if ok:
			_tables[id] = table
