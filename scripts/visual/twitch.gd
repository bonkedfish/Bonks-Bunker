# Twitch — sudden head and arm jerks on top of a zombie's animation (D-114). Presentation only, every peer.
# Every gap_min_s..gap_max_s one of the listed bones snaps a random angle (up to max_degrees) and back over jerk_s.
# Call apply() right after the CharacterAnimator re-sampled the pose (its `advanced` flag), so the jerk never adds up.
# Depends on: MixamoRetarget (bone names without the mixamorig prefix).
class_name Twitch
extends RefCounted

var range_sq := 900.0
var _bones := PackedInt32Array()
var _gap := Vector2(1.0, 3.0)
var _jerk_s := 0.14
var _max := 0.4
var _wait := 0.0
var _left := 0.0
var _bone := -1
var _axis := Vector3.RIGHT
var _angle := 0.0


# A twitch for this skeleton, or null when none of the listed bones are on it.
static func make(skel: Skeleton3D, t: Dictionary) -> Twitch:
	var tw := Twitch.new()
	var names: Array = t.get("bones", [])
	for i in skel.get_bone_count():
		if MixamoRetarget.strip(skel.get_bone_name(i)) in names:
			tw._bones.append(i)
	if tw._bones.is_empty():
		return null
	tw._gap = Vector2(float(t.get("gap_min_s", 1.0)), float(t.get("gap_max_s", 3.0)))
	tw._jerk_s = float(t.get("jerk_s", 0.14))
	tw._max = deg_to_rad(float(t.get("max_degrees", 25.0)))
	tw.range_sq = pow(float(t.get("range_m", 30.0)), 2.0)
	tw._wait = randf_range(tw._gap.x, tw._gap.y)
	return tw


func apply(skel: Skeleton3D, delta: float) -> void:
	_wait -= delta
	if _left <= 0.0 and _wait <= 0.0:
		_wait = randf_range(_gap.x, _gap.y)
		_left = _jerk_s
		_bone = _bones[randi() % _bones.size()]
		_axis = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		if _axis.length_squared() < 0.5:
			_axis = Vector3.RIGHT
		_angle = randf_range(0.45, 1.0) * _max
	if _left <= 0.0 or _bone < 0:
		return
	_left -= delta
	var k := sin(PI * clampf(1.0 - _left / _jerk_s, 0.0, 1.0))  # snap out and back
	skel.set_bone_pose_rotation(_bone, skel.get_bone_pose_rotation(_bone) * Quaternion(_axis, _angle * k))
