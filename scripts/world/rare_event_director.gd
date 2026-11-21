# RareEventDirector — the rare, quiet, slightly wrong things (D-108): somebody standing outside the bunker at
# 3 AM, a mannequin indoors that was not there before, a golf ball rolling to a stop at your feet, a knock with
# nobody behind it, lights on in a house you cleared, a car idling where no car was. Main child "RareEvents",
# group "rare_events"; same path on every peer.
# Host, every check_seconds: rolls `chance`, then picks one event whose conditions hold (in-game hour, distance
# from the bunker, weather, quest flags, its own cooldown and how many times it may ever happen) and sends it to
# ONE player - only that player's game shows it, so nobody can corroborate. That peer places it (a figure, a prop,
# a sound or a light) at the spot kind the event asks for, keeps it out of the way, and takes it away again when
# the player gets close, looks away, or its time runs out. Nothing here fights, blocks or drops anything.
# Depends on: PropKits, EncounterSite (prop building), CharacterAnimator, data/encounters/rare_events.json,
# SubtitleUI (group "subtitles"), SaveDirector (host_save_state / host_load_state).
class_name RareEventDirector
extends Node3D

const PATH := "res://data/encounters/rare_events.json"
const GROUND_MASK := 17
const WORLD_MASK := 1

var defs: Dictionary = {}
var seen: Dictionary = {}       # id -> how many times it has happened (saved)
var showing := ""               # the event this peer is showing

var _t: Dictionary = {}
var _timer := 60.0
var _last: Dictionary = {}      # host: id -> seconds
var _node: Node3D
var _left := 0.0
var _rng := RandomNumberGenerator.new()
var _player_was := Vector3.ZERO
var _roll_to := Vector3.INF
var _sound: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("rare_events")
	_rng.randomize()
	var raw := DataLoader.load_json(PATH)
	_t = raw.get("tuning", {})
	for id: String in raw.get("events", {}):
		var d: Dictionary = raw.events[id]
		d["id"] = id
		defs[id] = d
	_timer = float(_t.get("first_delay_s", 240.0))


func _process(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_timer -= delta
		if _timer <= 0.0:
			_timer = float(_t.get("check_seconds", 120.0))
			_host_roll()
	if showing != "":
		_tick(delta)


# --- host ---------------------------------------------------------------------------

func _host_roll() -> void:
	if _rng.randf() > float(_t.get("chance", 0.35)):
		return
	var players: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id > 0 and not p.health.is_dead():
			players.append(p)
	if players.is_empty():
		return
	var who: Node3D = players[_rng.randi() % players.size()]
	var hour := _hour()
	var bunker := _bunker()
	var dist := bunker.distance_to(who.global_position) if bunker != Vector3.INF else 0.0
	var can: Array = []
	for id: String in defs:
		if _can_fire(defs[id], hour, dist):
			can.append(id)
	if can.is_empty():
		return
	var id: String = can[_rng.randi() % can.size()]
	_last[id] = _now()
	seen[id] = int(seen.get(id, 0)) + 1
	_show.rpc_id(who.peer_id, id, int(_rng.randi()))


func _can_fire(def: Dictionary, hour: float, bunker_m: float) -> bool:
	var id := str(def.id)
	if int(seen.get(id, 0)) >= int(def.get("max_times", 99)):
		return false
	if _now() - float(_last.get(id, -1.0e12)) < float(def.get("cooldown_s", 3600.0)):
		return false
	if not EncounterRules.hour_in(def.get("hours", []), hour):
		return false
	if bunker_m < float(def.get("min_bunker_m", 0.0)) or bunker_m > float(def.get("max_bunker_m", 1.0e9)):
		return false
	var w: Array = def.get("weather", [])
	if not w.is_empty():
		var node := get_tree().get_first_node_in_group("weather")
		if node == null or not (str(node.state) in w):
			return false
	var quests := get_tree().get_first_node_in_group("quests")
	return QuestRules.requires_met(def.get("requires"), quests.flags if quests else {})


# Debug / tests: show `id` on this peer right now, wherever it can be placed.
func force(id: String) -> bool:
	if not defs.has(id):
		return false
	_show(id, int(_rng.randi()))
	return showing == id


# Seconds until `id` may happen again (0 = now). Host-side; a client reads zeroes, which is correct for it.
func _cooldown_left(id: String) -> float:
	if not defs.has(id):
		return 0.0
	return maxf(float(defs[id].get("cooldown_s", 3600.0)) - (_now() - float(_last.get(id, -1.0e12))), 0.0)


func host_save_state() -> Dictionary:
	return {"seen": seen.duplicate()}


func host_load_state(saved: Variant) -> void:
	seen.clear()
	if typeof(saved) == TYPE_DICTIONARY:
		for id: String in (saved as Dictionary).get("seen", {}):
			seen[id] = int((saved as Dictionary).seen[id])


# --- the showing peer ---------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _show(id: String, event_seed: int) -> void:
	if showing != "" or not defs.has(id):
		return
	var me := get_tree().get_first_node_in_group("local_player") as Node3D
	if me == null:
		return
	var def: Dictionary = defs[id]
	var rng := RandomNumberGenerator.new()
	rng.seed = event_seed
	var at := _spot(def, me, rng)
	if at == Vector3.INF:
		return
	showing = id
	_left = float(def.get("show_s", 45.0))
	_player_was = me.global_position
	_roll_to = me.global_position if bool(def.get("roll_to_player", false)) else Vector3.INF
	match str(def.get("kind", "prop")):
		"figure":
			_node = _figure(str(def.get("model", "suit_watcher")), at, me)
		"sound":
			_node = _noise(str(def.get("sound", "knock")), at)
		"light":
			_node = _lamp(at, def)
		_:
			_node = _props(def, at, rng)
	if def.has("line"):
		var ui := get_tree().get_first_node_in_group("subtitles")
		if ui:
			ui.show_bark(str(def.get("speaker", "")), str(def.line), at, 40.0)


func _tick(delta: float) -> void:
	var me := get_tree().get_first_node_in_group("local_player") as Node3D
	if me == null or _node == null or not is_instance_valid(_node):
		_clear()
		return
	var def: Dictionary = defs[showing]
	var d := me.global_position.distance_to(_node.global_position)
	if _roll_to != Vector3.INF:  # the golf ball: it rolls the last few metres and stops
		var to := me.global_position - _node.global_position
		to.y = 0.0
		if to.length() > 1.4:
			_node.global_position += to.normalized() * minf(2.2 * delta, to.length() - 1.4)
	if bool(def.get("face_player", false)):
		var look := me.global_position - _node.global_position
		_node.rotation.y = atan2(-look.x, -look.z)
	_left -= delta
	if d < float(def.get("vanish_m", 12.0)) or _left <= 0.0:
		if bool(def.get("stay", false)) and d >= float(def.get("vanish_m", 12.0)):
			return  # props that are simply left behind until the player walks up
		_clear()


func _clear() -> void:
	if _node and is_instance_valid(_node):
		_node.queue_free()
	_node = null
	showing = ""
	_roll_to = Vector3.INF


# --- placing ---------------------------------------------------------------------------

func _spot(def: Dictionary, me: Node3D, rng: RandomNumberGenerator) -> Vector3:
	var space := get_world_3d().direct_space_state
	match str(def.get("where", "near_player")):
		"bunker_out", "bunker_in":
			var home := get_tree().root.find_child("bonk_bunker", true, false) as Node3D
			if home == null:
				return Vector3.INF
			var off: Array = def.get("at", [0, 0, 6])
			var p: Vector3 = home.global_transform * Vector3(off[0], off[1], off[2])
			if me.global_position.distance_to(p) > float(def.get("player_within_m", 60.0)):
				return Vector3.INF
			return p
		_:
			var band: Array = def.get("distance_m", [25.0, 60.0])
			for i in 14:
				var a := rng.randf() * TAU
				var r := rng.randf_range(float(band[0]), float(band[1]))
				var p := me.global_position + Vector3(sin(a), 0, cos(a)) * r
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 40.0, p + Vector3.DOWN * 40.0, GROUND_MASK))
				if hit.is_empty():
					continue
				var ground: Vector3 = hit.position
				var eye: Vector3 = me.eye_position() if me.has_method("eye_position") else me.global_position + Vector3.UP * 1.6
				var clear := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, ground + Vector3.UP * 1.0, WORLD_MASK)).is_empty()
				if bool(def.get("out_of_sight", false)) == clear:
					continue
				return ground
	return Vector3.INF


