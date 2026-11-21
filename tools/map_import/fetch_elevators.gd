# FetchElevators — one-off map lookup (D-103, user-approved download): asks Overpass for grain elevators, silos,
# grain/industrial landuse and the railway lines inside the map area, saves the raw JSON to
# data/map/source/kearney_elevators.osm.json and lists each find with map x/z to tests/_look/elevators.txt.
# One request per run, identifying User-Agent (OSM usage policy). Depends on: DataLoader, CellGrid, MapProjection,
# data/map/import_config.json.
extends Node

const CONFIG_PATH := "res://data/map/import_config.json"
const OUT_PATH := "res://data/map/source/kearney_elevators.osm.json"
const REPORT := "res://tests/_look/elevators.txt"


func _ready() -> void:
	var cfg := DataLoader.load_json(CONFIG_PATH)
	var lat := float(cfg.center_lat)
	var lon := float(cfg.center_lon)
	var area := CellGrid.from_config(cfg).area_rect(0.0)
	var proj := MapProjection.new(lat, lon)
	var nw := proj.to_lat_lon(area.position.x, area.position.y)
	var se := proj.to_lat_lon(area.end.x, area.end.y)
	var bbox := "%.6f,%.6f,%.6f,%.6f" % [se.x, nw.y, nw.x, se.y]
	var query := ("[out:json][timeout:90];(nwr[\"man_made\"~\"silo|storage_tank|works\"](%s);nwr[\"building\"~\"silo|grain_silo|industrial|warehouse\"](%s);"
		+ "nwr[\"industrial\"](%s);nwr[\"landuse\"=\"industrial\"](%s);nwr[\"name\"~\"[Ee]levator|[Cc]o-?op|[Gg]rain|[Mm]ill\"](%s);"
		+ "way[\"railway\"~\"rail|abandoned|disused\"](%s););out geom;") % [bbox, bbox, bbox, bbox, bbox, bbox]
	var http := HTTPRequest.new()
	http.timeout = 120.0
	add_child(http)
	var headers := PackedStringArray(["User-Agent: " + str(cfg.user_agent), "Content-Type: application/x-www-form-urlencoded"])
	var err := http.request(str(cfg.overpass_url), headers, HTTPClient.METHOD_POST, "data=" + query.uri_encode())
	if err != OK:
		_done("could not start the request (%d)" % err)
		return
	var res: Array = await http.request_completed
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		_done("Overpass failed (result %d, HTTP %d)" % [res[0], res[1]])
		return
	var text: String = res[3].get_string_from_utf8()
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		_done("not JSON")
		return
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	var lines := PackedStringArray(["saved %d bytes" % text.length()])
	for el: Dictionary in data.get("elements", []):
		var tags: Dictionary = el.get("tags", {})
		var geom: Array = el.get("geometry", [])
		var c := Vector2.ZERO
		var n := 0
		if el.has("lat"):
			c = Vector2(float(el.lon), float(el.lat))
			n = 1
		for g: Variant in geom:
			if g is Dictionary:
				c += Vector2(float(g.lon), float(g.lat))
				n += 1
		if n == 0:
			lines.append("%s %d (no geometry) %s" % [el.type, el.id, str(tags)])
			continue
		c /= n
		var xz: Vector2 = proj.to_local(c.y, c.x)
		var size := ""
		if geom.size() > 1:
			var lo := Vector2(INF, INF)
			var hi := -lo
			for g: Variant in geom:
				if g is Dictionary:
					var p: Vector2 = proj.to_local(float(g.lat), float(g.lon))
					lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
					hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
			size = " size %.0fx%.0f" % [hi.x - lo.x, hi.y - lo.y]
		lines.append("%s %d at %.0f, %.0f%s %s" % [el.type, el.id, xz.x, xz.y, size, str(tags)])
	_done("\n".join(lines))


func _done(text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT.get_base_dir()))
	var f := FileAccess.open(REPORT, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("ELEVATORS: done")
	get_tree().quit()
