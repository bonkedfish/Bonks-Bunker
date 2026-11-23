# BikeSound — a ridden motorcycle's engine (D-083): three looping recordings of the bike's engine type (low / mid /
# high revs, assets/audio/bike_engine/<engine>_<band>.ogg from tools/audio/build_bike_sounds.py) played as 3D sounds
# on the bike, each pitched by rpm / the rpm it was made at (data/audio/bike_engines.json) and crossfaded by how close
# the revs are to it; the rev limiter chops the sound. Silent and stopped when the engine is off or the bike is farther
# than max_m from the camera. D-124: louder on the gas than off it (tuning engine_load_db), a touch deeper in each
# higher gear (engine_gear_pitch), and a tyre screech loop (assets/audio/bike_skid/skid_loop.ogg) with the skid.
# Presentation only. Depends on: DataLoader, the "SFX" bus (Sfx autoload).
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
var _load_db := 0.0
var _gear_pitch := 0.0
var _skid_db := 0.0
var _skid: AudioStreamPlayer3D


func setup(engine: String, _redline: float, max_m: float, t: Dictionary = {}) -> void:
	_max_m = max_m
	_load_db = float(t.get("engine_load_db", 0.0))
	_gear_pitch = float(t.get("engine_gear_pitch", 0.0))
	_skid_db = float(t.get("skid_db", -6.0))
	const SKID := "res://assets/audio/bike_skid/skid_loop.ogg"
	var skid := load(SKID) as AudioStreamOggVorbis if ResourceLoader.exists(SKID) else null
	if skid:
		skid.loop = true
		_skid = AudioStreamPlayer3D.new()
		_skid.stream = skid
		_skid.bus = "SFX"
		_skid.max_distance = max_m * 0.6
		_skid.unit_size = 6.0
		add_child(_skid)
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


func update(rpm: float, engine_on: bool, limiter: bool, delta: float, drive := 0.0, gear := 0, skid := 0.0) -> void:
	if _players.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	var near := cam != null and cam.global_position.distance_to(global_position) < _max_m
	if _skid:
		if skid > 0.05 and near:
			if not _skid.playing:
				_skid.play()
			_skid.volume_db = _skid_db + linear_to_db(clampf(skid, 0.0001, 1.0))
		elif _skid.playing:
			_skid.stop()
	if not engine_on or not near:
		for p in _players:
			if p.playing:
				p.stop()
		return
	_chop = fmod(_chop + delta * 22.0, 1.0)
	var cut := -14.0 if limiter and _chop < 0.45 else 0.0
	var r := maxf(rpm, 500.0)
	var gear_k := 1.0 + _gear_pitch * maxf(float(gear) - 1.0, 0.0)
	var load_db := _load_db * (clampf(drive, 0.0, 1.0) - 0.5)
	for i in _players.size():
		var p := _players[i]
		if not p.playing:
			p.play()
		p.pitch_scale = clampf(r / _band_rpm[i] * gear_k, 0.35, 2.6)
		# Weight: 1 at this band's rpm, fading out by the neighbouring band (log scale).
		var d := absf(log(r / _band_rpm[i])) / log(2.6)
		var w := clampf(1.0 - d, 0.0, 1.0)
		p.volume_db = linear_to_db(maxf(w, 0.0001)) + cut + load_db
