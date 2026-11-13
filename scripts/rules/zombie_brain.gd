# ZombieBrain — pure zombie decision-making (no nodes, no physics, no rendering).
# Each tick the Zombie node feeds in what it perceives; the brain updates state and timers.
#   WANDER      roam near home        -> INVESTIGATE on noise, CHASE on sight
#   INVESTIGATE walk to the noise     -> CHASE on sight, WANDER on arrival
#   CHASE       follow target         -> ATTACK when in range and off cooldown, WANDER after lose_interest_seconds unseen
#   ATTACK      stand, wind up swipe  -> sets attack_landed on the resolving tick, back to CHASE
# Depends on: an enemy definition Dictionary (EnemyDB).
class_name ZombieBrain
extends RefCounted

enum State { WANDER, INVESTIGATE, CHASE, ATTACK }

var state := State.WANDER
var attack_landed := false  # true only on the tick the swipe resolves
var cooldown_mult := 1.0     # < 1 = attacks more often (enraged bosses, D-055)

var _def: Dictionary
var _since_seen := 0.0
var _attack_time := 0.0
var _cooldown := 0.0


func _init(def: Dictionary) -> void:
	_def = def


func reset() -> void:
	state = State.WANDER
	attack_landed = false
	cooldown_mult = 1.0
	_since_seen = 0.0
	_attack_time = 0.0
	_cooldown = 0.0


func tick(delta: float, sees_target: bool, target_distance: float, heard_noise: bool, arrived: bool) -> void:
	attack_landed = false
	_cooldown = maxf(_cooldown - delta, 0.0)
	_since_seen = 0.0 if sees_target else _since_seen + delta
	match state:
		State.ATTACK:
			_attack_time += delta
			if _attack_time >= float(_def.attack_windup):
				attack_landed = true
				_cooldown = float(_def.attack_cooldown) * cooldown_mult
				state = State.CHASE
		State.CHASE:
			if sees_target and target_distance <= float(_def.attack_range) and _cooldown <= 0.0:
				state = State.ATTACK
				_attack_time = 0.0
			elif not sees_target and _since_seen >= float(_def.lose_interest_seconds):
				state = State.WANDER
		State.INVESTIGATE:
			if sees_target:
				state = State.CHASE
			elif arrived and not heard_noise:
				state = State.WANDER
		State.WANDER:
			if sees_target:
				state = State.CHASE
			elif heard_noise:
				state = State.INVESTIGATE
