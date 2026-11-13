# LifeState — a player's alive / downed / dead state (D-015).
# At 0 HP a player goes DOWNED and bleeds out over bleed_out_seconds. A teammate holding interact nearby
# calls host_revive_step() each tick; bleed-out pauses while that's happening, and progress resets if they
# stop for longer than REVIVE_GRACE. Full progress emits `revived`; running out of time emits `bled_out`.
# Host only changes state; net_* replicate through the player's MultiplayerSynchronizer ("Life:net_*").
# Depends on: CombatRules (tuning).
class_name LifeState
extends Node

signal revived
signal bled_out

enum { ALIVE, DOWNED, DEAD }

const REVIVE_GRACE := 0.25  # seconds without a revive step before progress resets

var net_state := ALIVE
var net_bleed_left := 0.0
var net_revive_progress := 0.0  # 0..1

var _bleed_out_seconds := 30.0
var _revive_seconds := 3.0
var _time := 0.0
var _last_revive_time := -1.0


func _ready() -> void:
	var tuning := CombatRules.load_tuning()
	_bleed_out_seconds = tuning.get("bleed_out_seconds", 30.0)
	_revive_seconds = tuning.get("revive_seconds", 3.0)


# Bonk (D-032) uses his own downed time; when it runs out he gets himself up instead of dying.
func set_bleed_out_seconds(seconds: float) -> void:
	_bleed_out_seconds = seconds


func is_downed() -> bool:
	return net_state == DOWNED


func host_go_down() -> void:
	net_state = DOWNED
	net_bleed_left = _bleed_out_seconds
	net_revive_progress = 0.0


func host_set_alive() -> void:
	net_state = ALIVE
	net_bleed_left = 0.0
	net_revive_progress = 0.0


# Host, once per physics tick.
func host_tick(delta: float) -> void:
	_time += delta
	if net_state != DOWNED:
		return
	var being_revived := _time - _last_revive_time <= REVIVE_GRACE
	if not being_revived:
		net_revive_progress = 0.0
		net_bleed_left -= delta
		if net_bleed_left <= 0.0:
			net_bleed_left = 0.0
			net_state = DEAD
			bled_out.emit()


# Host, each tick a living teammate in range holds interact.
func host_revive_step(delta: float) -> void:
	if net_state != DOWNED:
		return
	_last_revive_time = _time
	net_revive_progress = minf(net_revive_progress + delta / _revive_seconds, 1.0)
	if net_revive_progress >= 1.0:
		revived.emit()
