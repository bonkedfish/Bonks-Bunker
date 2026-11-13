# DiscTracer — the white see-through line behind a thrown disc (D-076). One per player's disc (DiscGolfDirector) and
# one for the ace replay (AceReplay). show_path() builds a ribbon mesh once per throw from the host's flight path
# (no per-frame allocation); set_progress(0..1) reveals it as the disc flies (shaders/disc_tracer.gdshader keeps it
# facing the camera). Sits at the world origin (top_level) so the path's map positions are used as they are.
# Depends on: shaders/disc_tracer.gdshader.
class_name DiscTracer
extends MeshInstance3D

const SHADER := preload("res://shaders/disc_tracer.gdshader")

var _mat := ShaderMaterial.new()


func _init() -> void:
	top_level = true
	_mat.shader = SHADER
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 4.0  # the shader widens it with distance
	visible = false


func show_path(path: PackedVector3Array) -> void:
	var n := path.size()
	if n < 2:
		visible = false
		return
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	verts.resize(n * 2)
	normals.resize(n * 2)
	uvs.resize(n * 2)
	idx.resize((n - 1) * 6)
	var dir := Vector3.FORWARD
	for i in n:
		var d := path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]
		if d.length() > 0.0001:
			dir = d.normalized()
		var u := float(i) / float(n - 1)
		verts[i * 2] = path[i]
		verts[i * 2 + 1] = path[i]
		normals[i * 2] = dir
		normals[i * 2 + 1] = dir
		uvs[i * 2] = Vector2(u, -1.0)
		uvs[i * 2 + 1] = Vector2(u, 1.0)
	for i in n - 1:
		var a := i * 2
		idx[i * 6] = a
		idx[i * 6 + 1] = a + 1
		idx[i * 6 + 2] = a + 2
		idx[i * 6 + 3] = a + 1
		idx[i * 6 + 4] = a + 3
		idx[i * 6 + 5] = a + 2
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = m
	global_transform = Transform3D.IDENTITY
	set_progress(0.0)
	visible = true


func set_progress(f: float) -> void:
	_mat.set_shader_parameter("progress", f)
