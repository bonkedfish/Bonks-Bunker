# CharacterAnimator — presentation only (D-045): instances a rigged character model from
# data/art/character_models.json by string ID, scales it to height_m, turns it to face -Z, and picks its
# animation each frame from what every peer already knows: horizontal speed (measured from position change, so
# host and interpolated clients look the same), attacking, dead/downed, armed (gun clips), crouched, and a health
# drop (hit react). Walk/run clips are sped up/slowed to match the speed so feet don't slide. Far from the camera
# the animation is advanced at far_animation_hz instead of every frame.
# Survivor models carry every weapon as a separate mesh: set_weapon_slot() shows only the one in weapons_by_slot;
# set_weapon_mesh() (players, D-087) shows any of them by its mesh name.
# First-person mode (set_model(id, true)): model placed at fp_offset under the camera, no shadows, and the bones
# in fp_hide_bones (head, legs) shrunk to nothing every frame so only arms + weapon are seen.
# Universal-rig models (D-058, Quaternius base characters): "path" (full res path), "anim_source" (a .glb whose
# AnimationPlayer library is shared onto the model), "outfit" (skin/shirt/pants/shoes colours through
# shaders/outfit.gdshader), "hair" (+ "hair_color") skinned onto the body's skeleton, "props" (weapon meshes copied
# from another model onto a hand bone, named for weapons_by_slot) and "fp_model" (model used for first-person arms).
# "gear" (D-061): primitive meshes built in code and fixed to bones (masks, pads, spikes): {shape: box | cylinder |
# cone | sphere, size [x,y,z] (cylinder/cone: [radius, height, -]), color [r,g,b], metal, bone, pos, rot_deg}.
# Disc throws (D-117, was clips in D-082): hand-made in code - start_throw(style, disc) plays that style's swing
# (ThrowPose keys: reach-back, pull-through, release, follow-through) on top of the idle clip with ArmIK (torso
# twist / lean + two-bone arm IK, rig from "throw_rigs"), the realistic disc (DiscMesh) in the hand until the
# release; pose_throw() holds a point of the swing (first person, while charging). Every peer runs it for remote
# players; the local player's first-person arms run it through DiscThrower. Hands are otherwise empty.
# Mixamo models (D-112): "anim_set" names an entry in the top-level "anim_sets" (a folder of Mixamo animation FBXs,
# one clip per file) and "anim_override" swaps single clips for this model; MixamoRetarget puts them all on the
# model's own skeleton and names each clip by its key, so "clips" is filled in automatically. "fallback" names
# another model to use when this one's file isn't there - Mixamo files are kept out of the public repo, so a fresh
# clone falls back to the CC0 models instead of failing to load.
# Scare looks (D-114): clip_remap swaps one clip key for another on this instance (a stumbler's walk is "stumble",
# a crawler crawls for everything), hide_bones() shrinks bones to nothing (a crawler's legs), `advanced` says the
# pose was re-sampled this frame (so Twitch can jerk bones on top of it), skeleton() / clip_length() for callers.
# Never affects gameplay. Depends on: DataLoader, MixamoRetarget, shaders/outfit.gdshader, ThrowPose, ArmIK, DiscMesh.
class_name CharacterAnimator
extends Node3D

const DATA_PATH := "res://data/art/character_models.json"
const LOOPING := ["idle", "walk", "run", "idle_gun", "walk_gun", "run_gun", "crouch"]

const OUTFIT_SHADER := preload("res://shaders/outfit.gdshader")
const DiscMesh := preload("res://scripts/discgolf/disc_mesh.gd")
const GRIP_M := 0.085  # disc centre from the fingertips (they hold the rim)

static var _data: Dictionary = {}
static var _anim_libs: Dictionary = {}  # anim_source path -> AnimationLibrary
static var _gear_mats: Dictionary = {}  # "r,g,b,metal" -> shared StandardMaterial3D
static var _gear_meshes: Dictionary = {}  # shape + size -> shared PrimitiveMesh

