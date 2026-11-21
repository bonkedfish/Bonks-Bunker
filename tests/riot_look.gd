# RiotLook — close-up of one enemy type's body (default the Riot Cop) from the front and the side, with no world
# loaded, to fit primitive gear to the zombie rig. Results: tests/_look/riot_front.png, riot_side.png.
# Depends on: scenes/zombie.tscn, EnemyDB, CharacterAnimator.
extends Node3D

const ZombieScript := preload("res://scripts/ai/zombie.gd")
const ENEMY := "zombie_riot"


func _ready() -> void:
	ZombieScript.frozen = true
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
	var z: Node = load("res://scenes/zombie.tscn").instantiate()
	z.net_enemy = ENEMY
	add_child(z)
	z.setup(EnemyDB.get_enemy(ENEMY), 5.0, 1.0)
	z.net_active = true
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true
	for view: Array in [["riot_front.png", Vector3(0, 1.3, -3.2)], ["riot_side.png", Vector3(3.2, 1.3, 0)]]:
		cam.look_at_from_position(view[1], Vector3(0, 1.0, 0))
		for i in 20:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/_look/" + str(view[0])))
	get_tree().quit()
