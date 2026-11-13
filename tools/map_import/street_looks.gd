# StreetLooks — how generated streets and ground look (D-043), from data/art/streets.json: which surface a road
# gets (OSM surface tag, else by kind), its centre-line style, which kinds get curbs + sidewalks, and the shared
# materials for ground, each street surface and textured pitched roofs. Used only by the offline map importer.
# Depends on: DataLoader, shaders/street_surface.gdshader, shaders/ground.gdshader, imported textures.
class_name StreetLooks
extends RefCounted

const DATA_PATH := "res://data/art/streets.json"
const STREET_SHADER := "res://shaders/street_surface.gdshader"
const GROUND_SHADER := "res://shaders/ground.gdshader"

var data: Dictionary
var error := ""


func _init() -> void:
	data = DataLoader.load_json(DATA_PATH)
	error = _check()


func _check() -> String:
	for key in ["textures_dir", "ground", "pitched_roof", "surfaces", "surface_by_osm_tag", "default_surface",
			"centre_line", "line_wear", "sidewalk_kinds", "sidewalk", "intersection_min_angle_deg", "intersection_margin_m"]:
		if not data.has(key):
			return "%s: missing '%s'" % [DATA_PATH, key]
	for s in data.surface_by_osm_tag.values() + data.default_surface.values():
		if not data.surfaces.has(s):
			return "%s: unknown surface '%s'" % [DATA_PATH, s]
	var textures: Array = [data.ground.texture, data.pitched_roof.texture]
	for s: Dictionary in data.surfaces.values():
		textures.append(s.texture)
	for t in textures:
		var path := "%s/%s/albedo.jpg" % [data.textures_dir, t]
		if not ResourceLoader.exists(path):
			return "texture %s not imported - run tools/assets/fetch_textures.tscn, then open the editor once" % path
	return ""


# Surface id for an OSM highway way.
func surface_for(kind: String, tags: Dictionary, drivable: bool) -> String:
	var tag := str(tags.get("surface", ""))
	if data.surface_by_osm_tag.has(tag):
		return data.surface_by_osm_tag[tag]
	if not drivable:
		return data.default_surface.path
	if kind == "service":
		return data.default_surface.alley if str(tags.get("service", "")) == "alley" else data.default_surface.service
	return data.default_surface.drivable


func centre_line(kind: String) -> float:
	return float(data.centre_line.get(kind, 0.0))


func has_sidewalks(kind: String) -> bool:
	return kind in data.sidewalk_kinds


func surface_ids() -> Array:
	var ids: Array = data.surfaces.keys()
	ids.sort()
	return ids


func make_surface_material(id: String) -> ShaderMaterial:
	var s: Dictionary = data.surfaces[id]
	var m := _shader_material(STREET_SHADER, s.texture, float(s.tile_m), s.tint)
	m.set_shader_parameter("joint_spacing_m", float(s.joint_spacing_m))
	m.set_shader_parameter("centre_joint", bool(s.centre_joint))
	m.set_shader_parameter("line_wear", float(data.line_wear))
	return m


func make_ground_material() -> ShaderMaterial:
	var g: Dictionary = data.ground
	var m := _shader_material(GROUND_SHADER, g.texture, float(g.tile_m), g.tint)
	m.set_shader_parameter("variation", float(g.variation))
	return m


# Pitched roofs: photo shingles multiplied by each roof's vertex colour; mesh UV is in metres.
func make_pitched_roof_material() -> ORMMaterial3D:
	var r: Dictionary = data.pitched_roof
	var dir := "%s/%s" % [data.textures_dir, r.texture]
	var m := ORMMaterial3D.new()
	m.albedo_texture = load(dir + "/albedo.jpg")
	m.normal_enabled = true
	m.normal_texture = load(dir + "/normal.jpg")
	m.orm_texture = load(dir + "/arm.jpg")
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.uv1_scale = Vector3.ONE / float(r.tile_m)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _shader_material(shader_path: String, texture: String, tile_m: float, tint: Array) -> ShaderMaterial:
	var dir := "%s/%s" % [data.textures_dir, texture]
	var m := ShaderMaterial.new()
	m.shader = load(shader_path)
	m.set_shader_parameter("albedo_tex", load(dir + "/albedo.jpg"))
	m.set_shader_parameter("normal_tex", load(dir + "/normal.jpg"))
	m.set_shader_parameter("arm_tex", load(dir + "/arm.jpg"))
	m.set_shader_parameter("tile_m", tile_m)
	m.set_shader_parameter("tint", Color(tint[0], tint[1], tint[2]))
	return m
