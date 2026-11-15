# InventoryHolder — a player's inventory (Player child "Inventory").
# Host owns it: host_add/host_remove change the pure Inventory and republish `net_items` (stackable counts) and
# `net_gear` (D-087: rolled weapon / armor instances + what's equipped), which replicate (on change) through the
# player's MultiplayerSynchronizer. Every peer mirrors them and keeps `weight` current, so the owning client
# predicts overweight movement with the same numbers as the host.
# Gear: host_add() of a weapon or armor item id rolls one instance per count (GearRules.roll) instead of stacking,
# so loot, trades, crafting and the starting kit all give rolled gear. Old saves' weapon counts become instances
# (host_upgrade_legacy).
# Depends on: Inventory (pure), CarryRules, GearRules.
class_name InventoryHolder
extends Node

signal changed

var model := Inventory.new()
var weight := 0.0
var _rng := RandomNumberGenerator.new()

# Replicated host -> clients. Always assign a NEW Dictionary (the synchronizer only sees reassignment).
var net_items: Dictionary = {}:
	set(value):
		net_items = value
		model.from_dict(value)
		weight = model.total_weight()
		changed.emit()

var net_gear: Dictionary = {}:
	set(value):
		net_gear = value
		model.gear_from_dict(value)
		weight = model.total_weight()
		changed.emit()


func _ready() -> void:
	_rng.randomize()


func count(id: String) -> int:
	return model.count(id)


func equipped(slot: String) -> Dictionary:
	return model.equipped(slot)


func get_gear(uid: int) -> Dictionary:
	return model.get_gear(uid)


func gear_list() -> Array:
	return model.gear


func host_add(id: String, n: int) -> void:
	if GearRules.is_gear(id):
		for i in n:
			model.add_gear(GearRules.roll(id, _rng))
		net_gear = model.gear_to_dict()
		return
	model.add(id, n)
	net_items = model.to_dict()


# Returns how many were removed.
func host_remove(id: String, n: int) -> int:
	var removed := model.remove(id, n)
	if removed > 0:
		net_items = model.to_dict()
	return removed


# --- gear (host) ---------------------------------------------------------------------------

func host_add_gear(inst: Dictionary) -> int:
	var uid := model.add_gear(inst)
	net_gear = model.gear_to_dict()
	return uid


func host_remove_gear(uid: int) -> Dictionary:
	var g := model.remove_gear(uid)
	if not g.is_empty():
		net_gear = model.gear_to_dict()
	return g


# Several instance updates (condition, magazine, mods) in one publish: {uid: inst}.
func host_set_gears(changes: Dictionary) -> void:
	if changes.is_empty():
		return
	for uid: int in changes:
		model.set_gear(uid, changes[uid])
	net_gear = model.gear_to_dict()


func host_equip(uid: int, slot: String) -> bool:
	if not model.equip_gear(uid, slot):
		return false
	net_gear = model.gear_to_dict()
	return true


func host_unequip(slot: String) -> void:
	model.unequip(slot)
	net_gear = model.gear_to_dict()


# --- requests (owning peer -> host) ----------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func request_equip(uid: int, slot: String) -> void:
	if not _from_owner():
		return
	var weapons: Node = get_parent().get_node_or_null("Weapons")
	if weapons:
		weapons.host_flush()  # magazines / wear into the instances before they move
	host_equip(uid, slot)


@rpc("any_peer", "call_local", "reliable")
func request_unequip(slot: String) -> void:
	if not _from_owner() or not slot in GearRules.SLOTS:
		return
	var weapons: Node = get_parent().get_node_or_null("Weapons")
	if weapons:
		weapons.host_flush()
	host_unequip(slot)


func _from_owner() -> bool:
	if not multiplayer.is_server():
		return false
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	var p := get_parent()
	return p != null and "peer_id" in p and int(p.peer_id) == sender and not p.health.is_dead()


# Old saves (before D-087) kept weapons as stack counts: roll them into instances.
func host_upgrade_legacy() -> void:
	var moved := false
	for id: String in model.items.keys():
		if GearRules.is_gear(id):
			var n := model.remove(id, model.count(id))
			for i in n:
				model.add_gear(GearRules.roll(id, _rng))
			moved = true
	if moved:
		net_items = model.to_dict()
		net_gear = model.gear_to_dict()
