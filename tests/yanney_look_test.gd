# YanneyLookTest — checks the Yanney Park landmarks (D-047): hosts a throwaway world, screenshots the tower, gardens,
# pavilion, amphitheater, ERC/marina and splashground into res://tests/_look/yanney_*.png, then walks the local
# player up the Gottschalk Tower stair cage (scripted move_forward input) and screenshots the view from the deck.
# Results also go to tests/_look/yanney_result.txt. Depends on: scenes/main.tscn, SaveStore, LandmarkLoader nodes.
extends Node

const OUT_DIR := "res://tests/_look"
const SHOTS := [
	["yanney_tower.png", Vector3(-348, 1.7, 18), Vector3(-327, 12, 42)],
	["yanney_gardens_air.png", Vector3(-290, 70, -95), Vector3(-375, 0, -190)],
	["yanney_gardens_ground.png", Vector3(-392, 1.7, -140), Vector3(-430, 1, -150)],
	["yanney_pavilion.png", Vector3(-335, 1.7, -168), Vector3(-299, 3, -180)],
	["yanney_amphitheater.png", Vector3(-310, 4.0, 78), Vector3(-280, 4, 122)],
	["yanney_erc.png", Vector3(-306, 3.0, 228), Vector3(-340, 2, 205)],
	["yanney_splashground.png", Vector3(-362, 9.0, 232), Vector3(-383, 0, 257)],
]

var _log := PackedStringArray()
var _player: Node3D
var _cam: Camera3D


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz yanney")
	main._on_host_pressed()
	await get_tree().create_timer(4.0).timeout
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for n: Node in get_tree().get_nodes_in_group("players"):
		if "water" in n:
			_player = n
	_cam = Camera3D.new()
	_cam.fov = 75.0
	add_child(_cam)
	for s: Array in SHOTS:
		var p: Vector3 = s[1]
		_player.global_position = Vector3(p.x, 40.0, p.z - 30.0)
		_player.velocity = Vector3.ZERO
		await get_tree().create_timer(3.0).timeout
		var g := _ray(p)
		_cam.make_current()
		_cam.global_position = Vector3(p.x, g + p.y, p.z)
		var at: Vector3 = s[2]
		_cam.look_at(Vector3(at.x, _ray(at) + at.y, at.z))
		await _shot(str(s[0]))
	await _climb()
	var f := FileAccess.open(OUT_DIR + "/yanney_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SaveStore.delete(main.saves.world_slug)
	await get_tree().create_timer(20.0).timeout
	get_tree().quit()


func _climb() -> void:
	var tower: Node3D = get_tree().root.find_child("yanney_tower", true, false)
	if tower == null:
		_say("climb: no yanney_tower node")
		return
	var o := tower.global_position
	_player.global_position = o + Vector3(-4.5, 0.3, 3.0)
	_player.velocity = Vector3.ZERO
	var pc: Camera3D = _player.get_node("Head/Camera3D") if _player.has_node("Head/Camera3D") else null
	if pc:
		pc.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().create_timer(1.0).timeout
	var path: Array[Vector2] = [Vector2(-1.0, 3.0)]
	for i in 16:
		if i % 2 == 0:
			path.append_array([Vector2(-1.0, 6.2), Vector2(1.0, 6.2)])
		else:
			path.append_array([Vector2(1.0, 3.0), Vector2(-1.0, 3.0)])
	path.append(Vector2(3.0, -2.5))
	var t0 := Time.get_ticks_msec()
	for wp: Vector2 in path:
		var target := Vector3(o.x + wp.x, 0, o.z + wp.y)
		var start := Time.get_ticks_msec()
		while Time.get_ticks_msec() - start < 6000:
			var to := target - _player.global_position
			to.y = 0.0
			if to.length() < 0.3:
				break
			_player.yaw = atan2(-to.x, -to.z)
			Input.action_press("move_forward")
			await get_tree().physics_frame
		Input.action_release("move_forward")
	await get_tree().create_timer(0.5).timeout
	var h := _player.global_position.y - o.y
	_say("climb: %.1f s, ended %.2f m above the tower base at local %s (deck is 21 m)" % [
		(Time.get_ticks_msec() - t0) / 1000.0, h, (_player.global_position - o).snapped(Vector3.ONE * 0.1)])
	_player.yaw = atan2(-(-48.0), -(-232.0))  # toward the gardens (NNW)
	_player.pitch = -0.25
	await _shot("yanney_from_tower_gardens.png")
	_player.yaw = atan2(-(80.0), -(110.0))     # toward the lake + amphitheater (SE)
	await _shot("yanney_from_tower_lake.png")


func _ray(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 300, p.z), Vector3(p.x, -300, p.z), 17)
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else 0.0


func _shot(file: String) -> void:
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT_DIR + "/" + file)
	_say("shot " + file)


func _say(s: String) -> void:
	print("YANNEY: " + s)
	_log.append(s)