var _def: Dictionary = {}
var _model_id := ""
var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _hidden_bones: PackedInt32Array = []
var _props: Array[MeshInstance3D] = []  # non-skinned meshes (weapons)
var _current := ""
var _last_pos := Vector3.INF
var _speed := 0.0
var _last_health := INF
var _hit_left := 0.0
var _oneshot_key := ""
var _oneshot_left := 0.0
var _accum := 0.0
var _blend := 0.2
var riding := false  # standing on the Meepo: idle pose instead of walk/run (D-057)
var on_bike := false  # sitting on a motorcycle: the "ride" clip, no weapon in hand (D-083)
var _first_person := false
var _model: Node3D  # the loaded model (first person: hidden while a disc is in hand - only the disc swings, D-120)
var _ik: ArmIK            # throwing-arm rig (D-117), found on first use
var _throw_style := ""    # "" = not throwing
var _throw_clip: ThrowPose.Clip
var _throw_t := 0.0       # 0..1 through the swing
var _throw_hold := false  # pose_throw: stay at _throw_t
var _released := false
var _sample := ThrowPose.Sample.new()
var _disc_node: MeshInstance3D  # the disc in the throwing hand
var _disc_id := ""
var _disc_dir := Vector3.FORWARD
var throw_ik_error := 0.0  # m: how far the hand tip ended up from the swing's target last pose (tests)
var _far_m := 35.0
var _far_period := 0.1
var clip_remap: Dictionary = {}  # clip key -> clip key played instead (D-114)
var advanced := false  # the animation was advanced during the last update()


# Loads model `id` (replacing any previous one). Returns false if the ID or file is missing.
# extra: keys that replace the model's own (a player's look from AppearanceRules.dress, D-096).
func set_model(id: String, first_person := false, extra := {}) -> bool:
	if _data.is_empty():
		_data = DataLoader.load_json(DATA_PATH)
	var models: Dictionary = _data.get("models", {})
	if not models.has(id):
		push_error("CharacterAnimator: unknown model '%s'" % id)
		return false
	var hops := 0
	while models[id].has("fallback") and models[id].has("path") and not ResourceLoader.exists(str(models[id].path)) \
			and models.has(str(models[id].fallback)) and hops < 4:
		id = str(models[id].fallback)  # the file isn't on this machine (Mixamo is kept out of the repo)
		hops += 1
	_model_id = id
	_def = models[id]
	if not extra.is_empty():
		_def = _def.duplicate()
		_def.merge(extra, true)
	_blend = float(_data.get("blend_seconds", 0.2))
	_far_m = float(_data.get("far_animation_m", 35.0))
	_far_period = 1.0 / maxf(float(_data.get("far_animation_hz", 10.0)), 1.0)
	for c in get_children():
		c.queue_free()
	_disc_node = null
	_ik = null
	_throw_style = ""
	_first_person = first_person
	var scene := load(str(_def.path) if _def.has("path") else "%s/%s" % [_data.kit_dir, _def.gltf]) as PackedScene
	if scene == null:
		push_error("CharacterAnimator: can't load %s" % _def.gltf)
		return false
	var model := scene.instantiate() as Node3D
	add_child(model)
	_model = model
	_dress(model)
	model.rotation.y = deg_to_rad(float(_def.get("yaw_offset_deg", 0.0)))
	var aabb := _bounds(model)
	if aabb.size.y > 0.01:
		model.scale = Vector3.ONE * (float(_def.height_m) / aabb.size.y)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	_player = players[0] as AnimationPlayer if players.size() > 0 else null
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	_skeleton = skeletons[0] as Skeleton3D if skeletons.size() > 0 else null
	_props.clear()
	for n: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.skin == null and _def.has("weapons_by_slot") and not mi.has_meta("gear"):
			_props.append(mi)
			mi.visible = false
		if first_person:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hidden_bones.clear()
	if first_person:
		var off: Array = _data.get("fp_offset", [0.0, -1.6, 0.1])
		model.position = Vector3(off[0], off[1], off[2])
		if _skeleton:
			for bone_name: String in _data.get("fp_hide_bones", []):
				var i := _skeleton.find_bone(bone_name)
				if i >= 0:
					_hidden_bones.append(i)
	if _player:
		_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for key: String in LOOPING:
			var clip := str(_def.clips.get(key, ""))
			if _player.has_animation(clip):
				_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		_current = ""
		_play("idle", 1.0, false)
	_last_pos = Vector3.INF
	return true


