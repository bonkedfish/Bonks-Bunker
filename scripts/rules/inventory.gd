# Inventory — pure item container: item ID -> count, plus total carried weight.
# No nodes, no networking. Used by InventoryHolder (players) and for rules/tests.
# Depends on: ItemDB, CarryRules.
class_name Inventory
extends RefCounted

var items: Dictionary = {}  # String item_id -> int count


func add(id: String, n: int) -> void:
	if n <= 0:
		return
	items[id] = int(items.get(id, 0)) + n


# Returns how many were actually removed.
func remove(id: String, n: int) -> int:
	var have := int(items.get(id, 0))
	var taken := mini(have, maxi(n, 0))
	if have - taken <= 0:
		items.erase(id)
	else:
		items[id] = have - taken
	return taken


func count(id: String) -> int:
	return int(items.get(id, 0))


func total_weight() -> float:
	var total := 0.0
	for id: String in items:
		total += CarryRules.item_weight(ItemDB.get_item(id)) * int(items[id])
	return total


func to_dict() -> Dictionary:
	return items.duplicate()


func from_dict(d: Dictionary) -> void:
	items = {}
	for id: String in d:
		var n := int(d[id])
		if n > 0:
			items[id] = n
