# BigMapTest — the D-048 map: hosts a throwaway world, sends the player to UNK, downtown and the Archway area
# (streaming cells in on the way), screenshots each at eye height with perf numbers + WorldStreamer slow events,
# then opens the M map centred on the player and zoomed out over the whole area.
# Screens: tests/_look/bigmap_*.png; results: tests/_look/bigmap_result.txt. Depends on: scenes/main.tscn,
# WorldStreamer, WorldMapUI, Perf, SaveStore.
extends Node

const SPOTS := [
	["unk", Vector3(-15, 0, -1760), 0.0],
	["downtown", Vector3(1867, 0, -1500), 0.0],
	["archway", Vector3(5300, 0, 1300), -90.0],
	["east_edge", Vector3(6300, 0, 0), 90.0],
]

var _log := PackedStringArray()


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz bigmap")
	main._on_host_pressed()
	await get_tree().create_timer(4.0).timeout
	var w: Node = main.get_node("World")
	var me: Node3D = get_tree().get_first_node_in_group("local_player")
	_say("grid %dx%d cells, origin %s" % [w.grid.cells_x, w.grid.cells_z, w.grid.origin])
	for s: Array in SPOTS:
		var p: Vector3 = s[1]
		w.slow_events.clear()
		me.global_position = Vector3(p.x, 60.0, p.z)
		me.velocity = Vector3.ZERO
		await get_tree().create_timer(6.0).timeout
		me.yaw = deg_to_rad(float(s[2]))
		me.pitch = -0.05
		await get_tree().create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tests/_look/bigmap_%s.png" % s[0])
		_say("%s: player at %s, cell %s loaded %s, frame %.1f ms worst %.1f, draw calls %d, VRAM %d MB, slow loads %s" % [
			s[0], me.global_position.snapped(Vector3.ONE * 0.1), w.grid.cell_of(me.global_position),
			w.is_loaded(w.grid.cell_of(me.global_position)), Perf.frame_ms, Perf.worst_ms, Perf.draw_calls, Perf.vram_mb,
			w.slow_events])
	var ui := get_tree().get_first_node_in_group("world_map_ui")
	ui.open()
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/_look/bigmap_map_near.png")
	var fit := minf(ui.size.x / float(ui._tex.get_width()), ui.size.y / float(ui._tex.get_height()))
	ui._zoom = fit
	ui._offset = (ui.size - Vector2(ui._tex.get_size()) * fit) * 0.5
	ui.queue_redraw()
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/_look/bigmap_map_all.png")
	_say("map: %dx%d px texture, open frame %.1f ms" % [ui._tex.get_width(), ui._tex.get_height(), Perf.frame_ms])
	var f := FileAccess.open("res://tests/_look/bigmap_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	await get_tree().create_timer(20.0).timeout
	get_tree().quit()


func _say(s: String) -> void:
	print("BIGMAP: " + s)
	_log.append(s)
