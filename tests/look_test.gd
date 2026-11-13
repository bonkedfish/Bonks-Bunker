# LookTest — screenshots of the generated town for checking building looks (D-041): hosts a throwaway world,
# then from a few street spots near the bunker takes eye-height shots in four directions plus one high view,
# saving PNGs to res://tests/_look/ (has a .gdignore so the editor does not import them). Run this scene directly after the map pipeline.
# Depends on: scenes/main.tscn, WorldStreamer ("World" node), SaveStore.
extends Node

const OUT_DIR := "res://tests/_look"
const SPOTS := [Vector2(-20.0, 30.0), Vector2(60.0, -40.0)]


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz look")
	main._on_host_pressed()
	await get_tree().create_timer(5.0).timeout
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	FileAccess.open(OUT_DIR + "/.gdignore", FileAccess.WRITE).close()
	var cam := Camera3D.new()
	cam.fov = 75.0
	add_child(cam)
	cam.make_current()
	var w: Node = main.get_node("World")
	var origin: Vector3 = w.spawn_hint
	var n := 0
	for s: Vector2 in SPOTS:
		var p := Vector3(origin.x + s.x, 0.0, origin.z + s.y)
		p.y = _ground(p) + 1.7
		for yaw in [0.0, 90.0, 180.0, 270.0]:
			cam.global_position = p
			cam.rotation_degrees = Vector3(-3.0, yaw, 0.0)
			n += 1
			await _shot(cam, "street_%d.png" % n)
	cam.global_position = origin + Vector3(-60.0, 45.0, 60.0)
	cam.look_at(origin + Vector3(10.0, 0.0, -10.0))
	await _shot(cam, "high.png")
	print("LOOK: %d shots in %s" % [n + 1, ProjectSettings.globalize_path(OUT_DIR)])
	SaveStore.delete(main.saves.world_slug)
	await get_tree().create_timer(20.0).timeout
	get_tree().quit()


func _ground(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 200, 0), p - Vector3(0, 200, 0), 1)
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else 0.0


func _shot(cam: Camera3D, path: String) -> void:
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "/" + path)
	print("LOOK: %s at %s" % [path, cam.global_position.snapped(Vector3.ONE * 0.1)])
