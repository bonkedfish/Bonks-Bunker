# Ambience — child of the Sfx autoload (D-077): the eerie open-world bed. A wind loop (replayed with a fresh variant
# whenever a file ends, so any file loops) plus one distant one-shot (far creaks, crows, gusts, moans) every
# min_gap_s..max_gap_s, placed at a random bearing min_dist_m..max_dist_m from the camera so it comes from somewhere
# out in the world. Wind keeps blowing while paused; one-shots wait. Tuning: data/audio/sounds.json "ambience".
# Depends on: Sfx (set as `sfx` before this enters the tree), DataLoader.
extends Node

const SCHEMA := {
	"wind": TYPE_STRING, "distant": TYPE_STRING, "min_gap_s": TYPE_FLOAT, "max_gap_s": TYPE_FLOAT,
	"min_dist_m": TYPE_FLOAT, "max_dist_m": TYPE_FLOAT,
}

var sfx: Node

var _a: Dictionary = {}
var _wind: AudioStreamPlayer
var _wait := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	var a: Dictionary = sfx.data.get("ambience", {})
	if not DataLoader.validate(a, SCHEMA, "sounds.json:ambience"):
		set_process(false)
		return
	_a = a
	_wind = AudioStreamPlayer.new()
	_wind.bus = "Ambience"
	add_child(_wind)
	_wind.finished.connect(_play_wind)
	_play_wind()
	_wait = _gap()


func _play_wind() -> void:
	var id := str(_a.wind)
	var s: AudioStream = sfx.pick(id)
	if s == null:
		return
	_wind.stream = s
	_wind.volume_db = float(sfx.event(id).get("volume_db", 0.0))
	_wind.play()


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = _gap()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var bearing := _rng.randf() * TAU
	var dist := _rng.randf_range(float(_a.min_dist_m), float(_a.max_dist_m))
	sfx.play_at(str(_a.distant), cam.global_position + Vector3(cos(bearing) * dist, _rng.randf_range(0.0, 8.0), sin(bearing) * dist))


func _gap() -> float:
	return _rng.randf_range(float(_a.min_gap_s), float(_a.max_gap_s))
