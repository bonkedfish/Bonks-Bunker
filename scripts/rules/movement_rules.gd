# MovementRules — pure player movement math. No nodes, no rendering.
# Used by player.gd on the host (authoritative) and on the owning client (prediction),
# so both sides run identical rules. Tuning comes from data/tuning/player_movement.json.
# Water (D-047): depth = metres of water above the feet; wading slows, swimming floats with the head above water.
class_name MovementRules
extends RefCounted

const SCHEMA := {
	"walk_speed": TYPE_FLOAT,
	"sprint_speed": TYPE_FLOAT,
	"crouch_speed": TYPE_FLOAT,
	"jump_velocity": TYPE_FLOAT,
	"ground_accel": TYPE_FLOAT,
	"air_accel": TYPE_FLOAT,
	"stand_height": TYPE_FLOAT,
	"crouch_height": TYPE_FLOAT,
	"eye_offset": TYPE_FLOAT,
	"mouse_sensitivity": TYPE_FLOAT,
	"wade_depth": TYPE_FLOAT,
	"swim_depth": TYPE_FLOAT,
	"swim_float_depth": TYPE_FLOAT,
	"wade_speed_mult": TYPE_FLOAT,
	"swim_speed_mult": TYPE_FLOAT,
	"swim_vertical_speed": TYPE_FLOAT,
	"swim_buoyancy": TYPE_FLOAT,
}

enum Water { DRY, WADE, SWIM }


# World-space direction the player wants to move. move: x = strafe, y = forward(-)/back(+).
static func wish_direction(move: Vector2, yaw: float) -> Vector3:
	if move.length_squared() > 1.0:
		move = move.normalized()
	return Vector3(move.x, 0.0, move.y).rotated(Vector3.UP, yaw)


# speed_multiplier: carry-weight slowdown from CarryRules (1.0 = not overweight).
static func step_velocity(velocity: Vector3, wish_dir: Vector3, sprint: bool, crouched: bool,
		jump: bool, on_floor: bool, gravity: float, t: Dictionary, delta: float,
		speed_multiplier: float = 1.0) -> Vector3:
	var speed: float = t.walk_speed
	if crouched:
		speed = t.crouch_speed
	elif sprint:
		speed = t.sprint_speed
	speed *= speed_multiplier
	var accel: float = t.ground_accel if on_floor else t.air_accel
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).lerp(wish_dir * speed, clampf(accel * delta, 0.0, 1.0))
	var vertical := velocity.y
	if on_floor:
		vertical = t.jump_velocity if (jump and not crouched) else 0.0
	else:
		vertical -= gravity * delta
	return Vector3(horizontal.x, vertical, horizontal.z)


static func water_mode(depth: float, t: Dictionary) -> Water:
	if depth > float(t.swim_depth):
		return Water.SWIM
	return Water.WADE if depth > float(t.wade_depth) else Water.DRY


# Swimming: slow horizontal moves, buoyancy pulls the feet to swim_float_depth below the surface;
# rise (jump) swims up while below that, dive (crouch) swims down.
static func swim_velocity(velocity: Vector3, wish_dir: Vector3, rise: bool, dive: bool, depth: float,
		t: Dictionary, delta: float) -> Vector3:
	var speed: float = float(t.walk_speed) * float(t.swim_speed_mult)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).lerp(wish_dir * speed, clampf(float(t.ground_accel) * 0.5 * delta, 0.0, 1.0))
	var float_depth := float(t.swim_float_depth)
	var target_y := (depth - float_depth) * float(t.swim_buoyancy)
	if dive:
		target_y = -float(t.swim_vertical_speed)
	elif rise and depth > float_depth:
		target_y = float(t.swim_vertical_speed)
	var vertical := lerpf(velocity.y, target_y, clampf(3.0 * delta, 0.0, 1.0))
	return Vector3(horizontal.x, vertical, horizontal.z)
