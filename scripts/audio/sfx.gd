# Sfx — autoload (D-077): plays sound events by string ID. Event tuning (volume, pitch jitter, range, bus) is in
# data/audio/sounds.json; the sounds are every .ogg / .wav / .mp3 in res://assets/audio/<event id>/ (one picked at
# random per play, so drop in as many variants as you like). An event with no files warns once, then stays silent.
# Makes the "SFX" and "Ambience" buses and remembers their volumes in user://settings.cfg [audio].
# Voices are created once and reused (the oldest is stolen); a 3D event farther than its max_distance from the camera
# is skipped. Owns the Ambience node. Presentation only: never decides anything for the game.
# Depends on: DataLoader, data/audio/sounds.json, scripts/audio/ambience.gd.
extends Node

const DATA_PATH := "res://data/audio/sounds.json"
const AUDIO_DIR := "res://assets/audio/"
const SETTINGS_PATH := "user://settings.cfg"
const BUSES := ["SFX", "Ambience"]
const EXTENSIONS := ["ogg", "wav", "mp3"]
const SCHEMA := {
	"note": TYPE_STRING, "voices_3d": TYPE_FLOAT, "voices_2d": TYPE_FLOAT, "land_min_speed": TYPE_FLOAT,
	"default_volume": TYPE_DICTIONARY, "events": TYPE_DICTIONARY, "item_use": TYPE_DICTIONARY,
	"ambience": TYPE_DICTIONARY,
}
const EVENT_SCHEMA := {"volume_db": TYPE_FLOAT, "pitch_jitter": TYPE_FLOAT, "max_distance": TYPE_FLOAT, "bus": TYPE_STRING}
const AmbienceScript := preload("res://scripts/audio/ambience.gd")

var data: Dictionary = {}
var _defs: Dictionary = {}     # event id -> tuning
var _streams: Dictionary = {}  # event id -> Array of AudioStream
var _voices: Array[Node] = []  # AudioStreamPlayer3D first, then AudioStreamPlayer (the local player's own sounds)
var _serials := PackedInt32Array()
var _n3 := 0
var _next3 := 0
var _next2 := 0
var _serial := 0
var _warned: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for bus: String in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	data = DataLoader.load_validated(DATA_PATH, SCHEMA)
	if data.is_empty():
		return
	for id: String in data.events:
		var def: Variant = data.events[id]
		if typeof(def) == TYPE_DICTIONARY and DataLoader.validate(def, EVENT_SCHEMA, "%s:%s" % [DATA_PATH, id]):
			_defs[id] = def
			_streams[id] = _load_streams(id)
	_n3 = int(data.voices_3d)
	for i in _n3:
		var p := AudioStreamPlayer3D.new()
		add_child(p)
		_voices.append(p)
	for i in int(data.voices_2d):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices.append(p)
	_serials.resize(_voices.size())
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	for bus: String in BUSES:
		set_volume(bus, float(cfg.get_value("audio", bus.to_lower(), data.default_volume.get(bus, 1.0))))
	var amb := AmbienceScript.new()
	amb.name = "Ambience"
	amb.sfx = self
	add_child(amb)


# A sound at a world position, heard by whoever is near. Returns a handle for stop() (0 = nothing played).
func play_at(id: String, pos: Vector3) -> int:
	var stream := pick(id)
	if stream == null or _n3 == 0:
		return 0
	var def: Dictionary = _defs[id]
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(pos) > float(def.max_distance):
		return 0
	var i := _next3
	_next3 = (_next3 + 1) % _n3
	var p := _voices[i] as AudioStreamPlayer3D
	p.global_position = pos
	p.max_distance = float(def.max_distance)
	return _start(i, stream, def)


# A sound the local player makes themselves (not positioned). Returns a handle for stop().
func play_local(id: String) -> int:
	var stream := pick(id)
	var n2 := _voices.size() - _n3
	if stream == null or n2 <= 0:
		return 0
	var i := _n3 + _next2
	_next2 = (_next2 + 1) % n2
	return _start(i, stream, _defs[id])


# Stops a sound started by play_at / play_local, unless its voice was already reused.
func stop(handle: int) -> void:
	if handle == 0:
		return
	var i := _serials.find(handle)
	if i >= 0:
		_voices[i].stop()


# A random file of the event (null when it has none).
func pick(id: String) -> AudioStream:
	var list: Array = _streams.get(id, [])
	if list.is_empty():
		if not _warned.has(id):
			_warned[id] = true
			if _defs.has(id):
				push_warning("Sfx: no sound files for '%s' (put .ogg/.wav/.mp3 in %s%s/)" % [id, AUDIO_DIR, id])
			else:
				push_warning("Sfx: unknown sound event '%s' (add it to %s)" % [id, DATA_PATH])
		return null
	return list[_rng.randi() % list.size()]


func event(id: String) -> Dictionary:
	return _defs.get(id, {})


# Which event plays while using an item: by item id, else by its category ("" = none).
func use_event(item_id: String, category: String) -> String:
	var u: Dictionary = data.get("item_use", {})
	return str(u.get("by_item", {}).get(item_id, u.get("by_category", {}).get(category, "")))


# Bus volume 0..1 (the Settings sliders).
func get_volume(bus: String) -> float:
	var i := AudioServer.get_bus_index(bus)
	if i < 0 or AudioServer.is_bus_mute(i):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(i))


func set_volume(bus: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	linear = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(i, linear <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.001)))


func save_volumes() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	for bus: String in BUSES:
		cfg.set_value("audio", bus.to_lower(), get_volume(bus))
	cfg.save(SETTINGS_PATH)


func _start(i: int, stream: AudioStream, def: Dictionary) -> int:
	var p: Node = _voices[i]
	var j := float(def.pitch_jitter)
	p.stream = stream
	p.volume_db = float(def.volume_db)
	p.pitch_scale = 1.0 + _rng.randf_range(-j, j)
	p.bus = str(def.bus)
	p.play()
	_serial += 1
	_serials[i] = _serial
	return _serial


func _load_streams(id: String) -> Array:
	var out: Array = []
	var dir := AUDIO_DIR + id + "/"
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f: String in ResourceLoader.list_directory(dir):
		if f.get_extension().to_lower() in EXTENSIONS:
			var s := load(dir + f) as AudioStream
			if s:
				out.append(s)
	return out
