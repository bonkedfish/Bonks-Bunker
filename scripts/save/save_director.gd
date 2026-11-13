# SaveDirector — "Saves" node in main.tscn (group "save_director"). Host only does anything (D-037):
#   * Host picks a world in the menu -> host_open_world() loads it (or makes a new one).
#   * Session starts -> host_start() puts saved container contents and Bonk back.
#   * Each player is matched to a saved character by PlayerIdentity: the host's own ID directly,
#     clients send theirs with register_player(). A known character gets its position, health, items
#     magazines and hunger/thirst back; a new one keeps the starting kit and bunker spawn.
#   * Saves: every autosave_seconds, F5 (quicksave), when the window closes, and a leaving player's
#     character is captured before their body is removed. Everyone sees a short "Game saved" note.
# Depends on: SaveFormat, SaveStore, PlayerIdentity, DataLoader, CombatRules, SurvivalRules, players (group "players"),
# QuestDirector (group "quests": quest flags, incl. killed bosses), loot containers (group "loot_containers"), world drops (group "world_drops"), Bonk (group "bonk"), HUD (group "hud").
extends Node

const TUNING_PATH := "res://data/tuning/save.json"
const TUNING_SCHEMA := {"autosave_seconds": TYPE_FLOAT, "toast_seconds": TYPE_FLOAT, "max_worlds_listed": TYPE_FLOAT}

var world: Dictionary = {}  # host: the world being played (the save file's contents)
var world_slug := ""

var _key_by_peer: Dictionary = {}  # host: peer_id -> key into world.players
var _autosave_seconds := 300.0
var _autosave_left := 0.0
var _toast_seconds := 2.5
var _started := false


func _ready() -> void:
	add_to_group("save_director")
	var t := DataLoader.load_validated(TUNING_PATH, TUNING_SCHEMA)
	_autosave_seconds = float(t.get("autosave_seconds", 300.0))
	_toast_seconds = float(t.get("toast_seconds", 2.5))
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)  # connected before Main's, so the body still exists


# --- host: choosing and starting a world ---------------------------------------------

# slug "" = a new world called new_name. False if the chosen save can't be read.
func host_open_world(slug: String, new_name: String) -> bool:
	if slug == "":
		world_slug = SaveStore.unique_slug(new_name)
		world = SaveFormat.new_world(new_name, _now())
		return true
	var data := SaveStore.read(slug)
	if data.is_empty():
		return false
	world = data
	world_slug = slug
	return true


# Called by Main when the host's session is up, before the host's own body spawns.
func host_start() -> void:
	if not _is_host() or world.is_empty():
		return
	_started = true
	_key_by_peer.clear()
	_autosave_left = _autosave_seconds
	for c in get_tree().get_nodes_in_group("loot_containers"):
		if world.containers.has(c.container_id):
			c.host_load_state(SaveFormat.clean_items(world.containers[c.container_id]))
	var drops := get_tree().get_first_node_in_group("world_drops")
	if drops:
		drops.host_load_state(SaveFormat.drops_of(world))
	var quests := get_tree().get_first_node_in_group("quests")
	if quests:
		var saved: Variant = world.get("quests", {})
		quests.host_load_state(saved if typeof(saved) == TYPE_DICTIONARY else {})
	var bonk := get_tree().get_first_node_in_group("bonk")
	if bonk and not world.bonk.is_empty():
		var pos := SaveFormat.array_to_vec(world.bonk.position)
		bonk.global_position = pos
		bonk.net_position = pos
		bonk.health.current = clampf(float(world.bonk.health), 1.0, bonk.health.max_health)
	print("Saves: playing world '%s' (%s), %d characters, %d opened containers" % [
		world.name, world_slug, world.players.size(), world.containers.size()])


# Called by Main right after a player body spawns on the host.
func host_player_spawned(player: Node) -> void:
	if not _started:
		return
	if player.peer_id == multiplayer.get_unique_id():
		_assign(player.peer_id, PlayerIdentity.uid())
	elif _key_by_peer.has(player.peer_id):
		_apply_player(player, _key_by_peer[player.peer_id])


