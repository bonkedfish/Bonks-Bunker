# BuildGrassMasks — map import pipeline step, run after build_cells (run this scene directly; no internet) (D-115).
# For every cell in the index, loads the baked cell and paints a density mask for the 3D grass (GrassField):
# one byte per mask_m square, 255 = open ground; Street_<surface> strips, sidewalks, building roofs, water, and
# the golf course paint layers are rasterized on top with the values in data/tuning/grass.json "mask_values"
# (the lowest value wins), then the road pixels that touch open ground become "road_edge" (overgrown edges).
# Saves world/generated/grass/cell_<x>_<z>.res (a compressed Image). Re-running regenerates them all.
# Optional user arg "--only=<x>_<z>" builds one cell (for testing).
# Log: tests/_look/grass_masks.txt. Depends on: DataLoader, CellGrid, data/map/streaming.json, the cell index.
extends Node

const TUNING := "res://data/tuning/grass.json"
const STREAMING := "res://data/map/streaming.json"

var _v: Dictionary
var _n := 256
var _m := 1.0
var _log := PackedStringArray()


func _ready() -> void:
	var t := DataLoader.load_json(TUNING)
	_v = t.mask_values
	_m = float(t.mask_m)
	var idx := DataLoader.load_json(str(DataLoader.load_json(STREAMING).index_path))
	var org: Array = idx.origin
	var grid := CellGrid.new(float(idx.cell_size), int(idx.cells_x), int(idx.cells_z), Vector2(org[0], org[1]))
	_n = int(round(grid.cell_size / _m))
	var out_dir := str(t.mask_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	var t0 := Time.get_ticks_msec()
	var done := 0
	var keys: Array = idx.cells.keys()
	keys.sort()
	for key: String in keys:
		if only != "" and key != only:
			continue
		var parts := key.split("_")
		var c := Vector2i(int(parts[0]), int(parts[1]))
		var scene := load(str(idx.cells[key].near)) as PackedScene
		if scene == null:
			_log.append("%s: cannot load" % key)
			continue
		var root := scene.instantiate() as Node3D
		var img := Image.create_from_data(_n, _n, false, Image.FORMAT_L8, _mask(root, grid.rect_of(c)))
		ResourceSaver.save(img, "%s/cell_%s.res" % [out_dir, key], ResourceSaver.FLAG_COMPRESS)
		root.free()
		done += 1
		if done % 50 == 0:
			print("GRASS: %d cells, %.0f s" % [done, (Time.get_ticks_msec() - t0) / 1000.0])
	_log.append("%d masks in %.0f s -> %s" % [done, (Time.get_ticks_msec() - t0) / 1000.0, out_dir])
	print("GRASS: " + _log[-1])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/_look"))
	var f := FileAccess.open("res://tests/_look/grass_masks.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	get_tree().quit()


func _mask(root: Node3D, rect: Rect2) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(_n * _n)
	data.fill(int(_v.open))
	var road := int(_v.road)
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var value := _value_for(str(mi.name))
		if value < 0 or mi.mesh == null:
			continue
		var xf := _xform(mi, root)
		for s in mi.mesh.get_surface_count():
			_raster(data, mi.mesh.surface_get_arrays(s), xf, rect, value)
	# road pixels touching open ground: overgrown edges
	var open := int(_v.open)
	var edge := int(_v.road_edge)
	var edges := PackedInt32Array()
	for y in range(1, _n - 1):
		for x in range(1, _n - 1):
			var i := y * _n + x
			if data[i] == road and (data[i - 1] == open or data[i + 1] == open or data[i - _n] == open or data[i + _n] == open):
				edges.append(i)
	for i in edges:
		data[i] = edge
	return data


func _value_for(node_name: String) -> int:
	if node_name == "Street_sidewalk":
		return int(_v.sidewalk)
	if node_name.begins_with("Street_"):
		return int(_v.road)
	if node_name == "Roofs" or node_name == "PitchedRoofs" or node_name == "Water":
		return int(_v.none)
	if node_name.begins_with("Paint_"):
		return int(_v.fairway) if node_name.ends_with("fairway") else int(_v.none)
	return -1


# Every triangle's pixels (centre inside the triangle, x/z) get min(current, value).
func _raster(data: PackedByteArray, arrays: Array, xf: Transform3D, rect: Rect2, value: int) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var count := index.size() if not index.is_empty() else verts.size()
	var p := PackedVector2Array()
	p.resize(verts.size())
	for i in verts.size():
		var w := xf * verts[i]
		p[i] = Vector2((w.x - rect.position.x) / _m, (w.z - rect.position.y) / _m)
	for t in range(0, count - 2, 3):
		var a := p[index[t] if not index.is_empty() else t]
		var b := p[index[t + 1] if not index.is_empty() else t + 1]
		var c := p[index[t + 2] if not index.is_empty() else t + 2]
		var x0 := maxi(floori(minf(a.x, minf(b.x, c.x))), 0)
		var x1 := mini(ceili(maxf(a.x, maxf(b.x, c.x))), _n - 1)
		var y0 := maxi(floori(minf(a.y, minf(b.y, c.y))), 0)
		var y1 := mini(ceili(maxf(a.y, maxf(b.y, c.y))), _n - 1)
		if x0 > x1 or y0 > y1:
			continue
		var area := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
		if absf(area) < 0.000001:
			continue
		for y in range(y0, y1 + 1):
			var py := y + 0.5
			for x in range(x0, x1 + 1):
				var px := x + 0.5
				var w0 := (b.x - a.x) * (py - a.y) - (b.y - a.y) * (px - a.x)
				var w1 := (c.x - b.x) * (py - b.y) - (c.y - b.y) * (px - b.x)
				var w2 := (a.x - c.x) * (py - c.y) - (a.y - c.y) * (px - c.x)
				if (w0 >= 0.0 and w1 >= 0.0 and w2 >= 0.0) or (w0 <= 0.0 and w1 <= 0.0 and w2 <= 0.0):
					var i := y * _n + x
					if data[i] > value:
						data[i] = value


func _xform(n: Node, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	while n != root and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return root.transform * xf
