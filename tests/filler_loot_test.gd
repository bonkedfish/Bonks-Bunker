# FillerLootTest — checks D-056: hosts a throwaway world, checks the generated POIs (data/map/pois.json) are placed,
# screenshots two of them (outside + inside) into res://tests/_look/poi_*.png, opens and empties one POI container,
# finds the LootSpots in the cells around the player, opens + empties one, checks its contents are kept in the save
# when its cell unloads (remove_child) and come back when it reloads, and reports perf next to a POI.
# Results: tests/_look/filler_loot_result.txt. Depends on: scenes/main.tscn, SaveStore, WorldStreamer, LootContainer.
extends Node

const OUT_DIR := "res://tests/_look"

var _log := PackedStringArray()
var _player: Node3D
var _fails := 0


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz filler")
	main._on_host_pressed()
	await get_tree().create_timer(4.0).timeout
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for n: Node in get_tree().get_nodes_in_group("players"):
		if "water" in n:
			_player = n
	_player.health.damage_mult = 0.0
	var pois: Dictionary = DataLoader.load_json("res://data/map/pois.json").get("pois", {})
	var placed: Array[Node3D] = []
	for key: String in pois:
		var n := get_tree().root.find_child(key, true, false) as Node3D
		if n:
			placed.append(n)
	_check("POIs placed: %d of %d" % [placed.size(), pois.size()], pois.size() >= 8 and placed.size() == pois.size())
	var cam := Camera3D.new()
	cam.fov = 75.0
	add_child(cam)
	for i in mini(2, placed.size()):
		var poi := placed[i]
		var fwd := -poi.global_basis.z  # the front faces local -Z
		_player.global_position = poi.global_position + fwd * 6.0 + Vector3(0, 1.0, 0)
		_player.velocity = Vector3.ZERO
		await get_tree().create_timer(3.0).timeout
		cam.make_current()
		cam.global_position = poi.global_position + fwd * 22.0 + poi.global_basis.x * 6.0 + Vector3(0, 4.0, 0)
		cam.look_at(poi.global_position + Vector3(0, 2.5, 0))
		await _shot("poi_%d_outside.png" % i)
		cam.global_position = poi.global_position + fwd * (-1.0) + Vector3(0, 1.7, 0)
		cam.look_at(poi.global_position - fwd * 8.0 + Vector3(0, 1.0, 0))
		await _shot("poi_%d_inside.png" % i)
		_say("%s (%s '%s'): %d loot containers" % [poi.name, pois[str(poi.name)].style, pois[str(poi.name)].name,
			poi.find_children("Loot_*", "", false, false).size()])
	if not placed.is_empty():
		var box: Node3D = placed[0].find_children("Loot_*", "", false, false)[0]
		await _empty(box, "POI container '%s'" % box.display_name)
	# Loot spots in the streamed cells.
	var spots: Array[Node] = []
	for c in get_tree().get_nodes_in_group("loot_containers"):
		if c.streamed:
			spots.append(c)
	_check("loot spots in loaded cells: %d" % spots.size(), spots.size() > 0)
	var by_table := {}
	for s: Node in spots:
		by_table[s.loot_table] = int(by_table.get(s.loot_table, 0)) + 1
	_say("spots by table: %s" % by_table)
	if not spots.is_empty():
		var spot: Node3D = spots[0]
		for s: Node3D in spots:
			if s.loot_table == "car_trunk":
				spot = s
		cam.global_position = spot.global_position + Vector3(4, 2.5, 4)
		cam.look_at(spot.global_position + Vector3(0, 0.6, 0))
		_player.global_position = spot.global_position + Vector3(1.8, 0.5, 0)
		await get_tree().create_timer(1.5).timeout
		await _shot("loot_spot.png")
		var id: String = spot.container_id
		await _empty(spot, "loot spot %s '%s'" % [id, spot.display_name])
		var saves := get_tree().get_first_node_in_group("save_director")
		var parent := spot.get_parent()
		parent.remove_child(spot)
		_check("unload keeps the spot's contents in the save", saves.world.containers.has(id))
		saves.world.containers[id] = {"scrap_metal": 2}
		var again: Node = spot.duplicate()
		spot.free()
		parent.add_child(again)
		await get_tree().process_frame
		_check("reload restores it (remaining %d)" % again.net_remaining, again.net_remaining == 2)
	if not placed.is_empty():
		_player.global_position = placed[0].global_position - placed[0].global_basis.z * 4.0 + Vector3(0, 1.0, 0)
		_player.yaw = placed[0].rotation.y
		await get_tree().create_timer(4.0).timeout
		cam.clear_current()
		var worst := 0.0
		for i in 120:
			await get_tree().process_frame
			worst = maxf(worst, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_say("perf at %s: frame %.1f ms (worst process %.1f ms), draw calls %d, VRAM %d MB, %d loot containers in the tree" % [
			placed[0].name, 1000.0 / maxf(Engine.get_frames_per_second(), 1.0), worst,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			get_tree().get_nodes_in_group("loot_containers").size()])
	_say("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/filler_loot_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SaveStore.delete(main.saves.world_slug)
	await get_tree().create_timer(2.0).timeout
	get_tree().quit()


func _empty(box: Node3D, what: String) -> void:
	var sz: Vector3 = box.size
	var side := box.global_basis.x * (sz.x * 0.5 + 0.8) if sz.x <= sz.z else -box.global_basis.z * (sz.z * 0.5 + 0.8)
	_player.global_position = box.global_position + Vector3(0, 0.5, 0) + side
	_player.velocity = Vector3.ZERO
	await get_tree().create_timer(0.5).timeout
	var before := _total()
	box.request_open()
	await get_tree().create_timer(0.3).timeout
	var rolled: int = box.net_remaining
	box.request_take_all()
	await get_tree().create_timer(0.3).timeout
	box.request_close()
	_check("%s: rolled %d, took all (inventory %d -> %d)" % [what, rolled, before, _total()],
		rolled >= 0 and box.net_remaining == 0 and _total() == before + rolled)


func _total() -> int:
	var t := 0
	for id: String in _player.inventory.net_items:
		t += int(_player.inventory.net_items[id])
	return t


func _shot(file: String) -> void:
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT_DIR + "/" + file)
	_say("shot " + file)


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	_say(("PASS " if ok else "FAIL ") + what)


func _say(s: String) -> void:
	print("FILLER: " + s)
	_log.append(s)
