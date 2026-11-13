# CompanionBrain — pure decision-making for Bonk (D-031). No nodes, no physics, no rendering.
# Each tick the Bonk node feeds in what he perceives; the brain sets this tick's wishes:
#   FOLLOW  stay within follow_distance of the nearest player (run if beyond catch_up_distance)
#   COMBAT  on first sight of a zombie (after reaction_time): shoot every fire_interval, or bat it
#           if within melee_range; regroup first if the group is beyond catch_up_distance;
#           back to FOLLOW after combat_cooldown seconds without seeing a zombie.
# Static helpers decide when a player is walking into Bonk and where he should sidestep to (D-035).
# Depends on: Bonk's companion definition Dictionary (data/companions/bonk.json).
class_name CompanionBrain
extends RefCounted

enum State { FOLLOW, COMBAT }

var state := State.FOLLOW
# This tick's outputs.
var wants_move := false
var move_fast := false
var wants_fire := false
var wants_melee := false
var combat_started := false

var _def: Dictionary
var _since_enemy := 0.0
var _reaction := 0.0
var _fire_cd := 0.0
var _melee_cd := 0.0


func _init(def: Dictionary) -> void:
	_def = def


func tick(delta: float, enemy_visible: bool, enemy_distance: float, leader_distance: float) -> void:
	wants_move = false
	move_fast = false
	wants_fire = false
	wants_melee = false
	combat_started = false
	_fire_cd = maxf(_fire_cd - delta, 0.0)
	_melee_cd = maxf(_melee_cd - delta, 0.0)
	_since_enemy = 0.0 if enemy_visible else _since_enemy + delta

	if enemy_visible and state == State.FOLLOW:
		state = State.COMBAT
		_reaction = float(_def.reaction_time)
		combat_started = true
	elif state == State.COMBAT and _since_enemy >= float(_def.combat_cooldown):
		state = State.FOLLOW

	var follow := float(_def.follow_distance)
	var catch_up := float(_def.catch_up_distance)
	if state == State.FOLLOW or not enemy_visible:
		wants_move = leader_distance > follow
		move_fast = leader_distance > catch_up
		return
	_reaction -= delta
	if leader_distance > catch_up:
		wants_move = true  # regroup before fighting
		move_fast = true
		return
	if enemy_distance <= float(_def.melee_range):
		if _melee_cd <= 0.0:
			wants_melee = true
			_melee_cd = float(_def.melee_interval)
	elif _reaction <= 0.0 and _fire_cd <= 0.0:
		wants_fire = true
		_fire_cd = float(_def.fire_interval)


# True when a player within trigger_distance is moving at least min_speed roughly toward Bonk
# (horizontal only). offset_to_bonk = bonk position - player position.
static func player_walking_into(offset_to_bonk: Vector3, player_velocity: Vector3, trigger_distance: float, min_speed: float) -> bool:
	var off := Vector2(offset_to_bonk.x, offset_to_bonk.z)
	var vel := Vector2(player_velocity.x, player_velocity.z)
	var dist := off.length()
	var speed := vel.length()
	if dist > trigger_distance or speed < min_speed:
		return false
	if dist < 0.01:
		return true
	return vel.dot(off) / (speed * dist) > 0.5  # within ~60 degrees of straight at him


# Candidate sidestep spots in order of preference: 0 = sideways away from the player's path,
# 1 = the other side, 2 = ahead of the player along their path (backing out of a corridor).
static func dodge_spot(bonk_pos: Vector3, player_pos: Vector3, player_velocity: Vector3, index: int, step: float) -> Vector3:
	var fwd := Vector3(player_velocity.x, 0.0, player_velocity.z).normalized()
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	if side.dot(bonk_pos - player_pos) < 0.0:
		side = -side
	match index:
		0:
			return bonk_pos + side * step
		1:
			return bonk_pos - side * step
		_:
			return bonk_pos + fwd * step * 2.0
