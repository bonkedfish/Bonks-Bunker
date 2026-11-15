# Net — owns the multiplayer session through the Tube addon (WebRTC, no server to host, no port forwarding).
#   Host:   create a session -> gets a 5-character lobby code to share.
#   Client: join with that code. Tube finds the host via public WebTorrent trackers (online) or
#           UDP broadcast (same LAN), then opens a direct WebRTC connection (STUN for NAT traversal,
#           TURN relays from data/net/network.json when a direct path can't be made).
# Tube installs its own MultiplayerAPI on the scene tree root when its TubeClient enters the tree,
# so this autoload adds it in _ready(), before any game scene connects to `multiplayer` signals.
# Recovery (D-091): every failed, timed-out or ended session goes back to a fresh start screen with a NEW
# TubeClient and a fresh Main (leave_to_menu), so nothing from the last attempt can block the next one
# (before, a stuck attempt made Host / Join do nothing until the game was restarted). Host starts on LAN after
# HOST_WAIT_S if no tracker has answered (trackers keep trying and announce when they open); joining gives up
# after JOIN_WAIT_S with a reason. menu_message carries that reason to the new start screen.
# Star topology: host = peer 1, clients talk only to the host (fits host-authoritative D-002).
# Requires: addons/tube, addons/webrtc_native.
# Depends on: DataLoader, data/net/network.json. Used by: main.gd (autoload "Net"), pause_menu.gd.
extends Node

signal session_started
signal session_failed(reason: String)
signal session_ended
signal lobby_code_changed(code: String)

const CONFIG_PATH := "res://data/net/network.json"
const CONFIG_SCHEMA := {
	"app_id": TYPE_STRING,
	"session_code_characters": TYPE_STRING,
	"signaling_timeout": TYPE_FLOAT,
	"signaling_attempts": TYPE_FLOAT,
	"trackers": TYPE_ARRAY,
	"stun_servers": TYPE_ARRAY,
	"turn_servers": TYPE_ARRAY,
}
const CODE_LENGTH := 5
const HOST_WAIT_S := 8.0
const JOIN_WAIT_S := 30.0
const JOIN_HELP := "Check the code and that the host is still in the game. If it keeps failing, one of your networks blocks direct connections and needs the TURN relay (data/net/network.json)."

var lobby_code := ""
var tube: TubeClient
var menu_message := ""  # read (and cleared) by the next Main's start screen
var _cfg: Dictionary
var _started := false
var _leaving := false
var _attempt := 0  # bumps on every host / join / leave so old timeouts do nothing


func _ready() -> void:
	_cfg = DataLoader.load_validated(CONFIG_PATH, CONFIG_SCHEMA)
	_new_tube()


# A brand-new TubeClient (and so a new MultiplayerAPI on the tree root). Only while no Main is connected to the old
# API: at start-up and inside leave_to_menu, between freeing the old Main and adding the new one.
func _new_tube() -> void:
	if tube:
		if tube.state != TubeClient.State.IDLE:
			tube._terminate_session()
		remove_child(tube)
		tube.free()
	tube = TubeClient.new()
	tube.name = "TubeClient"
	if not _cfg.is_empty():
		tube.context = _build_context(_cfg)
		tube.peer_signaling_timeout = _cfg.signaling_timeout
		tube.peer_signaling_max_attempts = int(_cfg.signaling_attempts)
	add_child(tube)
	tube.session_created.connect(_on_session_ready)
	tube.session_joined.connect(_on_session_ready)
	tube.session_left.connect(_on_session_left)
	tube.error_raised.connect(_on_error)


func host() -> void:
	if tube.context == null:
		session_failed.emit("Network config missing or invalid: %s" % CONFIG_PATH)
		return
	_unstick()
	tube.create_session()
	_watch(_attempt, HOST_WAIT_S, true)


# Singleplayer (D-063): Godot's offline peer (this game is the server, id 1, nobody can connect) and no Tube session.
func start_offline() -> void:
	_unstick()
	_started = true
	get_tree().get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	session_started.emit.call_deferred()


