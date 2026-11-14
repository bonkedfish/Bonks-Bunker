# BuildCells — map import pipeline, step 3 (run this scene directly; no internet needed) (D-039).
# Reads data/map/import_config.json, the OSM JSON from fetch_osm, the elevation GeoTIFF from
# fetch_elevation and data/map/landmarks.json (+ the generated POIs in data/map/pois.json), and writes into cells_dir:
#   cell_<x>_<z>.scn      full detail: Terrain (heightfield mesh + trimesh collider, landmark ground holes cut),
#                         Buildings (OSM footprints, plus Microsoft footprints from fetch_buildings wherever OSM has
#                         nothing (D-040), extruded from the lowest ground corner; one wall mesh per look + one
#                         roof mesh + one collider; looks, gable roofs and windows from BuildingLooks (D-041)),
#                         Street_<surface> meshes (draped strips, visual only: roads by OSM surface, lane lines,
#                         curbs + sidewalks generated along street kinds, from StreetLooks (D-043)),
#                         textured ground and shingled pitched roofs, Vegetation (street/yard trees, bushes,
#                         stumps, fallen trunks, grass clumps from VegetationBuilder, D-043), Clutter (power poles,
#                         lamps, hydrants, cars, trash, barriers, fences, debris; a second VegetationBuilder on
#                         data/art/clutter.json, D-044), Boundary walls on the map edge,
#                         ZombieSpawns markers on drivable roads, LootSpots (D-056: invisible searchable boxes on
#                         curb cars, trash cans, porch packages, yard barrels/boxes; no sync node), Navigation (navmesh baked here, tile-aligned),
#                         Water (lakes/ponds/rivers from WaterBuilder, D-047: terrain carved under them, the carved
#                         bed's collider on its own layer 16 so the navmesh skips it, surface collider layer 32),
#                         plus landmark plantings from each landmark's "plants_file", and Paint_<layer> meshes
#                         (golf greens, fairways, bunkers, cart paths...) from each landmark's "ground_paint" (D-080)
#   cell_<x>_<z>_far.scn  low-detail shell: coarse terrain + building blocks, ONE mesh, vertex colours, no shadows
#   index.json            grid, cell files, landmark heights and the player spawn hint for the streamer
#   materials/*.tres      shared materials so every cell references the same ones
# Landmarks are hand-built separate data: they're instanced here only so the navmesh walks around/into them,
# and their terrain_pad flattens the ground under their lot. Re-running regenerates everything from source.
# Batches (D-048): cells are built build_batch_rows rows at a time, each batch with one extra "context" row above
# and below (built, never saved) so navmesh tile borders, tree/building clearances and roads match across batch
# seams; per-batch state is reset and the batch is freed after saving, so memory stays flat on big maps.
# Depends on: DataLoader, MapProjection, HeightField, TiffReader, CellGrid, BuildingLooks, FootprintShape, StreetLooks,
# VegetationBuilder, TreeMesh, CarMesh, WaterBuilder, StreetSigns (street name signs at every intersection, D-070),
# GroundPaint (D-080).
extends Node

const CONFIG_PATH := "res://data/map/import_config.json"
const LANDMARKS_PATH := "res://data/map/landmarks.json"
const POIS_PATH := "res://data/map/pois.json"
const LOOT_SCRIPT := preload("res://scripts/inventory/loot_container.gd")
const GroundPaint := preload("res://tools/map_import/ground_paint.gd")
const ROAD_WIDTHS := {
	"motorway": 14.0, "trunk": 12.0, "primary": 12.0, "secondary": 10.0, "tertiary": 9.0,
	"residential": 7.5, "unclassified": 7.0, "living_street": 6.0, "service": 4.5, "track": 3.0,
	"footway": 1.8, "path": 1.5, "cycleway": 2.0, "pedestrian": 3.0,
}
const DRIVABLE := ["motorway", "trunk", "primary", "secondary", "tertiary", "residential",
	"unclassified", "living_street", "service"]
const BUILDING_HEIGHTS := {"house": 5.0, "garage": 3.0, "shed": 2.5, "school": 8.0, "commercial": 7.0,
	"retail": 6.0, "apartments": 10.0, "static_caravan": 3.2, "university": 12.0, "dormitory": 12.0,
	"church": 10.0, "industrial": 8.0, "warehouse": 8.0}
const DEFAULT_BUILDING_HEIGHT := 5.0
const ROAD_STEP := 4.0
const ROAD_LIFT := 0.06
const SPAWN_SPACING := 30.0
const SPAWN_EDGE_MARGIN := 10.0
const BOUNDARY_HEIGHT := 12.0
const NAV_BORDER := 2.0
const COLOR_GROUND := Color(0.42, 0.4, 0.3)
const COLOR_BUILDING := Color(0.62, 0.58, 0.52)
const COLOR_FAR_TREE := Color(0.36, 0.37, 0.24)
const COLOR_FAR_TREE_BARE := Color(0.3, 0.27, 0.22)
const DEDUPE_GRID := 32.0
const STREET_GRID := 32.0
const BED_LAYER := 16

