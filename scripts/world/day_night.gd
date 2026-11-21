# DayNight — the world clock and the sky that follows it (D-110). Main child "DayNight", group "daynight";
# every peer has it at the same path.
# One full day takes day_seconds (2880 = 48 real minutes), which is the clock the encounters already ran on.
# Every peer advances its own `hour` from delta so the sky is smooth, and the host sends the true hour every
# sync_seconds (and to any peer that joins), so nobody drifts. Sleeping (BunkerBed) calls host_skip_to(), which
# jumps everyone at once.
# Each frame it hands Atmosphere the sun's elevation and how far into night we are; Atmosphere does the look.
# After sunset the sun light is MIRRORED to the other side of the sky and recoloured: that is the moon, so night
# is lit and still casts soft shadows, and the sky shader draws its disc.
# Read by: ZombieDirector (more and nastier zombies at night), EncounterDirector / RareEventDirector (hour
# windows), BunkerBed. Saved by SaveDirector as world.day_night.
# Depends on: DayNightRules, DataLoader, data/tuning/day_night.json, Atmosphere (sibling "Atmosphere").
class_name DayNight
extends Node

const PATH := "res://data/tuning/day_night.json"

var hour := 8.0
var tuning: Dictionary = {}

var _sync_in := 0.0
var _atmosphere: Node


func _ready() -> void:
	add_to_group("daynight")
	tuning = DataLoader.load_json(PATH)
	hour = float(tuning.get("start_hour", 8.0))
	_sync_in = float(tuning.get("sync_seconds", 10.0))
	multiplayer.peer_connected.connect(_on_peer_connected)


func _process(delta: float) -> void:
	hour = DayNightRules.advance(hour, delta, float(tuning.get("day_seconds", 2880.0)))
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_in -= delta
		if _sync_in <= 0.0:
			_sync_in = float(tuning.get("sync_seconds", 10.0))
			_sync.rpc(hour)
	_drive_sky()


# --- what everything else asks ---------------------------------------------------------

func night() -> float:
	return DayNightRules.night_factor(hour, tuning)


func is_night() -> bool:
	return DayNightRules.is_night(hour, tuning)


func clock() -> String:
	return DayNightRules.clock(hour)


func phase() -> String:
	return DayNightRules.phase_name(hour, tuning)


# --- sleeping ---------------------------------------------------------------------------

# Host: everybody's clock jumps forward to wake_hour. Never goes backwards.
func host_skip_to_morning() -> float:
	var wake := float(tuning.get("wake_hour", 7.0))
	var skipped := DayNightRules.hours_until(hour, wake)
	_sync.rpc(wake)
	return skipped


# --- the look ----------------------------------------------------------------------------

func _drive_sky() -> void:
	if _atmosphere == null:
		_atmosphere = get_parent().get_node_or_null("Atmosphere")
		if _atmosphere == null:
			return
	_atmosphere.set_time_of_day(DayNightRules.sun_elevation(hour, tuning), night(),
		DayNightRules.dusk_factor(hour, tuning), tuning)


# --- net + save ---------------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		_sync.rpc_id(id, hour)


@rpc("authority", "call_local", "reliable")
func _sync(new_hour: float) -> void:
	hour = new_hour


func host_save_state() -> Dictionary:
	return {"hour": hour}


func host_load_state(saved: Variant) -> void:
	if typeof(saved) == TYPE_DICTIONARY:
		hour = float((saved as Dictionary).get("hour", hour))
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			_sync.rpc(hour)
