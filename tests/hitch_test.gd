# HitchTest — hunts frame spikes (D-047 follow-up): hosts a throwaway world, runs the local player at sprint speed
# along a route (house -> gardens -> tower), puts it on the tower deck and turns it 360 deg in steps, then runs on
# past the lake; logs every frame over 25 ms with where it happened, plus WorldStreamer.slow_events (cell adds /
# blocking loads over slow_ms). Results to tests/_look/hitch_result.txt. Depends on: scenes/main.tscn, SaveStore.
extends Node

const ROUTE := [Vector2(0, 0), Vector2(-250, -120), Vector2(-375, -190), Vector2(-327, 30)]
const ROUTE2 := [Vector2(-327, 30), Vector2(-120, 150), Vector2(-150, 450), Vector2(-383, 257)]
const SPEED := 10.0  # faster than sprint: worst case for streaming

var _log := PackedStringArray()
var _player: Node3D
var _stage := ""
var _t0 := 0


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz hitch")
	main._on_host_pressed()
	await get_tree().create_timer(5.0).timeout
	for n: Node in get_tree().get_nodes_in_group("players"):
		if "water" in n:
			_player = n
	var w: Node = main.get_node("World")
	w.slow_events.clear()
	_t0 = Time.get_ticks_msec()
	_stage = "run to tower"
	await _run(ROUTE)
	var tower: Node3D = get_tree().root.find_child("yanney_tower", true, false)
	_stage = "tower deck spin"
	_player.global_position = tower.global_position + Vector3(2.5, 21.2, -2.0)
	_player.velocity = Vector3.ZERO
	await get_tree().create_timer(2.0).timeout
	for i in 12:
		_player.yaw = TAU * i / 12.0
		await get_tree().create_timer(0.7).timeout
	_stage = "run past lake"
	await _run(ROUTE2)
	_say("--- streamer slow events ---")
	for e in w.slow_events:
		_say(e)
	var f := FileAccess.open("res://tests/_look/hitch_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	await get_tree().create_timer(20.0).timeout
	get_tree().quit()


func _process(delta: float) -> void:
	if _stage != "" and delta > 0.025:
		var p := _player.global_position if _player else Vector3.ZERO
		_say("%.1f s: %.1f ms frame during '%s' at (%d, %d, %d) yaw %d" % [Time.get_ticks_msec() / 1000.0, delta * 1000.0,
			_stage, p.x, p.y, p.z, rad_to_deg(_player.yaw) if _player else 0])


# Moves the player along points at SPEED (placed on the ground every physics frame, so no input needed).
func _run(points: Array) -> void:
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var t := 0.0
		var dur := a.distance_to(b) / SPEED
		_player.yaw = atan2(-(b - a).x, -(b - a).y)
		while t < dur:
			t += get_physics_process_delta_time()
			var p := a.lerp(b, t / dur)
			_player.global_position = Vector3(p.x, _ground(p) + 0.1, p.y)
			_player.velocity = Vector3.ZERO
			await get_tree().physics_frame


func _ground(p: Vector2) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 300, p.y), Vector3(p.x, -300, p.y), 17)
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else 5.0


func _say(s: String) -> void:
	print("HITCH: " + s)
	_log.append(s)