# Leave the session (host: ends it for everyone; offline: just drops the offline peer). Main reloads afterwards.
func leave() -> void:
	_attempt += 1
	_started = false
	_leaving = true
	if tube.state != TubeClient.State.IDLE:
		tube.leave_session()
	_leaving = false
	get_tree().get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	_set_lobby_code("")


# Back to a fresh start screen (Save & Quit, D-068; every failure / end, D-091): leave, make a new TubeClient, then
# swap Main for a fresh copy, which shows `message`. Done here because Main (and the pause menu calling this) is
# freed on the way. Call deferred.
func leave_to_menu(main: Node, message := "") -> void:
	if not is_instance_valid(main):
		return
	menu_message = message
	leave()
	var parent := main.get_parent()
	var path := main.scene_file_path
	var was_current := get_tree().current_scene == main
	main.free()
	_new_tube()
	var fresh := (load(path) as PackedScene).instantiate()
	parent.add_child(fresh)
	if was_current:
		get_tree().current_scene = fresh


func join(code: String) -> void:
	code = code.strip_edges().to_upper()
	if code.length() != CODE_LENGTH:
		session_failed.emit("Lobby codes are %d characters" % CODE_LENGTH)
		return
	if tube.context == null:
		session_failed.emit("Network config missing or invalid: %s" % CONFIG_PATH)
		return
	_unstick()
	tube.join_session(code)
	_watch(_attempt, JOIN_WAIT_S, false)


# A new attempt: cancel the old one's timeout and drop anything it left half-open.
func _unstick() -> void:
	_attempt += 1
	_started = false
	if tube.state != TubeClient.State.IDLE:
		tube._terminate_session()


func _watch(attempt: int, seconds: float, hosting: bool) -> void:
	await get_tree().create_timer(seconds).timeout
	if attempt != _attempt or _started:
		return
	if hosting:
		if tube.state == TubeClient.State.CREATING_SESSION:
			push_warning("Net: no tracker answered in %.0f s; lobby open on LAN, online trackers keep trying" % seconds)
			_on_session_ready()
	else:
		tube._terminate_session()
		session_failed.emit("No answer from lobby %s after %.0f s. %s" % [tube.session_id, seconds, JOIN_HELP])


func _build_context(cfg: Dictionary) -> TubeContext:
	var ctx := TubeContext.new()
	ctx.app_id = cfg.app_id
	ctx.session_id_characters_set = cfg.session_code_characters
	ctx.trackers_urls.assign(cfg.trackers)
	ctx.stun_servers_urls.assign(cfg.stun_servers)
	ctx.turn_servers.assign(cfg.turn_servers)
	return ctx


func _on_session_ready() -> void:
	if _started:
		return  # the host-wait timeout already started it; a tracker answering later only adds online joining
	_started = true
	_set_lobby_code(tube.session_id)
	session_started.emit()


func _on_session_left() -> void:
	if _leaving:
		return  # our own leave(); the caller already handles the menu
	_started = false
	_set_lobby_code("")
	session_ended.emit()


func _on_error(code: TubeClient.SessionError, message: String) -> void:
	match code:
		TubeClient.SessionError.CREATE_SESSION_FAILED:
			_attempt += 1
			session_failed.emit("Could not create lobby: %s" % message)
		TubeClient.SessionError.JOIN_SESSION_FAILED:
			_attempt += 1
			session_failed.emit("Could not join: %s. %s" % [message, JOIN_HELP])
		TubeClient.SessionError.ONLINE_SIGNALING_FAILED, TubeClient.SessionError.SIGNALING_FAILED:
			push_warning("Net: %s. Current players stay connected; new players may not be able to join." % message)
			# Tube never emits session_created if every tracker fails while creating, even though
			# same-LAN joining still works. Start the session anyway so the host isn't stuck.
			if tube.state == TubeClient.State.CREATING_SESSION and tube.is_server:
				_on_session_ready()


func _set_lobby_code(code: String) -> void:
	lobby_code = code
	lobby_code_changed.emit(code)
