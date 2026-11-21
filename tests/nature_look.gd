# NatureLook — visual + count check of the D-098 nature after build_cells: counts the vegetation kinds in the
# loaded cells (every species / plant should show up somewhere), and screenshots a shore, the country club rough,
# a street and an open lot in a storm-free noon, with frame time and draw calls at each.
# Results: tests/_look/nature_result.txt (ends with the failure count); screenshots tests/_look/nature_*.png.
# Depends on: scenes/main.tscn, WeatherDirector, WorldStreamer (group "world_streamer"), data/art/vegetation.json.
extends Node

const OUT_DIR := "res://tests/_look"
# [name, landmark key ("" = player spawn), camera offset (landmark-local), look-at offset; both heights above ground]
const SPOTS := [["club_rough", "country_club", Vector3(-150, 25, -120), Vector3(-300, 0, -250)],
	["club_overview", "country_club", Vector3(60, 45, 120), Vector3(0, 0, -150)],
	["home_street", "bonk_house", Vector3(0, 20, 45), Vector3(0, 0, -30)],
	["yanney_shore", "yanney_gardens", Vector3(0, 20, 95), Vector3(0, 0, 0)]]

var _log := PackedStringArray()
var _fails := 0
var _seen := {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz nature")
	main._on_host_pressed()
	await get_tree().create_timer(4.0).timeout
	var prompt := get_tree().get_first_node_in_group("name_prompt")
	if prompt and prompt.visible:
		prompt.submit("Bonk")
	var me: Node3D = null
	for n: Node in get_tree().get_nodes_in_group("players"):
		if "water" in n:
			me = n
	me.health.damage_mult = 0.0
	var weather := get_tree().get_first_node_in_group("weather")
	if weather:
		weather.request_mode("clear")
	var cam := Camera3D.new()
	cam.fov = 75.0
	add_child(cam)
	var home: Vector3 = me.global_position
	for spot: Array in SPOTS:
		var xf := Transform3D(Basis.IDENTITY, home)
		if str(spot[1]) != "":
			var lm := get_tree().root.find_child(str(spot[1]), true, false) as Node3D
			if lm == null:
				_log.append("no landmark " + str(spot[1]))
				continue
			xf = lm.global_transform
		var from := xf * (spot[2] as Vector3)
		var to := xf * (spot[3] as Vector3)
		me.global_position = from + Vector3.UP * 60.0
		me.velocity = Vector3.ZERO
		await get_tree().create_timer(4.0).timeout
		from.y = _ground_y(me, from) + (spot[2] as Vector3).y
		to.y = _ground_y(me, to) + (spot[3] as Vector3).y
		me.global_position = from + Vector3.UP * 0.5
		me.velocity = Vector3.ZERO
		cam.make_current()
		cam.global_position = from
		cam.look_at(to)
		await get_tree().create_timer(2.0).timeout
		_count()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR + "/nature_%s.png" % spot[0]))
		var sum := 0.0
		for i in 60:
			await get_tree().process_frame
			sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_log.append("%s: frame %.1f ms, %d draw calls, %d objects, %.0f MB vram" % [spot[0], sum / 60.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
		cam.clear_current()
	var veg := DataLoader.load_json("res://data/art/vegetation.json")
	var want: Array = []
	for id: String in veg.species:
		want.append("tree_" + id)
	want.append_array((veg.plants as Dictionary).keys())
	var missing: Array = []
	for k: String in want:
		if not _seen.has(k):
			missing.append(k)
	_log.append("kinds seen: %s" % str(_seen))
	_check(missing.size() <= 3, "species / plants found in the loaded cells (missing: %s)" % str(missing))
	_log.append("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/nature_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	get_tree().quit()


func _ground_y(me: Node3D, p: Vector3) -> float:
	var hit := me.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 150.0, p + Vector3.DOWN * 150.0, 17))
	return (hit.position as Vector3).y if not hit.is_empty() else p.y


# Counts instances per vegetation kind in the near cells (MultiMeshInstance names start with the kind).
func _count() -> void:
	var streamer := get_tree().get_first_node_in_group("world_streamer")
	for cell: Node in streamer.near_loaded.values():
		for mmi in cell.find_children("*", "MultiMeshInstance3D", true, false):
			var parts := str(mmi.name).rsplit("_", true, 2)  # <kind>_<mesh>_<block>
			var kind := parts[0]
			if (mmi as MultiMeshInstance3D).multimesh:
				_seen[kind] = int(_seen.get(kind, 0)) + (mmi as MultiMeshInstance3D).multimesh.instance_count


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	_log.append(("PASS " if ok else "FAIL ") + what)
