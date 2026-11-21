# EncounterDirector — random encounters in the open world (D-105). Main child "Encounters", group "encounters";
# every peer has it at the same path, so its RPCs line up.
# Host, every check_seconds: if fewer than max_active sites are open and the global cooldown is up, it looks for a
# spot on a road near_m from a random living player, out of everyone's sight, outside a safe zone (D-101), level
# and clear of buildings and other sites; then EncounterRules picks a definition (weight x rarity, per-encounter
# cooldown, quest flags, in-game hour, weather, distance from the bunker) and _open() tells every peer to build it.
# Every peer builds the identical EncounterSite from (id, position, yaw, seed) - nothing per-node is replicated.
# Sites close when everyone is beyond keep_m, when their life_s runs out, or when an action closes them.
# Outcomes are data: a use spot's or a dialogue node's action {needs, gives, flag(s), say, then} is run by the host
# ("then": close / ambush / hostile). Ambush bodies come from the shared LairDirector pool through markers the site
# adds on every peer. Which encounters have happened (and when) is saved in the world as "encounters".
# Depends on: EncounterRules, EncounterSite, data/encounters/encounters.json, data/tuning/encounters.json,
# WorldStreamer (group "world_streamer"), SafeZones (group "safe_zones"), WeatherDirector (group "weather"),
# QuestDirector (group "quests"), LairDirector (group "lair_director"), SaveDirector (group "save_director"),
# HUD (group "hud"), DialogueDirector (its node "encounter" action calls host_dialogue_action).
class_name EncounterDirector
extends Node3D

const DEFS_PATH := "res://data/encounters/encounters.json"
const TUNING_PATH := "res://data/tuning/encounters.json"
const GROUND_MASK := 17
const WORLD_MASK := 1

var defs: Dictionary = {}
var state: Dictionary = EncounterRules.new_state()
var sites: Dictionary = {}  # slot -> EncounterSite (every peer)

var _t: Dictionary = {}
var _timer := 5.0
var _global_until := 0.0
var _opened_at: Dictionary = {}  # host: slot -> seconds when it opened
var _rng := RandomNumberGenerator.new()
var _streamer: Node
var _saves: Node
var _quests: Node
var _clock: Node


func _ready() -> void:
	add_to_group("encounters")
	_rng.randomize()
	_t = DataLoader.load_json(TUNING_PATH)
	var raw := DataLoader.load_json(DEFS_PATH)
	for id: String in raw:
		if typeof(raw[id]) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = (raw[id] as Dictionary).duplicate(true)
		d["id"] = id
		defs[id] = d


func _process(delta: float) -> void:
	if not (multiplayer.has_multiplayer_peer() and multiplayer.is_server()):
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = float(_t.get("check_seconds", 20.0))
	_host_cull()
	if sites.size() >= int(_t.get("max_active", 3)) or _now() < _global_until:
		return
	_host_try_open()


# --- host: opening and closing ----------------------------------------------------------

func _host_try_open() -> void:
	var players := _living()
	if players.is_empty():
		return
	var who: Node3D = players[_rng.randi() % players.size()]
	var spot := _find_spot(who, players)
	if spot == Vector3.INF:
		return
	var id := EncounterRules.pick(defs, _rng, _now(), state, _flags(), hour(), _weather(),
		_bunker_distance(spot), "road", _t.get("rarity_weight", {}))
	if id == "":
		return
	host_open(id, spot, _rng.randf() * TAU)


# Opens `id` at `at` (also the debug force path). Returns the slot, or -1.
func host_open(id: String, at: Vector3, yaw := 0.0) -> int:
	if not defs.has(id):
		return -1
	while sites.size() >= int(_t.get("max_active", 3)):  # the oldest one makes room, so the cap always holds
		var oldest := -1
		var oldest_at := 1.0e12
		for s: int in _opened_at:
			if sites.has(s) and float(_opened_at[s]) < oldest_at:
				oldest_at = float(_opened_at[s])
				oldest = s
		if oldest < 0:
			break
		host_close(oldest)
	var slot := 0
	while sites.has(slot):
		slot += 1
	EncounterRules.mark_fired(state, id, _now(), bool(defs[id].get("once", false)))
	_global_until = _now() + float(_t.get("global_cooldown_s", 240.0))
	_opened_at[slot] = _now()
	_open.rpc(slot, id, at, yaw, int(_rng.randi()))
	return slot


