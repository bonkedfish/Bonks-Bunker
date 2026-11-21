# SuitLook — close-up lineup of the D-102/D-104 character looks (suit_watcher, suit_handler, retriever_m) with no
# world loaded, to fit their primitive gear. Results: tests/_look/suit_lineup_front.png, suit_lineup_side.png.
# Depends on: CharacterAnimator, data/art/character_models.json.
extends Node3D

const MODELS := ["suit_watcher", "suit_handler", "retriever_m"]


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.6, 0.68)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	add_child(sun)
	var log := PackedStringArray()
	var i := 0
	for id: String in MODELS:
		var a := CharacterAnimator.new()
		add_child(a)
		var ok := a.set_model(id)
		a.position = Vector3((i - 1) * 1.3, 0, 0)
		log.append("%s: %s" % [id, "loaded" if ok else "FAILED"])
		i += 1
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true
	for view: Array in [["suit_lineup_front.png", Vector3(0, 1.3, -5.0)], ["suit_lineup_side.png", Vector3(5.0, 1.3, -1.0)]]:
		cam.look_at_from_position(view[1], Vector3(0, 1.0, 0))
		for f in 20:
			for c in get_children():
				if c is CharacterAnimator:
					c.update(0.016, false, false, 100.0)
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/_look/" + str(view[0])))
	var f := FileAccess.open("res://tests/_look/suit_look.txt", FileAccess.WRITE)
	f.store_string("\n".join(log))
	f.close()
	get_tree().quit()
