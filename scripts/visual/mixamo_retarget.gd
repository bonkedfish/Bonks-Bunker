# MixamoRetarget — turns a folder of Mixamo animation FBXs into one AnimationLibrary for one Mixamo character
# (D-112). Mixamo exports every clip as its own file whose single animation is always called "mixamo.com", keyed to
# the skeleton of whichever character was selected at download time - so the bone prefix (mixamorig_, mixamorig1_,
# ...) and the node path to the skeleton can both differ from the model it is played on.
# Retargeting rule (the usual humanoid one): every bone's ROTATION is copied by bone name with that prefix stripped;
# the only POSITION kept is the hips', scaled by the two skeletons' hip heights so a big body doesn't sink into the
# ground on a small one's walk (other position and all scale tracks are dropped: they'd stretch a body with
# different proportions). Clips listed in in_place lose the hips' horizontal travel - the game moves the body, not
# the clip - in case "In Place" wasn't ticked when downloading. Each clip is renamed to its key ("walk", "scream").
# Tracks are re-sampled at 30 fps through the *_track_interpolate calls, so compressed imports work too.
# Cached: raw clips per file, finished libraries per model id. Presentation only; never affects gameplay.
# Depends on: nothing.
class_name MixamoRetarget
extends RefCounted

const FPS := 30.0

static var _raw: Dictionary = {}  # file path -> [Animation, source hips rest height] ([] when unusable)
static var _libs: Dictionary = {}  # model id -> AnimationLibrary
static var _prefix: RegEx


# The library for model `model_id`, whose skeleton is `skeleton` and whose AnimationPlayer will sit at `root`.
# anim_set: {dir, files: {key: file}, in_place: [keys], loop: [keys]}; override: {key: file} for this model only.
static func library(model_id: String, root: Node, skeleton: Skeleton3D, anim_set: Dictionary,
		override := {}) -> AnimationLibrary:
	if _libs.has(model_id):
		return _libs[model_id]
	var lib := AnimationLibrary.new()
	var skel_path := String(root.get_path_to(skeleton))
	var bones := {}  # stripped name -> this skeleton's real bone name
	for i in skeleton.get_bone_count():
		bones[strip(skeleton.get_bone_name(i))] = skeleton.get_bone_name(i)
	var hips := skeleton.find_bone(str(bones.get("Hips", "")))
	var target_hips := skeleton.get_bone_rest(hips).origin.y if hips >= 0 else 0.0
	var files: Dictionary = (anim_set.get("files", {}) as Dictionary).duplicate()
	files.merge(override, true)
	var in_place: Array = anim_set.get("in_place", [])
	var loop: Array = anim_set.get("loop", [])
	for key: String in files:
		var raw := _load(str(anim_set.get("dir", "")) + "/" + str(files[key]))
		if raw.is_empty():
			continue
		var src_hips := float(raw[1])
		var ratio := target_hips / src_hips if src_hips > 0.001 and target_hips > 0.001 else 1.0
		var anim := _retarget(raw[0], skel_path, bones, ratio, in_place.has(key))
		anim.loop_mode = Animation.LOOP_LINEAR if loop.has(key) else Animation.LOOP_NONE
		lib.add_animation(key, anim)
	_libs[model_id] = lib
	return lib


# "mixamorig1_LeftArm" / "mixamorig:LeftArm" -> "LeftArm".
static func strip(bone: String) -> String:
	if _prefix == null:
		_prefix = RegEx.create_from_string("^.*?mixamorig\\d*[:_]")
	return _prefix.sub(bone, "")


# The first real clip in an animation FBX, plus the hips' rest height on the skeleton it was made for.
static func _load(path: String) -> Array:
	if _raw.has(path):
		return _raw[path]
	_raw[path] = []
	if not ResourceLoader.exists(path):
		push_warning("MixamoRetarget: missing %s" % path)
		return []
	var scene := load(path) as PackedScene
	if scene == null:
		return []
	var inst := scene.instantiate()
	var anim: Animation = null
	for ap: Node in inst.find_children("*", "AnimationPlayer", true, false):
		for n: StringName in (ap as AnimationPlayer).get_animation_list():
			if n != &"RESET":
				anim = (ap as AnimationPlayer).get_animation(n)
				break
		if anim:
			break
	var hips_y := 0.0
	var skels := inst.find_children("*", "Skeleton3D", true, false)
	if skels.size() > 0:
		var sk := skels[0] as Skeleton3D
		for i in sk.get_bone_count():
			if strip(sk.get_bone_name(i)) == "Hips":
				hips_y = sk.get_bone_rest(i).origin.y
				break
	inst.free()
	if anim:
		_raw[path] = [anim, hips_y]
	return _raw[path]


static func _retarget(src: Animation, skel_path: String, bones: Dictionary, hip_ratio: float,
		in_place: bool) -> Animation:
	var out := Animation.new()
	out.length = src.length
	var steps := maxi(int(ceil(src.length * FPS)), 1)
	for t in src.get_track_count():
		var path := src.track_get_path(t)
		if path.get_subname_count() == 0:
			continue  # not a bone track
		var bone := strip(String(path.get_concatenated_subnames()))
		if not bones.has(bone):
			continue
		var type := src.track_get_type(t)
		var hips_pos := bone == "Hips" and type == Animation.TYPE_POSITION_3D
		if type != Animation.TYPE_ROTATION_3D and not hips_pos:
			continue
		var nt := out.add_track(type)
		out.track_set_path(nt, NodePath("%s:%s" % [skel_path, bones[bone]]))
		out.track_set_interpolation_type(nt, Animation.INTERPOLATION_LINEAR)
		var start := Vector3.ZERO
		for k in steps + 1:
			var time := minf(k / FPS, src.length)
			if hips_pos:
				var p := src.position_track_interpolate(t, time) * hip_ratio
				if k == 0:
					start = p
				if in_place:
					p = Vector3(start.x, p.y, start.z)
				out.position_track_insert_key(nt, time, p)
			else:
				out.rotation_track_insert_key(nt, time, src.rotation_track_interpolate(t, time))
	return out