# Model definition by ID (empty if unknown).
static func model_def(id: String) -> Dictionary:
	if _data.is_empty():
		_data = DataLoader.load_json(DATA_PATH)
	return _data.get("models", {}).get(id, {})


# Universal-rig extras: shared animation library, outfit colours, hair, hand-held weapon props.
func _dress(model: Node3D) -> void:
	var skels := model.find_children("*", "Skeleton3D", true, false)
	var skel: Skeleton3D = skels[0] if skels.size() > 0 else null
	if _def.has("anim_set") and skel:
		for old: Node in model.find_children("*", "AnimationPlayer", true, false):
			old.get_parent().remove_child(old)  # the FBX's own (T-pose) player: ours replaces it
			old.free()
		var anim_set: Dictionary = _data.get("anim_sets", {}).get(str(_def.anim_set), {})
		var lib := MixamoRetarget.library(_model_id, model, skel, anim_set, _def.get("anim_override", {}))
		var mx := AnimationPlayer.new()
		mx.name = "AnimationPlayer"
		model.add_child(mx)
		mx.root_node = NodePath("..")
		mx.add_animation_library("", lib)
		var clips := {}
		for k: StringName in lib.get_animation_list():
			clips[str(k)] = str(k)
		_def = _def.duplicate()
		_def.clips = clips
	if _def.has("anim_source"):
		var src := str(_def.anim_source)
		if not _anim_libs.has(src):
			var inst := (load(src) as PackedScene).instantiate()
			var aps := inst.find_children("*", "AnimationPlayer", true, false)
			if aps.size() > 0:
				_anim_libs[src] = (aps[0] as AnimationPlayer).get_animation_library("")
			inst.free()
		if _anim_libs.has(src):
			var ap := AnimationPlayer.new()
			ap.name = "AnimationPlayer"
			model.add_child(ap)
			ap.root_node = NodePath("..")
			ap.add_animation_library("", _anim_libs[src])
	if _def.has("outfit"):
		var o: Dictionary = _def.outfit
		for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null or not str(mi.name).begins_with(str(o.get("body_mesh", "Super"))):
				continue
			var src_mat := mi.mesh.surface_get_material(0) as BaseMaterial3D
			var m := ShaderMaterial.new()
			m.shader = OUTFIT_SHADER
			if src_mat:
				m.set_shader_parameter("albedo_tex", src_mat.albedo_texture)
				m.set_shader_parameter("normal_tex", src_mat.normal_texture)
			for k: String in ["skin", "shirt", "pants", "shoes"]:
				if o.has(k):
					var c: Array = o[k]
					m.set_shader_parameter(k + "_color", Color(c[0], c[1], c[2]))
			mi.material_override = m
	var hairs: Array = _def.hair if typeof(_def.get("hair")) == TYPE_ARRAY else ([_def.hair] if _def.has("hair") else [])
	for hair_path: String in hairs:
		if skel == null:
			break
		var hair := (load(hair_path) as PackedScene).instantiate()
		for hm: MeshInstance3D in hair.find_children("*", "MeshInstance3D", true, false):
			var copy := hm.duplicate() as MeshInstance3D
			skel.add_child(copy)
			copy.skeleton = NodePath("..")
			if _def.has("hair_color"):
				var hc: Array = _def.hair_color
				var hmat := (hm.mesh.surface_get_material(0) as BaseMaterial3D).duplicate() as BaseMaterial3D
				hmat.albedo_color = Color(hc[0], hc[1], hc[2])
				copy.material_override = hmat
		hair.free()
	for p: Dictionary in _def.get("props", []):
		var bone := skel.find_bone(str(p.bone)) if skel else -1
		if bone < 0:
			continue
		var from := (load(str(p.from)) as PackedScene).instantiate()
		var found := from.find_child(str(p.node), true, false) as MeshInstance3D
		if found:
			var att := BoneAttachment3D.new()
			att.bone_name = str(p.bone)
			skel.add_child(att)
			var mesh := MeshInstance3D.new()
			mesh.name = str(p.node)
			mesh.mesh = found.mesh
			var pos: Array = p.get("pos", [0, 0, 0])
			var rot: Array = p.get("rot_deg", [0, 0, 0])
			mesh.position = Vector3(pos[0], pos[1], pos[2])
			mesh.rotation_degrees = Vector3(rot[0], rot[1], rot[2])
			mesh.scale = Vector3.ONE * float(p.get("scale", 1.0))
			att.add_child(mesh)
		from.free()
	for g: Dictionary in _def.get("gear", []):
		if skel == null or skel.find_bone(str(g.bone)) < 0:
			continue
		var att := BoneAttachment3D.new()
		att.bone_name = str(g.bone)
		skel.add_child(att)
		var gm := MeshInstance3D.new()
		gm.mesh = _gear_mesh(g)
		gm.set_meta("gear", true)
		var pos: Array = g.get("pos", [0, 0, 0])
		var rot: Array = g.get("rot_deg", [0, 0, 0])
		gm.position = Vector3(pos[0], pos[1], pos[2])
		gm.rotation_degrees = Vector3(rot[0], rot[1], rot[2])
		att.add_child(gm)


