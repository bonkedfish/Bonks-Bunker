# Inventory — pure item container: item ID -> count for stackable items, plus rolled gear instances (D-087:
# weapons and armor, each {uid, id, rarity, cond, mods, perk, mag}) and which instance sits in each equip slot
# (GearRules.SLOTS), and the total carried weight. No nodes, no networking. Used by InventoryHolder (players) and
# for rules/tests. Depends on: ItemDB, CarryRules, GearRules.
class_name Inventory
extends RefCounted

var items: Dictionary = {}  # String item_id -> int count
var gear: Array = []        # gear instances
var equip: Dictionary = {}  # slot -> uid
var next_uid := 1


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
	for g: Dictionary in gear:
		total += GearRules.weight(g)
	return total


func to_dict() -> Dictionary:
	return items.duplicate()


func from_dict(d: Dictionary) -> void:
	items = {}
	for id: String in d:
		var n := int(d[id])
		if n > 0:
			items[id] = n


# --- gear (D-087) --------------------------------------------------------------------------

# Adds an instance (gives it a new uid) and puts it in the first matching empty slot. Returns the uid.
func add_gear(inst: Dictionary) -> int:
	var g := inst.duplicate(true)
	g.uid = next_uid
	next_uid += 1
	gear.append(g)
	for slot: String in GearRules.slots_for(str(g.id)):
		if not equip.has(slot):
			equip[slot] = g.uid
			break
	return g.uid


# Takes an instance out (unequipping it). Returns it, or {} if there's no such uid.
func remove_gear(uid: int) -> Dictionary:
	for i in gear.size():
		if int(gear[i].uid) == uid:
			var g: Dictionary = gear[i]
			gear.remove_at(i)
			for slot: String in equip.keys():
				if int(equip[slot]) == uid:
					equip.erase(slot)
			return g
	return {}


func get_gear(uid: int) -> Dictionary:
	for g: Dictionary in gear:
		if int(g.uid) == uid:
			return g
	return {}


# Replaces an instance's data (condition, magazine, mods); keeps its uid.
func set_gear(uid: int, inst: Dictionary) -> void:
	for i in gear.size():
		if int(gear[i].uid) == uid:
			var g := inst.duplicate(true)
			g.uid = uid
			gear[i] = g
			return


# Puts `uid` in `slot` if it fits there (moving it out of any other slot). False if it doesn't.
func equip_gear(uid: int, slot: String) -> bool:
	var g := get_gear(uid)
	if g.is_empty() or not slot in GearRules.slots_for(str(g.id)):
		return false
	for s: String in equip.keys():
		if int(equip[s]) == uid:
			equip.erase(s)
	equip[slot] = uid
	return true


func unequip(slot: String) -> void:
	equip.erase(slot)


func equipped(slot: String) -> Dictionary:
	return get_gear(int(equip[slot])) if equip.has(slot) else {}


func gear_to_dict() -> Dictionary:
	return {"list": gear.duplicate(true), "equip": equip.duplicate(), "next": next_uid}


func gear_from_dict(d: Dictionary) -> void:
	gear = []
	for g: Variant in d.get("list", []):
		if g is Dictionary and (g as Dictionary).has("id") and ItemDB.has_item(str(g.id)) and GearRules.is_gear(str(g.id)):
			var c: Dictionary = (g as Dictionary).duplicate(true)
			c.uid = int(c.get("uid", 0))
			c.cond = clampf(float(c.get("cond", 1.0)), 0.0, 1.0)
			c.mag = int(c.get("mag", 0))
			c.mods = (c.get("mods", []) as Array).filter(func(m: Variant) -> bool: return GearRules.is_mod(str(m)))
			c.perk = str(c.get("perk", ""))
			c.rarity = str(c.get("rarity", "standard"))
			gear.append(c)
	equip = {}
	var e: Variant = d.get("equip", {})
	if e is Dictionary:
		for slot: String in (e as Dictionary):
			if slot in GearRules.SLOTS and not get_gear(int(e[slot])).is_empty():
				equip[slot] = int(e[slot])
	next_uid = maxi(int(d.get("next", 1)), 1)
	for g: Dictionary in gear:
		next_uid = maxi(next_uid, int(g.uid) + 1)
