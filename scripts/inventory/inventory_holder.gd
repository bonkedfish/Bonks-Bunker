# InventoryHolder — a player's inventory (Player child "Inventory").
# Host owns it: host_add/host_remove change the pure Inventory and republish `net_items`, which replicates
# (on change) through the player's MultiplayerSynchronizer. Every peer mirrors it and keeps `weight` current,
# so the owning client predicts overweight movement with the same numbers as the host.
# Depends on: Inventory (pure), CarryRules.
class_name InventoryHolder
extends Node

signal changed

var model := Inventory.new()
var weight := 0.0

# Replicated host -> clients. Always assign a NEW Dictionary (the synchronizer only sees reassignment).
var net_items: Dictionary = {}:
	set(value):
		net_items = value
		model.from_dict(value)
		weight = model.total_weight()
		changed.emit()


func count(id: String) -> int:
	return model.count(id)


func host_add(id: String, n: int) -> void:
	model.add(id, n)
	net_items = model.to_dict()


# Returns how many were removed.
func host_remove(id: String, n: int) -> int:
	var removed := model.remove(id, n)
	if removed > 0:
		net_items = model.to_dict()
	return removed
