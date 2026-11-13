# BuildingLooks — picks how a generated building looks (D-041 phase 1), from data/art/building_looks.json:
# its class (shed / house / large) from the OSM building tag or footprint area, its wall look (weighted,
# deterministic per footprint so a re-import gives the same street), roof kind, pitch and colour.
# Also builds the shared wall ShaderMaterial for each look. Used only by the offline map importer.
# Depends on: DataLoader, shaders/building_wall.gdshader, imported textures under textures_dir.
class_name BuildingLooks
extends RefCounted

const DATA_PATH := "res://data/art/building_looks.json"
const SHADER_PATH := "res://shaders/building_wall.gdshader"

var data: Dictionary
var error := ""


func _init() -> void:
	data = DataLoader.load_json(DATA_PATH)
	error = _check()


func _check() -> String:
	for key in ["looks", "classes", "window", "roof_colors", "flat_roof_color", "textures_dir"]:
		if not data.has(key):
			return "%s: missing '%s'" % [DATA_PATH, key]
	for id: String in data.classes:
		var c: Dictionary = data.classes[id]
		for look: String in c.get("looks", {}):
			if not data.looks.has(look):
				return "%s: class '%s' uses unknown look '%s'" % [DATA_PATH, id, look]
	for id: String in data.looks:
		var tex := "%s/%s/albedo.jpg" % [data.textures_dir, data.looks[id].texture]
		if not ResourceLoader.exists(tex):
			return "look '%s': texture %s not imported - run tools/assets/fetch_textures.tscn, then open the editor once" % [id, tex]
	return ""


# Class id for a building: OSM tag first, otherwise the smallest class whose max_area fits.
func classify(osm_tag: String, area: float) -> String:
	var best := ""
	var best_max := INF
	for id: String in data.classes:
		var c: Dictionary = data.classes[id]
		if osm_tag in c.get("osm_tags", []):
			return id
		var m := float(c.max_area_m2)
		if area <= m and m < best_max:
			best = id
			best_max = m
	return best


func class_def(id: String) -> Dictionary:
	return data.classes[id]


# Weighted look for this class, the same every import for the same footprint.
func pick_look(class_id: String, centre: Vector2) -> String:
	var looks: Dictionary = data.classes[class_id].looks
	var total := 0.0
	for w in looks.values():
		total += float(w)
	var r := rand01(centre, 1) * total
	var ids := looks.keys()
	ids.sort()
	for id: String in ids:
		r -= float(looks[id])
		if r <= 0.0:
			return id
	return ids[ids.size() - 1]


func roof_color(centre: Vector2, pitched: bool) -> Color:
	var c: Array = data.flat_roof_color
	if pitched:
		var list: Array = data.roof_colors
		c = list[mini(int(rand01(centre, 2) * list.size()), list.size() - 1)]
	return Color(c[0], c[1], c[2])


# Deterministic 0..1 from a footprint centre (+ salt for independent picks).
static func rand01(centre: Vector2, salt: int) -> float:
	var h := hash(Vector3i(roundi(centre.x * 10.0), roundi(centre.y * 10.0), salt))
	return float(h & 0xFFFF) / 65535.0


func make_wall_material(look_id: String) -> ShaderMaterial:
	var look: Dictionary = data.looks[look_id]
	var dir := "%s/%s" % [data.textures_dir, look.texture]
	var w: Dictionary = data.window
	var m := ShaderMaterial.new()
	m.shader = load(SHADER_PATH)
	m.set_shader_parameter("albedo_tex", load(dir + "/albedo.jpg"))
	m.set_shader_parameter("normal_tex", load(dir + "/normal.jpg"))
	m.set_shader_parameter("arm_tex", load(dir + "/arm.jpg"))
	m.set_shader_parameter("tile_m", float(look.tile_m))
	var t: Array = look.tint
	m.set_shader_parameter("tint", Color(t[0], t[1], t[2]))
	m.set_shader_parameter("tint_variation", float(look.tint_variation))
	m.set_shader_parameter("lap_spacing_m", float(look.lap_spacing_m))
	m.set_shader_parameter("recolor", float(look.get("recolor", 0.0)))
	var paint: Array = look.get("paint", [])
	if paint.size() == 2:
		m.set_shader_parameter("paint_a", Color(paint[0][0], paint[0][1], paint[0][2]))
		m.set_shader_parameter("paint_b", Color(paint[1][0], paint[1][1], paint[1][2]))
	m.set_shader_parameter("windows", bool(look.windows))
	m.set_shader_parameter("win_spacing", float(w.spacing_m))
	m.set_shader_parameter("floor_h", float(w.floor_height_m))
	m.set_shader_parameter("win_w", float(w.width_m))
	m.set_shader_parameter("win_h", float(w.height_m))
	m.set_shader_parameter("sill", float(w.sill_m))
	m.set_shader_parameter("boarded_fraction", float(w.boarded_fraction))
	m.set_shader_parameter("broken_fraction", float(w.broken_fraction))
	return m
