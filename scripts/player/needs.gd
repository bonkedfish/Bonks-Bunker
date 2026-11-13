# PlayerNeeds — hunger and thirst for one player (D-046), Player child "Needs".
# Host owns them: host_tick() drains both, and an empty meter slowly hurts (can down the player). `net_hunger` /
# `net_thirst` replicate through the player's synchronizer so the owning client predicts "no sprint when low" with
# the host's numbers and the HUD shows them. Starving damage uses attacker -1. Math in SurvivalRules. Depends on: SurvivalRules, Health (sibling).
class_name PlayerNeeds
extends Node

var net_hunger := 100.0
var net_thirst := 100.0
var drain_mult := Vector2.ONE  # host: set by ActiveEffects (D-052)

var _t: Dictionary
var _damage_carry := 0.0

@onready var health: Health = $"../Health"


func _ready() -> void:
	_t = SurvivalRules.tuning()
	host_reset()


func value() -> Vector2:
	return Vector2(net_hunger, net_thirst)


func host_set(v: Vector2) -> void:
	net_hunger = v.x
	net_thirst = v.y


func host_reset() -> void:
	var m := float(_t.get("max_need", 100.0))
	host_set(Vector2(m, m))


# After a respawn: meters come back to at least respawn_need_floor.
func host_respawned() -> void:
	var f := float(_t.get("respawn_need_floor", 50.0))
	host_set(Vector2(maxf(net_hunger, f), maxf(net_thirst, f)))


func host_tick(delta: float, alive: bool) -> void:
	if _t.is_empty() or not alive:
		return
	host_set(SurvivalRules.drain(value(), delta, _t, drain_mult))
	_damage_carry += SurvivalRules.starving_damage(value(), _t) * delta
	if _damage_carry >= 1.0:
		var whole := floorf(_damage_carry)
		_damage_carry -= whole
		health.apply_damage(whole, -1)  # -1 = hunger/thirst (ItemUse ignores it)


func can_sprint() -> bool:
	return _t.is_empty() or SurvivalRules.can_sprint(value(), _t)


func is_low() -> bool:
	return not _t.is_empty() and SurvivalRules.is_low(value(), _t)
