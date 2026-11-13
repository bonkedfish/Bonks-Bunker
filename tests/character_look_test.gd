# CharacterLookTest — screenshots of the survivor models (D-045): hosts a throwaway world, then saves to
# res://tests/_look/: chars_fp_gun.png / chars_fp_bat.png (the local player's own first-person arms with each
# weapon), chars_row.png (all four survivors standing in a row as other players would see them, pistol out) and
# chars_bonk.png (Bonk). Run this scene directly. Depends on: scenes/main.tscn, CharacterAnimator, SaveStore.
extends Node

const OUT_DIR := "res://tests/_look"


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz chars")
	main._on_host_pressed()
	await get_tree().create_timer(5.0).timeout
	var zd := get_tree().get_first_node_in_group("zombie_director")
	zd.set_physics_process(false)
	for z in zd.get_children():
		if z.net_active:
			z.deactivate()
	var me: Node3D = get_tree().get_first_node_in_group("local_player")
	await _shot("chars_fp_gun.png")
	me._select_slot(1)
	await _shot("chars_fp_bat.png")
	me._select_slot(0)

	var w: Node = main.get_node("World")
	var origin: Vector3 = w.spawn_hint + Vector3(-20.0, 0.0, 30.0)
	origin.y = _ground(origin)
	var row: Array = []
	var ids := ["survivor_lis", "survivor_matt", "survivor_sam", "survivor_shaun"]
	for i in ids.size():
		var a := CharacterAnimator.new()
		add_child(a)
		a.global_position = origin + Vector3(i * 1.2 - 1.8, 0.0, 0.0)
		a.rotation.y = PI  # face the camera at +Z
		a.set_model(ids[i])
		a.set_weapon_slot(0)
		row.append(a)
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = origin + Vector3(0.0, 1.5, 4.5)
	cam.look_at(origin + Vector3(0.0, 1.0, 0.0))
	cam.make_current()
	for f in 60:
		for a: CharacterAnimator in row:
			a.update(1.0 / 60.0, false, false, 100.0, true, false)
		await get_tree().process_frame
	await _shot("chars_row.png")
	var bonk: Node3D = get_tree().get_first_node_in_group("bonk")
	cam.global_position = bonk.global_position + bonk.global_basis.z * -3.0 + Vector3(0, 1.4, 0)
	cam.look_at(bonk.global_position + Vector3(0, 1.0, 0))
	await _shot("chars_bonk.png")
	SaveStore.delete(main.saves.world_slug)
	await get_tree().create_timer(20.0).timeout
	get_tree().quit()


func _ground(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 200, 0), p - Vector3(0, 200, 0), 1)
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else 0.0


func _shot(path: String) -> void:
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT_DIR + "/" + path)
	print("CLOOK: %s" % path)