var _cfg: Dictionary
var _proj: MapProjection
var _field: HeightField
var _grid: CellGrid
var _mats: Dictionary = {}
var _looks: BuildingLooks
var _streets: StreetLooks
var _veg: VegetationBuilder
var _clutter: VegetationBuilder
var _signs: StreetSigns
var _crossings: Array = []  # every signed intersection on the map (StreetSigns.find)
var _water: WaterBuilder
var _paint: GroundPaint  # landmark ground paint (D-080)
var _landmarks: Dictionary = {}
var _no_plant: Array[Rect2] = []  # landmark "no_plant_rects" in map coords
var _corners: Array = []  # [point, way direction, way index, half width] where a street meets a crossing street
var _ways: Array = []  # every highway way kept by _build_roads (for street trees)
var _clear_hash: Dictionary = {}  # Vector2i (STREET_GRID cell) -> Array of [a, b, reach]: roads + sidewalks to keep clear
var _houses: Array = []  # [outline, centre, class] of every generated building
var _bld_hash: Dictionary = {}  # Vector2i (STREET_GRID cell) -> Array of indices into _houses
var _street_hash: Dictionary = {}  # Vector2i (STREET_GRID cell) -> Array of [way index, a, b, half width, direction]
var _cells: Dictionary = {}  # Vector2i -> { root, terrain_faces, walls {look: SurfaceTool}, roof_st, pitched_st, b_faces, b_count, streets {surface: SurfaceTool}, spawns, far_st }
var _osm_polys: Array = []  # [PackedVector2Array poly, Vector2 centre] of every OSM building, for de-duplication
var _osm_hash: Dictionary = {}  # Vector2i (DEDUPE_GRID cell) -> Array of indices into _osm_polys


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	_cfg = DataLoader.load_json(CONFIG_PATH)
	var landmarks := DataLoader.load_json(LANDMARKS_PATH)
	landmarks.merge(DataLoader.load_json(POIS_PATH).get("pois", {}))  # small generated POIs (D-056)
	_landmarks = landmarks
	var src := DataLoader.load_json(str(_cfg.get("source_path", "")))
	if _cfg.is_empty() or src.is_empty():
		_finish("CELLS: missing config or OSM source - run tools/map_import/fetch_osm.tscn first")
		return
	_proj = MapProjection.new(float(_cfg.center_lat), float(_cfg.center_lon))
	if not _load_heights():
		return
	_grid = CellGrid.from_config(_cfg)
	_looks = BuildingLooks.new()
	if _looks.error != "":
		_finish("CELLS: " + _looks.error)
		return
	_streets = StreetLooks.new()
	if _streets.error != "":
		_finish("CELLS: " + _streets.error)
		return
	_veg = VegetationBuilder.new()
	if _veg.error != "":
		_finish("CELLS: " + _veg.error)
		return
	_clutter = VegetationBuilder.new("res://data/art/clutter.json", "Clutter")
	if _clutter.error != "":
		_finish("CELLS: " + _clutter.error)
		return
	_make_materials()
	_veg.make_assets()
	_clutter.make_assets()
	_signs = StreetSigns.new(str(_cfg.cells_dir) + "/materials")
	_paint = GroundPaint.new(str(_cfg.cells_dir) + "/materials")
	_crossings = _signs.find(src, _proj)
	print("CELLS: %d street sign intersections" % _crossings.size())

	# Landmarks: replaced OSM buildings, exclusion circles, ground holes, flat pads, placed instances.
	var skip_ways := {}
	var exclusions: Array = []
	var holes: Array[Rect2] = []
	var keys := landmarks.keys()
	keys.sort()
	for key: String in keys:
		var lm: Dictionary = landmarks[key]
		var pos := _proj.to_local(float(lm.lat), float(lm.lon))
		var rot := deg_to_rad(float(lm.get("rotation_deg", 0.0)))
		for id in lm.get("replaces_osm_ways", []):
			skip_ways[int(id)] = true
		if lm.has("exclusion_radius_m"):
			exclusions.append([pos, float(lm.exclusion_radius_m)])
		for ex: Array in lm.get("exclusions", []):  # extra circles [local x, local z, radius] for long buildings
			exclusions.append([pos + Vector2(ex[0], ex[1]).rotated(-rot), float(ex[2])])
		for r in lm.get("no_plant_rects", []):  # building footprints: no trees, grass, clutter or fences inside
			_no_plant.append(_landmark_rect(r, pos, rot))
		for h in lm.get("ground_holes", []):
			holes.append(_landmark_rect(h, pos, rot))
		var pads: Array = lm.get("terrain_pads", []).duplicate()  # several pads for a lot that isn't one rectangle
		if lm.has("terrain_pad"):
			pads.push_front(lm.terrain_pad)
		for r: Array in pads:
			_field.add_pad(_landmark_rect(r, pos, rot), _field.sample(pos.x, pos.y), float(lm.get("terrain_pad_blend_m", 10.0)))
		if lm.has("ground_paint"):
			_paint.add(DataLoader.load_json(str(lm.ground_paint)), key, pos, rot)
	var road_halves := {}
	for k: String in DRIVABLE:
		road_halves[k] = float(ROAD_WIDTHS[k]) * 0.5
	_water = WaterBuilder.new(src, _proj, _field, road_halves)
	ResourceSaver.save(_water.material, str(_cfg.cells_dir) + "/materials/water.tres", ResourceSaver.FLAG_CHANGE_PATH)
	print("CELLS: %d water bodies carved" % _water.bodies)
	var landmark_y := {}
	var world := Node3D.new()
	world.name = "BuildWorld"
	add_child(world)
	for key: String in keys:
		var lm: Dictionary = landmarks[key]
		var pos := _proj.to_local(float(lm.lat), float(lm.lon))
		landmark_y[key] = snappedf(_field.sample(pos.x, pos.y), 0.001)
		var scene := load(str(lm.scene)) as PackedScene
		if scene:
			var node := scene.instantiate() as Node3D
			node.position = Vector3(pos.x, landmark_y[key], pos.y)
			node.rotation.y = deg_to_rad(float(lm.get("rotation_deg", 0.0)))
			world.add_child(node)

	var out_dir := str(_cfg.cells_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var index := {"version": 2, "cell_size": _grid.cell_size, "cells_x": _grid.cells_x, "cells_z": _grid.cells_z,
		"origin": [_grid.origin.x, _grid.origin.y], "datum_elevation_m": snappedf(_field.datum, 0.01),
		"landmarks": landmark_y, "cells": {}}
	var errors := 0
	var totals := {"buildings": 0, "plants": 0, "props": 0, "spawns": 0, "nav": 0, "ways": 0, "loot": 0}
	var rows := maxi(1, int(_cfg.get("build_batch_rows", 3.0)))
	for row0 in range(0, _grid.cells_z, rows):
		var row1 := mini(row0 + rows, _grid.cells_z)
		_reset_batch()
		var batch: Array[Vector2i] = []
		for z in range(maxi(row0 - 1, 0), mini(row1 + 1, _grid.cells_z)):
			for x in _grid.cells_x:
				var c := Vector2i(x, z)
				_cells[c] = _new_cell(c)
				if z >= row0 and z < row1:
					batch.append(c)
		print("CELLS: rows %d-%d of %d (%d cells + %d context), %.0f s so far" % [row0, row1 - 1, _grid.cells_z,
			batch.size(), _cells.size() - batch.size(), (Time.get_ticks_msec() - t0) / 1000.0])
		for c: Vector2i in _cells:
			_build_terrain(c, holes)
			_build_far_terrain(c)
		_build_buildings(src, skip_ways, exclusions)
		_build_ms_buildings(exclusions)
		totals.ways = maxi(totals.ways, _build_roads(src))
		_build_spawns(src)
		_build_vegetation()
		_build_clutter()
		_place_signs()
		for c: Vector2i in _cells:
			_finish_cell(c, world)
		totals.nav += _bake_navigation(world, batch)
		for c: Vector2i in batch:
			var cell: Dictionary = _cells[c]
			totals.buildings += int(cell.b_count)
			totals.plants += cell.veg.size()
			totals.props += cell.clutter.size()
			totals.spawns += int(cell.spawn_count)
			totals.loot += cell.loot.size()
			var near_path := "%s/cell_%s.scn" % [out_dir, _grid.key(c)]
			var far_path := "%s/cell_%s_far.scn" % [out_dir, _grid.key(c)]
			errors += _save_scene(cell.root, near_path)
			errors += _save_scene(cell.far_root, far_path)
			index.cells[_grid.key(c)] = {"near": near_path, "far": far_path, "buildings": cell.b_count, "spawns": cell.spawn_count}
		for c: Vector2i in _cells:
			var cell: Dictionary = _cells[c]
			cell.root.free()
			cell.far_root.free()
		_cells.clear()
	var spawn_lm: Dictionary = landmarks.get("bonk_bunker", {})
	if not spawn_lm.is_empty():
		var p := _proj.to_local(float(spawn_lm.lat), float(spawn_lm.lon))
		index.spawn_hint = [p.x, landmark_y.get("bonk_bunker", 0.0), p.y]
	var f := FileAccess.open(out_dir + "/index.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(index, "\t"))
	f.close()
	_finish("CELLS: %d cells (%d save errors) in %.1f s: %d buildings, %d road ways, %d plants, %d clutter props, %d zombie spawns, %d loot spots, %d navmesh polygons, datum %.1f m, landmark heights %s" % [
		index.cells.size(), errors, (Time.get_ticks_msec() - t0) / 1000.0, totals.buildings, totals.ways, totals.plants,
		totals.props, totals.spawns, totals.loot, totals.nav, _field.datum, landmark_y])


# Per-batch lookups are rebuilt by every batch's passes; clear the previous batch's.
func _reset_batch() -> void:
	_corners.clear()
	_ways.clear()
	_clear_hash.clear()
	_houses.clear()
	_bld_hash.clear()
	_street_hash.clear()
	_osm_polys.clear()
	_osm_hash.clear()


# --- inputs ---------------------------------------------------------------------------

func _load_heights() -> bool:
	var path := str(_cfg.elevation_path)
	var meta := DataLoader.load_json(path + ".json")
	if meta.is_empty() or not FileAccess.file_exists(path):
		_finish("CELLS: no elevation data - run tools/map_import/fetch_elevation.tscn first")
		return false
	var tif := TiffReader.read_f32(FileAccess.get_file_as_bytes(path))
	if tif.has("error"):
		_finish("CELLS: elevation file unreadable: %s" % tif.error)
		return false
	_field = HeightField.new(tif.width, tif.height, tif.values, meta.bbox, _proj)
	return true


# Map-axis bounds of a local rect [x0, z0, x1, z1] (all four corners, so off-axis rotations like Kenwood's work).
func _landmark_rect(r: Array, pos: Vector2, rot: float) -> Rect2:
	var out := Rect2(Vector2(r[0], r[1]).rotated(-rot) + pos, Vector2.ZERO)
	for c: Vector2 in [Vector2(r[2], r[1]), Vector2(r[2], r[3]), Vector2(r[0], r[3])]:
		out = out.expand(c.rotated(-rot) + pos)
	return out


func _make_materials() -> void:
	var dir := str(_cfg.cells_dir) + "/materials"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var specs := {"roof": Color.WHITE, "far": Color.WHITE}
	for mat_name: String in specs:
		var m := StandardMaterial3D.new()
		m.albedo_color = specs[mat_name]
		m.roughness = 0.95
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if mat_name == "far" or mat_name == "roof":
			m.vertex_color_use_as_albedo = true
		ResourceSaver.save(m, "%s/%s.tres" % [dir, mat_name], ResourceSaver.FLAG_CHANGE_PATH)
		_mats[mat_name] = m
	for look: String in _looks.data.looks:
		var w := _looks.make_wall_material(look)
		ResourceSaver.save(w, "%s/wall_%s.tres" % [dir, look], ResourceSaver.FLAG_CHANGE_PATH)
		_mats["wall_" + look] = w
	var extra := {"ground": _streets.make_ground_material(), "pitched_roof": _streets.make_pitched_roof_material()}
	for id: String in _streets.surface_ids():
		extra["street_" + id] = _streets.make_surface_material(id)
	for mat_name: String in extra:
		ResourceSaver.save(extra[mat_name], "%s/%s.tres" % [dir, mat_name], ResourceSaver.FLAG_CHANGE_PATH)
		_mats[mat_name] = extra[mat_name]


func _new_cell(c: Vector2i) -> Dictionary:
	var root := Node3D.new()
	root.name = "cell_" + _grid.key(c)
	var far_root := Node3D.new()
	far_root.name = "cell_%s_far" % _grid.key(c)
	var cell := {"root": root, "far_root": far_root, "terrain_faces": PackedVector3Array(),
		"walls": {}, "roof_st": SurfaceTool.new(), "pitched_st": SurfaceTool.new(), "pitched_used": false, "b_faces": PackedVector3Array(),
		"b_count": 0, "streets": {}, "veg": [], "clutter": [], "loot": [], "signs": [], "spawns": Node3D.new(), "spawn_count": 0,
		"far_st": SurfaceTool.new(), "terrain_st": SurfaceTool.new(), "bed_faces": PackedVector3Array()}
	for k in ["roof_st", "pitched_st", "far_st", "terrain_st"]:
		cell[k].begin(Mesh.PRIMITIVE_TRIANGLES)
	cell.spawns.name = "ZombieSpawns"
	return cell


# --- terrain ------------------------------------------------------------------------

func _build_terrain(c: Vector2i, holes: Array[Rect2]) -> void:
	var cell: Dictionary = _cells[c]
	var rect := _grid.rect_of(c)
	var step := float(_cfg.terrain_step_m)
	var n := roundi(rect.size.x / step)
	var st: SurfaceTool = cell.terrain_st
	var faces: PackedVector3Array = cell.terrain_faces
	var bed: PackedVector3Array = cell.bed_faces
	for iz in n:
		for ix in n:
			var x0 := rect.position.x + ix * step
			var z0 := rect.position.y + iz * step
			var q := Rect2(x0, z0, step, step)
			var hit := false
			for hole in holes:
				if q.intersects(hole):
					hit = true
					break
			if not hit:
				_terrain_quad(st, bed if _water.is_water(Vector2(x0, z0)) or _water.is_water(Vector2(x0 + step, z0 + step))
					or _water.is_water(Vector2(x0 + step, z0)) or _water.is_water(Vector2(x0, z0 + step)) else faces, x0, z0, x0 + step, z0 + step)
				continue
			# Quad touches a landmark hole: pads make it flat, so cut it into rects around the hole.
			var pieces: Array[Rect2] = [q]
			for hole in holes:
				pieces = _subtract(pieces, hole)
			for pc in pieces:
				_terrain_quad(st, faces, pc.position.x, pc.position.y, pc.end.x, pc.end.y)
	cell.terrain_faces = faces
	cell.bed_faces = bed


func _terrain_quad(st: SurfaceTool, faces: PackedVector3Array, x0: float, z0: float, x1: float, z1: float) -> void:
	var a := Vector3(x0, _water.ground(x0, z0), z0)
	var b := Vector3(x1, _water.ground(x1, z0), z0)
	var c := Vector3(x1, _water.ground(x1, z1), z1)
	var d := Vector3(x0, _water.ground(x0, z1), z1)
	for v in [a, b, c, a, c, d]:
		st.set_normal(_normal_at(v.x, v.z))
		st.set_uv(Vector2(v.x, v.z))
		st.add_vertex(v)
		faces.append(v)


func _normal_at(x: float, z: float) -> Vector3:
	var s := 2.0
	return Vector3(_field.sample(x - s, z) - _field.sample(x + s, z), 2.0 * s, _field.sample(x, z - s) - _field.sample(x, z + s)).normalized()


func _build_far_terrain(c: Vector2i) -> void:
	var cell: Dictionary = _cells[c]
	var rect := _grid.rect_of(c)
	var step := float(_cfg.far_terrain_step_m)
	var n := roundi(rect.size.x / step)
	var st: SurfaceTool = cell.far_st
	for iz in n:
		for ix in n:
			var x0 := rect.position.x + ix * step
			var z0 := rect.position.y + iz * step
			var a := Vector3(x0, _water.ground(x0, z0), z0)
			var b := Vector3(x0 + step, _water.ground(x0 + step, z0), z0)
			var cc := Vector3(x0 + step, _water.ground(x0 + step, z0 + step), z0 + step)
			var d := Vector3(x0, _water.ground(x0, z0 + step), z0 + step)
			for v: Vector3 in [a, b, cc, a, cc, d]:
				st.set_color(COLOR_GROUND)
				st.set_normal(_normal_at(v.x, v.z))
				st.add_vertex(v)


func _subtract(rects: Array[Rect2], hole: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for rc in rects:
		if not rc.intersects(hole):
			out.append(rc)
			continue
		var i := rc.intersection(hole)
		if i.position.y > rc.position.y:
			out.append(Rect2(rc.position.x, rc.position.y, rc.size.x, i.position.y - rc.position.y))
		if i.end.y < rc.end.y:
			out.append(Rect2(rc.position.x, i.end.y, rc.size.x, rc.end.y - i.end.y))
		if i.position.x > rc.position.x:
			out.append(Rect2(rc.position.x, i.position.y, i.position.x - rc.position.x, i.size.y))
		if i.end.x < rc.end.x:
			out.append(Rect2(i.end.x, i.position.y, rc.end.x - i.end.x, i.size.y))
	return out


# --- buildings -------------------------------------------------------------------------

# Returns Vector2i(built, skipped). Each building goes into the cell holding its centre.
func _build_buildings(src: Dictionary, skip_ways: Dictionary, exclusions: Array) -> Vector2i:
	var built := 0
	var skipped := 0
	for el: Dictionary in src.get("elements", []):
		var tags: Dictionary = el.get("tags", {})
		var geom: Array = el.get("geometry", [])
		if not tags.has("building") or geom.size() < 4:
			continue
		var poly := PackedVector2Array()
		for g: Dictionary in geom:
			poly.append(_proj.to_local(float(g.lat), float(g.lon)))
		if poly[0].distance_to(poly[poly.size() - 1]) < 0.01:
			poly.remove_at(poly.size() - 1)
		var centre := _centre(poly)
		_remember_osm(poly, centre)
		if not _cells.has(_grid.cell_of(Vector3(centre.x, 0, centre.y))):
			continue
		if skip_ways.has(int(el.id)) or _excluded(centre, exclusions):
			skipped += 1
			continue
		_place_building(poly, centre, _building_height(tags), str(tags.building))
		built += 1
	return Vector2i(built, skipped)


# Microsoft footprints (D-040) where OSM has no building. Returns Vector3i(added, duplicates, at landmarks).
func _build_ms_buildings(exclusions: Array) -> Vector3i:
	var data := DataLoader.load_json(str(_cfg.get("buildings_path", "")))
	if data.is_empty():
		print("CELLS: no Microsoft footprints - run tools/map_import/fetch_buildings.tscn to fill in missing buildings")
		return Vector3i.ZERO
	var added := 0
	var dupes := 0
	var landmark := 0
	for b: Dictionary in data.get("buildings", []):
		var poly := PackedVector2Array()
		for pt in b.coords:
			poly.append(_proj.to_local(float(pt[1]), float(pt[0])))
		if poly.size() > 3 and poly[0].distance_to(poly[poly.size() - 1]) < 0.01:
			poly.remove_at(poly.size() - 1)
		if poly.size() < 3:
			continue
		var centre := _centre(poly)
		if not _cells.has(_grid.cell_of(Vector3(centre.x, 0, centre.y))):
			continue
		if _excluded(centre, exclusions):
			landmark += 1
			continue
		if _overlaps_osm(poly, centre):
			dupes += 1
			continue
		var h := float(b.get("height", -1.0))
		_place_building(poly, centre, clampf(h, 2.5, 60.0) if h > 0.0 else _height_from_area(poly), "")
		added += 1
	return Vector3i(added, dupes, landmark)


# height = ground to roof top. Small near-rectangular footprints of gable classes get a pitched roof over their
# oriented rectangle (walls follow that rectangle); everything else keeps its outline and a flat roof.
func _place_building(poly: PackedVector2Array, centre: Vector2, height: float, osm_tag: String) -> void:
	var cls := _looks.classify(osm_tag, FootprintShape.area(poly))
	var def := _looks.class_def(cls)
	var look := _looks.pick_look(cls, centre)
	var rnd := BuildingLooks.rand01(centre, 3)
	var cell: Dictionary = _cells[_grid.cell_of(Vector3(centre.x, 0, centre.y))]
	if not cell.walls.has(look):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		cell.walls[look] = st
	var wall_st: SurfaceTool = cell.walls[look]
	var outline := poly
	var rect := {}
	if str(def.roof) == "gable":
		rect = FootprintShape.oriented_rect(poly)
		if FootprintShape.rectangularity(poly, rect) < float(_looks.data.gable_min_rectangularity):
			rect = {}
		else:
			outline = FootprintShape.rect_corners(rect)
	var base := INF
	var top := -INF
	for p in outline:
		var h := _field.sample(p.x, p.y)
		base = minf(base, h)
		top = maxf(top, h)
	var min_wall := float(_looks.data.min_wall_height_m)
	_remember_building(outline, centre, cls)
	if rect.is_empty():
		_walls(wall_st, cell.b_faces, outline, base - 0.3, top + height, rnd)
		_flat_roof(cell.roof_st, cell.b_faces, outline, top + height, _looks.roof_color(centre, false))
		_extrude(cell.far_st, null, outline, base - 0.3, top + height, COLOR_BUILDING)
	else:
		var rise := minf(float(rect.width) * 0.5 * tan(deg_to_rad(float(def.pitch_deg))), maxf(height - min_wall, 1.0))
		var eave := top + maxf(min_wall, height - rise)
		_walls(wall_st, cell.b_faces, outline, base - 0.3, eave, rnd)
		cell.pitched_used = true
		_gable_roof(wall_st, cell.pitched_st, cell.b_faces, rect, base - 0.3, eave, rise, _looks.roof_color(centre, true), rnd)
		_extrude(cell.far_st, null, outline, base - 0.3, eave + rise * 0.5, COLOR_BUILDING)
	cell.b_count += 1


# Near-detail walls with the BuildingWall shader's UV/UV2/COLOR contract (see shaders/building_wall.gdshader).
func _walls(st: SurfaceTool, faces: PackedVector3Array, poly: PackedVector2Array, y0: float, y1: float, rnd: float) -> void:
	if _signed_area(poly) < 0.0:
		poly.reverse()
	var col := Color((y1 - y0) / 64.0, rnd, 0.0)
	var along := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var edge_len := a.distance_to(b)
		if edge_len < 0.01:
			continue
		var e := (b - a) / edge_len
		var n := Vector3(e.y, 0.0, -e.x)
		var verts := [[a, y0, 0.0], [b, y0, edge_len], [b, y1, edge_len], [a, y0, 0.0], [b, y1, edge_len], [a, y1, 0.0]]
		for vt: Array in verts:
			var p: Vector2 = vt[0]
			var y: float = vt[1]
			var t: float = vt[2]
			st.set_color(col)
			st.set_normal(n)
			st.set_uv(Vector2(along + t, y - y0))
			st.set_uv2(Vector2(edge_len, t))
			var v := Vector3(p.x, y, p.y)
			st.add_vertex(v)
			faces.append(v)
		along += edge_len


func _flat_roof(st: SurfaceTool, faces: PackedVector3Array, poly: PackedVector2Array, y: float, color: Color) -> void:
	for i in Geometry2D.triangulate_polygon(poly):
		var v := Vector3(poly[i].x, y, poly[i].y)
		st.set_color(color)
		st.set_normal(Vector3.UP)
		st.add_vertex(v)
		faces.append(v)


# Two roof slopes along the rectangle's long axis (overhanging the walls), plus the two gable-end triangles
# in the wall material (no windows there). Slope UV = (metres along the ridge, metres down from the ridge).
func _gable_roof(wall_st: SurfaceTool, roof_st: SurfaceTool, faces: PackedVector3Array, rect: Dictionary,
		y0: float, eave: float, rise: float, color: Color, rnd: float) -> void:
	var ov := float(_looks.data.gable_overhang_m)
	var c: Vector2 = rect.centre
	var u: Vector2 = rect.axis
	var v := Vector2(-u.y, u.x)
	var hl := float(rect.length) * 0.5
	var hw := float(rect.width) * 0.5
	var drop := ov * rise / maxf(hw, 0.01)
	var ridge := eave + rise
	var r0 := c - u * (hl + ov)
	var r1 := c + u * (hl + ov)
	for side: float in [-1.0, 1.0]:
		var e0: Vector2 = r0 + v * (hw + ov) * side
		var e1: Vector2 = r1 + v * (hw + ov) * side
		var quad := [Vector3(r0.x, ridge, r0.y), Vector3(r1.x, ridge, r1.y), Vector3(e1.x, eave - drop, e1.y),
			Vector3(r0.x, ridge, r0.y), Vector3(e1.x, eave - drop, e1.y), Vector3(e0.x, eave - drop, e0.y)]
		var q0: Vector3 = quad[0]
		var n: Vector3 = (quad[1] - q0).cross(quad[2] - q0).normalized()
		if n.y < 0.0:
			n = -n
		var slope := Vector2(hw + ov, rise + drop).length()
		for p: Vector3 in quad:
			var flat := Vector2(p.x, p.z)
			roof_st.set_color(color)
			roof_st.set_normal(n)
			roof_st.set_uv(Vector2((flat - r0).dot(u), slope if absf(p.y - ridge) > 0.001 else 0.0))
			roof_st.add_vertex(p)
			faces.append(p)
	var col := Color(0.0, rnd, 0.0)
	for end: float in [-1.0, 1.0]:
		var m := c + u * hl * end
		var a := m - v * hw
		var b := m + v * hw
		var n3 := Vector3(u.x * end, 0.0, u.y * end)
		var tri := [[a, eave, 0.0], [b, eave, hw * 2.0], [m, ridge, hw]]
		for vt: Array in tri:
			var p: Vector2 = vt[0]
			var y: float = vt[1]
			var t: float = vt[2]
			wall_st.set_color(col)
			wall_st.set_normal(n3)
			wall_st.set_uv(Vector2(t, y - y0))
			wall_st.set_uv2(Vector2.ZERO)
			var q := Vector3(p.x, y, p.y)
			wall_st.add_vertex(q)
			faces.append(q)


func _signed_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a


func _centre(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / poly.size()


func _remember_osm(poly: PackedVector2Array, centre: Vector2) -> void:
	var index := _osm_polys.size()
	_osm_polys.append([poly, centre])
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	for gz in range(floori(lo.y / DEDUPE_GRID), floori(hi.y / DEDUPE_GRID) + 1):
		for gx in range(floori(lo.x / DEDUPE_GRID), floori(hi.x / DEDUPE_GRID) + 1):
			var k := Vector2i(gx, gz)
			if not _osm_hash.has(k):
				_osm_hash[k] = []
			_osm_hash[k].append(index)


# True if this footprint overlaps any OSM building (centre inside either, or the outlines intersect).
func _overlaps_osm(poly: PackedVector2Array, centre: Vector2) -> bool:
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	for gz in range(floori(lo.y / DEDUPE_GRID), floori(hi.y / DEDUPE_GRID) + 1):
		for gx in range(floori(lo.x / DEDUPE_GRID), floori(hi.x / DEDUPE_GRID) + 1):
			for i in _osm_hash.get(Vector2i(gx, gz), []):
				var other: PackedVector2Array = _osm_polys[i][0]
				if Geometry2D.is_point_in_polygon(centre, other) or Geometry2D.is_point_in_polygon(_osm_polys[i][1], poly):
					return true
				if not Geometry2D.intersect_polygons(poly, other).is_empty():
					return true
	return false


# No height estimate: sheds, houses and bigger buildings by footprint area.
func _height_from_area(poly: PackedVector2Array) -> float:
	var area := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	area = absf(area) * 0.5
	if area < 40.0:
		return 3.0
	return 5.0 if area < 400.0 else 7.0


func _excluded(centre: Vector2, exclusions: Array) -> bool:
	for ex in exclusions:
		if centre.distance_to(ex[0]) <= ex[1]:
			return true
	return false


func _building_height(tags: Dictionary) -> float:
	if tags.has("height"):
		var h := str(tags.height).replace("m", "").strip_edges()
		if h.is_valid_float():
			return h.to_float()
	if tags.has("building:levels") and str(tags["building:levels"]).is_valid_float():
		return str(tags["building:levels"]).to_float() * 3.0 + 1.0
	return BUILDING_HEIGHTS.get(str(tags.building), DEFAULT_BUILDING_HEIGHT)


# Walls + flat roof from y0 to y1, for the far shell (faces may be null). color.r < 0 = no vertex colour.
func _extrude(st: SurfaceTool, faces: Variant, poly: PackedVector2Array, y0: float, y1: float, color: Color) -> void:
	var area := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	if area < 0.0:
		poly.reverse()
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var e := (b - a).normalized()
		var tri := [Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y),
			Vector3(a.x, y0, a.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y)]
		for v: Vector3 in tri:
			if color.r >= 0.0:
				st.set_color(color)
			st.set_normal(Vector3(e.y, 0.0, -e.x))
			st.add_vertex(v)
			if faces != null:
				faces.append(v)
	var idx := Geometry2D.triangulate_polygon(poly)
	for i in idx:
		var v := Vector3(poly[i].x, y1, poly[i].y)
		if color.r >= 0.0:
			st.set_color(color)
		st.set_normal(Vector3.UP)
		st.add_vertex(v)
		if faces != null:
			faces.append(v)


# --- roads -----------------------------------------------------------------------------

# Strips draped over the terrain in ROAD_STEP pieces; each piece goes to the cell holding its middle. Surface,
# centre line and sidewalks come from StreetLooks; lines, curbs and sidewalks stop where another street crosses.
func _build_roads(src: Dictionary) -> int:
	var ways: Array = []
	for el: Dictionary in src.get("elements", []):
		var tags: Dictionary = el.get("tags", {})
		var kind := str(tags.get("highway", ""))
		if not ROAD_WIDTHS.has(kind) or str(tags.get("footway", "")) == "crossing":
			continue
		var pts: Array[Vector2] = []
		for g: Dictionary in el.get("geometry", []):
			pts.append(_proj.to_local(float(g.lat), float(g.lon)))
		if pts.size() < 2:
			continue
		var drivable := kind in DRIVABLE
		var half := float(ROAD_WIDTHS[kind]) * 0.5
		var lanes := clampi(int(str(tags.get("lanes", "2")).to_int() / 2), 1, 4)
		var rank := DRIVABLE.size() - DRIVABLE.find(kind) if drivable else 0
		ways.append({"kind": kind, "drivable": drivable, "half": half, "pts": pts,
			"surface": _streets.surface_for(kind, tags, drivable), "centre": _streets.centre_line(kind),
			"lanes": lanes, "lift": ROAD_LIFT + rank * 0.004 if drivable else float(_streets.data.sidewalk.lift_m)})
	_ways = ways
	var sw: Dictionary = _streets.data.sidewalk
	for w: Dictionary in ways:
		var walks := bool(w.drivable) and _streets.has_sidewalks(w.kind)
		var inner := float(w.half) + float(sw.parkway_m)
		var mid_off := inner + float(sw.width_m) * 0.5
		for j in range(w.pts.size() - 1):
			var a: Vector2 = w.pts[j]
			var b: Vector2 = w.pts[j + 1]
			if a.distance_to(b) < 0.01:
				continue
			_hash_segment(_clear_hash, [a, b, float(w.half) + float(sw.curb_width_m)])
			if walks:
				var side := (b - a).normalized().orthogonal()
				for sgn: float in [-1.0, 1.0]:
					_hash_segment(_clear_hash, [a + side * sgn * mid_off, b + side * sgn * mid_off, float(sw.width_m) * 0.5])
	for i in ways.size():
		var w: Dictionary = ways[i]
		if not w.drivable or w.kind == "service":
			continue  # sidewalks and lines carry on across alleys and driveways
		for j in range(w.pts.size() - 1):
			var a: Vector2 = w.pts[j]
			var b: Vector2 = w.pts[j + 1]
			if a.distance_to(b) < 0.01:
				continue
			var wh := float(w.half)
			var entry := [i, a, b, wh, (b - a).normalized()]
			var lo: Vector2 = (a.min(b) - Vector2.ONE * wh) / STREET_GRID
			var hi: Vector2 = (a.max(b) + Vector2.ONE * wh) / STREET_GRID
			for gz in range(floori(lo.y), floori(hi.y) + 1):
				for gx in range(floori(lo.x), floori(hi.x) + 1):
					var k := Vector2i(gx, gz)
					if not _street_hash.has(k):
						_street_hash[k] = []
					_street_hash[k].append(entry)
	var count := 0
	for i in ways.size():
		if _build_way(i, ways[i]):
			count += 1
	return count


func _build_way(idx: int, w: Dictionary) -> bool:
	var sw: Dictionary = _streets.data.sidewalk
	var margin := float(_streets.data.intersection_margin_m)
	var half := float(w.half)
	var lift := float(w.lift)
	var walks := bool(w.drivable) and _streets.has_sidewalks(w.kind)
	var inner := half + float(sw.parkway_m)
	var outer := inner + float(sw.width_m)
	var walk_lift := float(sw.lift_m)
	var curb_top := lift + float(sw.curb_height_m)
	var curb_out := half + float(sw.curb_width_m)
	var lines := Color(float(w.centre), float(w.lanes) / 4.0, half / 16.0, 1.0)
	var along := 0.0
	var used := false
	var was_crossing := false
	for i in range(w.pts.size() - 1):
		var a: Vector2 = w.pts[i]
		var b: Vector2 = w.pts[i + 1]
		var length := a.distance_to(b)
		if length < 0.01:
			continue
		var dir := (b - a) / length
		var side := dir.orthogonal()
		var steps := ceili(length / ROAD_STEP)
		for k in steps:
			var t0 := float(k) / steps
			var t1 := float(k + 1) / steps
			var p0 := a.lerp(b, t0)
			var p1 := a.lerp(b, t1)
			var mid := (p0 + p1) * 0.5
			var c := _grid.cell_of(Vector3(mid.x, 0, mid.y))
			if not _cells.has(c):
				continue
			var s0 := along + length * t0
			var s1 := along + length * t1
			var crossing := bool(w.drivable) and _crossing(mid, dir, idx, half + margin)
			if crossing != was_crossing and walks:
				_corners.append([mid, dir, idx, half])
			was_crossing = crossing
			var col := lines
			col.a = 0.0 if crossing else 1.0
			_strip(_street_st(c, w.surface), p0, p1, side, -half, half, lift, lift, s0, s1, 0.0, col)
			used = true
			if not walks:
				continue
			for sgn: float in [-1.0, 1.0]:
				var walk_mid := mid + side * sgn * (inner + outer) * 0.5
				if not _crossing(walk_mid, dir, idx, float(sw.width_m) * 0.5 + margin):
					_strip(_street_st(c, "sidewalk"), p0, p1, side * sgn, inner, outer, walk_lift, walk_lift, s0, s1,
						(inner + outer) * 0.5, Color(0, 0, 0, 0))
				if not crossing:
					var st := _street_st(c, "sidewalk")
					_strip(st, p0, p1, side * sgn, half, half, lift, curb_top, s0, s1, half, Color(0, 0, 0, 0))
					_strip(st, p0, p1, side * sgn, half, curb_out, curb_top, curb_top, s0, s1, half, Color(0, 0, 0, 0))
					_strip(st, p0, p1, side * sgn, curb_out, curb_out, curb_top, 0.0, s0, s1, half, Color(0, 0, 0, 0))
		var cb := _grid.cell_of(Vector3(b.x, 0, b.y))
		if _cells.has(cb):
			_cap(_street_st(cb, w.surface), b, side, half, lift, along + length)
		along += length
	return used


func _hash_segment(h: Dictionary, entry: Array) -> void:
	var a: Vector2 = entry[0]
	var b: Vector2 = entry[1]
	var r: float = entry[2]
	var lo: Vector2 = (a.min(b) - Vector2.ONE * r) / STREET_GRID
	var hi: Vector2 = (a.max(b) + Vector2.ONE * r) / STREET_GRID
	for gz in range(floori(lo.y), floori(hi.y) + 1):
		for gx in range(floori(lo.x), floori(hi.x) + 1):
			var k := Vector2i(gx, gz)
			if not h.has(k):
				h[k] = []
			h[k].append(entry)


# True if a drivable street other than way `idx`, running at a real angle to `dir`, comes within its own half
# width + reach of point p (an intersection: no lines, curbs or sidewalk there).
func _crossing(p: Vector2, dir: Vector2, idx: int, reach: float) -> bool:
	var min_cos := cos(deg_to_rad(float(_streets.data.intersection_min_angle_deg)))
	var g := Vector2i(floori(p.x / STREET_GRID), floori(p.y / STREET_GRID))
	for gz in range(g.y - 1, g.y + 2):
		for gx in range(g.x - 1, g.x + 2):
			for e: Array in _street_hash.get(Vector2i(gx, gz), []):
				if e[0] == idx or absf(dir.dot(e[4])) > min_cos:
					continue
				var q := Geometry2D.get_closest_point_to_segment(p, e[1], e[2])
				if p.distance_to(q) < float(e[3]) + reach:
					return true
	return false


func _street_st(c: Vector2i, surface: String) -> SurfaceTool:
	var streets: Dictionary = _cells[c].streets
	if not streets.has(surface):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		streets[surface] = st
	return streets[surface]


# One piece of a strip parallel to p0->p1, from offset o0 to o1 along `side` at heights y0 / y1 above the ground
# (o0 == o1 makes a vertical face). Follows the StreetSurface shader's UV/UV2/COLOR contract.
func _strip(st: SurfaceTool, p0: Vector2, p1: Vector2, side: Vector2, o0: float, o1: float, y0: float, y1: float,
		s0: float, s1: float, centre: float, col: Color) -> void:
	var corners := [[p0, o0, y0, s0], [p1, o0, y0, s1], [p1, o1, y1, s1], [p0, o1, y1, s0]]
	var v: Array[Vector3] = []
	for cn: Array in corners:
		var p: Vector2 = cn[0] + side * float(cn[1])
		v.append(_on_ground(p, cn[2]))
	var n := (v[1] - v[0]).cross(v[3] - v[0]).normalized()
	if absf(o1 - o0) > 0.001 and n.y < 0.0:
		n = -n
	elif absf(o1 - o0) <= 0.001 and n.dot(Vector3(side.x, 0, side.y)) * (y1 - y0) > 0.0:
		n = -n  # vertical face: normal points away from the raised side
	var shade_n := n if absf(o1 - o0) <= 0.001 else Vector3.UP
	# Godot's front faces wind clockwise: flip the order when it is counter-clockwise around the shading normal.
	var order := [0, 2, 1, 0, 3, 2] if (v[1] - v[0]).cross(v[2] - v[0]).dot(shade_n) > 0.0 else [0, 1, 2, 0, 2, 3]
	for i: int in order:
		var p: Vector3 = v[i]
		st.set_color(col)
		st.set_normal(shade_n)
		st.set_uv(Vector2(p.x, p.z) if absf(o1 - o0) > 0.001 else Vector2(float(corners[i][3]), p.y))
		st.set_uv2(Vector2(float(corners[i][1]) - centre, float(corners[i][3])))
		st.add_vertex(p)


func _on_ground(p: Vector2, lift: float) -> Vector3:
	return Vector3(p.x, _field.sample(p.x, p.y) + lift, p.y)


# Round end of a strip (fills the gap where ways meet at an angle). No paint.
func _cap(st: SurfaceTool, c: Vector2, side: Vector2, radius: float, lift: float, along: float) -> void:
	var centre := _on_ground(c, lift)
	var fwd := side.orthogonal() * -1.0
	for i in 8:
		var a0 := TAU * i / 8.0
		var a1 := TAU * (i + 1) / 8.0
		for off: Vector2 in [Vector2.ZERO, Vector2(cos(a0), sin(a0)) * radius, Vector2(cos(a1), sin(a1)) * radius]:
			var v := centre if off == Vector2.ZERO else _on_ground(c + off, lift)
			st.set_color(Color(0, 0, 0, 0))
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(v.x, v.z))
			st.set_uv2(Vector2(off.dot(side), along + off.dot(fwd)))
			st.add_vertex(v)


# --- vegetation --------------------------------------------------------------------------

func _remember_building(outline: PackedVector2Array, centre: Vector2, cls: String) -> void:
	var i := _houses.size()
	_houses.append([outline, centre, cls])
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p in outline:
		lo = lo.min(p)
		hi = hi.max(p)
	for gz in range(floori(lo.y / STREET_GRID) - 1, floori(hi.y / STREET_GRID) + 2):
		for gx in range(floori(lo.x / STREET_GRID) - 1, floori(hi.x / STREET_GRID) + 2):
			var k := Vector2i(gx, gz)
			if not _bld_hash.has(k):
				_bld_hash[k] = []
			_bld_hash[k].append(i)


func _clear_of_roads(p: Vector2, r: float) -> bool:
	var pad := float(_veg.data.placement.clearance_road_m) + r
	for e: Array in _clear_hash.get(Vector2i(floori(p.x / STREET_GRID), floori(p.y / STREET_GRID)), []):
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, e[0], e[1])) < float(e[2]) + pad:
			return false
	return true


