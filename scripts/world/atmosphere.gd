# Atmosphere — "Atmosphere" node in main.tscn (D-044, D-099, D-110): applies the warm dusty look from
# data/art/atmosphere.json to the sibling WorldEnvironment (a cloud sky shader - shaders/sky_clouds.gdshader -
# ambient light, distance + height fog, filmic tonemap, contrast/saturation) and the sibling "Sun" light (angle,
# colour, energy, shadow softness). set_weather() blends it toward the weather (WeatherDirector, every frame while
# weather changes): more cloud, a darker greyer sky, thicker fog, a dimmer sun, and lightning flashes. The sky
# radiance updates incrementally (spread over frames: drifting clouds stay cheap). No volumetric fog, no extra
# passes. set_time_of_day() (DayNight, every frame) swings the sun across the sky, mirrors it into a moon after
# dark, and blends the whole look toward night: deep blue sky with stars, low blue light, dim ambient, drained
# colour. Weather and time of day are kept separately and re-combined, so either can change at any time.
# Quality-tier switches (SSAO, shadows) stay with the Graphics autoload. Depends on: DataLoader.
extends Node

const DATA_PATH := "res://data/art/atmosphere.json"
const SKY_SHADER := preload("res://shaders/sky_clouds.gdshader")

var _a: Dictionary = {}
var _env: Environment
var _sun: DirectionalLight3D
var _sky: ShaderMaterial
var _weather := Vector4.ZERO   # rain, storm, fog, flash - kept so time of day can re-apply them
var _night := 0.0
var _dusk := 0.0
var _day: Dictionary = {}      # the day/night tuning, once DayNight has handed it over
var _sun_height := 1.0         # 0 at the horizon, 1 overhead: dims the light morning and evening


func _ready() -> void:
	_a = DataLoader.load_json(DATA_PATH)
	if _a.is_empty():
		push_error("Atmosphere: %s missing or invalid, keeping scene defaults" % DATA_PATH)
		return
	var we := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we and we.environment:
		_env = we.environment
		_apply_env(_env, _a)
	_sun = get_parent().get_node_or_null("Sun") as DirectionalLight3D
	if _sun:
		_sun.rotation = Vector3(deg_to_rad(-float(_a.sun_elevation_deg)), deg_to_rad(float(_a.sun_azimuth_deg)), 0.0)
		_sun.light_color = _c(_a.sun_color)
		_sun.light_energy = float(_a.sun_energy)
		_sun.shadow_blur = float(_a.shadow_blur)
	set_weather(0.0, 0.0, 0.0, 0.0)


# rain / storm / fog 0..1 (blended by the caller), flash 0..1 (a lightning strike, fading).
func set_weather(rain: float, storm: float, fog: float, flash: float) -> void:
	if _a.is_empty():
		return
	_weather = Vector4(rain, storm, fog, flash)
	var gloom := clampf(maxf(rain * 0.6, storm), 0.0, 1.0)
	if _sky:
		_sky.set_shader_parameter("cloud_cover", clampf(float(_a.cloud_cover) + rain * 0.45 + storm * 0.6 + fog * 0.3, 0.0, 1.0))
		_sky.set_shader_parameter("storm", storm * 0.85 + fog * 0.25)
		_sky.set_shader_parameter("flash", flash)
		_sky.set_shader_parameter("night", _night)
		_sky.set_shader_parameter("dusk", _dusk)
	if _env:
		_env.fog_density = float(_a.fog_density) * (1.0 + rain * 1.5 + storm * 2.0) + float(_a.weather_fog_density) * fog
		var fog_col := _c(_a.fog_color).lerp(_c(_a.storm_fog_color), maxf(gloom, fog * 0.7))
		_env.fog_light_color = fog_col.lerp(_c(_day.get("night_fog_color", [0.09, 0.12, 0.2])), _night)
		_env.ambient_light_energy = lerpf(float(_a.ambient_energy) * (1.0 - gloom * 0.35),
			float(_day.get("night_ambient_energy", 0.17)), _night) + flash * 1.5
		_env.adjustment_saturation = lerpf(float(_a.saturation) * (1.0 - gloom * 0.3),
			float(_day.get("night_saturation", 0.62)), _night)
		_env.tonemap_exposure = lerpf(float(_a.exposure), float(_day.get("night_exposure", 1.15)), _night)
	if _sun:
		var day_energy := float(_a.sun_energy) * _sun_height
		var night_energy := float(_day.get("moon_energy", 0.22))
		_sun.light_energy = lerpf(day_energy, night_energy, _night) * (1.0 - gloom * 0.7 - fog * 0.35) + flash * 2.0
		_sun.light_color = _c(_a.sun_color).lerp(_c(_day.get("moon_color", [0.6, 0.7, 1.0])), _night)
		_sun.shadow_enabled = gloom < 0.85  # overcast: no hard shadows (and fewer shadow passes)


# DayNight, every frame. elevation_deg is NEGATIVE at night; below the horizon the light is mirrored to the other
# side of the sky and recoloured, which is the moon. night 0..1, dusk 0..1 (orange at the horizon).
func set_time_of_day(elevation_deg: float, night: float, dusk: float, day: Dictionary) -> void:
	if _a.is_empty():
		return
	_day = day
	_night = night
	_dusk = dusk
	var azimuth := float(day.get("sun_azimuth_deg", _a.sun_azimuth_deg))
	var elev := elevation_deg
	if elev < 0.0:  # the moon: the same arc, mirrored across the horizon and half a turn round the sky
		elev = -elev
		azimuth += 180.0
	_sun_height = clampf(sin(deg_to_rad(maxf(elev, 0.0))) * 1.15, 0.0, 1.0)
	if _sun:
		_sun.rotation = Vector3(deg_to_rad(-maxf(elev, 1.5)), deg_to_rad(azimuth), 0.0)
	if _sky:
		# the disc fades out as it meets the horizon, so neither the sun nor the moon pops in or out
		_sky.set_shader_parameter("disc", smoothstep(0.0, 6.0, elev))
		_sky.set_shader_parameter("night_top", _c(day.get("night_sky_top", [0.015, 0.03, 0.08])))
		_sky.set_shader_parameter("night_horizon", _c(day.get("night_sky_horizon", [0.06, 0.08, 0.16])))
		_sky.set_shader_parameter("night_cloud", _c(day.get("night_cloud_color", [0.16, 0.19, 0.28])))
		_sky.set_shader_parameter("night_cloud_shade", _c(day.get("night_cloud_shade", [0.05, 0.06, 0.11])))
		_sky.set_shader_parameter("dusk_color", _c(day.get("dusk_color", [1.0, 0.55, 0.28])))
		_sky.set_shader_parameter("star_strength", float(day.get("star_strength", 0.75)))
	set_weather(_weather.x, _weather.y, _weather.z, _weather.w)


func _apply_env(env: Environment, a: Dictionary) -> void:
	_sky = ShaderMaterial.new()
	_sky.shader = SKY_SHADER
	for k: String in ["top_color", "horizon_color", "ground_color", "cloud_color", "cloud_shade", "storm_color"]:
		_sky.set_shader_parameter(k, _c(a[k]))
	_sky.set_shader_parameter("curve", float(a.sky_curve))
	_sky.set_shader_parameter("wind", Vector2(a.cloud_wind[0], a.cloud_wind[1]))
	_sky.set_shader_parameter("cloud_scale", float(a.cloud_scale))
	if env.sky == null:
		env.sky = Sky.new()
	env.sky.sky_material = _sky
	env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky.radiance_size = Sky.RADIANCE_SIZE_128
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
