# LootRules — pure loot rolling: picks `rolls` weighted entries from a loot table and sums the counts.
# Entries with item "" are "nothing" results. Depends on: a table Dictionary from LootDB.
class_name LootRules
extends RefCounted


static func roll(table: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	if table.is_empty():
		return out
	var entries: Array = table.entries
	var total := 0.0
	for e: Dictionary in entries:
		total += float(e.weight)
	if total <= 0.0:
		return out
	var rolls := rng.randi_range(int(table.rolls_min), int(table.rolls_max))
	for i in rolls:
		var pick := rng.randf() * total
		for e: Dictionary in entries:
			pick -= float(e.weight)
			if pick <= 0.0:
				if e.item != "":
					var n := rng.randi_range(int(e.min), int(e.max))
					if n > 0:
						out[e.item] = int(out.get(e.item, 0)) + n
				break
	return out
