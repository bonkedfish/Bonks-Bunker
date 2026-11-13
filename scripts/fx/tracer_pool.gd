# TracerPool — pooled bullet tracers (thin glowing boxes stretched from muzzle to impact).
# All meshes are created once; show_tracer() reuses the oldest. Visual only. Group: "tracers".
extends Node3D

const POOL_SIZE := 24
const LIFETIME := 0.06
const THICKNESS := 0.015

var _meshes: Array[MeshInstance3D] = []
var _life := PackedFloat32Array()
var _next := 0


func _ready() -> void:
	add_to_group("tracers")
	var box := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.5)
	box.material = mat
	_life.resize(POOL_SIZE)
	for i in POOL_SIZE:
		var m := MeshInstance3D.new()
		m.mesh = box
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		m.top_level = true
		add_child(m)
		_meshes.append(m)


func show_tracer(from: Vector3, to: Vector3) -> void:
	var span := to - from
	var length := span.length()
	if length < 0.05:
		return
	var dir := span / length
	var up := Vector3.FORWARD if absf(dir.y) > 0.99 else Vector3.UP
	var m := _meshes[_next]
	m.global_transform = Transform3D(
		Basis.looking_at(dir, up) * Basis.from_scale(Vector3(THICKNESS, THICKNESS, length)),
		from + span * 0.5)
	m.visible = true
	_life[_next] = LIFETIME
	_next = (_next + 1) % POOL_SIZE


func _process(delta: float) -> void:
	for i in POOL_SIZE:
		if _life[i] > 0.0:
			_life[i] -= delta
			if _life[i] <= 0.0:
				_meshes[i].visible = false
