# CraftingRules — pure crafting checks (D-046): what a recipe still needs given the items a player holds.
# Depends on: nothing (recipes come from RecipeDB, counts from the caller).
class_name CraftingRules
extends RefCounted


# item_id -> how many more are needed (empty = can craft). have(item_id) -> int.
static func missing(recipe: Dictionary, have: Callable) -> Dictionary:
	var out := {}
	var needs: Dictionary = recipe.get("needs", {})
	for item: String in needs:
		var short: int = int(needs[item]) - int(have.call(item))
		if short > 0:
			out[item] = short
	return out


static func can_craft(recipe: Dictionary, have: Callable) -> bool:
	return not recipe.is_empty() and missing(recipe, have).is_empty()