func _clear_of_buildings(p: Vector2, r: float) -> bool:
	var pad := float(_veg.data.placement.clearance_building_m) + r
	for i: int in _bld_hash.get(Vector2i(floori(p.x / STREET_GRID), floori(p.y / STREET_GRID)), []):
		var poly: PackedVector2Array = _houses[i][0]
		if Geometry2D.is_point_in_polygon(p, poly):
			return false
		for j in poly.size():
			if p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[j], poly[(j + 1) % poly.size()])) < pad:
				return false
	return true


func _in_map(p: Vector2) -> bool:
	return _cells.has(_grid.cell_of(Vector3(p.x, 0, p.y)))


# Adds one plant to its cell's list if the spot is on the map (and clear, when checked by the caller).
# yaw NAN = random; clutter = true puts it in the clutter list (data/art/clutter.json kinds).
func _plant(kind: String, rng: RandomNumberGenerator, p: Vector2, yaw := NAN, clutter := false) -> bool:
	if _water.is_water(p) or not _in_map(p):
		return false
	for r in _no_plant:
		if r.has_point(p):
			return false
	var cell: Dictionary = _cells[_grid.cell_of(Vector3(p.x, 0, p.y))]
	var b: VegetationBuilder = _clutter if clutter else _veg
	var variant := rng.randi_range(0, int(b.kinds[kind].meshes.size()) - 1)
	var sr := b.scale_range(kind)
	var entry := [kind, variant, _on_ground(p, -0.05), rng.randf() * TAU if is_nan(yaw) else yaw, rng.randf_range(sr.x, sr.y)]
	if clutter:
		cell.clutter.append(entry)
	else:
		cell.veg.append(entry)
		if kind.begins_with("tree_"):
			_far_tree(cell.far_st, entry[2], kind == "tree_bare", rng.randf_range(0.8, 1.2), rng)
	return true


