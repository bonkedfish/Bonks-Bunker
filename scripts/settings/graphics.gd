# Graphics — autoload: applies the chosen quality tier (D-038) and remembers the player's choice per PC
# in user://settings.cfg ("auto" or a tier name). "auto" picks from the GPU via GraphicsRules.
# Applies to the window (render scale, MSAA, FXAA, FPS cap, shadow atlas) and to nodes as they appear:
# WorldEnvironment (SSAO), DirectionalLight3D (shadows, shadow distance), Camera3D (view distance).
# Depends on: GraphicsRules, data/tuning/graphics.json.
extends Node

signal tier_changed(tier: String)

const SETTINGS_PATH := "user://settings.cfg"

var choice := "auto"  # what the player picked
var tier := "medium"  # what's applied
var adapter_name := ""

var _tiers: Dictionary = {}


func _ready() -> void:
	var data := GraphicsRules.load_data()
	if data.is_empty():
		push_error("Graphics: bad graphics.json, leaving engine defaults")
		return
	_tiers = data.tiers
	adapter_name = RenderingServer.get_video_adapter_name()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		choice = str(cfg.get_value("graphics", "tier", "auto"))
	get_tree().node_added.connect(_on_node_added)
	_apply()


# "auto", "low", "medium" or "high". Saved for next launch.
func set_choice(value: String) -> void:
	choice = value if value == "auto" or _tiers.has(value) else "auto"
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("graphics", "tier", choice)
	cfg.save(SETTINGS_PATH)
	_apply()


# The current tier's view distance (the streamer sizes the low-detail ring from it).
func get_view_distance() -> float:
	return float(_tiers.get(tier, {}).get("view_distance", 500.0))


func auto_tier() -> String:
	var integrated := RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU
	return GraphicsRules.pick_tier(adapter_name, integrated, GraphicsRules.load_data().get("auto", {}))


func _apply() -> void:
	tier = auto_tier() if choice == "auto" else choice
	var t: Dictionary = _tiers[tier]
	var vp := get_tree().root
	var scale := float(t.render_scale)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = scale
	vp.msaa_3d = {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X}.get(int(t.msaa), Viewport.MSAA_DISABLED)
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if t.fxaa else Viewport.SCREEN_SPACE_AA_DISABLED
	Engine.max_fps = int(t.max_fps)
	RenderingServer.directional_shadow_atlas_set_size(int(t.shadow_atlas), true)
	for n in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		_on_node_added(n)
	for n in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		_on_node_added(n)
	for n in get_tree().root.find_children("*", "Camera3D", true, false):
		_on_node_added(n)
	print("Graphics: %s tier (%s) on %s" % [tier, choice, adapter_name])
	tier_changed.emit(tier)


func _on_node_added(n: Node) -> void:
	if _tiers.is_empty():
		return
	var t: Dictionary = _tiers[tier]
	if n is Camera3D:
		n.far = float(t.view_distance)
	elif n is DirectionalLight3D:
		n.shadow_enabled = bool(t.shadows)
		n.directional_shadow_max_distance = float(t.shadow_distance)
	elif n is WorldEnvironment and n.environment:
		n.environment.ssao_enabled = bool(t.ssao)