func host_close(slot: int) -> void:
	if not sites.has(slot):
		return
	var lairs := get_tree().get_first_node_in_group("lair_director")
	if lairs and lairs.has_method("host_release"):
		lairs.host_release((sites[slot] as EncounterSite).ambush_prefix())
	_opened_at.erase(slot)
	_close.rpc(slot)


func _host_cull() -> void:
	var keep := float(_t.get("keep_m", 320.0))
	var players := _living()
	for slot: int in sites.keys():
		var site: EncounterSite = sites[slot]
		var near := INF
		for p: Node3D in players:
			near = minf(near, p.global_position.distance_to(site.global_position))
		var life := float((defs.get(site.encounter_id, {}) as Dictionary).get("life_s", 1800.0))
		if near > keep or _now() - float(_opened_at.get(slot, _now())) > life:
			host_close(slot)


# --- host: picking a spot ---------------------------------------------------------------

# A road spot near `who`, out of sight of everyone, level, clear and legal. Vector3.INF if none.
func _find_spot(who: Node3D, players: Array) -> Vector3:
	if _streamer == null:
		_streamer = get_tree().get_first_node_in_group("world_streamer")
	if _streamer == null or not _streamer.has_index():
		return Vector3.INF
	var band: Array = _t.get("near_m", [70.0, 190.0])
	var cells: Array = _streamer.want_near.keys()
	if cells.is_empty():
		return Vector3.INF
	var space := get_world_3d().direct_space_state
	var safe := get_tree().get_first_node_in_group("safe_zones")
	for i in int(_t.get("spot_tries", 14)):
		var markers: Array[Node] = _streamer.spawn_points(cells[_rng.randi() % cells.size()])
		if markers.is_empty():
			continue
		var point: Vector3 = markers[_rng.randi() % markers.size()].global_position
		var d := who.global_position.distance_to(point)
		if d < float(band[0]) or d > float(band[1]):
			continue
		if safe and safe.contains(point):
			continue
		var too_close := false
		for slot: int in sites:
			too_close = too_close or (sites[slot] as Node3D).global_position.distance_to(point) < float(_t.get("min_apart_m", 150.0))
		if too_close:
			continue
		var seen := false
		for p: Node3D in players:
			var eye: Vector3 = p.eye_position() if p.has_method("eye_position") else p.global_position + Vector3.UP * 1.6
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, point + Vector3.UP * 1.5, WORLD_MASK)).is_empty():
				seen = true
		if seen:
			continue
		var ground := _ground(space, point)
		if ground == Vector3.INF or not _level_and_clear(space, ground):
			continue
		return ground
	return Vector3.INF


func _ground(space: PhysicsDirectSpaceState3D, near: Vector3) -> Vector3:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(near + Vector3.UP * 40.0, near + Vector3.DOWN * 40.0, GROUND_MASK))
	return hit.position if not hit.is_empty() else Vector3.INF


# Level ground all round and nothing solid standing in the site's footprint.
func _level_and_clear(space: PhysicsDirectSpaceState3D, ground: Vector3) -> bool:
	var r := float(_t.get("clear_check_m", 2.5))
	for off: Vector3 in [Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, 0, r), Vector3(0, 0, -r)]:
		var g := _ground(space, ground + off)
		if g == Vector3.INF or absf(g.y - ground.y) > float(_t.get("flat_tolerance_m", 1.1)):
			return false
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(r * 2.0, 3.0, r * 2.0)
	query.shape = box
	query.collision_mask = WORLD_MASK
	query.transform = Transform3D(Basis(), ground + Vector3.UP * 1.8)
	return space.intersect_shape(query, 1).is_empty()


# --- host: player actions ---------------------------------------------------------------

# An E spot inside a site (the player's "sport_spots" path): index = slot * 100 + use index.
@rpc("any_peer", "call_local", "reliable")
func request_use(index: int) -> void:
	if not multiplayer.is_server():
		return
	var slot := floori(index / 100.0)
	var use_index := index % 100
	if not sites.has(slot):
		return
	var site: EncounterSite = sites[slot]
	var player := _validated(site.global_position, 6.0)
	if player == null:
		return
	var uses: Array = site.def.get("uses", [])
	if use_index < 0 or use_index >= uses.size():
		return
	_run_action(site, uses[use_index], player)


