# ZombieVoices — groans and breathing from the zombies nearest the camera (D-114). Main child "ZombieVoices".
# Only the nearest `budget` zombies with scare traits within groan_m get a voice (so a horde never steals the
# voices gunfire needs); each groans every groan_gap_min_s..max_s, and one within breath_m rasps instead.
# The groan gets louder as it closes in because it is a 3D sound at the zombie. Presentation only, every peer.
# Depends on: ZombieScare (tuning), Sfx; group "hittable".
class_name ZombieVoices
extends Node

var _v: Dictionary
var _scan := 0.0
var _next: Dictionary = {}  # zombie instance id -> time (s) it may make a sound again
var _near: Array[Node] = []
var _near_d := PackedFloat32Array()


func _ready() -> void:
	_v = ZombieScare.load_tuning().voices
	_near.resize(int(_v.budget))
	_near_d.resize(int(_v.budget))


func _process(delta: float) -> void:
	_scan -= delta
	if _scan > 0.0:
		return
	_scan = float(_v.scan_s)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var from := cam.global_position
	var n_budget := _near.size()
	for i in n_budget:
		_near[i] = null
		_near_d[i] = INF
	var max_sq := float(_v.groan_m) * float(_v.groan_m)
	for n in get_tree().get_nodes_in_group("hittable"):
		if not n.has_method("has_scare") or not n.has_scare() or not n.net_active or n.health.is_dead() \
				or n.net_pose == ZombieScare.Pose.DOWN:  # a feigner plays dead quietly
			continue
		var dsq: float = from.distance_squared_to(n.global_position)
		if dsq > max_sq or dsq >= _near_d[n_budget - 1]:
			continue
		var j := n_budget - 1  # insertion into the sorted nearest list
		while j > 0 and _near_d[j - 1] > dsq:
			_near[j] = _near[j - 1]
			_near_d[j] = _near_d[j - 1]
			j -= 1
		_near[j] = n
		_near_d[j] = dsq
	var now := Time.get_ticks_msec() / 1000.0
	var breath_sq := float(_v.breath_m) * float(_v.breath_m)
	for i in n_budget:
		var z: Node = _near[i]
		if z == null:
			break
		var id := z.get_instance_id()
		if not _next.has(id):
			_next[id] = now + randf_range(0.0, float(_v.groan_gap_max_s))  # don't all start at once
			continue
		if now < float(_next[id]):
			continue
		var at: Vector3 = z.global_position + Vector3.UP * 1.5
		if _near_d[i] < breath_sq:
			Sfx.play_at("zombie_breath", at)
			_next[id] = now + float(_v.breath_gap_s)
		else:
			Sfx.play_at("zombie_groan", at)
			_next[id] = now + randf_range(float(_v.groan_gap_min_s), float(_v.groan_gap_max_s))