static func _gear_mesh(g: Dictionary) -> Mesh:
	var sz: Array = g.get("size", [0.1, 0.1, 0.1])
	var c: Array = g.get("color", [0.3, 0.3, 0.3])
	var key := "%s %s %s" % [g.get("shape", "box"), sz, c]
	if _gear_meshes.has(key):
		return _gear_meshes[key]
	var mesh: PrimitiveMesh
	match str(g.get("shape", "box")):
		"cylinder", "cone":
			var cyl := CylinderMesh.new()
			cyl.bottom_radius = float(sz[0])
			cyl.top_radius = 0.0 if str(g.shape) == "cone" else float(sz[0])
			cyl.height = float(sz[1])
			cyl.radial_segments = 8
			cyl.rings = 1
			mesh = cyl
		"sphere":
			var sph := SphereMesh.new()
			sph.radius = float(sz[0])
			sph.height = float(sz[0]) * 2.0
			sph.radial_segments = 10
			sph.rings = 6
			mesh = sph
		_:
			var box := BoxMesh.new()
			box.size = Vector3(sz[0], sz[1], sz[2])
			mesh = box
	var mkey := "%s %s" % [c, g.get("metal", 0.0)]
	if not _gear_mats.has(mkey):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(c[0], c[1], c[2])
		mat.metallic = float(g.get("metal", 0.0))
		mat.roughness = 0.75
		_gear_mats[mkey] = mat
	mesh.material = _gear_mats[mkey]
	_gear_meshes[key] = mesh
	return mesh


# Shows the weapon mesh listed for this slot in weapons_by_slot (or none).
func set_weapon_slot(slot: int) -> void:
	if on_bike or _throw_style != "":
		slot = -1  # throwing a disc: no gun in the hand
	var names: Array = _def.get("weapons_by_slot", [])
	var want := str(names[slot]) if slot >= 0 and slot < names.size() else ""
	for mi in _props:
		mi.visible = str(mi.name) == want


# Shows the hand-held weapon mesh with this node name (D-087: any kit weapon - Pistol, SMG, Shotgun, Rifle, Knife,
# Axe, WoodenBat_Barbed ...), or nothing for "".
func set_weapon_mesh(want: String) -> void:
	if on_bike or _throw_style != "":
		want = ""
	for mi in _props:
		mi.visible = str(mi.name) == want


# Plays clip `key` (e.g. "attack") for `seconds`, over whatever update() would pick.
func one_shot(key: String, seconds: float) -> void:
	_oneshot_key = key
	_oneshot_left = seconds
	_current = ""


# A disc throw (D-117): plays style `style_id`'s swing from `from_t` (0 = address) to the end with disc `disc_id` in
# the hand until the release. Returns the seconds from now until the release (0 when this model can't do it).
func start_throw(style_id: String, disc_id: String, from_t := 0.0) -> float:
	if not _ready_ik():
		return 0.0
	_throw_clip = ThrowPose.clip(style_id)
	_throw_style = style_id
	_throw_t = clampf(from_t, 0.0, 1.0)
	_throw_hold = false
	_released = _throw_t >= _throw_clip.release
	set_weapon_mesh("")
	_show_disc(disc_id, not _released)
	return maxf(0.0, (_throw_clip.release - _throw_t) * _throw_clip.seconds)