# DialogueDirector calls this when a dialogue node carries "encounter": "<action key>".
func host_dialogue_action(npc: Node, action: String, peer: int) -> void:
	if not multiplayer.is_server():
		return
	var site := npc.get_parent() as EncounterSite
	if site == null:
		return
	var actions: Dictionary = site.def.get("actions", {})
	if not actions.has(action):
		return
	var player := _player(peer)
	if player:
		_run_action(site, actions[action], player)


# One data-driven outcome: {needs, gives, flag / flags, say, fail_say, then: ""|close|ambush|hostile}.
# A wager instead carries {chance, win, lose}: it rolls once and runs whichever outcome it lands on.
func _run_action(site: EncounterSite, action: Dictionary, player: Node) -> void:
	if action.has("chance"):
		var needs_bet: Dictionary = action.get("needs", {})
		for id: String in needs_bet:
			if player.inventory.count(id) < int(needs_bet[id]):
				_say.rpc_id(player.peer_id, str(action.get("fail_say", "You can't cover that bet.")))
				return
		_run_action(site, action.get("win" if _rng.randf() < float(action.chance) else "lose", {}), player)
		return
	var needs: Dictionary = action.get("needs", {})
	for id: String in needs:
		if player.inventory.count(id) < int(needs[id]):
			_say.rpc_id(player.peer_id, str(action.get("fail_say", "You don't have what that needs.")))
			return
	for id: String in needs:
		player.inventory.host_remove(id, int(needs[id]))
	for id: String in action.get("gives", {}):
		player.inventory.host_add(id, int(action.gives[id]))
	if _quests == null:
		_quests = get_tree().get_first_node_in_group("quests")
	if _quests:
		if action.has("flag"):
			_quests.host_set_flag(str(action.flag))
		for f: String in action.get("flags", []):
			_quests.host_set_flag(f)
	if action.has("say"):
		_say.rpc_id(player.peer_id, str(action.say))
	match str(action.get("then", "")):
		"close":
			host_close(site.slot)
		"ambush":
			_spring(site.slot)
		"hostile":
			_spring(site.slot)
			var npc := site.get_node_or_null("Npc")
			if npc:
				_hide_npc.rpc(site.slot)


func _spring(slot: int) -> void:
	if sites.has(slot) and not (sites[slot] as Node).has_node("Ambush"):
		_ambush.rpc(slot, int(_rng.randi()))


# --- saves (host) --------------------------------------------------------------------------

func host_save_state() -> Dictionary:
	return {"last": (state.last as Dictionary).duplicate(), "done": (state.done as Dictionary).duplicate()}


func host_load_state(saved: Variant) -> void:
	state = EncounterRules.clean_state(saved)


# --- debug ------------------------------------------------------------------------------

# Forces `id` to open near `who` (any spot rules that fail fall back to a clearing in front of them).
func debug_force(id: String, who: Node3D) -> int:
	var space := get_world_3d().direct_space_state
	var spot := _find_spot(who, _living())
	if spot == Vector3.INF:  # no road marker free: step round the player, still keeping sites apart
		var apart := float(_t.get("min_apart_m", 150.0))
		for i in 12:
			var a := TAU * i / 12.0
			var try_at := who.global_position + Vector3(sin(a), 0.0, cos(a)) * (apart + 20.0)
			var ground := _ground(space, try_at)
			if ground == Vector3.INF:
				continue
			var clear := true
			for site: Variant in sites.values():
				if (site as Node3D).global_position.distance_to(ground) < apart:
					clear = false
			if clear:
				spot = ground
				break
		if spot == Vector3.INF:
			spot = _ground(space, who.global_position - who.global_basis.z * 18.0)
		if spot == Vector3.INF:
			spot = who.global_position
	return host_open(id, spot, _rng.randf() * TAU)


# One line per definition: whether it could fire right now and why not.
func debug_report(at: Vector3) -> PackedStringArray:
	var out := PackedStringArray(["hour %.1f, weather %s, %d/%d sites, global cooldown %.0f s" % [hour(), _weather(),
		sites.size(), int(_t.get("max_active", 3)), maxf(_global_until - _now(), 0.0)]])
	var reasons := {}
	EncounterRules.pick(defs, _rng, _now(), state, _flags(), hour(), _weather(), _bunker_distance(at), "road",
		_t.get("rarity_weight", {}), reasons)
	for id: String in defs:
		out.append("  %-22s %-10s w %.2f  %s" % [id, str(defs[id].get("rarity", "common")),
			EncounterRules.weight_of(defs[id], _t.get("rarity_weight", {})), str(reasons.get(id, "READY"))])
	return out


