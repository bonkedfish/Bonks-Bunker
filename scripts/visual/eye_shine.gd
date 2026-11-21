# EyeShine — two small glints on a zombie's head that catch the light at night (D-114). Presentation only.
# One shared mesh (both eyes, one draw call per zombie) and one shared additive, unshaded, fog-free material;
# drawn only within range_m (visibility range) and only while it's night: Dread calls set_night() a couple of
# times a second and every eye is shown or hidden when night crosses night_above.
# attach() returns the per-zombie pivot, which the zombie hides while it's dead or lying down.
# Depends on: MixamoRetarget (bone names), data/tuning/scare.json "eyes".
class_name EyeShine
extends RefCounted

static var _mesh: ArrayMesh
static var _eyes: Array[MeshInstance3D] = []
static var _on := false


static func attach(skel: Skeleton3D, t: Dictionary) -> Node3D:
	var head := -1
	for i in skel.get_bone_count():
		if MixamoRetarget.strip(skel.get_bone_name(i)) == "Head":
			head = i
			break
	if head < 0:
		return null
	var att := BoneAttachment3D.new()
	att.bone_name = skel.get_bone_name(head)
	skel.add_child(att)
	var pivot := Node3D.new()
	att.add_child(pivot)
	var sc := skel.global_basis.get_scale().x if skel.is_inside_tree() else 1.0
	var o: Array = t.get("head_offset_m", [0.032, 0.09, 0.1])
	pivot.position = Vector3(0.0, float(o[1]), float(o[2])) / maxf(sc, 0.0001)
	var mi := MeshInstance3D.new()
	mi.mesh = _shared_mesh(t)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = float(t.get("range_m", 45.0))
	mi.visible = _on
	pivot.add_child(mi)
	_eyes.append(mi)
	mi.tree_exiting.connect(_forget.bind(mi))
	return pivot


# night = DayNight.night() (0 day .. 1 deep night).
static func set_night(night: float, t: Dictionary) -> void:
	var on := night > float(t.get("night_above", 0.25))
	if on == _on:
		return
	_on = on
	for mi in _eyes:
		mi.visible = on


static func is_on() -> bool:
	return _on


static func _forget(mi: MeshInstance3D) -> void:
	_eyes.erase(mi)


# Both eyes as billboarded quads (billboarding ignores the bone's scale, so sizes are in metres).
static func _shared_mesh(t: Dictionary) -> ArrayMesh:
	if _mesh:
		return _mesh
	var half := float(t.get("size_m", 0.03)) * 0.5
	var gap := float((t.get("head_offset_m", [0.032]) as Array)[0])
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for side in [-1.0, 1.0]:
		var base := verts.size()
		var cx: float = side * gap
		verts.append(Vector3(cx - half, -half, 0))
		verts.append(Vector3(cx + half, -half, 0))
		verts.append(Vector3(cx + half, half, 0))
		verts.append(Vector3(cx - half, half, 0))
		uvs.append(Vector2(0, 1))
		uvs.append(Vector2(1, 1))
		uvs.append(Vector2(1, 0))
		uvs.append(Vector2(0, 0))
		for k in [0, 1, 2, 0, 2, 3]:
			idx.append(base + int(k))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var c: Array = t.get("color", [1.0, 0.85, 0.45])
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_fog = true
	mat.albedo_color = Color(c[0], c[1], c[2])
	mat.albedo_texture = _dot()
	_mesh.surface_set_material(0, mat)
	return _mesh


static func _dot() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var d := Vector2(x - 7.5, y - 7.5).length() / 7.5
			var a := clampf((1.0 - d) * 1.8, 0.0, 1.0)  # bright core, soft edge
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
