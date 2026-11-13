# ZombieLookTest — screenshots of the animated zombies (D-045): hosts a throwaway world, activates four pooled
# zombies (one per model) in a row on open ground near the bunker, photographs them standing, then walking off,
# then one attacking and one dying (health set to 0 on the host), saving PNGs to res://tests/_look/zombie_*.png and
# printing each one's model and current clip. Run this scene directly. Depends on: scenes/main.tscn, SaveStore.
extends Node

const OUT_DIR := "res://tests/_look"


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz zombies")
	main._on_host_pressed()
	await get_tree().create_timer(5.0).timeout
	var w: Node = main.get_node("World")
	var origin: Vector3 = w.spawn_hint + Vector3(-20.0, 0.0, 30.0)
	var zd := get_tree().get_first_node_in_group("zombie_director")
	zd.set_physics_process(false)  # no new spawns during the test
	for z in zd.get_children():
		if z.net_active:
			z.deactivate()
	var row: Array = []
	for i in 4:
		var z: Node = zd.get_child(i)
		var p := origin + Vector3(i * 1.6 - 2.4, 0.0, 0.0)
		p.y = _ground(p) + 0.1
		z.activate(p)
		z.rotation.y = PI  # face the camera
		row.append(z)
	var me: Node3D = get_tree().get_first_node_in_group("local_player")
	me.global_position = origin + Vector3(0, 0, 60.0)  # far away so they don't chase yet
	var cam := Camera3D.new()
	cam.fov = 60.0
	add_child(cam)
	cam.make_current()
	cam.global_position = origin + Vector3(0.0, 1.6, 5.5)
	cam.look_at(origin + Vector3(0.0, 1.0, 0.0))
	await _shot("zombie_idle.png", row)
	for z in row:
		z.nav.target_position = z.global_position + Vector3(0, 0, -12.0)
		z.brain.state = ZombieBrain.State.INVESTIGATE
	await _shot("zombie_walk.png", row)
	me.global_position = row[1].global_position + Vector3(0, 0, 1.2)
	await get_tree().create_timer(1.5).timeout
	await _shot("zombie_attack.png", row)
	row[2].health.apply_damage(1000.0, 0)
	await _shot("zombie_death.png", row)
	SaveStore.delete(main.saves.world_slug)
	await get_tree().create_timer(20.0).timeout
	get_tree().quit()


func _ground(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 200, 0), p - Vector3(0, 200, 0), 1)
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else 0.0


func _shot(path: String, row: Array) -> void:
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT_DIR + "/" + path)
	var states: Array = []
	for z in row:
		states.append("%s/%s" % [z.body._def.get("gltf", "?"), z.body._current])
	print("ZLOOK: %s %s" % [path, states])
