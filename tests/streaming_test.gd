# StreamingTest — real level: host, then report which map cells are loaded, the frame cost, a navmesh path,
# zombies per cell; teleport the player 800 m east and report again (what loaded/unloaded, worst frame while
# streaming, standing on ground); then teleport back. Run this scene directly after the map pipeline.
# Depends on: scenes/main.tscn, Net autoload, WorldStreamer, Perf, SaveStore.
extends Node

var _worst := 0.0
var _track := false


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz test")
	main._on_host_pressed()
	await get_tree().create_timer(4.0).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var w: Node = main.get_node("World")
	var me: Node3D = get_tree().get_first_node_in_group("local_player")
	_report("at spawn", w, me)
	_path_check(me)

	_worst = 0.0
	_track = true
	me.global_position = Vector3(800.0, 40.0, 0.0)
	await get_tree().create_timer(8.0).timeout
	_track = false
	_report("800 m east (worst frame while streaming %.1f ms)" % (_worst * 1000.0), w, me)
	_path_check(me)

	_worst = 0.0
	_track = true
	me.global_position = w.spawn_hint + Vector3(0, 2.0, -4.0)
	await get_tree().create_timer(6.0).timeout
	_track = false
	_report("back at the bunker (worst frame %.1f ms)" % (_worst * 1000.0), w, me)
	SaveStore.delete(main.saves.world_slug)
	await get_tree().create_timer(20.0).timeout
	get_tree().quit()


func _process(delta: float) -> void:
	if _track:
		_worst = maxf(_worst, delta)


func _report(label: String, w: Node, me: Node3D) -> void:
	var cells: Array = w.near_loaded.keys()
	cells.sort()
	var far_visible := 0
	for c in w._far_loaded:
		if w._far_loaded[c].visible:
			far_visible += 1
	var zd := get_tree().get_first_node_in_group("zombie_director")
	var per_cell := {}
	for z in zd.get_children():
		if z.net_active:
			var c: Vector2i = w.grid.cell_of(z.global_position)
			per_cell[c] = int(per_cell.get(c, 0)) + 1
	print("STREAM [%s]: player %s cell %s on floor %s" % [label, me.global_position.snapped(Vector3.ONE * 0.1), w.grid.cell_of(me.global_position), me.is_on_floor()])
	print("STREAM   near cells %d %s, far shells %d loaded / %d shown, pending %d" % [cells.size(), cells, w._far_loaded.size(), far_visible, w._pending.size()])
	print("STREAM   frame %.1f ms, draw calls %d, primitives %dk, VRAM %d MB, RAM %d MB, nodes %d" % [Perf.frame_ms, int(Perf.draw_calls), int(Perf.primitives_k), int(Perf.vram_mb), int(Perf.ram_mb), int(Perf.nodes)])
	print("STREAM   zombies %d active, per cell %s" % [zd.active_count, per_cell])


func _path_check(me: Node3D) -> void:
	var map := me.get_world_3d().navigation_map
	var to := me.global_position + Vector3(40, 0, 25)
	var path := NavigationServer3D.map_get_path(map, me.global_position, to, true)
	var end := path[path.size() - 1] if path.size() > 0 else Vector3.INF
	var closest := NavigationServer3D.map_get_closest_point(map, to)
	print("STREAM   nav path 47 m: %d points, ends %.1f m from the closest navmesh point to the target (end %s, closest %s)" % [
		path.size(), end.distance_to(closest), end.snapped(Vector3.ONE * 0.1), closest.snapped(Vector3.ONE * 0.1)])
