# FetchOSM — map import pipeline, step 1 (run this scene directly, on a machine with internet).
# Reads data/map/import_config.json. If center_lat/center_lon are 0, geocodes center_query with Nominatim
# and writes the result back into the config so later runs are reproducible. Then downloads every
# building and highway way in the map area (import config "area" rectangle + fetch_margin_m, D-048) from Overpass (with geometry) and saves the raw JSON to
# source_path. Prints a summary, including the buildings closest to the center.
# Respect OSM usage policies: one request each per run, identifying User-Agent, no bulk scraping.
# Depends on: DataLoader. Output is consumed by tools/map_import/build_cells.gd (D-039).
extends Node

const CONFIG_PATH := "res://data/map/import_config.json"

var _http: HTTPRequest
var _cfg: Dictionary


func _ready() -> void:
	_cfg = DataLoader.load_json(CONFIG_PATH)
	_http = HTTPRequest.new()
	_http.timeout = 300.0
	add_child(_http)
	var lat := float(_cfg.get("center_lat", 0.0))
	var lon := float(_cfg.get("center_lon", 0.0))
	if lat == 0.0 and lon == 0.0:
		var geo := await _geocode(str(_cfg.center_query))
		if geo.is_empty():
			_finish("FETCH: geocoding failed for '%s'" % _cfg.center_query)
			return
		lat = geo.lat
		lon = geo.lon
		print("FETCH: geocoded '%s' -> %.6f, %.6f (%s)" % [_cfg.center_query, lat, lon, geo.label])
		_cfg.center_lat = lat
		_cfg.center_lon = lon
		_save_text(CONFIG_PATH, JSON.stringify(_cfg, "\t"))
	var area := CellGrid.from_config(_cfg).area_rect(float(_cfg.get("area", {}).get("fetch_margin_m", 100.0)))
	var proj := MapProjection.new(lat, lon)
	var nw := proj.to_lat_lon(area.position.x, area.position.y)
	var se := proj.to_lat_lon(area.end.x, area.end.y)
	var bbox := "%.6f,%.6f,%.6f,%.6f" % [se.x, nw.y, nw.x, se.y]  # south, west, north, east
	# Buildings + roads, plus water, waterways, parks/leisure areas and grass for landmarks like Yanney Park (D-047).
	var query := ("[out:json][timeout:180];(way[\"building\"](%s);way[\"highway\"](%s);way[\"natural\"=\"water\"](%s);"
		+ "relation[\"natural\"=\"water\"](%s);way[\"waterway\"](%s);way[\"leisure\"](%s);way[\"landuse\"~\"grass|recreation_ground\"](%s););out geom;") \
		% [bbox, bbox, bbox, bbox, bbox, bbox, bbox]
	var body := "data=" + query.uri_encode()
	var headers := PackedStringArray(["User-Agent: " + str(_cfg.user_agent),
		"Content-Type: application/x-www-form-urlencoded"])
	var err := _http.request(str(_cfg.overpass_url), headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_finish("FETCH: could not start Overpass request (%d)" % err)
		return
	var res: Array = await _http.request_completed
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		_finish("FETCH: Overpass failed (result %d, HTTP %d): %s" % [res[0], res[1], res[3].get_string_from_utf8().left(300)])
		return
	var text: String = res[3].get_string_from_utf8()
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		_finish("FETCH: Overpass returned something that isn't JSON")
		return
	_save_text(str(_cfg.source_path), text)
	_summarize(data, lat, lon)
	_finish("FETCH: saved %d bytes to %s" % [text.length(), _cfg.source_path])


func _geocode(q: String) -> Dictionary:
	var url := "%s?q=%s&format=json&limit=1&addressdetails=0" % [_cfg.nominatim_url, q.uri_encode()]
	var err := _http.request(url, PackedStringArray(["User-Agent: " + str(_cfg.user_agent)]))
	if err != OK:
		return {}
	var res: Array = await _http.request_completed
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		print("FETCH: Nominatim HTTP %d" % res[1])
		return {}
	var arr: Variant = JSON.parse_string(res[3].get_string_from_utf8())
	if typeof(arr) != TYPE_ARRAY or arr.is_empty():
		return {}
	return {"lat": float(arr[0].lat), "lon": float(arr[0].lon), "label": str(arr[0].get("display_name", ""))}


func _summarize(data: Dictionary, lat: float, lon: float) -> void:
	var buildings := 0
	var roads := 0
	var nearest: Array = []
	for el: Dictionary in data.get("elements", []):
		var tags: Dictionary = el.get("tags", {})
		var geom: Array = el.get("geometry", [])
		if geom.is_empty():
			continue
		if tags.has("building"):
			buildings += 1
			var c := Vector2.ZERO
			for g: Dictionary in geom:
				c += Vector2(float(g.lon), float(g.lat))
			c /= geom.size()
			var dx := (c.x - lon) * 111320.0 * cos(deg_to_rad(lat))
			var dz := (c.y - lat) * 110540.0
			nearest.append([sqrt(dx * dx + dz * dz), el.id, tags])
		elif tags.has("highway"):
			roads += 1
	nearest.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	print("FETCH: %d buildings, %d highway ways" % [buildings, roads])
	for i in mini(5, nearest.size()):
		print("FETCH: near center: %.1f m  way %d  %s" % [nearest[i][0], nearest[i][1], nearest[i][2]])


func _save_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
	else:
		print("FETCH: could not write %s" % path)


func _finish(message: String) -> void:
	print(message)
	await get_tree().create_timer(20.0).timeout
	get_tree().quit()
