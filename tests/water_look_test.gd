# WaterLookTest — checks the D-047 water: hosts a throwaway world, takes screenshots of Yanney Park Lake, the
# Tailrace canal behind the house and the Platte channel into res://tests/_look/water_*.png, probes water surface
# and bed heights, then drops the local player into the lake and reports whether it swims and floats.
# Results also go to tests/_look/water_result.txt. Depends on: scenes/main.tscn, SaveStore, MovementRules.
extends Node

const OUT_DIR := "res://tests/_look"
const SHOTS := [
	["water_lake_shore.png", Vector3(-110, 1.7, 200), Vector3(-270, 0, 200)],
	["water_lake_high.png", Vector3(-120, 70, 470), Vector3(-280, 0, 150)],
	["water_canal.png", Vector3(-45, 1.7, 120), Vector3(-86, 0, 60)],
	["water_canal_high.png", Vector3(-20, 45, 90), Vector3(-86, 0, 0)],
	["water_platte.png", Vector3(0, 1.7, 440), Vector3(0, 0, 560)],
]
const PROBES := [Vector2(-270, 180), Vector2(-300, 0), Vector2(-78, 60), Vector2(-77, 300), Vector2(0, 560)]

var _log := PackedStringArray()


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz water")
	main._on_host_pressed()
	await get_tree().create_timer(4.0).timeout
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var player: Node3D = null
	for n: Node in get_tree().get_nodes_in_group("players"):
		if "water" in n:
			player = n
	var cam := Camera3D.new()
	cam.fov = 75.0
	add_child(cam)
	for s: Array in SHOTS:
		var p: Vector3 = s[1]
		player.global_position = Vector3(p.x, maxf(_ray(p, 17), 0.0) + 10.0, p.z)  # streams the cells in
		await get_tree().create_timer(3.0).timeout
		cam.make_current()
		var at: Vector3 = s[2]
		cam.global_position = Vector3(p.x, _ray(p, 17) + p.y, p.z)
		cam.look_at(Vector3(at.x, _ray(at, 17), at.z))
		await get_tree().create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUT_DIR + "/" + str(s[0]))
		_say("shot %s" % s[0])
		for q: Vector2 in PROBES:
			var v := Vector3(q.x, 0, q.y)
			var s_y := _ray(v, 32)
			if s_y > -9000.0 and not _said(q):
				_say("probe %s: surface %.2f bed %.2f depth %.2f" % [q, s_y, _ray(v, 16), s_y - _ray(v, 16)])
	# Swim check: drop the player into the deepest probe.
	var lake := Vector3(-270, 0, 180)
	player.global_position = Vector3(lake.x, _ray(lake, 32) + 0.5, lake.z)
	player.velocity = Vector3.ZERO
	await get_tree().create_timer(4.0).timeout
	var surf := _ray(lake, 32)
	_say("swim: water mode %d (2 = swim), feet %.2f below surface, eye %.2f above" % [player.water,
		surf - player.global_position.y, player.eye_position().y - surf])
	var canal := Vector3(-78, 0, 60)
	player.global_position = Vector3(canal.x, _ray(canal, 32) + 0.5, canal.z)
	await get_tree().create_timer(3.0).timeout
	_say("canal: water mode %d, feet %.2f below surface" % [player.water, _ray(canal, 32) - player.global_position.y])
	var f := FileAccess.open(OUT_DIR + "/water_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	await get_tree().create_timer(20.0).timeout
	get_tree().quit()


var _probed := {}
func _said(q: Vector2) -> bool:
	var was := _probed.has(q)
	_probed[q] = true
	return was


func _ray(p: Vector3, mask: int) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 500, p.z), Vector3(p.x, -500, p.z), mask)
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else -9999.0


func _say(s: String) -> void:
	print("WATER: " + s)
	_log.append(s)
