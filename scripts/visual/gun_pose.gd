# GunPose — the hand-made weapon animations (D-123), presentation only, built like ThrowPose: data/weapons/
# weapon_anims.json holds clips (keys [t, offset m, rotation deg about the right-hand grip, left-hand freedom,
# torso twist deg]) and, per weapon ID, which clip is its draw / holster / reload / kick / swing, their seconds and
# where its left hand holds it. clip() parses one once; sample_into() fills a reusable Sample at normalized time t
# (smooth ease between keys). CharacterAnimator layers an action clip (draw, holster, reload, swing) and a kick clip
# on the model's own gun-holding clip and puts both hands on the gun with ArmIK.
# Depends on: DataLoader.
class_name GunPose
extends RefCounted

const PATH := "res://data/weapons/weapon_anims.json"


class Clip:
	extends RefCounted
	var times := PackedFloat32Array()
	var offs := PackedVector3Array()
	var rots := PackedVector3Array()    # degrees: pitch (up), yaw (left), roll
	var lefts := PackedFloat32Array()   # 0 = left hand on the gun .. 1 = free
	var twists := PackedFloat32Array()  # degrees, + = turned left


class Sample:
	extends RefCounted
	var off := Vector3.ZERO
	var rot := Vector3.ZERO   # degrees
	var left := 0.0
	var twist := 0.0          # degrees


static var _data: Dictionary = {}
static var _clips: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = DataLoader.load_json(PATH)
	return _data


# The animation entry for weapon `id` ({} for none: fists, thrown, unknown).
static func weapon(id: String) -> Dictionary:
	return data().get("weapons", {}).get(id, {})


static func clip(id: String) -> Clip:
	if not _clips.has(id):
		var c := Clip.new()
		for k: Array in data().get("clips", {}).get(id, {}).get("keys", []):
			c.times.append(float(k[0]))
			c.offs.append(_v3(k[1]))
			c.rots.append(_v3(k[2]))
			c.lefts.append(float(k[3]))
			c.twists.append(float(k[4]) if k.size() > 4 else 0.0)
		if c.times.is_empty():
			c.times.append(0.0)
			c.offs.append(Vector3.ZERO)
			c.rots.append(Vector3.ZERO)
			c.lefts.append(0.0)
			c.twists.append(0.0)
		_clips[id] = c
	return _clips[id]


static func sample_into(c: Clip, t: float, out: Sample) -> void:
	var n := c.times.size()
	t = clampf(t, c.times[0], c.times[n - 1])
	var i := 0
	while i < n - 2 and t > c.times[i + 1]:
		i += 1
	if n == 1:
		out.off = c.offs[0]
		out.rot = c.rots[0]
		out.left = c.lefts[0]
		out.twist = c.twists[0]
		return
	var u := clampf((t - c.times[i]) / maxf(c.times[i + 1] - c.times[i], 0.0001), 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	out.off = c.offs[i].lerp(c.offs[i + 1], e)
	out.rot = c.rots[i].lerp(c.rots[i + 1], e)
	out.left = lerpf(c.lefts[i], c.lefts[i + 1], e)
	out.twist = lerpf(c.twists[i], c.twists[i + 1], e)


static func _v3(a: Variant) -> Vector3:
	var arr: Array = a
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
