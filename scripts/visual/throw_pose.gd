# ThrowPose — the hand-made disc throw animations (D-117), presentation only: each throw style's "anim" in
# data/discgolf/throw_styles.json is a list of keys [t, hand offset, elbow pole, torso twist, lean, disc rotation].
# clip(style_id) parses one once; sample_into() fills a reusable Sample at normalized time t (0 address ..
# reach = full reach-back .. release = the disc leaves the hand .. 1 recovered): the hand moves on a Catmull-Rom
# curve through its keys (so the swing has no corners) and also gives its direction of travel, the rest eases
# between keys. Offsets are in the thrower's body frame (x right, y up, z back), the hand in arm lengths from the
# throwing shoulder. ArmIK puts the skeleton there. Depends on: DiscFlightRules (styles).
class_name ThrowPose
extends RefCounted


class Clip:
	extends RefCounted
	var seconds := 1.0
	var reach := 0.3
	var release := 0.55
	var disc_lead := -1.0
	var times := PackedFloat32Array()
	var hands := PackedVector3Array()
	var poles := PackedVector3Array()
	var twists := PackedFloat32Array()   # degrees
	var leans := PackedFloat32Array()    # degrees
	var discs := PackedVector3Array()    # degrees: pitch, yaw, roll


class Sample:
	extends RefCounted
	var hand := Vector3.ZERO
	var travel := Vector3.ZERO  # direction the hand is moving (zero when it's still)
	var pole := Vector3.UP
	var twist := 0.0            # radians, + = turned left
	var lean := 0.0             # radians, + = bent forward
	var disc := Basis()         # the disc's rotation in the body frame


static var _clips: Dictionary = {}


static func clip(style_id: String) -> Clip:
	if not _clips.has(style_id):
		var anim: Dictionary = DiscFlightRules.style(style_id).get("anim", {})
		var c := Clip.new()
		c.seconds = maxf(float(anim.get("seconds", 1.0)), 0.1)
		c.reach = float(anim.get("reach", 0.3))
		c.release = float(anim.get("release", 0.55))
		c.disc_lead = float(anim.get("disc_lead", -1.0))
		for k: Array in anim.get("keys", []):
			c.times.append(float(k[0]))
			c.hands.append(_v3(k[1]))
			c.poles.append(_v3(k[2]))
			c.twists.append(float(k[3]))
			c.leans.append(float(k[4]))
			c.discs.append(_v3(k[5]))
		if c.times.is_empty():
			c.times.append(0.0)
			c.hands.append(Vector3(0.0, -0.5, -0.5))
			c.poles.append(Vector3.DOWN)
			c.twists.append(0.0)
			c.leans.append(0.0)
			c.discs.append(Vector3.ZERO)
		_clips[style_id] = c
	return _clips[style_id]


static func sample_into(c: Clip, t: float, out: Sample) -> void:
	var n := c.times.size()
	t = clampf(t, c.times[0], c.times[n - 1])
	var i := 0
	while i < n - 2 and t > c.times[i + 1]:
		i += 1
	if n == 1:
		out.hand = c.hands[0]
		out.travel = Vector3.ZERO
		out.pole = c.poles[0]
		out.twist = deg_to_rad(c.twists[0])
		out.lean = deg_to_rad(c.leans[0])
		out.disc = Basis.from_euler(c.discs[0] * (PI / 180.0))
		return
	var t0 := c.times[i]
	var t1 := c.times[i + 1]
	var u := clampf((t - t0) / maxf(t1 - t0, 0.0001), 0.0, 1.0)
	var p0 := c.hands[maxi(i - 1, 0)]
	var p1 := c.hands[i]
	var p2 := c.hands[i + 1]
	var p3 := c.hands[mini(i + 2, n - 1)]
	out.hand = _catmull(p0, p1, p2, p3, u)
	out.travel = _catmull_d(p0, p1, p2, p3, u) / maxf(t1 - t0, 0.0001)
	var e := u * u * (3.0 - 2.0 * u)  # ease in and out between keys
	out.pole = c.poles[i].lerp(c.poles[i + 1], e)
	out.twist = deg_to_rad(lerpf(c.twists[i], c.twists[i + 1], e))
	out.lean = deg_to_rad(lerpf(c.leans[i], c.leans[i + 1], e))
	out.disc = Basis.from_euler(c.discs[i].lerp(c.discs[i + 1], e) * (PI / 180.0))


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	var u2 := u * u
	return 0.5 * (2.0 * p1 + (p2 - p0) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * u2 * u)


static func _catmull_d(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	return 0.5 * ((p2 - p0) + 2.0 * (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u + 3.0 * (3.0 * p1 - p0 - 3.0 * p2 + p3) * u * u)


static func _v3(a: Variant) -> Vector3:
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
