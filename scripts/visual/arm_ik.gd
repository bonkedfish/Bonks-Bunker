# ArmIK — puts a character's skeleton into a ThrowPose sample (D-117), presentation only, rig-agnostic: on top of
# whatever clip was just sampled it turns the spine (twist about the body's up axis, lean about its right axis,
# spread over the rig's spine bones), then solves a two-bone IK for the throwing arm (upper arm + forearm) so the
# hand tip reaches the target, the elbow bending toward the pole. Rigs come from "throw_rigs" in
# data/art/character_models.json (the first whose bones all exist): {spine [bones], upper, lower, end (the bone the
# hand tip hangs off), tip [x, y, z] in that bone's space}. Work in skeleton space; `node_to_skel` maps the
# character node's frame (x right, y up, -z forward) into it. Call right after the AnimationPlayer has advanced.
# Depends on: Skeleton3D only.
class_name ArmIK
extends RefCounted

var spine := PackedInt32Array()
var upper := -1
var lower := -1
var end := -1
var tip := Vector3.ZERO
var valid := false


static func find(skel: Skeleton3D, rigs: Array) -> ArmIK:
	var ik := ArmIK.new()
	if skel == null:
		return ik
	for r: Dictionary in rigs:
		var ids := PackedInt32Array()
		var ok := true
		for b: Variant in r.get("spine", []):
			var i := skel.find_bone(str(b))
			ok = ok and i >= 0
			ids.append(i)
		var u := skel.find_bone(str(r.get("upper", "")))
		var l := skel.find_bone(str(r.get("lower", "")))
		var e := skel.find_bone(str(r.get("end", "")))
		if ok and u >= 0 and l >= 0 and e >= 0:
			ik.spine = ids
			ik.upper = u
			ik.lower = l
			ik.end = e
			var t: Array = r.get("tip", [0, 0, 0])
			ik.tip = Vector3(t[0], t[1], t[2])
			ik.valid = true
			return ik
	return ik


# Shoulder (upper arm root) and hand tip, skeleton space.
func shoulder(skel: Skeleton3D) -> Vector3:
	return skel.get_bone_global_pose(upper).origin


func hand_tip(skel: Skeleton3D) -> Vector3:
	return skel.get_bone_global_pose(end) * tip


func arm_length(skel: Skeleton3D) -> float:
	var s := shoulder(skel)
	var e := skel.get_bone_global_pose(lower).origin
	return s.distance_to(e) + e.distance_to(hand_tip(skel))


# Twist (+ = turn left about up) and lean (+ = forward) the torso, in radians.
func bend(skel: Skeleton3D, node_to_skel: Basis, twist: float, lean: float) -> void:
	if spine.is_empty():
		return
	var up := (node_to_skel * Vector3.UP).normalized()
	var right := (node_to_skel * Vector3.RIGHT).normalized()
	var n := float(spine.size())
	var r := Basis(up, twist / n) * Basis(right, -lean / n)
	for b in spine:
		_rotate_global(skel, b, r)


# Reach the hand tip to `target` (skeleton space), elbow bending toward `pole` (a skeleton-space direction).
func reach(skel: Skeleton3D, target: Vector3, pole: Vector3) -> void:
	var s := shoulder(skel)
	var e := skel.get_bone_global_pose(lower).origin
	var h := hand_tip(skel)
	var a := s.distance_to(e)
	var b := e.distance_to(h)
	if a < 0.0001 or b < 0.0001:
		return
	var to := target - s
	var d := clampf(to.length(), absf(a - b) + 0.001, a + b - 0.001)
	var u := to.normalized() if to.length() > 0.0001 else (h - s).normalized()
	var cos_a := clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var v := pole - u * pole.dot(u)
	if v.length() < 0.0001:
		v = u.cross(Vector3.RIGHT if absf(u.x) < 0.9 else Vector3.FORWARD)
	v = v.normalized()
	var elbow := s + a * (cos_a * u + sqrt(1.0 - cos_a * cos_a) * v)
	_rotate_global(skel, upper, _arc(e - s, elbow - s))
	e = skel.get_bone_global_pose(lower).origin
	h = hand_tip(skel)
	_rotate_global(skel, lower, _arc(h - e, s + u * d - e))


# Turns bone b about its own origin by r (skeleton space), keeping its parent where it is.
static func _rotate_global(skel: Skeleton3D, b: int, r: Basis) -> void:
	var parent := skel.get_bone_parent(b)
	var pg := skel.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
	var local := skel.get_bone_pose_rotation(b)
	var nb := pg.inverse() * r * pg * Basis(local)
	skel.set_bone_pose_rotation(b, nb.orthonormalized().get_rotation_quaternion())


static func _arc(from: Vector3, to: Vector3) -> Basis:
	if from.length() < 0.00001 or to.length() < 0.00001:
		return Basis()
	var f := from.normalized()
	var t := to.normalized()
	if f.dot(t) > 0.99999:
		return Basis()
	if f.dot(t) < -0.99999:
		var axis := f.cross(Vector3.UP if absf(f.y) < 0.9 else Vector3.RIGHT).normalized()
		return Basis(axis, PI)
	return Basis(Quaternion(f, t))
