# CarLook — D-116 cars in the baked map: counts every car_* (and covered_car) instance across all cells (so each
# placement kind shows up), then visits a jam with the bus or a crashed car, a parking lot row and a driveway car
# in the running game and screenshots each from a person's height, with frame time and draw calls.
# Results: tests/_look/car_look.txt (ends with the failure count); screenshots tests/_look/car_look_*.png.
# Depends on: scenes/main.tscn, the baked cells (world/generated/cells), data/art/clutter.json.
extends Node

const OUT_DIR := "res://tests/_look"

var _log := PackedStringArray()
var _fails := 0
var _me: Node3D
var _cam: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var idx := DataLoader.load_json("res://world/generated/cells/index.json")
	var counts := {}
	var where := {}  # kind -> [world position, yaw] of one instance
	var kinds: Array = []
	for k: String in DataLoader.load_json("res://data/art/clutter.json").props:
		if k.begins_with("car_") or k == "covered_car":
			kinds.append(k)
	var keys: Array = idx.cells.keys()
	keys.sort()
	for key: String in keys:
		var root := (load(str(idx.cells[key].near)) as PackedScene).instantiate() as Node3D
		for mmi: MultiMeshInstance3D in root.find_children("*", "MultiMeshInstance3D", true, false):
			var n := str(mmi.name)
			var kind := ""
			for k: String in kinds:
				if n.begins_with(k + "_") and n.substr(k.length() + 1, 1).is_valid_int():
					kind = k
			if kind == "":
				continue
			var mm := mmi.multimesh
			counts[kind] = int(counts.get(kind, 0)) + mm.instance_count
			if mm.instance_count > 0 and not where.has(kind):
				var xf := mmi.transform * mm.get_instance_transform(0)
				where[kind] = [xf.origin, xf.basis.get_euler().y]
		root.free()
		await get_tree().process_frame  # lets the renderer actually free each cell's meshes (else VRAM runs out)
	_log.append("cars in the whole map: %s" % str(counts))
	var total := 0
	for k: String in counts:
		total += int(counts[k])
	_check(total > 500, "%d cars placed" % total)
	for k: String in ["car_sedan_a", "car_sedan_b", "car_pickup_blue", "car_rusty_truck", "car_cadillac", "car_crashed_car",
			"car_crashed_truck", "car_bus"]:
		_check(int(counts.get(k, 0)) > 0, "%s is used (%d)" % [k, int(counts.get(k, 0))])
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz cars")
	main.menu.play_offline.emit()
	await get_tree().create_timer(5.0).timeout
	var prompt := get_tree().get_first_node_in_group("name_prompt")
	if prompt and prompt.visible:
		prompt.submit("Bonk")
	_me = get_tree().get_first_node_in_group("local_player")
	_me.health.invulnerable = true
	var dn := get_tree().get_first_node_in_group("daynight")
	if dn:
		dn.hour = 11.0
	_cam = Camera3D.new()
	_cam.fov = 70.0
	add_child(_cam)
	for k: String in ["car_bus", "car_crashed_car", "car_sedan_a", "car_pickup_blue"]:
		if where.has(k):
			await _visit(k, where[k][0], float(where[k][1]))
	_log.append("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/car_look.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	get_tree().quit()


# Stands 9 m off the car's side and 2 m up, looking at it, after the cell has loaded.
func _visit(kind: String, at: Vector3, yaw: float) -> void:
	var side := Vector3(cos(yaw), 0, -sin(yaw)) * 9.0 + Vector3(sin(yaw), 0, cos(yaw)) * 4.0
	_me.global_position = at + side + Vector3.UP * 30.0
	_me.velocity = Vector3.ZERO
	await get_tree().create_timer(5.0).timeout
	_me.global_position = at + side + Vector3.UP * 1.0
	_cam.make_current()
	_cam.global_position = at + side + Vector3.UP * 2.0
	_cam.look_at(at + Vector3.UP * 0.8)
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR + "/car_look_%s.png" % kind))
	var sum := 0.0
	for i in 60:
		await get_tree().process_frame
		sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_log.append("%s at %s: frame %.1f ms, %d draw calls, %d k primitives" % [kind, str(at.round()), sum / 60.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)])


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	_log.append(("PASS " if ok else "FAIL ") + what)
