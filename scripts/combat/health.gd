# Health — hit points for anything that can be damaged. Only the host changes it;
# `current` replicates to clients through the owner's MultiplayerSynchronizer ("Health:current").
# Armor (D-087): `resist` (0-1, set by the player from equipped armor) blocks that share of each hit after
# damage_mult; armor_blocked reports the blocked amount so the armor can wear.
# Feigning (D-114): with down_once set, the first lethal hit leaves 1 HP and emits `downed` instead of `died`
# (the zombie lies there, then gets up); the next lethal hit is a real death.
class_name Health
extends Node

signal died(attacker_peer: int)
signal damaged(amount: float, attacker_peer: int)
signal armor_blocked(amount: float)
signal downed

@export var max_health := 100.0
var current := 100.0
var damage_mult := 1.0  # host: damage-taken multiplier (player effects, D-052)
var invulnerable := false  # host: takes no damage (ace replay, D-076)
var resist := 0.0  # host: share of damage blocked by armor (D-087)
var down_once := false  # host: the next lethal hit downs instead of kills (D-114)


func is_dead() -> bool:
	return current <= 0.0


func reset() -> void:
	current = max_health


# Host only. Returns true if this hit killed.
func apply_damage(amount: float, attacker_peer: int) -> bool:
	if current <= 0.0 or amount <= 0.0 or invulnerable:
		return false
	amount *= damage_mult
	if resist > 0.0:
		var blocked := amount * clampf(resist, 0.0, 0.95)
		amount -= blocked
		armor_blocked.emit(blocked)
	if down_once and current - amount <= 0.0:
		down_once = false
		current = 1.0
		damaged.emit(amount, attacker_peer)
		downed.emit()
		return false
	current = maxf(current - amount, 0.0)
	damaged.emit(amount, attacker_peer)
	if current <= 0.0:
		died.emit(attacker_peer)
		return true
	return false
