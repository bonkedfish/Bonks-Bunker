# SaveFormat — the save file's shape, version, validation and migration (D-037). Pure: no nodes, no files.
# A world save stores only IDs, rolled values and world-state changes, never scene data:
#   version, name, created, saved (unix seconds), play_seconds,
#   containers: { container_id: { item_id: count } }   (only containers that were opened; what's left inside)
#   players:    { player_key: { position: [x,y,z], health, items: { item_id: count }, mags: [int],
#                               needs: [hunger, thirst] (optional, D-046; missing = full) } }
#   bonk:       { position: [x,y,z], health }            (empty until first save)
#   drops:      [[item_id, count, x, y, z], ...] oldest first (optional, D-046; items dropped into the world)
#   quests:     { flag: int } (optional, D-054; the party's quest flags + counters, incl. boss_<id>_dead)
# Zombies are not saved (they respawn). Bump VERSION and add a step to migrate() when the shape changes.
# Depends on: ItemDB (to drop items that no longer exist).
class_name SaveFormat
extends RefCounted

const VERSION := 1
const SLUG_MAX := 40


static func new_world(world_name: String, now: int) -> Dictionary:
	return {
		"version": VERSION, "name": world_name, "created": now, "saved": now, "play_seconds": 0.0,
		"containers": {}, "players": {}, "bonk": {},
	}


# Brings an older save up to VERSION. Returns {} for saves from a newer game or without a version.
static func migrate(data: Dictionary) -> Dictionary:
	var v := int(data.get("version", 0))
	if v < 1 or v > VERSION:
		return {}
	# Future: if v == 1: <reshape>; v = 2 ... then data.version = VERSION.
	return data


# "" when the (migrated) save is usable, otherwise what's wrong with it.
static func check(data: Dictionary) -> String:
	for key: String in ["name", "containers", "players", "bonk"]:
		if not data.has(key):
			return "missing '%s'" % key
	if typeof(data.name) != TYPE_STRING:
		return "name is not text"
	for key: String in ["containers", "players", "bonk"]:
		if typeof(data[key]) != TYPE_DICTIONARY:
			return "'%s' is not an object" % key
	for id: String in data.containers:
		if typeof(data.containers[id]) != TYPE_DICTIONARY:
			return "container '%s' is not an object" % id
	for key: String in data.players:
		var p: Variant = data.players[key]
		if typeof(p) != TYPE_DICTIONARY or not _is_vec(p.get("position")) or not _is_number(p.get("health")) \
				or typeof(p.get("items")) != TYPE_DICTIONARY:
			return "player '%s' is malformed" % key
	if not data.bonk.is_empty() and (not _is_vec(data.bonk.get("position")) or not _is_number(data.bonk.get("health"))):
		return "bonk is malformed"
	return ""


# Item stacks from a save, minus anything the item data no longer defines or non-positive counts.
static func clean_items(items: Dictionary) -> Dictionary:
	var out := {}
	for id: String in items:
		var n := int(items[id])
		if n > 0 and ItemDB.has_item(id):
			out[id] = n
	return out


static func player_entry(pos: Vector3, health: float, items: Dictionary, mags: Array, needs := Vector2(100, 100)) -> Dictionary:
	return {"position": vec_to_array(pos), "health": health, "items": items.duplicate(), "mags": mags.duplicate(),
		"needs": [snappedf(needs.x, 0.1), snappedf(needs.y, 0.1)]}


# Saved world drops, minus malformed entries and items the data no longer defines.
static func drops_of(data: Dictionary) -> Array:
	var out: Array = []
	var list: Variant = data.get("drops", [])
	if typeof(list) != TYPE_ARRAY:
		return out
	for e: Variant in list:
		if typeof(e) == TYPE_ARRAY and e.size() == 5 and typeof(e[0]) == TYPE_STRING and ItemDB.has_item(e[0]) \
				and _is_number(e[1]) and int(e[1]) > 0 and _is_number(e[2]) and _is_number(e[3]) and _is_number(e[4]):
			out.append([e[0], int(e[1]), float(e[2]), float(e[3]), float(e[4])])
	return out


# Saved needs as Vector2(hunger, thirst); full if missing or malformed.
static func needs_of(entry: Dictionary, full: float) -> Vector2:
	var n: Variant = entry.get("needs", [])
	if typeof(n) != TYPE_ARRAY or n.size() != 2 or not _is_number(n[0]) or not _is_number(n[1]):
		return Vector2(full, full)
	return Vector2(clampf(float(n[0]), 0.0, full), clampf(float(n[1]), 0.0, full))


static func vec_to_array(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


static func array_to_vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


# File-name-safe version of a world name: "Bonk's World!" -> "bonk_s_world".
static func slug(world_name: String) -> String:
	var out := ""
	for ch in world_name.to_lower():
		var ok := (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9")
		out += ch if ok else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.trim_prefix("_").trim_suffix("_").left(SLUG_MAX)
	return out if out != "" else "world"


static func _is_vec(v: Variant) -> bool:
	return typeof(v) == TYPE_ARRAY and v.size() == 3 and _is_number(v[0]) and _is_number(v[1]) and _is_number(v[2])


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT
