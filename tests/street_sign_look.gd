# StreetSignLook — screenshot of a street sign close up (D-070): offline world, walk to 7th Ave & W 11th St, find the
# nearest sign post in the loaded cells' StreetSigns and look at it from 3.5 m. Output tests/_look/street_sign_close.png.
extends Node


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz signs")
	main.menu.play_offline.emit()
	await get_tree().create_timer(5.0).timeout
	var player: Node3D = get_tree().get_first_node_in_group("local_player")
	var slug: String = main.saves.world_slug
	player.global_position = Vector3(1030, 5, -290)
	await get_tree().create_timer(4.0).timeout
	var best := Vector3.INF
	var best_label: Label3D = null
	for cell in get_tree().get_first_node_in_group("world_streamer").near_loaded.values():
		var h: Node3D = cell.get_node_or_null("StreetSigns")
		if h == null:
			continue
		for c in h.get_children():
			if c is Label3D and c.global_position.distance_to(player.global_position) < best.distance_to(player.global_position):
				best = c.global_position
				best_label = c
	var lines := PackedStringArray()
	if best_label:
		var face: Vector3 = best_label.global_basis.z  # labels face +Z
		var eye := best + face * 3.5
		player.global_position = Vector3(eye.x, eye.y - 1.6, eye.z)
		var d := best - eye
		player.yaw = atan2(-d.x, -d.z)
		player.rotation.y = player.yaw
		player.pitch = atan2(d.y, Vector2(d.x, d.z).length())
		player.head.rotation.x = player.pitch
		lines.append("sign '%s' at %s" % [best_label.text, best])
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/_look/street_sign_close.png")
	var f := FileAccess.open("res://tests/_look/street_sign_close.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	SaveStore.delete(slug)
	get_tree().quit()