# Holds style `style_id`'s swing at point t (0 address .. clip.reach full reach-back), disc in hand.
func pose_throw(style_id: String, disc_id: String, t: float) -> void:
	if not _ready_ik():
		return
	_throw_clip = ThrowPose.clip(style_id)
	_throw_style = style_id
	_throw_t = clampf(t, 0.0, 1.0)
	_throw_hold = true
	_released = false
	set_weapon_mesh("")
	_show_disc(disc_id, true)


func stop_throw() -> void:
	_throw_style = ""
	if _first_person and _model:
		_model.visible = true
	if _disc_node:
		_disc_node.visible = false


func throwing() -> bool:
	return _throw_style != ""


# Seconds until the disc leaves the hand in the swing that's playing (0 if it has, or nothing is playing).
func time_to_release() -> float:
	if _throw_style == "" or _released or _throw_hold:
		return 0.0
	return maxf(0.0, (_throw_clip.release - _throw_t) * _throw_clip.seconds)


func _ready_ik() -> bool:
	if _skeleton == null:
		return false
	if _ik == null:
		_ik = ArmIK.find(_skeleton, _data.get("throw_rigs", []))
	return _ik.valid


func _show_disc(disc_id: String, on: bool) -> void:
	if _disc_node == null:
		_disc_node = MeshInstance3D.new()
		_disc_node.name = "ThrowDisc"
		if _first_person:
			_disc_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_disc_node)
	if disc_id != _disc_id or _disc_node.mesh == null:
		_disc_id = disc_id
		_disc_node.mesh = DiscMesh.mesh(disc_id)
	_disc_node.visible = on


# After the clip is sampled: the swing on top (torso, throwing arm) and the disc in the hand (D-117).
func _apply_throw(delta: float) -> void:
	if _throw_style == "":
		return
	if not _throw_hold:
		_throw_t = minf(1.0, _throw_t + delta / _throw_clip.seconds)
		if not _released and _throw_t >= _throw_clip.release:
			_released = true
			if _disc_node:
				_disc_node.visible = false  # let go
	ThrowPose.sample_into(_throw_clip, _throw_t, _sample)
	if _first_person:  # the chibi arm swings below the camera, so first person shows only the disc (D-120)
		_fp_disc()
		if not _throw_hold and _throw_t >= 1.0:
			stop_throw()
		return
	var node_to_skel := _skeleton.global_transform.affine_inverse() * global_transform
	var skel_to_node := node_to_skel.affine_inverse()
	if advanced:  # the clip re-sampled every bone this frame, so the swing goes on top of a fresh pose
		var fp: Dictionary = DiscFlightRules.styles_fp()
		var tw := _sample.twist * (float(fp.get("twist_scale", 0.35)) if _first_person else 1.0)
		var ln := _sample.lean * (float(fp.get("lean_scale", 0.3)) if _first_person else 1.0)
		_ik.bend(_skeleton, node_to_skel.basis, tw, ln)
		var arm := _ik.arm_length(_skeleton) * skel_to_node.basis.get_scale().x
		var target := skel_to_node * _ik.shoulder(_skeleton) + _sample.hand * arm
		_ik.reach(_skeleton, node_to_skel * target, node_to_skel.basis * _sample.pole)
		throw_ik_error = (skel_to_node * _ik.hand_tip(_skeleton)).distance_to(target)
	if _disc_node and _disc_node.visible:
		var tip := skel_to_node * _ik.hand_tip(_skeleton)
		var up := _sample.disc * Vector3.UP
		var dir: Vector3 = _sample.travel * _throw_clip.disc_lead if not _throw_hold and _sample.travel.length() > 0.3 else Vector3.FORWARD
		dir = dir - up * dir.dot(up)
		if dir.length() > 0.001:
			_disc_dir = _disc_dir.slerp(dir.normalized(), clampf(delta * 18.0, 0.0, 1.0)).normalized()
		var flat := _disc_dir - up * _disc_dir.dot(up)
		_disc_node.position = tip + (flat.normalized() if flat.length() > 0.001 else Vector3.ZERO) * GRIP_M
		_disc_node.basis = _sample.disc
	if not _throw_hold and _throw_t >= 1.0:
		stop_throw()


