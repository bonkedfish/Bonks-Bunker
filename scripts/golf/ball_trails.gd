# BallTrails — the white tracer line behind each player's golf shot (D-097), the same DiscTracer the disc golf
# uses: shown from the host's path when the shot starts, revealed as the ball flies (paths are sampled at hz, like BallPlayback) and
# kept until its player walks up to the ball (or hits again). One pooled tracer per player. Visual only, every
# peer. Used by CourseGolf and DzRange. Depends on: DiscTracer, Player (group "players").
class_name BallTrails
extends Node

const NEAR_M := 3.0

var _lines: Dictionary = {}  # peer -> DiscTracer
var _time: Dictionary = {}   # peer -> [seconds since the shot, flight seconds, end Vector3]


func start(peer: int, path: PackedVector3Array, hz: float) -> void:
	if not _lines.has(peer):
		var line := DiscTracer.new()
		add_child(line)
		_lines[peer] = line
	var tr: DiscTracer = _lines[peer]
	tr.show_path(path)
	tr.set_progress(0.0)
	_time[peer] = [0.0, maxf(0.0, path.size() - 1) / hz, path[path.size() - 1] if path.size() > 0 else Vector3.ZERO]


func clear(peer: int) -> void:
	if _lines.has(peer):
		(_lines[peer] as DiscTracer).visible = false
	_time.erase(peer)


func _process(delta: float) -> void:
	for peer: int in _time.keys():
		var t: Array = _time[peer]
		t[0] = float(t[0]) + delta
		var dur := float(t[1])
		(_lines[peer] as DiscTracer).set_progress(clampf(float(t[0]) / dur, 0.0, 1.0) if dur > 0.0 else 1.0)
		if float(t[0]) >= dur + 1.0 and _near(peer, t[2]):
			clear(peer)


func _near(peer: int, at: Vector3) -> bool:
	for p in get_tree().get_nodes_in_group("players"):
		if p.get("peer_id") == peer:
			return (p as Node3D).global_position.distance_to(at) <= NEAR_M
	return true  # they left: nothing to keep it for
