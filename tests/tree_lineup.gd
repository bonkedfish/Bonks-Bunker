# TreeLineup — photographs the baked D-098 species and plant meshes side by side (no map needed): trees at their
# mean height in a row (built fresh from TreeMesh), then the bushes and ground plants up close. Run after build_cells (it makes the meshes).
# Results: tests/_look/tree_lineup_trees.png, tree_lineup_small.png.
# Depends on: TreeMesh, data/art/vegetation.json (species, plants, out_dir), the baked bush/plant meshes under out_dir.
extends Node3D

const OUT_DIR := "res://tests/_look"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var veg := DataLoader.load_json("res://data/art/vegetation.json")
	var dir := str(veg.out_dir)
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.24, 0.45, 0.76)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.45, 0.4, 0.3)
	ground.material_override = gmat
	add_child(ground)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	# trees: one row, labelled by order (elm, ash, maple, cottonwood, honey locust, willow, spruce, pine, cedar)
	var x := 0.0
	var small: Array = []
	for id: String in veg.species:
		var sp: Dictionary = veg.species[id]
		if bool(sp.get("bush", false)):
			small.append(["%s/tree_%s_%%d.res" % [dir, id], float(sp.height_m[0] + sp.height_m[1]) * 0.5, int(sp.variants)])
			continue
		var h := float(sp.height_m[0] + sp.height_m[1]) * 0.5
		x += h * 0.45
		_put_built(sp, Vector3(x, 0, 0), h)  # built fresh from the current TreeMesh, so shape edits show without a re-bake
		x += h * 0.45 + 2.0
	for id: String in veg.plants:
		var p: Dictionary = veg.plants[id]
		small.append(["%s/plant_%s_%%d.res" % [dir, id], float(p.height_m[0] + p.height_m[1]) * 0.5, int(p.variants)])
	cam.position = Vector3(x * 0.5, 9.0, x * 0.62)
	cam.look_at(Vector3(x * 0.5, 7.0, 0))
	await _shot("tree_lineup_trees.png")
	# small things: a row at z = 40
	var sx := 0.0
	for s: Array in small:
		for v in s[2]:
			_put(str(s[0]) % v, Vector3(sx, 0, 40), s[1])
			sx += maxf(1.2, s[1] * 1.2)
		sx += 1.0
	cam.position = Vector3(sx * 0.5, 2.2, 40 + sx * 0.55)
	cam.look_at(Vector3(sx * 0.5, 0.6, 40))
	await _shot("tree_lineup_small.png")
	get_tree().quit()


func _put(path: String, at: Vector3, height: float) -> void:
	if not ResourceLoader.exists(path):
		push_warning("TreeLineup: no mesh " + path)
		return
	var mi := MeshInstance3D.new()
	mi.mesh = load(path)
	mi.position = at
	var h := maxf(mi.mesh.get_aabb().size.y, 0.01)
	mi.scale = Vector3.ONE * height / h
	add_child(mi)


func _put_built(sp: Dictionary, at: Vector3, height: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9898
	var r := float(sp.trunk_radius_m[0] + sp.trunk_radius_m[1]) * 0.5 / float(sp.height_m[1])
	var c: Array = sp.canopy_colors[0]
	var b: Array = sp.bark_color
	var mesh := TreeMesh.build_species(rng, sp, r * 1.6, Color(b[0], b[1], b[2]), Color(c[0], c[1], c[2]))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.scale = Vector3.ONE * height / maxf(mesh.get_aabb().size.y, 0.01)
	add_child(mi)


func _shot(file: String) -> void:
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR + "/" + file))
