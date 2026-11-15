# HoleScan — finds every spot on the map where a player would fall forever (D-091). Run this scene directly:
# opens a throwaway offline world, then streams every cell in turn (WorldStreamer._update) and casts a ray
# straight down every STEP_M metres with the PLAYER's collision mask, from well above the highest ground to far
# below the lowest. No hit = nothing to stand on = an endless fall. Misses are grouped into clusters with their
# world position, cell and nearest landmark so they can be fixed in the data / builder. Optional user args
# "--cells=x0,z0,x1,z1" limit the scan to a block of cells.
# Log: tests/_look/hole_scan.txt. Depends on: scenes/main.tscn, WorldStreamer, CellGrid, MapProjection,
# data/map/landmarks.json + pois.json, data/map/import_config.json.
extends Node

const STEP_M := 3.0
const TOP_Y := 220.0
const BOTTOM_Y := -260.0
const PLAYER_MASK := 19  # = scenes/player.tscn collision_mask

var _log := PackedStringArray()


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz holescan")
	main.menu.play_offline.emit()
	await get_tree().create_timer(4.0).timeout
	var prompt: Control = get_tree().get_first_node_in_group("name_prompt")
	if prompt and prompt.visible:
		prompt.submit("Bonk")
	var player: Node3D = get_tree().get_first_node_in_group("local_player")
	player.set_physics_process(false)  # parked; we only need its position to keep cells streamed
	var streamer: Node = get_tree().get_first_node_in_group("world_streamer")
	if streamer == null:
		streamer = main.find_child("WorldStreamer", true, false)
	var grid: CellGrid = streamer.grid
	var lm := _landmarks()
	var x0 := 0
	var z0 := 0
	var x1: int = grid.cells_x - 1
	var z1: int = grid.cells_z - 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cells="):
			var p := a.trim_prefix("--cells=").split(",")
			x0 = int(p[0]); z0 = int(p[1]); x1 = int(p[2]); z1 = int(p[3])
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = PLAYER_MASK
	var misses := []  # Vector2 world x/z
	var cells_done := 0
	var t0 := Time.get_ticks_msec()
	for cz in range(z0, z1 + 1):
		for cx in range(x0, x1 + 1):
			var c := Vector2i(cx, cz)
			var r: Rect2 = grid.rect_of(c)
			player.global_position = Vector3(r.get_center().x, 50.0, r.get_center().y)
			streamer._update()  # re-reads player positions (keep set) and blocking-loads the cell under the player
			await get_tree().physics_frame
			await get_tree().physics_frame
			if not streamer.is_loaded(c):
				_say("cell %s did not load" % c)
				continue
			cells_done += 1
			var n := int(r.size.x / STEP_M)
			for iz in n:
				for ix in n:
					var p := r.position + Vector2((ix + 0.5) * STEP_M, (iz + 0.5) * STEP_M)
					q.from = Vector3(p.x, TOP_Y, p.y)
					q.to = Vector3(p.x, BOTTOM_Y, p.y)
					if space.intersect_ray(q).is_empty():
						misses.append(p)
			if cells_done % 25 == 0:
				print("HOLESCAN: %d cells, %d misses, %.0f s" % [cells_done, misses.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	_say("scanned %d cells (%d..%d, %d..%d) every %.0f m in %.0f s: %d point(s) with nothing underneath" % [
		cells_done, x0, x1, z0, z1, STEP_M, (Time.get_ticks_msec() - t0) / 1000.0, misses.size()])
	for cl: Dictionary in _clusters(misses):
		var centre: Vector2 = cl.centre
		var near := _nearest(lm, centre)
		_say("HOLE %d pts around (%.1f, %.1f) size %.0fx%.0f m, cell %s, nearest landmark %s (%.0f m)" % [
			cl.count, centre.x, centre.y, cl.size.x, cl.size.y, grid.cell_of(Vector3(centre.x, 0, centre.y)),
			near[0], near[1]])
	DirAccess.make_dir_recursive_absolute("res://tests/_look")
	var f := FileAccess.open("res://tests/_look/hole_scan.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	get_tree().quit()


# Groups miss points that are within 2 grid steps of each other.
func _clusters(points: Array) -> Array:
	var out := []
	var used := {}
	for i in points.size():
		if used.has(i):
			continue
		var stack := [i]
		used[i] = true
		var pts: Array = []
		while not stack.is_empty():
			var k: int = stack.pop_back()
			pts.append(points[k])
			for j in points.size():
				if not used.has(j) and (points[k] as Vector2).distance_to(points[j]) <= STEP_M * 2.1:
					used[j] = true
					stack.append(j)
		var box := Rect2(pts[0], Vector2.ZERO)
		for p: Vector2 in pts:
			box = box.expand(p)
		out.append({"count": pts.size(), "centre": box.get_center(), "size": box.size + Vector2(STEP_M, STEP_M)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.count > b.count)
	return out


func _landmarks() -> Dictionary:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/map/import_config.json"))
	var proj := MapProjection.new(float(cfg.center_lat), float(cfg.center_lon))
	var out := {}
	for file in ["res://data/map/landmarks.json", "res://data/map/pois.json"]:
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
		if not d is Dictionary:
			continue
		for id: String in (d as Dictionary):
			var l: Variant = d[id]
			if l is Dictionary and (l as Dictionary).has("lat") and (l as Dictionary).has("lon"):
				out[id] = proj.to_local(float(l.lat), float(l.lon))
	return out


func _nearest(lm: Dictionary, p: Vector2) -> Array:
	var best := ["(none)", INF]
	for id: String in lm:
		var d := p.distance_to(lm[id])
		if d < best[1]:
			best = [id, d]
	return best


func _say(s: String) -> void:
	print("HOLESCAN: " + s)
	_log.append(s)
