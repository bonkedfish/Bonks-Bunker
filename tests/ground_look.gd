# GroundLook — D-115 realistic ground: layered terrain, abandoned roads and 3D grass. Checks the grass masks exist
# and are low on roads, the refreshed materials carry the new layers, GrassField builds chunks on the high tier;
# screenshots a street at eye level, open ground at eye level, the bonk_house street from above and the country
# club rough; frame time / draw calls / video memory with grass on (high) and off (low).
# Results: tests/_look/ground_result.txt (ends with the failure count); screenshots tests/_look/ground_*.png.
# Depends on: scenes/main.tscn, GrassField ("Grass"), WorldStreamer, data/tuning/grass.json, the cell materials.
extends Node

const OUT_DIR := "res://tests/_look"

var _log := PackedStringArray()
var _fails := 0
var _me: Node3D
var _cam: Camera3D
var _grass: Node
var _streamer: Node


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var ground := load("res://world/generated/cells/materials/ground.tres") as ShaderMaterial
	var asphalt := load("res://world/generated/cells/materials/street_asphalt.tres") as ShaderMaterial
	_check(float(ground.get_shader_parameter("grass2_amount")) > 0.0 and ground.get_shader_parameter("dirt_albedo") != null,
		"ground material has the grass + dirt layers")
	_check(float(asphalt.get_shader_parameter("crack_amount")) > 0.0 and asphalt.get_shader_parameter("edge_albedo") != null
		and asphalt.get_shader_parameter("alt_albedo") != null, "asphalt material has cracks, edge dirt and the second asphalt")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz ground")
	main.menu.play_offline.emit()
	await get_tree().create_timer(5.0).timeout
	var prompt := get_tree().get_first_node_in_group("name_prompt")
	if prompt and prompt.visible:
		prompt.submit("Bonk")
	_me = get_tree().get_first_node_in_group("local_player")
	_me.health.invulnerable = true
	_grass = get_tree().get_first_node_in_group("grass")
	_streamer = get_tree().get_first_node_in_group("world_streamer")
	_check(_grass != null, "Main has the GrassField")
	_grass._apply_tier("high")
	var weather := get_tree().get_first_node_in_group("weather")
	if weather:
		weather.request_mode("clear")
	var dn := get_tree().get_first_node_in_group("daynight")
	if dn:
		dn.hour = 11.0
	var zd := get_tree().get_first_node_in_group("zombie_director")
	if zd:
		zd.set("_spawn_timer", 1.0e9)
	_cam = Camera3D.new()
	_cam.fov = 75.0
	add_child(_cam)
	var home := (get_tree().root.find_child("bonk_house", true, false) as Node3D).global_position
	_me.global_position = home + Vector3(0, 40, 45)
	await get_tree().create_timer(5.0).timeout

	# masks
	var c: Vector2i = _streamer.grid.cell_of(home)
	var mask_path := "res://world/generated/grass/cell_%d_%d.res" % [c.x, c.y]
	_check(ResourceLoader.exists(mask_path), "grass mask exists for the home cell")
	var road := _road_points(home)
	if road.size() == 4:
		var cen: Vector3 = road[2]
		_check(_grass._mask_at(cen.x, cen.z) < 0.45, "mask is low on the road (%.2f at a road triangle's centre)" % _grass._mask_at(cen.x, cen.z))
		await _shot("street_eye", road[0] + Vector3.UP * 1.7, road[1] + Vector3.UP * 0.4)
		asphalt = load("res://world/generated/cells/materials/street_asphalt.tres") as ShaderMaterial
		_log.append("asphalt half-width colour sample: COLOR.b = %s" % str(road[3]))
		var keys := ["alt_mix", "edge_dirt_m", "drift_amount", "crack_amount", "weed_amount", "pothole_amount", "patch_amount"]
		var was := {}
		for k: String in keys:
			was[k] = asphalt.get_shader_parameter(k)
			asphalt.set_shader_parameter(k, 0.0)
		await _shot("street_eye_base", road[0] + Vector3.UP * 1.7, road[1] + Vector3.UP * 0.4)
		var tint: Color = asphalt.get_shader_parameter("tint")
		asphalt.set_shader_parameter("tint", Color(3, 0, 0))
		await _shot("street_eye_red", road[0] + Vector3.UP * 1.7, road[1] + Vector3.UP * 0.4)
		asphalt.set_shader_parameter("tint", tint)
		for cell: Node in _streamer.near_loaded.values():
			var smi := cell.get_node_or_null("Street_asphalt") as MeshInstance3D
			if smi:
				_log.append("cell %s Street_asphalt material: %s (%s)" % [cell.name, smi.material_override.resource_path if smi.material_override else "none",
					str(smi.material_override == asphalt)])
				break
		for k: String in keys:
			asphalt.set_shader_parameter(k, was[k])
	else:
		_check(false, "found an asphalt street near home")
	var open := _open_spot(home)
	if open != Vector3.INF:
		var away := open + (open - home).normalized() * 25.0
		away.y = _ground_y(away) + 0.3
		await _shot("field_eye", open + Vector3.UP * 1.7, away)
		_check(_grass.active.size() > 10 and _grass.built_count > 0, "grass chunks around the camera (%d)" % _grass.active.size())
		var near := 0
		for mmi: MultiMeshInstance3D in _grass.active.values():
			near += mmi.multimesh.instance_count
		_log.append("grass clumps out: %d" % near)
		await get_tree().create_timer(8.0).timeout  # let streaming and shader compiles settle first
		_log.append("grass busy: %s, last chunk build %.2f ms" % [str(_grass.busy()), _grass.build_ms])
		await _perf("grass high")
		_grass._apply_tier("low")
		await get_tree().create_timer(2.0).timeout
		await _perf("grass off (low tier)")
		_grass._apply_tier("high")
		await get_tree().create_timer(4.0).timeout
		await _perf("grass high again")
		_grass._apply_tier("medium")
		await get_tree().create_timer(4.0).timeout
		await _perf("grass medium")
		_grass._apply_tier("high")
	else:
		_check(false, "found open ground near home")
	if open != Vector3.INF:  # D-120: the distance with and without the far blend + broad patches
		var gm := load("res://world/generated/cells/materials/ground.tres") as ShaderMaterial
		var look_to := home + (open - home).normalized() * 380.0
		look_to.y = _ground_y(look_to)
		var eye := home + Vector3.UP * (_ground_y(home) - home.y + 35.0)
		await _shot("far", eye, look_to)
		var was_far: Variant = gm.get_shader_parameter("far_amount")
		var was_macro: Variant = gm.get_shader_parameter("macro")
		var was_hue: Variant = gm.get_shader_parameter("macro_hue")
		gm.set_shader_parameter("far_amount", 0.0)
		gm.set_shader_parameter("macro", 0.0)
		gm.set_shader_parameter("macro_hue", 0.0)
		await _shot("far_base", eye, look_to)
		var was_tint: Variant = gm.get_shader_parameter("tint")
		gm.set_shader_parameter("tint", Color(3, 0, 0))
		await _shot("far_red", eye, look_to)
		gm.set_shader_parameter("tint", was_tint)
		var n_shared := 0
		for cell: Node in _streamer.near_loaded.values():
			var tm := cell.get_node_or_null("Terrain/Mesh") as MeshInstance3D
			if tm and tm.material_override == gm:
				n_shared += 1
		_log.append("near cells using the shared ground material: %d of %d" % [n_shared, _streamer.near_loaded.size()])
		gm.set_shader_parameter("far_amount", was_far)
		gm.set_shader_parameter("macro", was_macro)
		gm.set_shader_parameter("macro_hue", was_hue)
	await _shot("street_above", home + Vector3(0, 20, 45), home + Vector3(0, 0, -30))
	var club := get_tree().root.find_child("country_club", true, false) as Node3D
	if club:
		await _shot("club_rough", club.global_transform * Vector3(-150, 25, -120), club.global_transform * Vector3(-300, 0, -250))
	_log.append("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/ground_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	get_tree().quit()


# Two points along an asphalt strip near `home`, ~25 m apart (world space), or [] if none loaded.
func _road_points(home: Vector3) -> Array:
	var best := Vector3.INF
	var centre := Vector3.INF
	var col := Color()
	var pts := PackedVector3Array()
	for cell: Node in _streamer.near_loaded.values():
		var mi := cell.get_node_or_null("Street_asphalt") as MeshInstance3D
		if mi == null:
			continue
		var arr := mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if centre == Vector3.INF and idx.size() >= 3:
			centre = mi.global_transform * ((verts[idx[0]] + verts[idx[1]] + verts[idx[2]]) / 3.0)
			col = cols[idx[0]] if not cols.is_empty() else Color()
		elif centre == Vector3.INF and verts.size() >= 3:
			centre = mi.global_transform * ((verts[0] + verts[1] + verts[2]) / 3.0)
			col = cols[0] if not cols.is_empty() else Color()
		for v in verts:
			var w := mi.global_transform * v
			pts.append(w)
			if w.distance_to(home) > 30.0 and w.distance_to(home) < 120.0 and (best == Vector3.INF or w.distance_to(home) < best.distance_to(home)):
				best = w
	if best == Vector3.INF:
		return []
	var far := Vector3.INF
	for w in pts:
		var d := w.distance_to(best)
		if d > 22.0 and d < 30.0:
			far = w
			break
	return [best, far, centre, col] if far != Vector3.INF and centre != Vector3.INF else []


# A point 40-90 m from home where the mask is fully open and the ray lands on Terrain.
func _open_spot(home: Vector3) -> Vector3:
	for i in 48:
		var a := TAU * float(i) / 48.0
		var p := home + Vector3(cos(a), 0, sin(a)) * (40.0 + float(i % 4) * 15.0)
		if _grass._mask_at(p.x, p.z) < 0.99:
			continue
		var hit := _me.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 100.0, p + Vector3.DOWN * 100.0, 1))
		if not hit.is_empty() and str((hit.collider as Node).name) == "Terrain":
			return hit.position
	return Vector3.INF


func _shot(shot_name: String, from: Vector3, to: Vector3) -> void:
	_me.global_position = from + Vector3.UP * 0.5
	_me.velocity = Vector3.ZERO
	_cam.make_current()
	_cam.global_position = from
	_cam.look_at(to)
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR + "/ground_%s.png" % shot_name))
	_log.append("shot ground_%s.png" % shot_name)


func _perf(label: String) -> void:
	var sum := 0.0
	for i in 90:
		await get_tree().process_frame
		sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_log.append("%s: frame %.1f ms, %d draw calls, %d k primitives, %.0f MB video memory" % [label, sum / 90.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])


func _ground_y(p: Vector3) -> float:
	var hit := _me.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 150.0, p + Vector3.DOWN * 150.0, 17))
	return (hit.position as Vector3).y if not hit.is_empty() else p.y


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	_log.append(("PASS " if ok else "FAIL ") + what)