# Low-detail tree for the far shell: a 6-sided double cone crown (~8-9 m tall at scale 1) on the vertex-coloured
# shell mesh (no extra draws).
func _far_tree(st: SurfaceTool, base: Vector3, bare: bool, scale: float, rng: RandomNumberGenerator) -> void:
	var r := (1.6 if bare else 2.8) * scale
	var mid := base + Vector3.UP * (5.5 if bare else 5.0) * scale
	var top := mid + Vector3.UP * (2.5 if bare else 3.0) * scale
	var bottom := base + Vector3.UP * 1.5 * scale
	var col := (COLOR_FAR_TREE_BARE if bare else COLOR_FAR_TREE) * rng.randf_range(0.85, 1.1)
	var ring: Array[Vector3] = []
	for i in 6:
		var a := TAU * i / 6.0
		ring.append(mid + Vector3(cos(a), 0, sin(a)) * r)
	for i in 6:
		var a := ring[i]
		var b := ring[(i + 1) % 6]
		for tip: Vector3 in [top, bottom]:
			var out := ((a + b + tip) / 3.0 - mid).normalized()
			var tri := [tip, a, b] if (a - tip).cross(b - tip).dot(out) < 0.0 else [tip, b, a]
			for v: Vector3 in tri:
				st.set_color(col)
				st.set_normal(out)
				st.add_vertex(v)


