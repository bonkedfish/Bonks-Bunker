# BuildPois — picks and builds the small walk-in POIs between the big landmarks (D-056; run this scene directly, no
# internet needed). Reads data/landmarks/pois.json + the OSM source: buildings whose shop/amenity tag maps to a style,
# sized within area_m2, min_spacing_m apart and landmark_clearance_m from data/map/landmarks.json, round-robin over
# styles up to max_count. Each is turned to face its nearest street (snapped to its footprint's oriented rectangle),
# built with poi_building.gd to world/landmarks/poi_<n>.scn, and listed in data/map/pois.json in landmark format
# (replaces its OSM way, flat pad, small exclusion). Re-run, then build_cells. Log: tests/_look/pois_build.txt.
# Depends on: DataLoader, MapProjection, FootprintShape, LandmarkKit, poi_building.gd.
extends Node

const DATA_PATH := "res://data/landmarks/pois.json"
const CONFIG_PATH := "res://data/map/import_config.json"
const LANDMARKS_PATH := "res://data/map/landmarks.json"
const PoiBuilding := preload("res://tools/landmarks/poi_building.gd")
const ROADS := ["primary", "secondary", "tertiary", "residential", "unclassified", "trunk", "service"]

var _log := PackedStringArray()


func _ready() -> void:
	var d := DataLoader.load_json(DATA_PATH)
	var cfg := DataLoader.load_json(CONFIG_PATH)
	var proj := MapProjection.new(float(cfg.center_lat), float(cfg.center_lon))
	var src := DataLoader.load_json(str(cfg.source_path))
	var area: Dictionary = cfg.area
	var lo := Vector2(float(area.x_min_m), float(area.z_min_m)) + Vector2(60, 60)
	var hi := Vector2(float(area.x_min_m) + float(area.cells_x) * float(cfg.cell_size_m),
		float(area.z_min_m) + float(area.cells_z) * float(cfg.cell_size_m)) - Vector2(60, 60)
	var landmark_pos: Array[Vector2] = []
	var landmarks := DataLoader.load_json(LANDMARKS_PATH)
	for key: String in landmarks:
		landmark_pos.append(proj.to_local(float(landmarks[key].lat), float(landmarks[key].lon)))
	# Street segments (for facing) and candidate buildings by style.
	var segs: Array = []
	var by_style: Dictionary = {}
	var tags_map: Dictionary = d.tags
	for el: Dictionary in src.get("elements", []):
		var t: Dictionary = el.get("tags", {})
		var geom: Array = el.get("geometry", [])
		if geom.size() < 2:
			continue
		if str(t.get("highway", "")) in ROADS:
			for i in range(geom.size() - 1):
				segs.append([proj.to_local(float(geom[i].lat), float(geom[i].lon)), proj.to_local(float(geom[i + 1].lat), float(geom[i + 1].lon))])
			continue
		if not t.has("building"):
			continue
		var tag := str(t.get("shop", t.get("amenity", "")))
		if not tags_map.has(tag):
			continue
		var poly := PackedVector2Array()
		for g: Dictionary in geom:
			poly.append(proj.to_local(float(g.lat), float(g.lon)))
		var a := FootprintShape.area(poly)
		var c := _centre(poly)
		if a < float(d.area_m2[0]) or a > float(d.area_m2[1]) or c.x < lo.x or c.y < lo.y or c.x > hi.x or c.y > hi.y:
			continue
		var near_lm := false
		for lp in landmark_pos:
			near_lm = near_lm or lp.distance_to(c) < float(d.landmark_clearance_m)
		if near_lm:
			continue
		var style := str(tags_map[tag])
		if not by_style.has(style):
			by_style[style] = []
		by_style[style].append({"poly": poly, "centre": c, "id": int(el.id), "name": str(t.get("name", "")), "tag": tag})
	# Round-robin pick.
	var picked: Array = []
	var styles: Array = by_style.keys()
	styles.sort()
	for s: String in styles:
		by_style[s].sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x.id < y.id)
	var progress := true
	while picked.size() < int(d.max_count) and progress:
		progress = false
		for s: String in styles:
			var list: Array = by_style[s]
			while not list.is_empty():
				var cand: Dictionary = list.pop_front()
				var ok := true
				for p: Dictionary in picked:
					ok = ok and (p.centre as Vector2).distance_to(cand.centre) >= float(d.min_spacing_m)
				if ok:
					cand.style = s
					picked.append(cand)
					progress = true
					break
			if picked.size() >= int(d.max_count):
				break
	# Build each one.
	var out := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d.seed)
	for i in picked.size():
		var p: Dictionary = picked[i]
		var rect := FootprintShape.oriented_rect(p.poly)
		var to_road := _nearest_dir(p.centre, segs)
		var u: Vector2 = rect.axis
		var v := Vector2(-u.y, u.x)
		var front := u
		for cand_dir: Vector2 in [u, -u, v, -v]:
			if cand_dir.dot(to_road) > front.dot(to_road):
				front = cand_dir
		var along_long := absf(front.dot(u)) > 0.5
		var width := float(rect.width) if along_long else float(rect.length)
		var depth := float(rect.length) if along_long else float(rect.width)
		var sc: Dictionary = d.size_clamp
		width = clampf(width, float(sc.width[0]), float(sc.width[1]))
		depth = clampf(depth, float(sc.depth[0]), float(sc.depth[1]))
		var yaw := atan2(-front.x, -front.y)
		var key := "poi_%02d" % i
		var style: Dictionary = d.styles[p.style]
		var mats: Dictionary = d.materials.duplicate(true)
		mats.accent.color = style.accent
		var k := LandmarkKit.new("Poi%02d" % i, mats)
		var sign_text := str(p.name).to_upper() if str(p.name) != "" else str(style.sign)
		var loot := PoiBuilding.build(k, key, p.style, style, width, depth, sign_text, rng)
		var msg := k.save("%s/%s.scn" % [d.out_dir, key])
		var ll := proj.to_lat_lon(float(rect.centre.x), float(rect.centre.y))
		var canopy := 12.0 if bool(style.get("canopy", false)) else 0.0
		out[key] = {"note": "Generated POI (D-056): %s '%s' from OSM way %d. Do not edit; re-run build_pois." % [p.style, p.name, p.id],
			"lat": snappedf(ll.x, 0.0000001), "lon": snappedf(ll.y, 0.0000001), "rotation_deg": snappedf(rad_to_deg(yaw), 0.01),
			"scene": "%s/%s.scn" % [d.out_dir, key], "replaces_osm_ways": [p.id],
			"exclusion_radius_m": snappedf(maxf(width, depth) * 0.5 + 2.0 + canopy, 0.1),
			"terrain_pad": [-width * 0.5 - 2.0, -depth * 0.5 - 2.0 - canopy, width * 0.5 + 2.0, depth * 0.5 + 2.0],
			"no_plant_rects": [[-width * 0.5 - 1.0, -depth * 0.5 - 1.0 - canopy, width * 0.5 + 1.0, depth * 0.5 + 1.0]],
			"terrain_pad_blend_m": 6.0, "style": p.style, "name": p.name}
		_say("%s: %s '%s' (%s) %.0f x %.0f m at (%.0f, %.0f), %d loot  | %s" % [key, p.style, p.name, p.tag, width, depth,
			rect.centre.x, rect.centre.y, loot, msg])
	var f := FileAccess.open(str(d.out_list), FileAccess.WRITE)
	f.store_string(JSON.stringify({"note": "Generated by tools/landmarks/build_pois.tscn (D-056) - do not edit; same shape as landmarks.json.", "pois": out}, "\t"))
	f.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/_look"))
	var lf := FileAccess.open("res://tests/_look/pois_build.txt", FileAccess.WRITE)
	lf.store_string("\n".join(_log))
	lf.close()
	get_tree().quit()


func _centre(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / maxf(poly.size(), 1)


func _nearest_dir(p: Vector2, segs: Array) -> Vector2:
	var best := INF
	var dir := Vector2(0, 1)
	for s: Array in segs:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		if absf(a.x - p.x) > 400.0 and absf(b.x - p.x) > 400.0:
			continue
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var dd := p.distance_squared_to(q)
		if dd < best and dd > 1.0:
			best = dd
			dir = (q - p).normalized()
	return dir


func _say(s: String) -> void:
	print("POIS: " + s)
	_log.append(s)
