# WeatherSound — rain and thunder for the weather (D-099), made in code (no sound files): a looping filtered-noise
# rain bed and two rolling thunder clips plus a sharp crack for close strikes, generated once on a worker thread
# the first time they're needed (16-bit mono, 22 kHz). Rain volume follows the rain level (quieter indoors);
# thunder plays after the sound has travelled (distance / speed of sound), louder and with a crack when close.
# Plays on the "Ambience" bus. Child of WeatherDirector, every peer. Depends on: nothing.
class_name WeatherSound
extends Node

const RATE := 22050

var _rain: AudioStreamPlayer
var _thunder: Array[AudioStreamPlayer] = []
var _rain_stream: AudioStreamWAV
var _thunder_streams: Array[AudioStreamWAV] = []
var _crack: AudioStreamWAV
var _task := -1
var _pending: Array = []  # [seconds left, volume_db, close]


func _ready() -> void:
	_rain = AudioStreamPlayer.new()
	_rain.bus = "Ambience"
	_rain.volume_db = -80.0
	add_child(_rain)
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.bus = "Ambience"
		add_child(p)
		_thunder.append(p)


func prepare() -> void:
	if _task < 0 and _rain_stream == null:
		_task = WorkerThreadPool.add_task(_generate)


# rain 0..1, indoors: under a roof (muffled).
func set_rain(rain: float, indoors: bool) -> void:
	if _rain_stream == null:
		_check_ready()
		return
	if rain <= 0.01:
		if _rain.playing:
			_rain.stop()
		return
	if not _rain.playing:
		_rain.stream = _rain_stream
		_rain.play()
	_rain.volume_db = linear_to_db(rain * (0.35 if indoors else 1.0)) - 6.0


func thunder(distance: float, speed: float) -> void:
	_pending.append([distance / maxf(speed, 1.0), clampf(-4.0 - distance / 60.0, -30.0, 0.0), distance < 60.0])


func _process(delta: float) -> void:
	_check_ready()
	for i in range(_pending.size() - 1, -1, -1):
		var p: Array = _pending[i]
		p[0] = float(p[0]) - delta
		if float(p[0]) <= 0.0:
			_pending.remove_at(i)
			_play_thunder(float(p[1]), bool(p[2]))


func _play_thunder(db: float, close: bool) -> void:
	if _thunder_streams.is_empty():
		return
	for pl in _thunder:
		if not pl.playing:
			pl.stream = _crack if close else _thunder_streams[randi() % _thunder_streams.size()]
			pl.volume_db = db
			pl.pitch_scale = randf_range(0.85, 1.1)
			pl.play()
			return


func _check_ready() -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _generate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# Rain: white noise through a gentle low-pass, with sparse louder drops. Loops seamlessly enough at 3 s.
	var n := RATE * 3
	var rain := PackedFloat32Array()
	rain.resize(n)
	var lp := 0.0
	for i in n:
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.35
		var drop := rng.randf_range(-1.0, 1.0) * 0.6 if rng.randf() < 0.002 else 0.0
		rain[i] = lp * 0.5 + drop
	var streams: Array[AudioStreamWAV] = []
	for k in 2:  # rolling thunder: brown noise, a soft swell then a long uneven decay
		var m := RATE * 5
		var th := PackedFloat32Array()
		th.resize(m)
		var b := 0.0
		for i in m:
			b = clampf(b + rng.randf_range(-1.0, 1.0) * 0.04, -1.0, 1.0) * 0.998
			var t := float(i) / RATE
			var env := minf(t / 0.25, 1.0) * exp(-t * (0.55 + k * 0.2)) * (0.75 + 0.25 * sin(t * (3.0 + k)))
			th[i] = b * env * 2.2
		streams.append(_wav(th, false))
	var c := RATE * 3  # close crack: a bright snap into rumble
	var cr := PackedFloat32Array()
	cr.resize(c)
	var bb := 0.0
	for i in c:
		var t := float(i) / RATE
		bb = clampf(bb + rng.randf_range(-1.0, 1.0) * 0.05, -1.0, 1.0) * 0.998
		cr[i] = rng.randf_range(-1.0, 1.0) * exp(-t * 18.0) + bb * exp(-t * 0.9) * 1.8
	_rain_stream = _wav(rain, true)
	_crack = _wav(cr, false)
	_thunder_streams = streams


func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = samples.size()
	return w
