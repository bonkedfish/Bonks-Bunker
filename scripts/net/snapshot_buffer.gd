# SnapshotBuffer — ring of (arrival time, position, yaw) for rendering a host-owned object on a client
# NetClock.INTERP_DELAY in the past, matching what lag compensation rewinds to. Preallocated.
class_name SnapshotBuffer
extends RefCounted

const SIZE := 16

var _time := PackedFloat64Array()
var _pos := PackedVector3Array()
var _yaw := PackedFloat32Array()
var _newest := 0
var _count := 0


func _init() -> void:
	_time.resize(SIZE)
	_pos.resize(SIZE)
	_yaw.resize(SIZE)


func clear() -> void:
	_count = 0


func is_empty() -> bool:
	return _count == 0


func push(time: float, pos: Vector3, yaw: float) -> void:
	_newest = (_newest + 1) % SIZE
	_count = mini(_count + 1, SIZE)
	_time[_newest] = time
	_pos[_newest] = pos
	_yaw[_newest] = yaw


# Returns Vector4(x, y, z, yaw) interpolated at render_time. Call only when not empty.
func sample(render_time: float) -> Vector4:
	var newer := _newest
	for i in range(1, _count):
		var older := (_newest - i + SIZE) % SIZE
		if _time[older] <= render_time:
			var span := _time[newer] - _time[older]
			var t := 1.0 if span <= 0.0 else clampf((render_time - _time[older]) / span, 0.0, 1.0)
			var p := _pos[older].lerp(_pos[newer], t)
			return Vector4(p.x, p.y, p.z, lerp_angle(_yaw[older], _yaw[newer], t))
		newer = older
	var q := _pos[newer]
	return Vector4(q.x, q.y, q.z, _yaw[newer])
