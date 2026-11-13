# BuildWorldMap — map import pipeline, last step (D-048; run this scene directly, no internet needed). Draws the
# players' in-game map from the same sources as the cells: parks/grass, lakes + rivers, every OSM + Microsoft
# building footprint and every road/path (cased by class) over the whole map area at metres_per_pixel, renders it in
# a SubViewport and saves it as one lossless PortableCompressedTexture2D (no import step), plus a meta file with the
# area and the labels (landmark ids / lat-lon resolved to world x/z) that the WorldMapUI draws on top, and street
# names along every named street (shortened like the signs) that the Minimap draws (D-070).
# Look + labels in data/map/world_map.json. Depends on: DataLoader, MapProjection, CellGrid, import_config.json,
# landmarks.json, data/map/water.json, StreetSigns (names, data/art/street_signs.json).
extends Node

const CONFIG_PATH := "res://data/map/import_config.json"
const MAP_PATH := "res://data/map/world_map.json"
const LANDMARKS_PATH := "res://data/map/landmarks.json"
const WATER_PATH := "res://data/map/water.json"
const ROAD_WIDTHS := {
	"motorway": 14.0, "motorway_link": 8.0, "trunk": 12.0, "primary": 12.0, "primary_link": 8.0, "secondary": 10.0,
	"tertiary": 9.0, "tertiary_link": 7.0, "residential": 7.5, "unclassified": 7.0, "living_street": 6.0,
	"service": 4.5, "track": 3.0, "footway": 1.8, "path": 1.5, "cycleway": 2.0, "pedestrian": 3.0,
}
const PATHS := ["footway", "path", "cycleway", "pedestrian", "track"]
const STREET_NAME_EVERY_M := 220.0  # minimap street names (D-070)
const STREET_NAME_GAP_M := 150.0