# Seconds until the global cooldown is up (0 = now).
func global_left() -> float:
	return maxf(_global_until - _now(), 0.0)


func weather_now() -> String:
	return _weather()


func is_open(id: String) -> bool:
	for slot: int in sites:
		if str((sites[slot] as EncounterSite).encounter_id) == id:
			return true
	return false


# Fills `reasons` with id -> why it can't fire right now ("" when it can) and id + "#w" -> its weight, and
# returns the total eligible weight, so a debug readout can show each one's real chance of being picked next.
func debug_weights(reasons: Dictionary) -> float:
	var players := _living()
	var at: Vector3 = (players[0] as Node3D).global_position if not players.is_empty() else Vector3.ZERO
	var why := {}
	EncounterRules.pick(defs, _rng, _now(), state, _flags(), hour(), _weather(), _bunker_distance(at), "road",
		_t.get("rarity_weight", {}), why)
	var total := 0.0
	for id: String in defs:
		var blocked := str(why.get(id, ""))
		reasons[id] = blocked
		var w := EncounterRules.weight_of(defs[id], _t.get("rarity_weight", {})) if blocked == "" else 0.0
		reasons[id + "#w"] = w
		total += w
	return total


# --- shared helpers ------------------------------------------------------------------------

# The in-game hour. Since D-110 the world clock (DayNight) owns it and the sky follows it; the old derived
# clock is only a fallback for a scene that has no DayNight in it.
func hour() -> float:
	if _clock == null or not is_instance_valid(_clock):
		_clock = get_tree().get_first_node_in_group("daynight")
	if _clock:
		return float(_clock.hour)
	return EncounterRules.hour_of(_play_seconds(), float(_t.get("in_game_minutes_per_real_minute", 30.0)),
		float(_t.get("day_start_hour", 8.0)))


func _play_seconds() -> float:
	if _saves == null:
		_saves = get_tree().get_first_node_in_group("save_director")
	return float(_saves.world.get("play_seconds", 0.0)) if _saves and not _saves.world.is_empty() else 0.0


func _weather() -> String:
	var w := get_tree().get_first_node_in_group("weather")
	return str(w.state) if w and "state" in w else "clear"


func _flags() -> Dictionary:
	if _quests == null:
		_quests = get_tree().get_first_node_in_group("quests")
	return _quests.flags if _quests else {}


func _bunker_distance(at: Vector3) -> float:
	var home := get_tree().root.find_child("bonk_bunker", true, false) as Node3D
	return home.global_position.distance_to(at) if home else 0.0


func _living() -> Array:
	var out: Array = []
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id > 0 and not p.health.is_dead():
			out.append(p)
	return out


func _player(peer: int) -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == peer:
			return p
	return null


func _validated(near: Vector3, reach: float) -> Node:
	var id := multiplayer.get_remote_sender_id()
	var player := _player(id if id != 0 else multiplayer.get_unique_id())
	if player == null or player.health.is_dead() or player.global_position.distance_to(near) > reach + 8.0:
		return null
	return player


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# --- host -> everyone --------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _open(slot: int, id: String, at: Vector3, yaw: float, site_seed: int) -> void:
	if sites.has(slot) or not defs.has(id):
		return
	var site := EncounterSite.new()
	site.name = "Site_%d" % slot
	add_child(site)
	site.global_position = at
	site.rotation.y = yaw
	site.build(slot, id, defs[id], site_seed, self)
	sites[slot] = site


@rpc("authority", "call_local", "reliable")
func _close(slot: int) -> void:
	if sites.has(slot):
		(sites[slot] as Node).queue_free()
		sites.erase(slot)


@rpc("authority", "call_local", "reliable")
func _ambush(slot: int, site_seed: int) -> void:
	if not sites.has(slot):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = site_seed
	(sites[slot] as EncounterSite).add_ambush_markers(rng)


@rpc("authority", "call_local", "reliable")
func _hide_npc(slot: int) -> void:
	if not sites.has(slot):
		return
	var npc := (sites[slot] as Node).get_node_or_null("Npc")
	if npc:
		npc.queue_free()


@rpc("authority", "call_local", "reliable")
func _say(text: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_toast(text, 3.5)