func _tree_kind(rng: RandomNumberGenerator) -> String:
	return "tree_bare" if rng.randf() < float(_veg.data.trees.bare_fraction) else "tree_leafy"


func _build_vegetation() -> int:
	var pl: Dictionary = _veg.data.placement
	var sw: Dictionary = _streets.data.sidewalk
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	# Street trees in the grass strip between curb and sidewalk.
	for idx in _ways.size():
		var w: Dictionary = _ways[idx]
		if not (bool(w.drivable) and _streets.has_sidewalks(w.kind)):
			continue
		var off := float(w.half) + float(sw.parkway_m) * 0.5
		var carried := rng.randf() * float(pl.street_tree_spacing_m)
		for j in range(w.pts.size() - 1):
			var a: Vector2 = w.pts[j]
			var b: Vector2 = w.pts[j + 1]
			var length := a.distance_to(b)
			if length < 0.01:
				continue
			var dir := (b - a) / length
			var t := carried
			while t < length:
				for sgn: float in [-1.0, 1.0]:
					var p := a + dir * t + dir.orthogonal() * sgn * off
					if rng.randf() < float(pl.street_tree_chance) and _in_map(p) \
							and not _crossing(p, dir, idx, 3.0) and _clear_of_buildings(p, 1.0):
						_plant(_tree_kind(rng), rng, p)
				t += float(pl.street_tree_spacing_m)
			carried = t - length
	# Yard trees and foundation bushes around houses.
	var ring: Array = pl.yard_tree_ring_m
	for h: Array in _houses:
		if h[2] != "house":
			continue
		var centre: Vector2 = h[1]
		var outline: PackedVector2Array = h[0]
		var n := int(float(pl.yard_trees_per_house) + rng.randf())
		for i in n:
			for attempt in 6:
				var a := rng.randf() * TAU
				var p := centre + Vector2(cos(a), sin(a)) * rng.randf_range(float(ring[0]), float(ring[1]))
				if _in_map(p) and _clear_of_roads(p, 1.0) and _clear_of_buildings(p, 1.5):
					_plant(_tree_kind(rng), rng, p)
					break
		for i in int(pl.foundation_shrubs_per_house):
			var j := rng.randi_range(0, outline.size() - 1)
			var e0 := outline[j]
			var e1 := outline[(j + 1) % outline.size()]
			var p := e0.lerp(e1, rng.randf_range(0.15, 0.85))
			var out := (e1 - e0).normalized().orthogonal()
			if Geometry2D.is_point_in_polygon(p + out * 0.5, outline):
				out = -out
			p += out * float(pl.shrub_offset_m)
			if _in_map(p) and _clear_of_roads(p, 0.5):
				_plant(["shrub_a", "shrub_b", "shrub_c"][rng.randi_range(0, 2)], rng, p)
	# Scattered ground cover, stumps and fallen trunks.
	for c: Vector2i in _cells:
		var r := _grid.rect_of(c)
		for spec: Array in [["grass_clump", int(pl.grass_clumps_per_cell), 0.3], ["stump", int(pl.stumps_per_cell), 1.0],
				["dead_trunk", int(pl.dead_trunks_per_cell), 2.5]]:
			for i in int(spec[1]):
				var p := r.position + Vector2(rng.randf(), rng.randf()) * r.size
				if _clear_of_roads(p, spec[2]) and _clear_of_buildings(p, spec[2]):
					_plant(spec[0], rng, p)
	# Landmark plantings (map coords, e.g. data/landmarks/yanney_plants.json from the Yanney builder).
	for key: String in _landmarks:
		var file := str(_landmarks[key].get("plants_file", ""))
		if file == "":
			continue
		for e: Array in DataLoader.load_json(file).get("plants", []):
			var p := Vector2(float(e[1]), float(e[2]))
			if _in_map(p) and _clear_of_roads(p, 1.0) and _clear_of_buildings(p, 1.0):
				_plant(str(e[0]), rng, p)
	var total := 0
	for c: Vector2i in _cells:
		total += _cells[c].veg.size()
	return total


