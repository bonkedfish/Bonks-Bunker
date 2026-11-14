# NameTag — the floating name over another player's head (D-081). A Label3D child of their Player body: faces the
# camera, is hidden by walls (normal depth test), fully visible to visible_m and fades out over the next fade_m.
# The text is the body's replicated net_name (Player sets it). Never added to your own body.
# Depends on: DataLoader, data/tuning/name_tags.json.
extends Label3D

const TUNING_PATH := "res://data/tuning/name_tags.json"
const SCHEMA := {"max_length": TYPE_FLOAT, "visible_m": TYPE_FLOAT, "fade_m": TYPE_FLOAT, "height_m": TYPE_FLOAT,
	"font_size": TYPE_FLOAT}

static var tuning: Dictionary = {}

var _visible_m := 30.0
var _fade_m := 10.0


static func load_tuning() -> Dictionary:
	if tuning.is_empty():
		tuning = DataLoader.load_validated(TUNING_PATH, SCHEMA)
	return tuning


func _ready() -> void:
	var t := load_tuning()
	_visible_m = float(t.get("visible_m", 30.0))
	_fade_m = maxf(float(t.get("fade_m", 10.0)), 0.1)
	name = "NameTag"
	position.y = float(t.get("height_m", 2.15))
	font_size = int(t.get("font_size", 40))
	pixel_size = 0.005
	outline_size = 10
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	modulate = Color(0.95, 0.92, 0.82)
	outline_modulate = Color(0, 0, 0, 0.85)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_range_end = _visible_m + _fade_m


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or text == "":
		visible = false
		return
	var d := cam.global_position.distance_to(global_position)
	var a := clampf((_visible_m + _fade_m - d) / _fade_m, 0.0, 1.0)
	visible = a > 0.0
	modulate.a = a
	outline_modulate.a = 0.85 * a
