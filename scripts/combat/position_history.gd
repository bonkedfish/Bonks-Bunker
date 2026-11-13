# PositionHistory — fixed-size ring of (host tick -> feet position, capsule height) for one hittable.
# The host records every physics tick; lag compensation samples it at a fractional past tick.
# Pure, preallocated, no per-tick allocation.
class_name PositionHistory
extends RefCounted

const SIZE := 64  # ~1 second at 60 Hz; must exceed max_rewind_seconds
const MISSING := Vector4(0.0, 0.0, 0.0, -1.0)

var _pos := PackedVector3Array()
var _height := PackedFloat32Array()
var _tick := PackedInt32Array()


func _init() -> void:
	_pos.resize(SIZE)
	_height.resize(SIZE)
	_tick.resize(SIZE)
	_tick.fill(-1)


func record(tick: int, pos: Vector3, height: float) -> void:
	var i := posmod(tick, SIZE)
	_tick[i] = tick
	_pos[i] = pos
	_height[i] = height


# Returns Vector4(feet x, y, z, height), or MISSING (w < 0) if that tick isn't recorded.
func sample(tick: float) -> Vector4:
	var t0 := floori(tick)
	var a := _at(t0)
	var b := _at(t0 + 1)
	if a.w < 0.0:
		return b
	if b.w < 0.0:
		return a
	return a.lerp(b, tick - t0)


func _at(t: int) -> Vector4:
	var i := posmod(t, SIZE)
	if _tick[i] != t:
		return MISSING
	var p := _pos[i]
	return Vector4(p.x, p.y, p.z, _height[i])