# --- clutter (D-044) ----------------------------------------------------------------------

# Yaw that turns a prop's local +X to point along v (x, z).
func _yaw_x(v: Vector2) -> float:
	return atan2(-v.y, v.x)


# Yaw that turns a prop's local +Z (car length) to point along v (x, z).
func _yaw_z(v: Vector2) -> float:
	return atan2(v.x, v.y)


# Street signs (D-070) for the intersections in this batch's cells, on a clear corner.
func _place_signs() -> void:
	var half_of := func(kind: String) -> float: return float(ROAD_WIDTHS.get(kind, 7.0)) * 0.5
	var clear := func(p: Vector2) -> bool: return _on_map_clear(p, 0.4) and _clear_of_roads(p, -0.6) and not _water.is_water(p)
	for x: Array in _crossings:
		var p: Vector2 = x[0]
		if not _in_map(p):
			continue
		var at := _signs.place(x, half_of, clear)
		if at.is_empty() or not _in_map(at[0]):
			continue
		_cells[_grid.cell_of(Vector3(at[0].x, 0, at[0].y))].signs.append([_on_ground(at[0], 0.0), at[1], x[1], at[2], x[4]])


func _on_map_clear(p: Vector2, r: float) -> bool:
	return _in_map(p) and _clear_of_buildings(p, r)


# Calls fn(point, direction, way index, way) every `spacing` metres along every way whose kind is in kinds
# (a kind "service" matches only alleys when alleys_only).
func _along_ways(kinds: Array, spacing: float, rng: RandomNumberGenerator, fn: Callable, alleys_only := false) -> void:
	for idx in _ways.size():
		var w: Dictionary = _ways[idx]
		if not w.kind in kinds:
			continue
		if w.kind == "service" and alleys_only and w.surface != _streets.data.default_surface.alley:
			continue
		var carried := rng.randf() * spacing
		for j in range(w.pts.size() - 1):
			var a: Vector2 = w.pts[j]
			var b: Vector2 = w.pts[j + 1]
			var length := a.distance_to(b)
			if length < 0.01:
				continue
			var dir := (b - a) / length
			var t := carried
			while t < length:
				fn.call(a + dir * t, dir, idx, w)
				t += spacing
			carried = t - length


