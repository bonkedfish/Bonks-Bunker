# UbcLookTest — screenshots of the Quaternius base-body player models (D-058): hosts a throwaway world, lines up all
# ubc_* models (outfit, hair, pistol out) and saves res://tests/_look/ubc_row.png, ubc_walk.png (walking), ubc_hand.png
# (close-up of the pistol in the hand), ubc_bat.png (bat out). Depends on: scenes/main.tscn, CharacterAnimator, SaveStore.
extends Node

const OUT_DIR := "res://tests/_look"

var _row: Array = []


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz ubc")
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
		if id.begins_with("ubc_"):
			ids.append(id)
	for i in ids.size():
		var a := CharacterAnimator.new()
		add_child(a)
		a.global_position = origin + Vector3(i * 1.1 - ids.size() * 0.55, 0.0, 0.0)
		a.rotation.y = PI
		a.set_model(str(ids[i]))
		a.set_weapon_slot(0)
		_row.append(a)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 60.0
	cam.global_position = origin + Vector3(0.0, 1.4, 5.0)
	cam.look_at(origin + Vector3(0.0, 1.0, 0.0))
	cam.make_current()
	await _animate(60, Vector3.ZERO, true)
	await _shot("ubc_row.png")
	await _animate(60, Vector3(0, 0, 0.06), false)
	await _shot("ubc_walk.png")
	var a0: CharacterAnimator = _row[0]
	cam.global_position = a0.global_position + Vector3(-0.9, 1.2, 0.6)
	cam.look_at(a0.global_position + Vector3(0, 1.0, 0))
	await _animate(30, Vector3.ZERO, true)
	await _shot("ubc_hand.png")
	# Pistol orientation candidates, one per model left to right (tuning aid).
	var cands := [Vector3(0, 90, 90)]  # chosen: [0, 90, 90] grip down, barrel forward (tried [0,90,0] down, [0,90,-90] backwards, x +-90 / 180 off)
	for i in _row.size():
		for m: Node in (_row[i] as Node).find_children("Pistol", "MeshInstance3D", true, false):
			(m as Node3D).rotation_degrees = cands[i % cands.size()]
	cam.global_position = _row[0].global_position + Vector3(-1.6, 1.5, 1.4)
	cam.look_at(_row[0].global_position + Vector3(2.75, 1.1, 0))
	await _animate(20, Vector3.ZERO, true)
	await _shot("ubc_pistol_cands.png")
	for i in _row.size():  # side close-ups, one per candidate
		cam.global_position = _row[i].global_position + Vector3(-0.55, 1.25, 0.25)
		cam.look_at(_row[i].global_position + Vector3(0.0, 1.15, 0.35))
		await _animate(5, Vector3.ZERO, true)
		await _shot("ubc_cand_%d.png" % i)
	for a: CharacterAnimator in _row:
		a.set_weapon_slot(1)
	await _animate(30, Vector3.ZERO, false)
	await _shot("ubc_bat.png")
	SaveStore.delete(main.saves.world_slug)
	await get_tree().create_timer(3.0).timeout
	get_tree().quit()


func _animate(frames: int, step: Vector3, armed: bool) -> void:
	for f in frames:
		for a: CharacterAnimator in _row:
			a.global_position += step
			a.update(1.0 / 60.0, false, false, 100.0, armed, false)
		await get_tree().process_frame


func _ground(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 300, p.z), Vector3(p.x, -300, p.z), 1)
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else 0.0


func _shot(file: String) -> void:
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT_DIR + "/" + file)
