# CharacterAnimator — presentation only (D-045): instances a rigged character model from
# data/art/character_models.json by string ID, scales it to height_m, turns it to face -Z, and picks its
# animation each frame from what every peer already knows: horizontal speed (measured from position change, so
# host and interpolated clients look the same), attacking, dead/downed, armed (gun clips), crouched, and a health
# drop (hit react). Walk/run clips are sped up/slowed to match the speed so feet don't slide. Far from the camera
# the animation is advanced at far_animation_hz instead of every frame.
# Survivor models carry every weapon as a separate mesh: set_weapon_slot() shows only the one in weapons_by_slot.
# First-person mode (set_model(id, true)): model placed at fp_offset under the camera, no shadows, and the bones
# in fp_hide_bones (head, legs) shrunk to nothing every frame so only arms + weapon are seen.
# Universal-rig models (D-058, Quaternius base characters): "path" (full res path), "anim_source" (a .glb whose
# AnimationPlayer library is shared onto the model), "outfit" (skin/shirt/pants/shoes colours through
# shaders/outfit.gdshader), "hair" (+ "hair_color") skinned onto the body's skeleton, "props" (weapon meshes copied
# from another model onto a hand bone, named for weapons_by_slot) and "fp_model" (model used for first-person arms).
# "gear" (D-061): primitive meshes built in code and fixed to bones (masks, pads, spikes): {shape: box | cylinder |
# cone | sphere, size [x,y,z] (cylinder/cone: [radius, height, -]), color [r,g,b], metal, bone, pos, rot_deg}.
# Never affects gameplay. Depends on: DataLoader, shaders/outfit.gdshader.
class_name CharacterAnimator
extends Node3D

const DATA_PATH := "res://data/art/character_models.json"
const LOOPING := ["idle", "walk", "run", "idle_gun", "walk_gun", "run_gun", "crouch"]

const OUTFIT_SHADER := preload("res://shaders/outfit.gdshader")

static var _data: Dictionary = {}
static var _anim_libs: Dictionary = {}  # anim_source path -> AnimationLibrary
static var _gear_mats: Dictionary = {}  # "r,g,b,metal" -> shared StandardMaterial3D
static var _gear_meshes: Dictionary = {}  # shape + size -> shared PrimitiveMesh

var _def: Dictionary = {}
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
var _far_m := 35.0
var _far_period := 0.1


# Loads model `id` (replacing any previous one). Returns false if the ID or file is missing.
func set_model(id: String, first_person := false) -> bool:
	if _data.is_empty():
		_data = DataLoader.load_json(DATA_PATH)
	var models: Dictionary = _data.get("models", {})
	if not models.has(id):
		push_error("CharacterAnimator: unknown model '%s'" % id)
		return false
	_def = models[id]
	_blend = float(_data.get("blend_seconds", 0.2))
	_far_m = float(_data.get("far_animation_m", 35.0))
	_far_period = 1.0 / maxf(float(_data.get("far_animation_hz", 10.0)), 1.0)
	for c in get_children():
		c.queue_free()
	var scene := load(str(_def.path) if _def.has("path") else "%s/%s" % [_data.kit_dir, _def.gltf]) as PackedScene
	if scene == null:
		push_error("CharacterAnimator: can't load %s" % _def.gltf)
		return false
	var model := scene.instantiate() as Node3D
	add_child(model)
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
	var names: Array = _def.get("weapons_by_slot", [])
	var want := str(names[slot]) if slot >= 0 and slot < names.size() else ""
	for mi in _props:
		mi.visible = str(mi.name) == want


# Plays clip `key` (e.g. "attack") for `seconds`, over whatever update() would pick.
func one_shot(key: String, seconds: float) -> void:
	_oneshot_key = key
	_oneshot_left = seconds
	_current = ""


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
	elif _oneshot_left > 0.0:
		_play(_oneshot_key, 1.0, armed)
	elif attacking:
		_play("attack", 1.0, armed)
	elif _hit_left > 0.0:
		_play("hit", 1.0, armed)
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
	var cam := get_viewport().get_camera_3d()
	var far := cam != null and cam.global_position.distance_to(pos) > _far_m
	if not far or _accum >= _far_period:
		_player.advance(_accum)
		_accum = 0.0
		for i in _hidden_bones:
			_skeleton.set_bone_pose_scale(i, Vector3.ONE * 0.001)


func _play(key: String, speed: float, armed: bool) -> void:
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