func _build_clutter() -> int:
	var pl: Dictionary = _clutter.data.placement
	var sw: Dictionary = _streets.data.sidewalk
	var rng := RandomNumberGenerator.new()
	rng.seed = 6868
	var count := [0]
	var put := func(kind: String, p: Vector2, yaw: float, r: float) -> bool:
		if _on_map_clear(p, r):
			count[0] += 1
			return _plant(kind, rng, p, yaw, true)
		return false
	# Power poles: alleys (middle of the alley edge) and streets (grass strip by the curb).
	var f1 := func(p: Vector2, dir: Vector2, idx: int, w: Dictionary) -> void:
		if rng.randf() > float(pl.pole_chance) or _crossing(p, dir, idx, 4.0):
			return
		var off := float(w.half) + (0.6 if w.kind == "service" else 0.7)
		put.call("power_pole", p + dir.orthogonal() * off, _yaw_x(dir.orthogonal()), 0.2)
	_along_ways(pl.pole_kinds, float(pl.pole_spacing_m), rng, f1, true)
	# Street lamps on the bigger streets, both sides alternating.
	var side_flip := [1.0]
	var f2 := func(p: Vector2, dir: Vector2, idx: int, w: Dictionary) -> void:
		if _crossing(p, dir, idx, 3.0):
			return
		side_flip[0] = -side_flip[0]
		var side: Vector2 = dir.orthogonal() * float(side_flip[0])
		put.call("street_lamp", p + side * (float(w.half) + 0.6), _yaw_x(-side), 0.2)
	_along_ways(pl.lamp_kinds, float(pl.lamp_spacing_m), rng, f2)
	# Hydrants where streets meet.
	for c: Array in _corners:
		if rng.randf() < float(pl.hydrant_chance):
			var side: Vector2 = (c[1] as Vector2).orthogonal() * (1.0 if rng.randf() < 0.5 else -1.0)
			put.call("hydrant", (c[0] as Vector2) + side * (float(c[3]) + 0.8), rng.randf() * TAU, 0.2)
	# Utility boxes in the grass strip.
	var f3 := func(p: Vector2, dir: Vector2, idx: int, w: Dictionary) -> void:
		if rng.randf() > float(pl.utility_box_chance) or _crossing(p, dir, idx, 3.0):
			return
		var side := dir.orthogonal() * (1.0 if rng.randf() < 0.5 else -1.0)
		put.call("utility_box", p + side * (float(w.half) + float(sw.parkway_m) * 0.5), _yaw_x(dir), 0.4)
	_along_ways(_streets.data.sidewalk_kinds, float(pl.utility_box_spacing_m), rng, f3)
	# Barriers: a few blocks across bigger streets (an old checkpoint).
	var f4 := func(p: Vector2, dir: Vector2, idx: int, w: Dictionary) -> void:
		if rng.randf() > float(pl.barrier_chance) or _crossing(p, dir, idx, 6.0):
			return
		var side := dir.orthogonal()
		var n := rng.randi_range(2, 4)
		for i in n:
			var off := (float(i) - (n - 1) * 0.5) * 1.9 + rng.randf_range(-0.3, 0.3)
			_plant_clutter_free(rng, "road_barrier", p + side * off + dir * rng.randf_range(-0.6, 0.6), _yaw_x(side) + rng.randf_range(-0.3, 0.3))
			count[0] += 1
	_along_ways(pl.barrier_kinds, float(pl.barrier_spacing_m), rng, f4)
	# Abandoned cars left in the street, some skewed.
	var f5 := func(p: Vector2, dir: Vector2, idx: int, w: Dictionary) -> void:
		if w.kind == "service" or rng.randf() > float(pl.street_car_chance) or _crossing(p, dir, idx, 6.0):
			return
		var lane := dir.orthogonal() * (float(w.half) * 0.45) * (1.0 if rng.randf() < 0.5 else -1.0)
		_car(rng, p + lane, _yaw_z(dir) + rng.randf_range(-0.6, 0.6))
		count[0] += 1
	_along_ways(DRIVABLE, float(pl.street_car_spacing_m), rng, f5)
	# Alley debris.
	var f6 := func(p: Vector2, dir: Vector2, idx: int, w: Dictionary) -> void:
		if rng.randf() > float(pl.alley_debris_chance):
			return
		var kinds: Array = pl.debris_kinds
		var side := dir.orthogonal() * (1.0 if rng.randf() < 0.5 else -1.0)
		put.call(kinds[rng.randi_range(0, kinds.size() - 1)], p + side * (float(w.half) + 0.4), rng.randf() * TAU, 0.0)
	_along_ways(["service"], float(pl.alley_debris_spacing_m), rng, f6, true)
	# Chain-link fence runs along alleys (panel + post every panel width), one collider per run.
	var panel_w: float = _clutter.kinds.fence_panel.meshes[0].get_aabb().size.x
	var f7 := func(p: Vector2, dir: Vector2, idx: int, w: Dictionary) -> void:
		if rng.randf() > float(pl.fence_chance):
			return
		var side := dir.orthogonal() * (1.0 if rng.randf() < 0.5 else -1.0)
		var start := p + side * (float(w.half) + float(pl.fence_offset_m))
		var n := int(float(pl.fence_run_m) * rng.randf_range(0.4, 1.0) / panel_w)
		var placed := 0
		for i in n:
			var c := start + dir * (panel_w * (i + 0.5))
			if not _on_map_clear(c, 0.3) or not _clear_of_roads(c, 0.0):
				break
			_plant("fence_panel", rng, c, _yaw_x(dir), true)
			_plant("fence_post", rng, start + dir * (panel_w * i), 0.0, true)
			placed += 1
		if placed > 0:
			_plant("fence_post", rng, start + dir * (panel_w * placed), 0.0, true)
			var mid := start + dir * (panel_w * placed * 0.5)
			if not _in_map(mid):
				return
			var cell: Dictionary = _cells[_grid.cell_of(Vector3(mid.x, 0, mid.y))]
			cell.clutter.append(["_box", 0, _on_ground(mid, 1.2), _yaw_x(dir), Vector3(panel_w * placed, 2.4, 0.1)])
			count[0] += placed * 2 + 1
	_along_ways(["service"], float(pl.fence_run_m), rng, f7, true)
	# Around houses: a car at the curb out front, trash cans by the curb, junk in the yard.
	var ring: Array = pl.house_debris_ring_m
	for h: Array in _houses:
		if h[2] != "house":
			continue
		var centre: Vector2 = h[1]
		var front := _nearest_street(centre, 40.0)
		if not front.is_empty():
			var q: Vector2 = front[0]
			var dir: Vector2 = front[1]
			var half: float = front[2]
			var to_house := (centre - q).normalized()
			if rng.randf() < float(pl.curb_car_chance_per_house) and not _crossing(q, dir, int(front[3]), 6.0):
				var cp := q + to_house * (half - 1.15)
				var cy := _yaw_z(dir) + rng.randf_range(-0.06, 0.06) + (PI if rng.randf() < 0.5 else 0.0)
				if _car(rng, cp, cy) and rng.randf() < float(pl.loot_car_chance):
					_loot_spot(cp, cy, "car_trunk", "Car Trunk", Vector3(2.3, 1.7, 4.9))
				count[0] += 1
			if rng.randf() < float(pl.porch_loot_chance):
				var door := _house_edge(h[0], q)
				var pp := door + (q - door).normalized() * 0.9
				if _clear_of_roads(pp, 0.5) and _plant("cardboard_box", rng, pp, rng.randf() * TAU, true):
					_loot_spot(pp, 0.0, "porch", "Porch Package", Vector3(0.9, 0.8, 0.9))
			var tp := q + to_house * (half + 0.7) + dir * rng.randf_range(-3.0, 3.0)
			if rng.randf() < float(pl.trash_can_chance_per_house):
				if put.call("trash_can", tp, rng.randf() * TAU, 0.3) and rng.randf() < float(pl.loot_trash_chance):
					_loot_spot(tp, 0.0, "trash", "Trash Can", Vector3(0.9, 1.3, 0.9))
				if rng.randf() < 0.5:
					put.call("trashbag", q + to_house * (half + 0.9) + dir * rng.randf_range(-3.0, 3.0), rng.randf() * TAU, 0.3)
		var kinds: Array = pl.debris_kinds
		for i in int(float(pl.house_debris_per_house) + rng.randf()):
			var a := rng.randf() * TAU
			var p := centre + Vector2(cos(a), sin(a)) * rng.randf_range(float(ring[0]), float(ring[1])) * 1.6
			if _clear_of_roads(p, 0.3):
				var kind: String = kinds[rng.randi_range(0, kinds.size() - 1)]
				if put.call(kind, p, rng.randf() * TAU, float(pl.clearance_building_m)) and kind in ["barrel", "cardboard_box"] \
						and rng.randf() < float(pl.loot_debris_chance):
					_loot_spot(p, 0.0, "junk_pile", "Barrel" if kind == "barrel" else "Cardboard Box", Vector3(0.9, 1.1, 0.9))
	return count[0]


# Loot spot (D-056) at map point p: an invisible searchable box around a clutter prop, written into the cell as
# LootSpots/L<n> with a stable container_id c<x>_<z>_<n>. Capped per cell (placement.loot_spots_per_cell_max).
func _loot_spot(p: Vector2, yaw: float, table: String, label: String, size: Vector3) -> void:
	var cell: Dictionary = _cells[_grid.cell_of(Vector3(p.x, 0, p.y))]
	if cell.loot.size() < int(_clutter.data.placement.loot_spots_per_cell_max):
		cell.loot.append([table, label, _on_ground(p, -0.05), yaw, size])


# Closest point on a building outline to q (the side facing the street).
func _house_edge(outline: PackedVector2Array, q: Vector2) -> Vector2:
	var best := outline[0]
	for i in outline.size():
		var e := Geometry2D.get_closest_point_to_segment(q, outline[i], outline[(i + 1) % outline.size()])
		if e.distance_squared_to(q) < best.distance_squared_to(q):
			best = e
	return best