var _cfg: Dictionary
var _map: Dictionary
var _proj: MapProjection
var _area: Rect2
var _mpp := 2.0
var _layers: Dictionary = {"park": [], "water": [], "building": []}  # PackedVector2Array polygons in pixels
var _rivers: Array = []  # [PackedVector2Array, width px]
var _roads: Array = []   # [PackedVector2Array, width px, kind]
var _street_names: Array = []  # [short name, x, z, angle] along named streets, for the minimap (D-070)


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	_cfg = DataLoader.load_json(CONFIG_PATH)
	_map = DataLoader.load_json(MAP_PATH)
	_proj = MapProjection.new(float(_cfg.center_lat), float(_cfg.center_lon))
	_area = CellGrid.from_config(_cfg).area_rect()
	_mpp = float(_map.metres_per_pixel)
	var size := Vector2i(ceili(_area.size.x / _mpp), ceili(_area.size.y / _mpp))
	_collect()
	print("MAP: %d parks, %d water, %d rivers, %d buildings, %d roads -> %dx%d px" % [_layers.park.size(),
		_layers.water.size(), _rivers.size(), _layers.building.size(), _roads.size(), size.x, size.y])

	var vp := SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.disable_3d = true
	add_child(vp)
	var canvas := Node2D.new()
	vp.add_child(canvas)
	canvas.draw.connect(_paint.bind(canvas, size))
	canvas.queue_redraw()
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png("res://tests/_look/world_map_render.png")  # check copy (tests/_look is not imported)
	print("MAP: rendered %dx%d" % [img.get_width(), img.get_height()])
	var tex := PortableCompressedTexture2D.new()
	tex.keep_compressed_buffer = true  # otherwise the data is dropped after GPU upload and the saved file is empty
	tex.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(str(_map.out_texture).get_base_dir()))
	var err := ResourceSaver.save(tex, str(_map.out_texture))
	var meta := {"area": [_area.position.x, _area.position.y, _area.size.x, _area.size.y], "pixels": [size.x, size.y],
		"texture": _map.out_texture, "labels": _labels(), "streets": _street_names}
	var f := FileAccess.open(str(_map.out_meta), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	print("MAP: saved %s (err %d), %d labels, %d street names, %.1f s" % [_map.out_texture, err, meta.labels.size(),
		_street_names.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	await get_tree().create_timer(20.0).timeout
	get_tree().quit()


func _paint(canvas: Node2D, size: Vector2i) -> void:
	var c: Dictionary = _map.colors
	canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(size)), _col(c.background))
	for layer: String in ["park", "water", "building"]:
		for poly: PackedVector2Array in _layers[layer]:
			canvas.draw_colored_polygon(poly, _col(c[layer]))
	for r: Array in _rivers:
		canvas.draw_polyline(r[0], _col(c.water), r[1], true)
	var major: Array = _map.major_roads
	for r: Array in _roads:  # paths first, then casings, then fills (majors last, on top)
		if r[2] in PATHS:
			canvas.draw_polyline(r[0], _col(c.path), maxf(r[1], 1.0), true)
	for r: Array in _roads:
		if not r[2] in PATHS:
			canvas.draw_polyline(r[0], _col(c.road_casing), r[1] + 2.0, true)
	for pass_major in [false, true]:
		for r: Array in _roads:
			if not r[2] in PATHS and (r[2] in major) == pass_major:
				canvas.draw_polyline(r[0], _col(c.major_road if pass_major else c.road), r[1], true)


# --- sources -------------------------------------------------------------------------------

func _collect() -> void:
	var src := DataLoader.load_json(str(_cfg.source_path))
	var water: Dictionary = DataLoader.load_json(WATER_PATH)
	var scale := float(_map.road_width_scale)
	var signs := DataLoader.load_json(StreetSigns.DATA_PATH)
	for el: Dictionary in src.get("elements", []):
		var tags: Dictionary = el.get("tags", {})
		var rings: Array = []
		if el.get("type", "") == "relation":
			for m: Dictionary in el.get("members", []):
				if str(m.get("role", "")) == "outer":
					rings.append(_px(m.get("geometry", [])))
		else:
			rings.append(_px(el.get("geometry", [])))
		if tags.has("building"):
			_add_poly("building", rings)
		elif str(tags.get("natural", "")) == "water":
			_add_poly("water", rings)
		elif tags.has("leisure") or tags.has("landuse"):
			_add_poly("park", rings)
		elif tags.has("waterway"):
			var w := float(water.waterway_widths_m.get(str(tags.waterway), 0.0))
			for key: String in water.name_overrides:
				if str(tags.get("name", "")).begins_with(key):
					w = float(water.name_overrides[key].width_m)
			if w > 0.0:
				_rivers.append([rings[0], maxf(w / _mpp, 1.5)])
		elif tags.has("highway") and ROAD_WIDTHS.has(str(tags.highway)):
			_roads.append([rings[0], float(ROAD_WIDTHS[str(tags.highway)]) * scale / _mpp, str(tags.highway)])
			if tags.has("name") and str(tags.highway) in signs.kinds:
				_name_street(StreetSigns.shorten(str(tags.name), signs.abbreviations), el.get("geometry", []))
	var ms := DataLoader.load_json(str(_cfg.get("buildings_path", "")))
	for b: Dictionary in ms.get("buildings", []):
		var pts := PackedVector2Array()
		for pt in b.coords:
			pts.append(_to_px(_proj.to_local(float(pt[1]), float(pt[0]))))
		_add_poly("building", [pts])


# A name every STREET_NAME_EVERY_M along a street (none closer than STREET_NAME_GAP_M to the same name).
func _name_street(street: String, geom: Array) -> void:
	var pts: Array[Vector2] = []
	for g: Dictionary in geom:
		pts.append(_proj.to_local(float(g.lat), float(g.lon)))
	var next := STREET_NAME_EVERY_M * 0.4
	var along := 0.0
	for i in range(pts.size() - 1):
		var seg := pts[i].distance_to(pts[i + 1])
		while seg > 0.01 and along + seg >= next:
			var p := pts[i].lerp(pts[i + 1], (next - along) / seg)
			var near := false
			for s: Array in _street_names:
				if s[0] == street and Vector2(s[1], s[2]).distance_to(p) < STREET_NAME_GAP_M:
					near = true
					break
			if not near:
				var d := pts[i + 1] - pts[i]
				_street_names.append([street, snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(atan2(d.y, d.x), 0.001)])
			next += STREET_NAME_EVERY_M
		along += seg


func _add_poly(layer: String, rings: Array) -> void:
	for poly: PackedVector2Array in rings:
		if poly.size() > 3 and poly[0].distance_to(poly[poly.size() - 1]) < 0.01:
			poly.remove_at(poly.size() - 1)
		if poly.size() >= 3 and not Geometry2D.triangulate_polygon(poly).is_empty():
			_layers[layer].append(poly)


func _px(geom: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for g: Dictionary in geom:
		out.append(_to_px(_proj.to_local(float(g.lat), float(g.lon))))
	return out


func _to_px(p: Vector2) -> Vector2:
	return (p - _area.position) / _mpp


func _labels() -> Array:
	var landmarks := DataLoader.load_json(LANDMARKS_PATH)
	var out: Array = []
	for l: Dictionary in _map.labels:
		var lat := 0.0
		var lon := 0.0
		if l.has("landmark"):
			var lm: Dictionary = landmarks.get(str(l.landmark), {})
			if lm.is_empty():
				push_warning("MAP: label '%s' names unknown landmark '%s'" % [l.name, l.landmark])
				continue
			lat = float(lm.lat)
			lon = float(lm.lon)
		else:
			lat = float(l.lat)
			lon = float(l.lon)
		var p := _proj.to_local(lat, lon)
		out.append({"name": l.name, "x": snappedf(p.x, 0.1), "z": snappedf(p.y, 0.1), "size": l.get("size", "minor"),
			"below": bool(l.get("below", false))})
	return out


func _col(c: Array) -> Color:
	return Color(float(c[0]), float(c[1]), float(c[2]))
