# Atmosphere — "Atmosphere" node in main.tscn (D-044): applies the dusty-haze look from data/art/atmosphere.json
# to the sibling WorldEnvironment (procedural sky colours, ambient light, distance + height fog, filmic tonemap,
# mild contrast/saturation) and the sibling "Sun" light (angle, colour, energy, shadow softness). Runs once at
# start; all cheap fixed-function settings (no volumetric fog, no extra passes). Quality-tier switches (SSAO,
# shadows) stay with the Graphics autoload. Depends on: DataLoader.
extends Node

const DATA_PATH := "res://data/art/atmosphere.json"


func _ready() -> void:
	var a := DataLoader.load_json(DATA_PATH)
	if a.is_empty():
		push_error("Atmosphere: %s missing or invalid, keeping scene defaults" % DATA_PATH)
		return
	var we := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we and we.environment:
		_apply_env(we.environment, a)
	var sun := get_parent().get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.rotation = Vector3(deg_to_rad(-float(a.sun_elevation_deg)), deg_to_rad(float(a.sun_azimuth_deg)), 0.0)
		sun.light_color = _c(a.sun_color)
		sun.light_energy = float(a.sun_energy)
		sun.shadow_blur = float(a.shadow_blur)


func _apply_env(env: Environment, a: Dictionary) -> void:
	var sky_mat: ProceduralSkyMaterial = env.sky.sky_material as ProceduralSkyMaterial if env.sky else null
	if sky_mat:
		sky_mat.sky_top_color = _c(a.sky_top)
		sky_mat.sky_horizon_color = _c(a.sky_horizon)
		sky_mat.sky_curve = float(a.sky_curve)
		sky_mat.ground_bottom_color = _c(a.ground_bottom)
		sky_mat.ground_horizon_color = _c(a.ground_horizon)
	env.ambient_light_sky_contribution = float(a.ambient_sky_contribution)
	env.ambient_light_energy = float(a.ambient_energy)
	env.fog_enabled = true
	env.fog_light_color = _c(a.fog_color)
	env.fog_density = float(a.fog_density)
	env.fog_sun_scatter = float(a.fog_sun_scatter)
	env.fog_aerial_perspective = float(a.fog_aerial_perspective)
	env.fog_sky_affect = float(a.fog_sky_affect)
	env.fog_height = float(a.fog_height)
	env.fog_height_density = float(a.fog_height_density)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = float(a.tonemap_white)
	env.tonemap_exposure = float(a.exposure)
	env.adjustment_enabled = true
	env.adjustment_contrast = float(a.contrast)
	env.adjustment_saturation = float(a.saturation)


func _c(v: Array) -> Color:
	return Color(float(v[0]), float(v[1]), float(v[2]))