# Client -> host, once after joining.
@rpc("any_peer", "call_remote", "reliable")
func register_player(uid: String) -> void:
	if not _is_host() or not _started:
		return
	var peer := multiplayer.get_remote_sender_id()
	if _key_by_peer.has(peer) or not PlayerIdentity.is_valid(uid):
		return
	_assign(peer, uid)


# --- host: saving ------------------------------------------------------------------

func host_save(reason: String) -> bool:
	if not _is_host() or not _started:
		return false
	_capture()
	var ok := SaveStore.write(world_slug, world)
	print("Saves: %s save of '%s' %s" % [reason, world_slug, "ok" if ok else "FAILED"])
	_toast.rpc("Game saved" if ok else "SAVE FAILED")
	_autosave_left = _autosave_seconds
	return ok


func _process(delta: float) -> void:
	if not _started or not _is_host():
		return
	world.play_seconds = float(world.play_seconds) + delta
	_autosave_left -= delta
	if _autosave_left <= 0.0:
		host_save("auto")


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("quicksave"):
		return
	if _is_host():
		host_save("quick")
	elif multiplayer.has_multiplayer_peer():
		_toast("Only the host can save")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		host_save("quit")


func _on_peer_disconnected(peer: int) -> void:
	if not _is_host() or not _key_by_peer.has(peer):
		return
	var p := _player(peer)
	if p:
		world.players[_key_by_peer[peer]] = _player_entry(p)
	_key_by_peer.erase(peer)


# --- host: state <-> nodes -------------------------------------------------------------

func _assign(peer: int, uid: String) -> void:
	var key := uid
	if key in _key_by_peer.values():
		key = "%s-%d" % [uid, peer]  # same install twice (two windows on one PC): a separate guest character
	_key_by_peer[peer] = key
	var p := _player(peer)
	if p:
		_apply_player(p, key)


func _apply_player(player: Node, key: String) -> void:
	var e: Dictionary = world.players.get(key, {})
	if e.is_empty():
		return  # new character: starting kit, bunker spawn
	var pos := SaveFormat.array_to_vec(e.position)
	player.global_position = pos
	player.net_position = pos
	player.velocity = Vector3.ZERO
	player.health.current = clampf(float(e.health), 1.0, player.health.max_health)
	player.inventory.net_items = SaveFormat.clean_items(e.items)
	player.weapons.host_load_mags(e.get("mags", []))
	player.needs.host_set(SaveFormat.needs_of(e, float(SurvivalRules.tuning().get("max_need", 100.0))))


func _capture() -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id > 0 and _key_by_peer.has(p.peer_id):
			world.players[_key_by_peer[p.peer_id]] = _player_entry(p)
	for c in get_tree().get_nodes_in_group("loot_containers"):
		var state: Variant = c.host_save_state()
		if state != null and c.container_id != "":
			world.containers[c.container_id] = state
	var drops := get_tree().get_first_node_in_group("world_drops")
	if drops:
		world["drops"] = drops.host_save_state()
	var quests := get_tree().get_first_node_in_group("quests")
	if quests:
		world["quests"] = quests.host_save_state()
	var bonk := get_tree().get_first_node_in_group("bonk")
	if bonk:
		world.bonk = {"position": SaveFormat.vec_to_array(bonk.global_position),
			"health": maxf(bonk.health.current, float(bonk.def.get("revive_health", 60.0)))}
	world.saved = _now()


# Downed or dead players are saved at revive health so a load never starts someone dying.
func _player_entry(p: Node) -> Dictionary:
	var hp: float = p.health.current
	if p.health.is_dead() or p.life.net_state != LifeState.ALIVE:
		hp = float(CombatRules.load_tuning().get("revive_health", 30.0))
	return SaveFormat.player_entry(p.global_position, hp, p.inventory.net_items, p.weapons.host_save_mags(), p.needs.value())


func _player(peer: int) -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == peer:
			return p
	return null


func _is_host() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


func _now() -> int:
	return int(Time.get_unix_time_from_system())


# --- host -> everyone ------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _toast(text: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_toast(text, _toast_seconds)
