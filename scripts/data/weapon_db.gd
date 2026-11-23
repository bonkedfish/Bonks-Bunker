# WeaponDB — weapon definitions from data/weapons/weapons.json, looked up by string ID.
# Each entry is validated against the schema for its "kind" (gun, melee or thrown, D-088), plus optional keys
# (D-087): mesh (kit weapon mesh shown in hand), spread_deg, pellets, auto (fires while held), zoom, wear
# (condition lost per attack), mod_slots, speed (thrown); D-122 gun feel: feel (recoil, bloom, aim, kick, flash),
# reload_cues, eject, cycle (see data/weapons/gun_feel.json note). Pure: no scene or rendering dependencies.
# Depends on: DataLoader.
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
	"thrown": {
		"name": TYPE_STRING, "kind": TYPE_STRING, "damage": TYPE_FLOAT, "fire_interval": TYPE_FLOAT,
		"range": TYPE_FLOAT, "speed": TYPE_FLOAT, "noise_radius": TYPE_FLOAT,
	},
}
const OPTIONAL := {
	"mesh": TYPE_STRING, "spread_deg": TYPE_FLOAT, "pellets": TYPE_FLOAT, "auto": TYPE_BOOL, "zoom": TYPE_FLOAT,
	"wear": TYPE_FLOAT, "mod_slots": TYPE_ARRAY,
	"feel": TYPE_DICTIONARY, "reload_cues": TYPE_ARRAY, "eject": TYPE_STRING, "cycle": TYPE_DICTIONARY,
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


static func has_weapon(id: String) -> bool:
	if not _loaded:
		_load()
	return _weapons.has(id)


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
		var required: Dictionary = entry.duplicate()
		var ok := true
		for key: String in OPTIONAL:
			if required.has(key):
				if typeof(required[key]) != OPTIONAL[key]:
					push_error("WeaponDB: %s:%s '%s' should be %s" % [PATH, id, key, type_string(OPTIONAL[key])])
					ok = false
				required.erase(key)
		if ok and DataLoader.validate(required, SCHEMAS[kind], "%s:%s" % [PATH, id]):
			entry["id"] = id  # sound events are named after the weapon (Sfx, D-077)
			_weapons[id] = entry
