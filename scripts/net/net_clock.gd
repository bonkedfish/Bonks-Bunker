# NetClock — shared simulation tick for lag compensation.
# Host: counts physics ticks; the count replicates to clients at 20 Hz through child "Sync".
# Client: estimates which host tick it is currently *seeing* (remote things render INTERP_DELAY
# behind the newest snapshot) and sends it with every intent, so the host can rewind hitboxes to it.
# Group: "net_clock". Used by: Player (INTERP_DELAY, view_tick), CombatWorld (rewind_tick), TrainingDummy.
class_name NetClock
extends Node

const INTERP_DELAY := 0.1  # seconds remote things render behind the newest snapshot
const BUFFER := 16

var tick := 0
var net_tick := 0  # replicated host -> clients

var _arrival := PackedFloat64Array()
var _ticks := PackedInt32Array()
var _newest := 0
var _count := 0


func _ready() -> void:
	add_to_group("net_clock")
	_arrival.resize(BUFFER)
	_ticks.resize(BUFFER)
	$Sync.synchronized.connect(_on_synchronized)


func _physics_process(_delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		tick += 1
		net_tick = tick


func _on_synchronized() -> void:
	_newest = (_newest + 1) % BUFFER
	_count = mini(_count + 1, BUFFER)
	_arrival[_newest] = Time.get_ticks_msec() / 1000.0
	_ticks[_newest] = net_tick


# Host: the current tick. Client: the host tick being displayed right now (fractional).
func view_tick() -> float:
	if multiplayer.is_server() or _count == 0:
		return float(tick if multiplayer.is_server() else net_tick)
	var render_time := Time.get_ticks_msec() / 1000.0 - INTERP_DELAY
	var newer := _newest
	for i in range(1, _count):
		var older := (_newest - i + BUFFER) % BUFFER
		if _arrival[older] <= render_time:
			var span := _arrival[newer] - _arrival[older]
			var t := 1.0 if span <= 0.0 else clampf((render_time - _arrival[older]) / span, 0.0, 1.0)
			return lerpf(_ticks[older], _ticks[newer], t)
		newer = older
	return float(_ticks[newer])


# Host: clamp a client's claimed view tick so nobody can rewind further than allowed or into the future.
func rewind_tick(requested: float, max_rewind_seconds: float) -> float:
	var oldest := tick - max_rewind_seconds * Engine.physics_ticks_per_second
	return clampf(requested, oldest, float(tick))
