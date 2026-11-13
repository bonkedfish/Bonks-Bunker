# FetchElevation — map import pipeline, step 2 (run this scene directly, on a machine with internet).
# Downloads one USGS 3DEP elevation image (32-bit float GeoTIFF, uncompressed, lat/lon grid) covering the
# same area as fetch_osm (import config "area" rectangle + fetch_margin_m, D-048) at elevation_pixel_m per pixel, saves it
# to elevation_path plus a .json with its bounding box, then reads it back and prints the height range.
# The server keeps pixels square IN DEGREES and silently grows the box when the requested size doesn't match, so
# this asks for f=json first, records the extent the server actually used, then downloads that image (D-048).
# Two requests per run. Depends on: DataLoader, TiffReader, MapProjection, data/map/import_config.json.
# Output is consumed by tools/map_import/build_cells.gd.
extends Node

const CONFIG_PATH := "res://data/map/import_config.json"


func _ready() -> void:
	var cfg := DataLoader.load_json(CONFIG_PATH)
	var lat := float(cfg.get("center_lat", 0.0))
	var lon := float(cfg.get("center_lon", 0.0))
	if lat == 0.0:
		_finish("ELEV: run fetch_osm first (it fills in the map centre)")
		return
	var proj := MapProjection.new(lat, lon)
	var area := CellGrid.from_config(cfg).area_rect(float(cfg.get("area", {}).get("fetch_margin_m", 100.0)))
	var nw := proj.to_lat_lon(area.position.x, area.position.y)
	var se := proj.to_lat_lon(area.end.x, area.end.y)
	var bbox := [nw.y, se.x, se.y, nw.x]  # lon_min, lat_min, lon_max, lat_max
	# Square-in-degrees pixels no bigger than elevation_pixel_m in either direction.
	var deg := float(cfg.elevation_pixel_m) / 110540.0
	var size_x := ceili((bbox[2] - bbox[0]) / deg)
	var size_z := ceili((bbox[3] - bbox[1]) / deg)
	var query := "%s?bbox=%.7f,%.7f,%.7f,%.7f&bboxSR=4326&imageSR=4326&size=%d,%d&format=tiff&pixelType=F32" % [
		cfg.elevation_url, bbox[0], bbox[1], bbox[2], bbox[3], size_x, size_z] \
		+ "&compression=None&noDataInterpretation=esriNoDataMatchAny&interpolation=RSP_BilinearInterpolation"
	print("ELEV: requesting %dx%d px for %.0f x %.0f m" % [size_x, size_z, area.size.x, area.size.y])
	var http := HTTPRequest.new()
	http.timeout = 300.0
	add_child(http)
	var headers := PackedStringArray(["User-Agent: " + str(cfg.user_agent)])
	if http.request(query + "&f=json", headers) != OK:
		_finish("ELEV: could not start request")
		return
	var info: Array = await http.request_completed
	var meta_json: Variant = JSON.parse_string((info[3] as PackedByteArray).get_string_from_utf8())
	if info[1] != 200 or typeof(meta_json) != TYPE_DICTIONARY or not meta_json.has("extent") or not meta_json.has("href"):
		_finish("ELEV: USGS did not describe the image (HTTP %d)" % info[1])
		return
	var ext: Dictionary = meta_json.extent
	bbox = [float(ext.xmin), float(ext.ymin), float(ext.xmax), float(ext.ymax)]
	print("ELEV: server extent %s (asked %.6f..%.6f N)" % [bbox, se.x, nw.x])
	var url := str(meta_json.href)
	var err := http.request(url, headers)
	if err != OK:
		_finish("ELEV: could not start request (%d)" % err)
		return
	var res: Array = await http.request_completed
	var body: PackedByteArray = res[3]
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		_finish("ELEV: USGS failed (result %d, HTTP %d): %s" % [res[0], res[1], body.get_string_from_utf8().left(300)])
		return
	var tif := TiffReader.read_f32(body)
	if tif.has("error"):
		_finish("ELEV: unusable image: %s" % tif.error)
		return
	var path := str(cfg.elevation_path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(body)
	f.close()
	var meta := FileAccess.open(path + ".json", FileAccess.WRITE)
	meta.store_string(JSON.stringify({"bbox": bbox, "width": tif.width, "height": tif.height, "source": cfg.elevation_url}, "\t"))
	meta.close()
	var field := HeightField.new(tif.width, tif.height, tif.values, bbox, proj)
	var lo := INF
	var hi := -INF
	for v: float in tif.values:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	_finish("ELEV: saved %d bytes, %dx%d, elevation %.1f..%.1f m, map centre %.1f m (= y 0)" % [
		body.size(), tif.width, tif.height, lo, hi, field.datum])


func _finish(message: String) -> void:
	print(message)
	await get_tree().create_timer(20.0).timeout
	get_tree().quit()
