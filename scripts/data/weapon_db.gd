# WeaponDB — weapon definitions from data/weapons/weapons.json, looked up by string ID.
# Each entry is validated against the schema for its "kind" (gun or melee).
# Pure: no scene or rendering dependencies. Depends on: DataLoader.
class_name WeaponDB
extends RefCounted

const PATH := "res://data/weapons/weapons.json"
const SCHEMAS := {
	"gun": {
		"name": TYPE_STRING, "kind": TYPE_STRING, "damage": TYPE_FLOAT, "fire_interval": TYPE_FLOAT,
		"range": TYPE_FLOAT, "mag_size": TYPE_FLOAT, "ammo_item": TYPE_STRING, "reload_time": TYPE_FLOAT,
		"noise_radius": TYPE_FLOAT,
	},
	"melee": {
		"name": TYPE_STRING, "kind": TYPE_STRING, "damage": TYPE_FLOAT, "windup": TYPE_FLOAT,
		"swing_interval": TYPE_FLOAT, "range": TYPE_FLOAT, "arc_degrees": TYPE_FLOAT,
		"noise_radius": TYPE_FLOAT,
	},
}

static var _weapons: Dictionary = {}
static var _loaded := false


static func get_weapon(id: String) -> Dictionary:
	if not _loaded:
		_load()
	if not _weapons.has(id):
		push_error("WeaponDB: unknown weapon id '%s'" % id)
		return {}
	return _weapons[id]


static func _load() -> void:
	_loaded = true
	var raw := DataLoader.load_json(PATH)
	for id: String in raw:
		var entry: Variant = raw[id]
		if typeof(entry) != TYPE_DICTIONARY:
			push_error("WeaponDB: %s:%s is not an object" % [PATH, id])
			continue
		var kind := str(entry.get("kind", ""))
		if not SCHEMAS.has(kind):
			push_error("WeaponDB: %s:%s has unknown kind '%s'" % [PATH, id, kind])
			continue
		if DataLoader.validate(entry, SCHEMAS[kind], "%s:%s" % [PATH, id]):
			_weapons[id] = entry
