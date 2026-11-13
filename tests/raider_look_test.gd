# RaiderLookTest — screenshots of the raider models (D-061): hosts a throwaway world, lines up every raider_* model
# (gear on, weapon out) and saves res://tests/_look/raider_row.png (front), raider_side.png (3/4 from the side),
# raider_head_<n>.png (close-ups of each head and shoulders). Depends on: scenes/main.tscn, CharacterAnimator, SaveStore.
extends Node

const OUT_DIR := "res://tests/_look"

var _row: Array = []


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz raiders look")
	main._on_host_pressed()
	await get_tree().create_timer(5.0).timeout
	var zd := get_tree().get_first_node_in_group("zombie_director")
	zd.set_physics_process(false)
	for z in zd.get_children():
		if z.net_active:
			z.deactivate()
	var w: Node = main.get_node("World")
	var origin: Vector3 = w.spawn_hint + Vector3(-20.0, 0.0, 30.0)
	origin.y = _ground(origin)
	var ids: Array = []
	for id: String in DataLoader.load_json(CharacterAnimator.DATA_PATH).models:
		if id.begins_with("raider_"):
			ids.append(id)
	for i in ids.size():
		var a := CharacterAnimator.new()
		add_child(a)
		a.global_position = origin + Vector3(i * 1.2 - ids.size() * 0.6, 0.0, 0.0)
		a.rotation.y = PI
		a.set_model(str(ids[i]))
		a.set_weapon_slot(1 if "brute" in str(ids[i]) else 0)
		_row.append(a)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 60.0
	cam.global_position = origin + Vector3(0.0, 1.4, 5.5)
	cam.look_at(origin + Vector3(0.0, 1.0, 0.0))
	cam.make_current()
	await _animate(60)
	await _shot("raider_row.png")
	cam.global_position = origin + Vector3(-ids.size() * 0.6 - 3.0, 1.6, 2.5)
	cam.look_at(origin + Vector3(0.0, 1.1, 0.0))
	await _animate(10)
	await _shot("raider_side.png")
	for i in _row.size():
		var a: Node3D = _row[i]
		cam.global_position = a.global_position + Vector3(0.7, 1.75, 1.3)
		cam.look_at(a.global_position + Vector3(0.0, 1.45, 0.0))
		await _animate(5)
		await _shot("raider_head_%d.png" % i)
	SaveStore.delete(main.saves.world_slug)
	await get_tree().create_timer(3.0).timeout
	get_tree().quit()


func _animate(frames: int) -> void:
	for f in frames:
		for a: CharacterAnimator in _row:
			a.update(1.0 / 60.0, false, false, 100.0, true, false)
		await get_tree().process_frame


func _ground(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 300, p.z), Vector3(p.x, -300, p.z), 1)
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else 0.0


func _shot(file: String) -> void:
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT_DIR + "/" + file)
