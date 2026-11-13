# BallPlayback — shows host-simulated ball paths on every peer (D-074): one pooled ball per player (a small sphere
# under this node, positions in the Drop Zone's local space), played back at sample_hz and left resting at the end
# until put away. Visual only. Depends on: nothing.
class_name BallPlayback
extends Node3D

var radius := 0.06
var color := Color(1, 1, 1)
var _balls: Dictionary = {}  # peer -> {node, path, t, hz}
var _mesh: SphereMesh


func _ready() -> void:
	_mesh = SphereMesh.new()
	_mesh.radius = radius
	_mesh.height = radius * 2.0
	_mesh.radial_segments = 10
	_mesh.rings = 5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.4
	_mesh.material = mat


func play(peer: int, path: PackedVector3Array, hz: float) -> void:
	var b := _ball(peer)
	b.path = path
	b.t = 0.0
	b.hz = hz
	b.node.visible = true


# Shows the ball resting at `pos` (local), or hides it (pos = Vector3.INF).
func rest(peer: int, pos: Vector3) -> void:
	var b := _ball(peer)
	b.path = PackedVector3Array()
	b.node.visible = pos != Vector3.INF
	if pos != Vector3.INF:
		b.node.position = pos


func duration(path: PackedVector3Array, hz: float) -> float:
	return maxf(0.0, path.size() - 1) / hz


func is_playing(peer: int) -> bool:
	if not _balls.has(peer):
		return false
	var b: Dictionary = _balls[peer]
	return b.path.size() > 1 and float(b.t) < duration(b.path, b.hz)


func _ball(peer: int) -> Dictionary:
	if not _balls.has(peer):
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_balls[peer] = {"node": mi, "path": PackedVector3Array(), "t": 0.0, "hz": 30.0}
	return _balls[peer]


func _process(delta: float) -> void:
	for peer: int in _balls:
		var b: Dictionary = _balls[peer]
		var path: PackedVector3Array = b.path
		if path.size() < 2 or not b.node.visible:
			continue
		var dur := duration(path, b.hz)
		if float(b.t) > dur:
			continue
		b.t = float(b.t) + delta
		var k := clampf(float(b.t) * float(b.hz), 0.0, path.size() - 1.0)
		var i := mini(int(k), path.size() - 2)
		b.node.position = path[i].lerp(path[i + 1], k - i)