func _add_loot_spots(c: Vector2i, root: Node3D, spots: Array) -> void:
	if spots.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "LootSpots"
	root.add_child(holder)
	for i in spots.size():
		var s: Array = spots[i]
		var body := StaticBody3D.new()
		body.name = "L%d" % i
		body.collision_layer = 8  # interactable only: rays find it, nobody bumps into it
		body.collision_mask = 0
		body.set_script(LOOT_SCRIPT)
		body.set("container_id", "c%s_%d" % [_grid.key(c), i])
		body.set("display_name", s[1])
		body.set("loot_table", s[0])
		body.set("size", s[4])
		body.set("streamed", true)
		body.position = s[2]
		body.rotation.y = s[3]
		var col := CollisionShape3D.new()
		col.name = "Collider"
		body.add_child(col)
		holder.add_child(body)


func _plant_clutter_free(rng: RandomNumberGenerator, kind: String, p: Vector2, yaw: float) -> void:
	if _in_map(p):
		_plant(kind, rng, p, yaw, true)


func _car(rng: RandomNumberGenerator, p: Vector2, yaw: float) -> bool:
	if not _in_map(p):
		return false
	if rng.randf() < float(_clutter.data.placement.covered_car_fraction):
		return _plant("covered_car", rng, p, yaw, true)
	return _plant("car", rng, p, yaw, true)


# [closest point, direction, half width, way index] on the nearest drivable non-alley street within max_d, or [].
func _nearest_street(p: Vector2, max_d: float) -> Array:
	var best: Array = []
	var best_d := max_d
	var g := Vector2i(floori(p.x / STREET_GRID), floori(p.y / STREET_GRID))
	for gz in range(g.y - 1, g.y + 2):
		for gx in range(g.x - 1, g.x + 2):
			for e: Array in _street_hash.get(Vector2i(gx, gz), []):
				var q := Geometry2D.get_closest_point_to_segment(p, e[1], e[2])
				var d := p.distance_to(q)
				if d < best_d:
					best_d = d
					best = [q, e[4], float(e[3]), int(e[0])]
	return best


# --- zombie spawns ------------------------------------------------------------------------

func _build_spawns(src: Dictionary) -> int:
	var n := 0
	var lo := _grid.area_rect(-SPAWN_EDGE_MARGIN).position
	var hi := _grid.area_rect(-SPAWN_EDGE_MARGIN).end
	for el: Dictionary in src.get("elements", []):
		var kind := str(el.get("tags", {}).get("highway", ""))
		if not kind in DRIVABLE:
			continue
		var carried := SPAWN_SPACING * 0.5
		var geom: Array = el.get("geometry", [])
		for i in range(geom.size() - 1):
			var a := _proj.to_local(float(geom[i].lat), float(geom[i].lon))
			var b := _proj.to_local(float(geom[i + 1].lat), float(geom[i + 1].lon))
			var length := a.distance_to(b)
			var t := carried
			while t < length:
				var p := a.lerp(b, t / length)
				if p.x > lo.x and p.y > lo.y and p.x < hi.x and p.y < hi.y and _in_map(p):
					var cell: Dictionary = _cells[_grid.cell_of(Vector3(p.x, 0, p.y))]
					var m := Marker3D.new()
					m.name = "Spawn%d" % cell.spawn_count
					m.position = _on_ground(p, 0.1)
					cell.spawns.add_child(m)
					cell.spawn_count += 1
					n += 1
				t += SPAWN_SPACING
			carried = t - length
	return n


# --- assembling ---------------------------------------------------------------------------

func _finish_cell(c: Vector2i, world: Node3D) -> void:
	var cell: Dictionary = _cells[c]
	var root: Node3D = cell.root
	var terrain := StaticBody3D.new()
	terrain.name = "Terrain"
	root.add_child(terrain)
	cell.terrain_st.generate_tangents()
	_add_mesh(terrain, "Mesh", cell.terrain_st, _mats.ground)
	_add_trimesh(terrain, cell.terrain_faces)
	_paint.add_cell(_grid.rect_of(c), root, _water.ground, float(_cfg.terrain_step_m))
	if not cell.bed_faces.is_empty():
		var bed := StaticBody3D.new()
		bed.name = "WaterBed"
		bed.collision_layer = BED_LAYER
		root.add_child(bed)
		_add_trimesh(bed, cell.bed_faces)
	_water.add_cell(_grid.rect_of(c), root, cell.far_st)
	if cell.b_count > 0:
		var buildings := StaticBody3D.new()
		buildings.name = "Buildings"
		root.add_child(buildings)
		var looks: Array = cell.walls.keys()
		looks.sort()
		for look: String in looks:
			var st: SurfaceTool = cell.walls[look]
			st.generate_tangents()
			_add_mesh(buildings, "Walls_" + look, st, _mats["wall_" + look])
		_add_mesh(buildings, "Roofs", cell.roof_st, _mats.roof)
		if cell.pitched_used:
			cell.pitched_st.generate_tangents()
			_add_mesh(buildings, "PitchedRoofs", cell.pitched_st, _mats.pitched_roof)
		_add_trimesh(buildings, cell.b_faces)
	var surfaces: Array = cell.streets.keys()
	surfaces.sort()
	for id: String in surfaces:
		var st: SurfaceTool = cell.streets[id]
		st.generate_tangents()
		_add_mesh(root, "Street_" + id, st, _mats["street_" + id], false)
	_veg.build_cell(root, cell.veg)
	_clutter.build_cell(root, cell.clutter)
	_signs.build_cell(root, cell.signs)
	_add_boundary(c, root)
	root.add_child(cell.spawns)
	_add_loot_spots(c, root, cell.loot)
	var far: Node3D = cell.far_root
	var mi := MeshInstance3D.new()
	mi.name = "Shell"
	mi.mesh = cell.far_st.commit()
	mi.material_override = _mats.far
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	far.add_child(mi)
	world.add_child(root)  # in the tree so the navmesh parser sees global transforms


func _add_boundary(c: Vector2i, root: Node3D) -> void:
	var r := _grid.rect_of(c)
	var walls: Array = []
	if c.x == 0:
		walls.append([Vector3(r.position.x - 0.5, 0, r.get_center().y), Vector3(1, 0, r.size.y)])
	if c.x == _grid.cells_x - 1:
		walls.append([Vector3(r.end.x + 0.5, 0, r.get_center().y), Vector3(1, 0, r.size.y)])
	if c.y == 0:
		walls.append([Vector3(r.get_center().x, 0, r.position.y - 0.5), Vector3(r.size.x, 0, 1)])
	if c.y == _grid.cells_z - 1:
		walls.append([Vector3(r.get_center().x, 0, r.end.y + 0.5), Vector3(r.size.x, 0, 1)])
	if walls.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "Boundary"
	root.add_child(body)
	for w in walls:
		var p: Vector3 = w[0]
		var s: Vector3 = w[1]
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(s.x, 400.0, s.z)
		shape.shape = box
		shape.position = Vector3(p.x, _field.sample(p.x, p.z), p.z)
		body.add_child(shape)


func _bake_navigation(world: Node3D, batch: Array[Vector2i]) -> int:
	var template := NavigationMesh.new()
	template.cell_size = 0.25
	template.cell_height = 0.25
	template.agent_height = 1.75
	template.agent_radius = 0.5
	template.agent_max_climb = 0.25
	template.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	template.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	template.geometry_collision_mask = 0xFFFFFFFF & ~(BED_LAYER | WaterBuilder.SURFACE_LAYER | 8)  # no paths through water; loot spots (layer 4 only) are walk-through
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(template, source, world)
	var total := 0
	var done := 0
	for c: Vector2i in batch:
		var r := _grid.rect_of(c)
		var nm := template.duplicate() as NavigationMesh
		# border_size is trimmed off the bake box, so grow the box by it: tiles then meet exactly at the cell edge.
		nm.border_size = NAV_BORDER
		nm.edge_max_error = 1.0  # Godot: tile-aligned borders need <= 1.0
		nm.filter_baking_aabb = AABB(Vector3(r.position.x - NAV_BORDER, -200.0, r.position.y - NAV_BORDER),
			Vector3(r.size.x + NAV_BORDER * 2.0, 400.0, r.size.y + NAV_BORDER * 2.0))
		NavigationServer3D.bake_from_source_geometry_data(nm, source)
		var region := NavigationRegion3D.new()
		region.name = "Navigation"
		region.navigation_mesh = nm
		_cells[c].root.add_child(region)
		total += nm.get_polygon_count()
		done += 1
		if done % 10 == 0:
			print("CELLS: navmesh %d/%d cells, %d polygons so far" % [done, batch.size(), total])
	return total


func _save_scene(root: Node, path: String) -> int:
	_set_owner(root, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("CELLS: saving %s failed (%d)" % [path, err])
		return 1
	return 0


# --- helpers ----------------------------------------------------------------------------

func _add_mesh(parent: Node, node_name: String, st: SurfaceTool, mat: Material, shadows := true) -> void:
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _add_trimesh(body: StaticBody3D, faces: PackedVector3Array) -> void:
	if faces.is_empty():
		return
	var shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.backface_collision = true
	concave.set_faces(faces)
	shape.shape = concave
	body.add_child(shape)


func _set_owner(node: Node, owner_node: Node) -> void:
	for c in node.get_children():
		c.owner = owner_node
		_set_owner(c, owner_node)


func _finish(message: String) -> void:
	print(message)
	await get_tree().create_timer(20.0).timeout
	get_tree().quit()
