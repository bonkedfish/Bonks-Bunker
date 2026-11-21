# BunkerBed — the bunks in Bonk's bunker, and what happens when somebody sleeps in one (D-110). Main child "Bed",
# group "bunker_bed"; every peer has it at the same path.
# It adds an E spot (group "sport_spots") to each bunk listed in data/tuning/day_night.json `beds` (local to the
# bonk_bunker landmark, so the bunker scene itself is untouched). The bunks are already modelled in that scene -
# this only makes them usable.
# Pressing E: the host refuses by day (the prompt says so), and at night ONE player sleeping skips the whole
# server to wake_hour and wakes everybody healed, fed and watered - the party slept through the night together.
# Depends on: DayNight (group "daynight"), the bonk_bunker landmark, Players (group "players": health, needs),
# HUD (group "hud"), DataLoader.
class_name BunkerBed
extends Node3D

const PATH := "res://data/tuning/day_night.json"
const SLOT := 94100  # its own E-spot slot, well clear of the encounter and oddity slots

var tuning: Dictionary = {}
var built := false

var _retry := 1.0


func _ready() -> void:
	add_to_group("bunker_bed")
	tuning = DataLoader.load_json(PATH)


func _process(delta: float) -> void:
	if built:
		return
	_retry -= delta
	if _retry > 0.0:
		return
	_retry = 3.0
	var home := get_tree().root.find_child(str(tuning.get("bed_landmark", "bonk_bunker")), true, false) as Node3D
	if home == null:
		return
	built = true
	var beds: Array = tuning.get("beds", [])
	for i in beds.size():
		var bed: Dictionary = beds[i]
		var at: Array = bed.get("at", [0, 0, 0])
		var size: Array = bed.get("size", [1.6, 1.3, 2.2])
		var body := StaticBody3D.new()
		body.name = "Bunk_%d" % i
		body.collision_layer = 9
		body.collision_mask = 0
		add_child(body)
		body.global_transform = home.global_transform * Transform3D(Basis(), Vector3(at[0], at[1], at[2]))
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(size[0], size[1], size[2])
		shape.shape = box
		body.add_child(shape)
		body.add_to_group("sport_spots")
		body.set_meta("display_name", str(tuning.get("bed_label", "Sleep until morning")))
		body.set_meta("target", self)
		body.set_meta("index", SLOT * 100 + i)


# A player pressed E on a bunk.
@rpc("any_peer", "call_local", "reliable")
func request_use(index: int) -> void:
	if not multiplayer.is_server() or floori(index / 100.0) != SLOT:
		return
	var who := _player()
	if who == null:
		return
	var clock := get_tree().get_first_node_in_group("daynight")
	if clock == null:
		return
	if not clock.is_night():
		_say.rpc_id(who.peer_id, str(tuning.get("bed_day_say", "Not until dark.")))
		return
	var skipped: float = clock.host_skip_to_morning()
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id > 0 and not p.health.is_dead():
			p.health.reset()
			var needs := p.get_node_or_null("Needs")
			if needs:
				needs.host_reset()
	_slept.rpc(str(who.net_name) if str(who.net_name) != "" else "Someone", skipped)


@rpc("authority", "call_local", "reliable")
func _slept(sleeper: String, skipped: float) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_toast("%s slept. %.0f hours pass; everyone wakes rested." % [sleeper, skipped], 5.0)


@rpc("authority", "call_local", "reliable")
func _say(text: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_toast(text, 3.5)


func _player() -> Node:
	var id := multiplayer.get_remote_sender_id()
	var peer := id if id != 0 else multiplayer.get_unique_id()
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == peer and not p.health.is_dead():
			return p
	return null