# First person (D-120): the body is hidden and the disc follows the swing on screen - the sampled hand offset
# scaled down (styles "fp" disc_swing_m per arm length) around a point in front of the camera (disc_anchor_m).
func _fp_disc() -> void:
	if _model:
		_model.visible = false
	if _disc_node == null or not _disc_node.visible:
		return
	var fp: Dictionary = DiscFlightRules.styles_fp()
	var a: Array = fp.get("disc_anchor_m", [0.16, -0.06, -0.62])
	_disc_node.position = Vector3(float(a[0]), float(a[1]), float(a[2])) + _sample.hand * float(fp.get("disc_swing_m", 0.28))
	_disc_node.basis = _sample.disc


# Call every frame (all peers). health = current HP (replicated).
func update(delta: float, attacking: bool, dead: bool, health: float, armed := false, crouched := false) -> void:
	if _player == null:
		return
	var pos := global_position
	if _last_pos != Vector3.INF and delta > 0.0:
		var moved := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length() / delta
		_speed = lerpf(_speed, minf(moved, 12.0), clampf(delta * 8.0, 0.0, 1.0))
	_last_pos = pos
	if health < _last_health - 0.01 and not dead:
		_hit_left = 0.35
	_last_health = health
	_hit_left = maxf(_hit_left - delta, 0.0)
	_oneshot_left = maxf(_oneshot_left - delta, 0.0)
	if dead:
		_play("death", 1.0, false)
		stop_throw()
	elif _throw_style != "":
		_play("idle", 1.0, false)  # the swing goes on top (D-117)
	elif _oneshot_left > 0.0:
		_play(_oneshot_key, 1.0, armed)
	elif attacking:
		_play("attack", 1.0, armed)
	elif _hit_left > 0.0:
		_play("hit", 1.0, armed)
	elif on_bike:
		_play("ride" if _def.clips.has("ride") else "idle", 1.0, false)
	elif riding:
		_play("idle", 1.0, armed)
	elif crouched and _def.clips.has("crouch"):
		_play("crouch", 1.0, false)
	elif _speed > float(_def.run_above_speed):
		_play("run", _speed / float(_def.run_ref_speed), armed)
	elif _speed > 0.15:
		_play("walk", _speed / float(_def.walk_ref_speed), armed)
	else:
		_play("idle", 1.0, armed)

	_accum += delta
	advanced = false
	var cam := get_viewport().get_camera_3d()
	var far := cam != null and cam.global_position.distance_to(pos) > _far_m
	if not far or _accum >= _far_period:
		_player.advance(_accum)
		_accum = 0.0
		advanced = true
		for i in _hidden_bones:
			_skeleton.set_bone_pose_scale(i, Vector3.ONE * 0.001)
	_apply_throw(delta)


# Shrinks these bones (names without the "mixamorig_" prefix, e.g. "LeftUpLeg") to nothing every frame.
func hide_bones(names: Array) -> void:
	if _skeleton == null:
		return
	for i in _skeleton.get_bone_count():
		if MixamoRetarget.strip(_skeleton.get_bone_name(i)) in names and not _hidden_bones.has(i):
			_hidden_bones.append(i)


# Undoes hide_bones() (a pooled body that's no longer a crawler).
func unhide_bones() -> void:
	for i in _hidden_bones:
		_skeleton.set_bone_pose_scale(i, Vector3.ONE)
	_hidden_bones.clear()


func skeleton() -> Skeleton3D:
	return _skeleton


# Length in seconds of clip `key` on this model (0 when it has none).
func clip_length(key: String) -> float:
	var clip := str(_def.get("clips", {}).get(clip_remap.get(key, key), ""))
	return _player.get_animation(clip).length if _player and _player.has_animation(clip) else 0.0


func _play(key: String, speed: float, armed: bool) -> void:
	if clip_remap.has(key) and _def.clips.has(clip_remap[key]):
		key = str(clip_remap[key])
	var k := key + "_gun" if armed and _def.clips.has(key + "_gun") else key
	var clip := str(_def.clips.get(k, ""))
	if not _player.has_animation(clip):
		return
	_player.speed_scale = clampf(speed, 0.3, 2.5)
	if _current == k:
		return
	_current = k
	_player.play(clip, _blend)


func _bounds(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi: Node in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.skin == null and (_def.has("weapons_by_slot") or m.has_meta("gear")):
			continue  # weapons laid out beside the body (and gear) would skew the height
		var box := _local_xform(m, node) * m.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


func _local_xform(n: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	while n != root and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf
