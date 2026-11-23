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
# Weapon animations (D-123): set_weapon(mesh, weapon_id) holds that weapon with its GunPose animations - the kit
# mesh is drawn as a copy placed from the model's own gun-holding clip plus the playing action (draw, holster,
# reload, swing - gun_action) and kick (gun_kick) clips, then ArmIK puts the right hand on the grip and the left hand
# on the support point (or lets it hang free where the clip says). Switching weapons holsters the old one first.
# Works the same in first person and on other players' bodies, on both rigs ("left" entries in throw_rigs).
# Riding (D-124): set_ride_pose() puts the hands on the bar grips and the feet on the pegs (ArmIK, "leg_l" / "leg_r"
# rig entries) with the torso tucked forward, on top of the "ride" clip, while on_bike.
# Never affects gameplay. Depends on: DataLoader, MixamoRetarget, shaders/outfit.gdshader, ThrowPose, ArmIK, DiscMesh,
# GunPose.
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
# Weapon animations (D-123).
var _gun_id := ""
var _gun_def: Dictionary = {}
var _gun_mesh := ""
var _held: MeshInstance3D        # the drawn copy of the weapon in hand
var _held_src: MeshInstance3D    # the kit prop it copies (hidden; its clip pose is the base hold)
var _held_bone := -1
var _held_att: BoneAttachment3D  # what the kit prop hangs off (refreshed right after the clip is sampled)
var _held_left := false          # the model's clip holds it in the left hand (the kit survivors do)
var _fp_base := Vector3.ZERO
var _axes_ready := false
var _barrel_ax := Vector3.FORWARD  # weapon-local unit axes (from the clip's hold)
var _up_ax := Vector3.UP
var _side_ax := Vector3.RIGHT
var _grip_local := Vector3.ZERO
var _ik_l: ArmIK
var _act := ""                   # draw / holster / reload / swing, "" = none
var _act_clip: GunPose.Clip
var _act_t := 1.0
var _act_s := 1.0
var _next_mesh := ""             # switching: shown when the holster ends
var _next_id := ""
var _switching := false
var _kick_clip: GunPose.Clip
var _kick_t := 1.0
var _kick_s := 0.2
var _gs := GunPose.Sample.new()
var _ks := GunPose.Sample.new()
var _ride_on := false             # D-124 riding pose targets (this node's frame)
var _ride_grip_l := Vector3.ZERO
var _ride_grip_r := Vector3.ZERO
var _ride_peg_l := Vector3.ZERO
var _ride_peg_r := Vector3.ZERO
var _ride_tuck := 0.0
var _ik_leg_l: ArmIK
var _ik_leg_r: ArmIK
var ride_error := 0.0  # m: the farthest hand / foot from its grip / peg last pose (tests)
var grip_error_r := 0.0  # m: right hand tip to the grip last pose (tests)
var gun_debug_on := false  # tests: fill gun_debug each pose
var gun_debug := ""
var grip_error_l := 0.0  # m: left hand tip to the support point while it holds the gun (0 when free)


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
	_ik_l = null
	_ik_leg_l = null
	_ik_leg_r = null
	_held = null
	_held_src = null
	_gun_mesh = ""
	_gun_id = ""
	_act = ""
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
		_fp_base = model.position
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
	_drop_gun()
	for mi in _props:
		mi.visible = str(mi.name) == want


# Shows the hand-held weapon mesh with this node name (D-087: any kit weapon - Pistol, SMG, Shotgun, Rifle, Knife,
# Axe, WoodenBat_Barbed ...), or nothing for "".
func set_weapon_mesh(want: String) -> void:
	if on_bike or _throw_style != "":
		want = ""
	_drop_gun()
	for mi in _props:
		mi.visible = str(mi.name) == want


# Weapon `id` (its kit mesh `mesh`) in hand with its animations (D-123); weapons without any (fists, thrown, NPC
# guns) are just shown as set_weapon_mesh does. A change holsters the old weapon, then draws the new one.
# Cheap to call every frame with the same arguments.
func set_weapon(mesh: String, id: String) -> void:
	if on_bike or _throw_style != "":
		mesh = ""
		id = ""
	if _switching:
		_next_mesh = mesh
		_next_id = id
		return
	if mesh == _gun_mesh and id == _gun_id:
		return
	if _held and _held.visible and _gun_def.has("holster") and mesh != _gun_mesh:
		_next_mesh = mesh
		_next_id = id
		_switching = true
		gun_action("holster")
		return
	_show_gun(mesh, id)


# Plays the held weapon's `kind` clip (draw / holster / reload / swing) over `seconds` (-1: its data seconds).
func gun_action(kind: String, seconds := -1.0) -> void:
	if not _gun_def.has(kind):
		return
	_act = kind
	_act_clip = GunPose.clip(str(_gun_def[kind]))
	_act_s = maxf(seconds if seconds > 0.0 else float(_gun_def.get(kind + "_s", 0.3)), 0.05)
	_act_t = 0.0


func has_gun_action(kind: String) -> bool:
	return _gun_def.has(kind) and _held != null and _held.visible


# One shot's kick of the held gun (D-123).
func gun_kick() -> void:
	if not _gun_def.has("kick"):
		return
	_kick_clip = GunPose.clip(str(_gun_def.kick))
	_kick_s = maxf(float(_gun_def.get("kick_s", 0.2)), 0.05)
	_kick_t = 0.0


func gun_action_playing() -> String:
	return _act


func _drop_gun() -> void:
	_gun_mesh = ""
	_gun_id = ""
	_gun_def = {}
	_act = ""
	_switching = false
	if _held:
		_held.visible = false


func _show_gun(mesh: String, id: String) -> void:
	_drop_gun()
	_gun_mesh = mesh
	_gun_id = id
	_held_src = null
	for mi in _props:
		mi.visible = false
		if str(mi.name) == mesh:
			_held_src = mi
	if mesh == "" or _held_src == null:
		return
	var def := GunPose.weapon(id)
	if def.is_empty() or not _ready_ik() or not _ready_left():
		_held_src.visible = true  # no animations: the clip's own hold
		return
	_gun_def = def
	if _held == null:
		_held = MeshInstance3D.new()
		_held.name = "HeldWeapon"
		if _first_person:
			_held.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_held)
	_held.mesh = _held_src.mesh
	_held.material_override = _held_src.material_override
	for i in _held_src.get_surface_override_material_count():
		_held.set_surface_override_material(i, _held_src.get_surface_override_material(i))
	_held.visible = true
	_held_bone = -1
	_held_att = null
	var n: Node = _held_src.get_parent()
	while n != null and n != _skeleton:
		if n is BoneAttachment3D:
			_held_att = n
			_held_bone = _skeleton.find_bone(_held_att.bone_name)
			break
		n = n.get_parent()
	_held_left = false  # which arm the clip holds it with: is the attachment bone under the left forearm?
	var b := _held_bone
	while b >= 0:
		if b == _ik_l.lower:
			_held_left = true
		b = _skeleton.get_bone_parent(b)
	_axes_ready = false
	gun_action("draw")


func _ready_left() -> bool:
	if _skeleton == null:
		return false
	if _ik_l == null:
		_ik_l = ArmIK.find(_skeleton, _data.get("throw_rigs", []), "left")
	return _ik_l.valid


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


# Front end of the weapon mesh in hand along `forward` (global), on the barrel's centre line (D-122: the muzzle
# flash and tracers start here). INF when no weapon is shown.
func weapon_tip(forward: Vector3) -> Vector3:
	for k in _props.size() + 1:
		var mi: MeshInstance3D = _held if k == _props.size() else _props[k]
		if mi == null or not mi.visible:
			continue
		var box := mi.get_aabb()
		var xf := mi.global_transform
		var centre := xf * box.get_center()
		var far := -INF
		for i in 8:
			far = maxf(far, (xf * box.get_endpoint(i)).dot(forward))
		return centre + forward * (far - centre.dot(forward))
	return Vector3.INF


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
	_apply_gun(delta)
	_apply_ride()


func _rest_chain(ik: ArmIK) -> void:
	if ik.valid:
		_skeleton.reset_bone_pose(ik.upper)
		_skeleton.reset_bone_pose(ik.lower)
		_skeleton.reset_bone_pose(ik.end)


# D-124: hands on the bar grips, feet on the pegs, torso tucked by `tuck` (rad), every frame while riding.
func set_ride_pose(grip_l: Vector3, grip_r: Vector3, peg_l: Vector3, peg_r: Vector3, tuck: float) -> void:
	_ride_on = true
	_ride_grip_l = grip_l
	_ride_grip_r = grip_r
	_ride_peg_l = peg_l
	_ride_peg_r = peg_r
	_ride_tuck = tuck


func clear_ride_pose() -> void:
	_ride_on = false
	if _model and not _first_person:
		_model.position = Vector3.ZERO  # back from sliding up the seat


func _apply_ride() -> void:
	if not _ride_on or not on_bike or not advanced or _skeleton == null or not _ready_ik() or not _ready_left():
		return
	if _ik_leg_l == null:
		_ik_leg_l = ArmIK.find(_skeleton, _data.get("throw_rigs", []), "leg_l")
		_ik_leg_r = ArmIK.find(_skeleton, _data.get("throw_rigs", []), "leg_r")
	# Start from the rest pose for the bones the pose drives: a ride clip that doesn't key them would otherwise keep
	# last frame's bend / IK and pile it up every frame.
	_rest_chain(_ik)
	_rest_chain(_ik_l)
	_rest_chain(_ik_leg_l)
	_rest_chain(_ik_leg_r)
	for bone in _ik.spine:
		_skeleton.reset_bone_pose(bone)
	if _model and not _first_person:
		_model.position = Vector3.ZERO
	var node_to_skel := _skeleton.global_transform.affine_inverse() * global_transform
	var skel_to_node := node_to_skel.affine_inverse()
	var b := node_to_skel.basis
	_ik.bend(_skeleton, b, 0.0, _ride_tuck)
	var reach_r := _ik.arm_length(_skeleton) * 0.97
	var reach_l := _ik_l.arm_length(_skeleton) * 0.97
	for k in 8:  # bars out of reach (a long tank, a short rider): lean further forward, a bit at a time
		if _ik.shoulder(_skeleton).distance_to(node_to_skel * _ride_grip_r) <= reach_r \
				and _ik_l.shoulder(_skeleton).distance_to(node_to_skel * _ride_grip_l) <= reach_l:
			break
		_ik.bend(_skeleton, b, 0.0, 0.08)
	# Still short (a reclined seat pose): slide the rider up the seat toward the bars until the arms reach.
	var sh_mid := skel_to_node * (_ik.shoulder(_skeleton) + _ik_l.shoulder(_skeleton)) * 0.5
	var g_mid := (_ride_grip_r + _ride_grip_l) * 0.5
	var short := maxf(_ik.shoulder(_skeleton).distance_to(node_to_skel * _ride_grip_r) - reach_r,
		_ik_l.shoulder(_skeleton).distance_to(node_to_skel * _ride_grip_l) - reach_l) * skel_to_node.basis.get_scale().x
	if short > 0.0 and _model:
		var flat := Vector3(g_mid.x - sh_mid.x, 0.0, g_mid.z - sh_mid.z)
		if flat.length() > 0.001:
			_model.position += flat.normalized() * minf(short + 0.02, 0.45)
			node_to_skel = _skeleton.global_transform.affine_inverse() * global_transform
			skel_to_node = node_to_skel.affine_inverse()
			b = node_to_skel.basis
	_ik.reach(_skeleton, node_to_skel * _ride_grip_r, b * Vector3(1.0, -0.6, 0.3))
	_ik_l.reach(_skeleton, node_to_skel * _ride_grip_l, b * Vector3(-1.0, -0.6, 0.3))
	ride_error = maxf((skel_to_node * _ik.hand_tip(_skeleton)).distance_to(_ride_grip_r),
		(skel_to_node * _ik_l.hand_tip(_skeleton)).distance_to(_ride_grip_l))
	if _ik_leg_l.valid and _ik_leg_r.valid:
		var up := Vector3(0, 0.07, 0)  # the ankle sits above the peg
		_ik_leg_l.reach(_skeleton, node_to_skel * (_ride_peg_l + up), b * Vector3(-0.4, 0.2, -1.0))
		_ik_leg_r.reach(_skeleton, node_to_skel * (_ride_peg_r + up), b * Vector3(0.4, 0.2, -1.0))
		ride_error = maxf(ride_error, maxf((skel_to_node * _ik_leg_l.hand_tip(_skeleton)).distance_to(_ride_peg_l + up),
			(skel_to_node * _ik_leg_r.hand_tip(_skeleton)).distance_to(_ride_peg_r + up)))


# After the clip is sampled (D-123): the held weapon moved by the playing clips about the right-hand grip, the right
# hand on the grip and the left on the support point (or free).
func _apply_gun(delta: float) -> void:
	if _act != "":
		_act_t += delta / _act_s
		if _act_t >= 1.0:
			var was := _act
			_act = ""
			if was == "holster" and _switching:
				_switching = false
				_show_gun(_next_mesh, _next_id)
	_kick_t = minf(_kick_t + delta / _kick_s, 1.0)
	if _first_person and _model:  # first person: the arms come up while a weapon is held so it is in view
		var on := _held != null and _held.visible and _throw_style == ""
		_model.position = _fp_base + (Vector3(0.0, float(GunPose.data().get("fp_lift_m", 0.0)),
			-float(GunPose.data().get("fp_forward_m", 0.0))) if on else Vector3.ZERO)
	if _held == null or not _held.visible or _throw_style != "" or not advanced:
		return
	var node_to_skel := _skeleton.global_transform.affine_inverse() * global_transform
	var skel_to_node := node_to_skel.affine_inverse()
	if _held_att:
		_held_att.on_skeleton_update()  # the clip pose of this frame, before any IK
	var w_clip := global_transform.affine_inverse() * _held_src.global_transform
	if not _axes_ready:
		_find_axes(w_clip, skel_to_node * (_ik_l if _held_left else _ik).hand_tip(_skeleton))
	var off := Vector3.ZERO
	var rot := Vector3.ZERO
	var left := 0.0
	var twist := 0.0
	if _act != "":
		GunPose.sample_into(_act_clip, _act_t, _gs)
		off = _gs.off
		rot = _gs.rot
		left = _gs.left
		twist = _gs.twist
	if _kick_t < 1.0 and _kick_clip:
		GunPose.sample_into(_kick_clip, _kick_t, _ks)
		var ks := float(_gun_def.get("kick_scale", 1.0)) * (float(GunPose.data().get("fp_kick_scale", 0.5)) if _first_person else 1.0)
		off += _ks.off * ks
		rot += _ks.rot * ks
		left = maxf(left, _ks.left)
	var w_base := w_clip
	var hold: Variant = _gun_def.get("fp_hold" if _first_person else "hold")
	if hold is Array:  # a set hold: grip at [x, y, z] arm lengths from the right shoulder, barrel ahead + pitch / yaw
		var h: Array = hold
		var sh := skel_to_node * _ik.shoulder(_skeleton)
		var arm := _ik.arm_length(_skeleton) * skel_to_node.basis.get_scale().x
		var canon := Basis(_side_ax, _up_ax, -_barrel_ax).transposed()
		var b := Basis.from_euler(Vector3(deg_to_rad(float(h[3])), deg_to_rad(float(h[4])), 0.0)) * canon \
			* Basis.from_scale(w_clip.basis.get_scale())
		var g := sh + Vector3(float(h[0]), float(h[1]), float(h[2])) * arm
		w_base = Transform3D(b, g - b * _grip_local)
	var g0 := w_base * _grip_local
	var r := Basis.from_euler(rot * (PI / 180.0))
	var wd := Transform3D(Basis(Vector3.UP, deg_to_rad(twist)), Vector3.ZERO) * Transform3D(r, g0 + off) \
		* Transform3D(Basis.IDENTITY, -g0) * w_base
	if twist != 0.0:
		_ik.bend(_skeleton, node_to_skel.basis, deg_to_rad(twist), 0.0)
	# Keep both grips within reach: pull the weapon in toward a shoulder it would leave the hand short of.
	var d := GunPose.data()
	var sup: Variant = _gun_def.get("support")
	var box := _held_src.get_aabb()
	var sup_local := Vector3.ZERO
	if sup is Array:
		var a: Array = sup
		sup_local = box.get_center() + _barrel_ax * (float(a[0]) - 0.5) * absf(box.size.dot(_barrel_ax)) \
			+ _up_ax * float(a[1]) * absf(box.size.dot(_up_ax)) + _side_ax * float(a[2]) * absf(box.size.dot(_side_ax))
	var scale_k := skel_to_node.basis.get_scale().x
	var sh_r := skel_to_node * _ik.shoulder(_skeleton)
	var sh_l := skel_to_node * _ik_l.shoulder(_skeleton)
	var reach_r := _ik.arm_length(_skeleton) * scale_k * 0.96
	var reach_l := _ik_l.arm_length(_skeleton) * scale_k * 0.96
	for k in 2:
		var gr := wd * _grip_local
		if gr.distance_to(sh_r) > reach_r:
			wd.origin += sh_r + (gr - sh_r).normalized() * reach_r - gr
		if sup is Array and left < 0.5:
			var sp := wd * sup_local
			if sp.distance_to(sh_l) > reach_l:
				wd.origin += (sh_l + (sp - sh_l).normalized() * reach_l - sp) * (1.0 - left * 2.0)
	_held.transform = wd
	var target_r := wd * _grip_local
	_ik.reach(_skeleton, node_to_skel * target_r, node_to_skel.basis * GunPose._v3(d.get("pole_right", [0.8, -1, 0.5])))
	grip_error_r = (skel_to_node * _ik.hand_tip(_skeleton)).distance_to(target_r)
	var arm_l := _ik_l.arm_length(_skeleton) * scale_k
	var free := skel_to_node * _ik_l.shoulder(_skeleton) + GunPose._v3(d.get("left_rest", [0, -0.9, -0.1])) * arm_l
	var target_l := free
	if sup is Array:
		target_l = (wd * sup_local).lerp(free, clampf(left, 0.0, 1.0))
	_ik_l.reach(_skeleton, node_to_skel * target_l, node_to_skel.basis * GunPose._v3(d.get("pole_left", [-0.8, -1, 0.5])))
	grip_error_l = (skel_to_node * _ik_l.hand_tip(_skeleton)).distance_to(target_l) if sup is Array and left < 0.01 else 0.0
	if gun_debug_on:
		gun_debug = "shR %s shL %s armR %.3f armL %.3f grip %s sup %s shL->sup %.3f len %.3f tipL %s" % [
			skel_to_node * _ik.shoulder(_skeleton), skel_to_node * _ik_l.shoulder(_skeleton), _ik.arm_length(_skeleton) * skel_to_node.basis.get_scale().x,
			arm_l, target_r, target_l, (skel_to_node * _ik_l.shoulder(_skeleton)).distance_to(target_l),
			absf(_held_src.get_aabb().size.dot(_barrel_ax)) * w_clip.basis.get_scale().x, skel_to_node * _ik_l.hand_tip(_skeleton)]
		gun_debug += " | muzzle dir %s up dir %s" % [(wd.basis * _barrel_ax).normalized(), (wd.basis * _up_ax).normalized()]
		gun_debug += " | bone %d %s src %s wclip %s bar %s up %s scale %s box %s path %s" % [_held_bone,
			_skeleton.get_bone_name(_held_bone) if _held_bone >= 0 else "-", global_transform.affine_inverse() * _held_src.global_position,
			w_clip.origin, _barrel_ax, _up_ax, w_clip.basis.get_scale(), _held_src.get_aabb(), _skeleton.get_path_to(_held_src)]


# The weapon's own axes: barrel = its longest side, toward the end farther from the hand (muzzle / blade); up = the
# mesh's "up" from weapon_anims.json "meshes", else the other side pointing most up in the clip's hold; the grip is
# the mesh's "grip" point there, else where the clip has the hand.
func _find_axes(w_clip: Transform3D, hand: Vector3) -> void:
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var box := _held_src.get_aabb()
	var m: Dictionary = GunPose.data().get("meshes", {}).get(_gun_mesh, {})
	_grip_local = GunPose._v3(m.grip) if m.has("grip") else w_clip.affine_inverse() * hand
	var bi := 0
	for i in 3:
		if absf(box.size.dot(axes[i])) > absf(box.size.dot(axes[bi])):
			bi = i
	var lo := box.position.dot(axes[bi])  # the muzzle / blade is the end farther from the hand
	var hi := (box.position + box.size).dot(axes[bi])
	var g := _grip_local.dot(axes[bi])
	_barrel_ax = axes[bi] * (1.0 if hi - g >= g - lo else -1.0)
	if m.has("up"):
		_up_ax = GunPose._v3(m.up)
	else:
		var best := -1.0
		var ui := (bi + 1) % 3
		for i in 3:
			if i == bi:
				continue
			var v := (w_clip.basis * axes[i]).normalized()
			if absf(v.dot(Vector3.UP)) > best:
				best = absf(v.dot(Vector3.UP))
				ui = i
		_up_ax = axes[ui] * signf((w_clip.basis * axes[ui]).dot(Vector3.UP) + 0.0001)
	_side_ax = _barrel_ax.cross(_up_ax).normalized()
	_axes_ready = true


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
