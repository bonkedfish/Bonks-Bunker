# SwingMeter — the 3-click golf swing (D-086), pure (no nodes): Hot Shots / Mario Golf style.
#   click 1: the marker starts climbing from 0 to 1 (up_s seconds for the full bar)
#   click 2: locks the power where the marker is (it locks at 1 by itself at the top)
#   click 3: the marker is coming back down; stop it on the 0 line. Early = hook (left), late = slice (right);
#            within `sweet` of the line is PERFECT (dead straight), within `good` is GOOD (a little curve).
#            Let it run past the bottom of the accuracy zone and it's a SHANK (big slice, power cut).
# error: -1 (full hook) .. 0 (straight) .. +1 (full slice), shank = cfg.shank. Used by SportInput (the local
# player) and drawn by the HUDs; the host only gets the resulting power and error (clamped there).
# Depends on: nothing (config Dictionary from data/tuning/drop_zone.json "swing").
class_name SwingMeter
extends RefCounted

enum Phase { IDLE, POWER, ACCURACY, DONE }

var phase := Phase.IDLE
var value := 0.0     # marker: 0..1 power side, below 0 = the accuracy zone
var power := 0.0
var error := 0.0
var grade := ""      # PERFECT / GOOD / HOOK / SLICE / SHANK once done

var _up_s := 1.0
var _down_s := 0.8
var _cfg: Dictionary = {}


func setup(up_s: float, down_s: float, cfg: Dictionary) -> void:
	_up_s = maxf(up_s, 0.05)
	_down_s = maxf(down_s, 0.05)
	_cfg = cfg
	cancel()


func cancel() -> void:
	phase = Phase.IDLE
	value = 0.0
	power = 0.0
	error = 0.0
	grade = ""


func busy() -> bool:
	return phase == Phase.POWER or phase == Phase.ACCURACY


func zone() -> float:
	return float(_cfg.get("zone", 0.14))


func click() -> void:
	match phase:
		Phase.IDLE, Phase.DONE:
			cancel()
			phase = Phase.POWER
		Phase.POWER:
			power = clampf(value, 0.0, 1.0)
			phase = Phase.ACCURACY
		Phase.ACCURACY:
			_finish(value)


func update(dt: float) -> void:
	if phase == Phase.POWER:
		value += dt / _up_s
		if value >= 1.0:
			value = 1.0
			power = 1.0
			phase = Phase.ACCURACY
	elif phase == Phase.ACCURACY:
		value -= dt / _down_s
		if value < -zone():
			value = -zone()
			_shank()


func _finish(at: float) -> void:
	var off := absf(at)
	if off <= float(_cfg.get("sweet", 0.03)):
		error = 0.0
		grade = "PERFECT"
	else:
		error = clampf(-at / zone(), -1.0, 1.0)  # early (above the line) = negative = hook
		if off <= float(_cfg.get("good", 0.07)):
			error *= 0.5
			grade = "GOOD"
		else:
			grade = "HOOK" if error < 0.0 else "SLICE"
	phase = Phase.DONE


func _shank() -> void:
	error = float(_cfg.get("shank", 1.5))
	power *= float(_cfg.get("shank_power", 0.6))
	grade = "SHANK"
	phase = Phase.DONE
