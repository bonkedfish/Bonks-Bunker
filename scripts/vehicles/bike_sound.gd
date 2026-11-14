# BikeSound — a ridden motorcycle's engine (D-083): three looping recordings of the bike's engine type (low / mid /
# high revs, assets/audio/bike_engine/<engine>_<band>.ogg from tools/audio/build_bike_sounds.py) played as 3D sounds
# on the bike, each pitched by rpm / the rpm it was made at (data/audio/bike_engines.json) and crossfaded by how close
# the revs are to it; the rev limiter chops the sound. Silent and stopped when the engine is off or the bike is farther
# than max_m from the camera. Presentation only. Depends on: DataLoader, the "SFX" bus (Sfx autoload).
class_name BikeSound
extends Node3D

const META_PATH := "res://data/audio/bike_engines.json"
const DIR := "res://assets/audio/bike_engine/"
const BANDS := ["low", "mid", "high"]

static var _meta: Dictionary = {}

var _players: Array[AudioStreamPlayer3D] = []
var _band_rpm := PackedFloat32Array()
var _max_m := 90.0
var _chop := 0.0


func setup(engine: String, _redline: float, max_m: float) -> void:
	_max_m = max_m
	if _meta.is_empty():
		_meta = DataLoader.load_json(META_PATH)
	var rpms: Dictionary = _meta.get("engines", {}).get(engine, {})
	for band: String in BANDS:
		var stream := load(DIR + "%s_%s.ogg" % [engine, band]) as AudioStreamOggVorbis
		if stream == null:
			continue
		stream.loop = true
		var p := AudioStreamPlayer3D.new()
		p.stream = stream
		p.bus = "SFX"
		p.max_distance = max_m
		p.unit_size = 6.0
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
		_band_rpm.append(float(rpms.get(band, 3000.0)))


func update(rpm: float, engine_on: bool, limiter: bool, delta: float) -> void:
	if _players.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	var near := cam != null and cam.global_position.distance_to(global_position) < _max_m
	if not engine_on or not near:
		for p in _players:
			if p.playing:
				p.stop()
		return
	_chop = fmod(_chop + delta * 22.0, 1.0)
	var cut := -14.0 if limiter and _chop < 0.45 else 0.0
	var r := maxf(rpm, 500.0)
	for i in _players.size():
		var p := _players[i]
		if not p.playing:
			p.play()
		p.pitch_scale = clampf(r / _band_rpm[i], 0.35, 2.6)
		# Weight: 1 at this band's rpm, fading out by the neighbouring band (log scale).
		var d := absf(log(r / _band_rpm[i])) / log(2.6)
		var w := clampf(1.0 - d, 0.0, 1.0)
		p.volume_db = linear_to_db(maxf(w, 0.0001)) + cut
