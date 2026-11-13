# RecipeDB — crafting recipes from data/crafting/recipes.json by string ID (D-046): name, needs {item: count},
# gives {item: count}. A recipe naming an unknown item or a non-positive count is rejected with an error.
# Pure: no scene or rendering dependencies. Depends on: DataLoader, ItemDB.
class_name RecipeDB
extends RefCounted

const PATH := "res://data/crafting/recipes.json"

static var _recipes: Dictionary = {}
static var _loaded := false


static func ids() -> Array:
	_ensure_loaded()
	var out := _recipes.keys()
	out.sort()
	return out


static func has_recipe(id: String) -> bool:
	_ensure_loaded()
	return _recipes.has(id)


static func get_recipe(id: String) -> Dictionary:
	_ensure_loaded()
	return _recipes.get(id, {})


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var raw := DataLoader.load_json(PATH)
	for id: String in raw:
		var r: Variant = raw[id]
		if typeof(r) != TYPE_DICTIONARY or typeof(r.get("name")) != TYPE_STRING \
				or not _stacks_ok(r.get("needs")) or not _stacks_ok(r.get("gives")):
			push_error("RecipeDB: %s:%s is malformed (name, needs {item: n}, gives {item: n})" % [PATH, id])
			continue
		_recipes[id] = r


static func _stacks_ok(v: Variant) -> bool:
	if typeof(v) != TYPE_DICTIONARY or v.is_empty():
		return false
	for item: String in v:
		if not ItemDB.has_item(item) or int(v[item]) <= 0:
			return false
	return true
