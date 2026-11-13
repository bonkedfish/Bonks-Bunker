# FetchBuildings — map import pipeline, step 2b (run this scene directly, on a machine with internet) (D-040).
# Fills in buildings OSM doesn't have: reads Microsoft Global ML Building Footprints' dataset-links.csv,
# finds the level-9 quadkey file(s) covering the map area (import config "area" rectangle + fetch_margin_m, D-048),
# downloads them (.csv.gz = gzipped GeoJSON lines), keeps footprints with a corner inside the square and
# saves them to buildings_path as { license, source, buildings: [{ coords: [[lon, lat]...], height, confidence }] }.
# Height -1 = no estimate. Depends on: DataLoader, MapProjection, data/map/import_config.json.
# Output is consumed by tools/map_import/build_cells.gd (OSM wins where both have a building).
extends Node

const CONFIG_PATH := "res://data/map/import_config.json"
const MAX_UNZIPPED := 1024 * 1024 * 1024

var _http: HTTPRequest
var _cfg: Dictionary


func _ready() -> void:
	_cfg = DataLoader.load_json(CONFIG_PATH)
	var proj := MapProjection.new(float(_cfg.center_lat), float(_cfg.center_lon))
	var area := CellGrid.from_config(_cfg).area_rect(float(_cfg.get("area", {}).get("fetch_margin_m", 100.0)))
	var nw := proj.to_lat_lon(area.position.x, area.position.y)
	var se := proj.to_lat_lon(area.end.x, area.end.y)
	var lon0 := nw.y
	var lon1 := se.y
	var lat0 := se.x
	var lat1 := nw.x
	var keys := {}
	for corner in [Vector2(lon0, lat0), Vector2(lon0, lat1), Vector2(lon1, lat0), Vector2(lon1, lat1)]:
		keys[_quadkey(corner.y, corner.x, 9)] = true
	print("MSB: map square needs quadkey(s) %s" % [keys.keys()])
	_http = HTTPRequest.new()
	_http.timeout = 600.0
	add_child(_http)

	var index := await _download(str(_cfg.buildings_index_url))
	if index.is_empty():
		_finish("MSB: could not download dataset-links.csv")
		return
	var lines := index.get_string_from_utf8().split("\n", false)
	var header := lines[0].strip_edges().to_lower().split(",")
	var col_key := header.find("quadkey")
	var col_url := header.find("url")
	var col_loc := header.find("location")
	if col_key < 0 or col_url < 0:
		_finish("MSB: unexpected dataset-links.csv header: %s" % lines[0])
		return
	var urls: Array[String] = []
	for i in range(1, lines.size()):
		var cols := lines[i].strip_edges().split(",")
		if cols.size() <= maxi(col_key, col_url):
			continue
		for k: String in keys:
			if cols[col_key].to_int() == k.to_int():
				urls.append(cols[col_url])
				print("MSB: %s quadkey %s -> %s" % [cols[col_loc] if col_loc >= 0 else "?", cols[col_key], cols[col_url]])
	if urls.is_empty():
		_finish("MSB: no files listed for quadkey(s) %s" % [keys.keys()])
		return

	var kept: Array = []
	var seen := 0
	var with_height := 0
	for url in urls:
		var gz := await _download(url)
		if gz.is_empty():
			_finish("MSB: download failed: %s" % url)
			return
		var text := gz.decompress_dynamic(MAX_UNZIPPED, FileAccess.COMPRESSION_GZIP).get_string_from_utf8()
		print("MSB: %s: %.0f KB compressed, %.0f KB of GeoJSON lines" % [url.get_file(), gz.size() / 1024.0, text.length() / 1024.0])
		for line in text.split("\n", false):
			seen += 1
			var f: Variant = JSON.parse_string(line)
			if typeof(f) != TYPE_DICTIONARY or not f.has("geometry"):
				continue
			var rings: Array = f.geometry.get("coordinates", [])
			if rings.is_empty():
				continue
			var ring: Array = rings[0]
			var inside := false
			for pt in ring:
				if pt[0] >= lon0 and pt[0] <= lon1 and pt[1] >= lat0 and pt[1] <= lat1:
					inside = true
					break
			if not inside:
				continue
			var props: Dictionary = f.get("properties", {})
			var h := float(props.get("height", -1.0))
			if h > 0.0:
				with_height += 1
			kept.append({"coords": ring, "height": h, "confidence": float(props.get("confidence", -1.0))})
	var out := {"license": "CDLA-Permissive-2.0", "source": "Microsoft Global ML Building Footprints", "files": urls, "buildings": kept}
	var path := str(_cfg.buildings_path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(out))
	file.close()
	_finish("MSB: kept %d of %d footprints inside the map square (%d with a height estimate) -> %s" % [kept.size(), seen, with_height, path])


func _download(url: String) -> PackedByteArray:
	var err := _http.request(url, PackedStringArray(["User-Agent: " + str(_cfg.user_agent)]))
	if err != OK:
		return PackedByteArray()
	var res: Array = await _http.request_completed
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		print("MSB: %s failed (result %d, HTTP %d)" % [url, res[0], res[1]])
		return PackedByteArray()
	return res[3]


# Bing-maps quadkey of the tile at `level` containing lat/lon.
func _quadkey(lat: float, lon: float, level: int) -> String:
	var n := 1 << level
	var x := clampi(floori((lon + 180.0) / 360.0 * n), 0, n - 1)
	var s := sin(deg_to_rad(lat))
	var y := clampi(floori((0.5 - log((1.0 + s) / (1.0 - s)) / (4.0 * PI)) * n), 0, n - 1)
	var key := ""
	for i in range(level, 0, -1):
		var digit := 0
		var mask := 1 << (i - 1)
		if x & mask:
			digit += 1
		if y & mask:
			digit += 2
		key += str(digit)
	return key


func _finish(message: String) -> void:
	print(message)
	await get_tree().create_timer(20.0).timeout
	get_tree().quit()
