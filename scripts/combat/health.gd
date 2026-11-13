# Health — hit points for anything that can be damaged. Only the host changes it;
# `current` replicates to clients through the owner's MultiplayerSynchronizer ("Health:current").
class_name Health
extends Node

signal died(attacker_peer: int)
signal damaged(amount: float, attacker_peer: int)

@export var max_health := 100.0
var current := 100.0
var damage_mult := 1.0  # host: damage-taken multiplier (player effects, D-052)


func is_dead() -> bool:
	return current <= 0.0


func reset() -> void:
	current = max_health


# Host only. Returns true if this hit killed.
func apply_damage(amount: float, attacker_peer: int) -> bool:
	if current <= 0.0 or amount <= 0.0:
		return false
	amount *= damage_mult
	current = maxf(current - amount, 0.0)
	damaged.emit(amount, attacker_peer)
	if current <= 0.0:
		died.emit(attacker_peer)
		return true
	return false