func _figure(model: String, at: Vector3, me: Node3D) -> Node3D:
	var holder := Node3D.new()
	add_child(holder)
	holder.global_position = at
	var body := CharacterAnimator.new()
	holder.add_child(body)
	body.set_model(model)
	var look := me.global_position - at
	holder.rotation.y = atan2(-look.x, -look.z)
	return holder


func _props(def: Dictionary, at: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var site := EncounterSite.new()
	add_child(site)
	site.global_position = at
	site.rotation.y = rng.randf() * TAU
	site.build(0, str(def.id), {"props": def.get("props", [])}, int(rng.randi()), self)
	return site


func _lamp(at: Vector3, def: Dictionary) -> Node3D:
	var holder := Node3D.new()
	add_child(holder)
	holder.global_position = at + Vector3.UP * float(def.get("height_m", 2.0))
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.86, 0.6)
	light.light_energy = 3.0
	light.omni_range = 18.0
	light.shadow_enabled = false
	holder.add_child(light)
	return holder


# Short generated sounds, so nothing has to be downloaded: a knock, a phone ring, or radio static.
func _noise(kind: String, at: Vector3) -> Node3D:
	var holder := Node3D.new()
	add_child(holder)
	holder.global_position = at + Vector3.UP * 1.2
	_sound = AudioStreamPlayer3D.new()
	_sound.stream = _wav(kind)
	_sound.unit_size = 14.0
	_sound.max_distance = 60.0
	holder.add_child(_sound)
	_sound.play()
	return holder


func _wav(kind: String) -> AudioStreamWAV:
	var rate := 22050
	var seconds := 2.4
	var n := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var v := 0.0
		match kind:
			"knock":
				for k in 3:
					var dt := t - 0.25 * k
					if dt >= 0.0 and dt < 0.12:
						v += sin(TAU * 90.0 * dt) * exp(-dt * 38.0) * 0.9
			"ring":
				var cycle := fmod(t, 1.2)
				if cycle < 0.45:
					v = (sin(TAU * 1050.0 * t) + sin(TAU * 1420.0 * t)) * 0.3 * (0.6 + 0.4 * sin(TAU * 22.0 * t))
			_:
				lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), 0.4)
				v = lp * 0.5 * (0.5 + 0.5 * sin(TAU * 0.7 * t)) + sin(TAU * (220.0 + 60.0 * sin(t * 3.0)) * t) * 0.12
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 10000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav


func _hour() -> float:
	var clock := get_tree().get_first_node_in_group("daynight")  # D-110: the world clock owns the time of day
	if clock:
		return float(clock.hour)
	var enc := get_tree().get_first_node_in_group("encounters")
	return enc.hour() if enc and enc.has_method("hour") else 12.0


func _bunker() -> Vector3:
	var home := get_tree().root.find_child("bonk_bunker", true, false) as Node3D
	return home.global_position if home else Vector3.INF


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
