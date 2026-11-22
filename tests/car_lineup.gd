# CarLineup — D-116 vehicles: builds every car_* clutter prop the way build_cells does (VegetationBuilder: merge,
# fit to length along +Z, LODs) and lines them up with name labels: one screenshot from the side and one looking
# back at their fronts (camera on +Z), so the "flip" values in data/art/clutter.json can be checked by eye.
# Logs each car's fitted size, triangles, LOD count and draw time.
# Results: tests/_look/car_lineup.txt; car_lineup_side.png, car_lineup_front.png.
# Depends on: VegetationBuilder (tools), data/art/clutter.json.
extends Node3D

const OUT_DIR := "res://tests/_look"

var _log := PackedStringArray()


func _ready() -> void:
	var src := DataLoader.load_json("res://data/art/clutter.json")
	var only := {"models_dir": src.models_dir, "out_dir": OUT_DIR + "/car_assets", "block_m": 64.0, "props": {}, "placement": {}}
	for k: String in src.props:
		if k.begins_with("car_") or k == "covered_car":
			only.props[k] = src.props[k]
	var f := FileAccess.open(OUT_DIR + "/car_lineup.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(only))
	f.close()
	var b := VegetationBuilder.new(OUT_DIR + "/car_lineup.json", "Cars")
	if b.error != "":
		_log.append("ERROR " + b.error)
		_finish()
		return
	b.make_assets()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.6, 0.65, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	add_child(env)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 40)
	ground.mesh = pm
	add_child(ground)
	var keys: Array = b.kinds.keys()
	keys.sort()
	var x := 0.0
	for k: String in keys:
		var mesh: Mesh = b.kinds[k].meshes[0]
		var box := mesh.get_aabb()
		x += box.size.x * 0.5 + 1.5
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = Vector3(x, 0, 0)
		add_child(mi)
		var lab := Label3D.new()
		lab.text = k.trim_prefix("car_")
		lab.font_size = 96
		lab.pixel_size = 0.01
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.position = Vector3(x, box.size.y + 0.8, 0)
		add_child(lab)
		var tris := 0
		for s in mesh.get_surface_count():
			tris += mesh.surface_get_array_index_len(s) / 3
		var lods: int = RenderingServer.mesh_get_surface(mesh.get_rid(), 0).get("lods", []).size()
		_log.append("%-18s %5.2f x %4.2f x %5.2f m (w x h x l), %6d triangles, %d surfaces, %d LODs" % [k, box.size.x, box.size.y, box.size.z, tris, mesh.get_surface_count(), lods])
		x += box.size.x * 0.5 + 1.5
	var cam := Camera3D.new()
	cam.fov = 60
	add_child(cam)
	cam.position = Vector3(x * 0.5, 4.0, 16.0)
	cam.look_at(Vector3(x * 0.5, 0.8, 0))
	cam.make_current()
	await get_tree().create_timer(1.5).timeout
	await _shot("car_lineup_front.png")
	cam.position = Vector3(x * 0.5, 30.0, 0.01)
	cam.look_at(Vector3(x * 0.5, 0, 0))
	await get_tree().create_timer(0.5).timeout
	await _shot("car_lineup_top.png")
	_finish()


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT_DIR + "/" + file)


func _finish() -> void:
	var f := FileAccess.open(OUT_DIR + "/car_lineup.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	get_tree().quit()
