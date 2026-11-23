# HouseLook — D-118 house detail in the baked map: checks build_cells recorded an example of every kind (house,
# porch, garage, boarded-up, burned, caved-in roof, large building), then visits each in the running game and
# screenshots its front from a person's height (the caved roof from above), with frame time and draw calls.
# Results: tests/_look/house_look.txt (ends with the failure count); screenshots tests/_look/house_look_*.png.
# Depends on: scenes/main.tscn, the baked cells (world/generated/cells/index.json "house_examples").
extends Node

const OUT_DIR := "res://tests/_look"
const KINDS := ["house", "porch", "garage", "boarded", "burned", "caved", "large"]

var _log := PackedStringArray()
var _fails := 0
var _me: Node3D
var _cam: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var idx := DataLoader.load_json("res://world/generated/cells/index.json")
	var ex: Dictionary = idx.get("house_examples", {})
	for k: String in KINDS:
		_check(ex.has(k), "an example of '%s' was built" % k)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz houses")
	main.menu.play_offline.emit()
	await get_tree().create_timer(5.0).timeout
	var prompt := get_tree().get_first_node_in_group("name_prompt")
	if prompt and prompt.visible:
		prompt.submit("Bonk")
	_me = get_tree().get_first_node_in_group("local_player")
	_me.health.invulnerable = true
	var dn := get_tree().get_first_node_in_group("daynight")
	if dn:
		dn.hour = 10.5
	_cam = Camera3D.new()
	_cam.fov = 70.0
	add_child(_cam)
	for k: String in KINDS:
		if ex.has(k):
			var e: Array = ex[k]
			await _visit(k, Vector3(e[0], e[1], e[2]), Vector3(e[3], 0.0, e[4]))
	_log.append("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/house_look.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	get_tree().quit()


# Stands out from the front wall (above the roof for the caved one), looking back at it, once the cell has loaded.
func _visit(kind: String, at: Vector3, out: Vector3) -> void:
	var side := out.cross(Vector3.UP).normalized()
	var eye := at + out * 11.0 + side * 3.0 + Vector3.UP * 1.7
	var look := at + Vector3.UP * 1.8
	if kind == "caved":
		eye = at + out * 4.0 + side * 2.0 + Vector3.UP * 22.0
		look = at - out * 4.0 + Vector3.UP * 3.0
	elif kind == "large":
		eye = at + out * 22.0 + side * 6.0 + Vector3.UP * 1.7
		look = at + Vector3.UP * 4.0
	_me.global_position = at + out * 11.0 + Vector3.UP * 30.0
	_me.velocity = Vector3.ZERO
	await get_tree().create_timer(5.0).timeout
	_me.global_position = at + out * 11.0 + Vector3.UP * 1.0
	_cam.make_current()
	_cam.global_position = eye
	_cam.look_at(look)
	await get_tree().create_timer(10.0).timeout  # let streaming settle before the shot and the timing
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR + "/house_look_%s.png" % kind))
	var sum := 0.0
	for i in 60:
		await get_tree().process_frame
		sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var on := [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)]
	var details: Array[Node] = get_tree().root.find_children("Trim", "MeshInstance3D", true, false)
	details.append_array(get_tree().root.find_children("Boards", "MeshInstance3D", true, false))
	for n: Node in details:
		(n as MeshInstance3D).visible = false
	for i in 3:
		await get_tree().process_frame
	_log.append("  without the D-118 detail: %d draw calls (%d with), %d k primitives (%d k with)" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), int(on[0]),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0), int(on[1] / 1000.0)])
	for n: Node in details:
		(n as MeshInstance3D).visible = true
	_log.append("%s at %s: frame %.1f ms, %d draw calls, %d k primitives, %d MB video memory" % [kind, str(at.round()),
		sum / 60.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
		int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)])


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	_log.append(("PASS " if ok else "FAIL ") + what)
