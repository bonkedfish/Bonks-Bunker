# StreetLooks — how generated streets and ground look (D-043), from data/art/streets.json: which surface a road
# gets (OSM surface tag, else by kind), its centre-line style, which kinds get curbs + sidewalks, and the shared
# materials for ground, each street surface and textured pitched roofs. Used only by the offline map importer.
# D-115: the ground material also gets its extra layers ("ground.layers") and each street surface its abandonment
# ("decay" per surface + the shared "decay" edge texture). The materials are saved as shared .tres files, so
# shader changes reach existing cells without a re-bake.
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
		if s.get("decay", {}).has("alt"):
			textures.append(s.decay.alt)
	var layers: Dictionary = data.ground.get("layers", {})
	for k in ["grass2", "dirt"]:
		if layers.has(k):
			textures.append(layers[k])
	if data.has("decay"):
		textures.append(data.decay.edge_texture)
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
	var d: Dictionary = s.get("decay", {})
	if not d.is_empty():
		var shared: Dictionary = data.decay
		_set_maps(m, "edge", str(shared.edge_texture))
		m.set_shader_parameter("edge_tile_m", float(shared.edge_tile_m))
		var wc: Array = shared.weed_color
		m.set_shader_parameter("weed_color", Color(wc[0], wc[1], wc[2]))
		if d.has("alt"):
			_set_maps(m, "alt", str(d.alt))
		for k: String in ["alt_tile_m", "alt_mix", "edge_dirt_m", "drift_amount", "crack_amount", "weed_amount",
				"pothole_amount", "patch_amount"]:
			if d.has(k):
				m.set_shader_parameter(k, float(d[k]))
	return m


func make_ground_material() -> ShaderMaterial:
	var g: Dictionary = data.ground
	var m := _shader_material(GROUND_SHADER, g.texture, float(g.tile_m), g.tint)
	m.set_shader_parameter("variation", float(g.variation))
	var l: Dictionary = g.get("layers", {})
	if not l.is_empty():
		_set_maps(m, "grass2", str(l.grass2))
		_set_maps(m, "dirt", str(l.dirt))
		for k: String in ["grass2_tile_m", "grass2_amount", "dirt_tile_m", "dirt_amount", "patch_m", "slope_dirt"]:
			m.set_shader_parameter(k, float(l[k]))
		var t: Array = l.layer_tint
		m.set_shader_parameter("layer_tint", Color(t[0], t[1], t[2]))
	var far: Dictionary = g.get("far", {})  # D-120: hides the tiling in the distance
	for k: String in far:
		m.set_shader_parameter({"start_m": "far_start_m", "end_m": "far_end_m", "tile_mult": "far_tile_mult",
			"amount": "far_amount"}.get(k, k), float(far[k]))
	return m


# Sets <prefix>_albedo / _normal / _arm from a texture folder.
func _set_maps(m: ShaderMaterial, prefix: String, texture: String) -> void:
	var dir := "%s/%s" % [data.textures_dir, texture]
	m.set_shader_parameter(prefix + "_albedo", load(dir + "/albedo.jpg"))
	m.set_shader_parameter(prefix + "_normal", load(dir + "/normal.jpg"))
	m.set_shader_parameter(prefix + "_arm", load(dir + "/arm.jpg"))


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
