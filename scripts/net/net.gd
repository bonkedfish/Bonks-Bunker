# Net — owns the multiplayer session through the Tube addon (WebRTC, no server to host, no port forwarding).
#   Host:   create a session -> gets a 5-character lobby code to share.
#   Client: join with that code. Tube finds the host via public WebTorrent trackers (online) or
#           UDP broadcast (same LAN), then opens a direct WebRTC connection (STUN for NAT traversal).
# Tube installs its own MultiplayerAPI on the scene tree root when its TubeClient enters the tree,
# so this autoload adds it in _ready(), before any game scene connects to `multiplayer` signals.
# Star topology: host = peer 1, clients talk only to the host (fits host-authoritative D-002).
# Requires: addons/tube, addons/webrtc_native.
# Depends on: DataLoader, data/net/network.json. Used by: main.gd (autoload "Net").
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

var lobby_code := ""
var tube: TubeClient


func _ready() -> void:
	tube = TubeClient.new()
	tube.name = "TubeClient"
	var cfg := DataLoader.load_validated(CONFIG_PATH, CONFIG_SCHEMA)
	if not cfg.is_empty():
		tube.context = _build_context(cfg)
		tube.peer_signaling_timeout = cfg.signaling_timeout
		tube.peer_signaling_max_attempts = int(cfg.signaling_attempts)
	add_child(tube)
	tube.session_created.connect(_on_session_ready)
	tube.session_joined.connect(_on_session_ready)
	tube.session_left.connect(_on_session_left)
	tube.error_raised.connect(_on_error)


func host() -> void:
	if tube.state != TubeClient.State.IDLE:
		return  # already creating/in a session (e.g. double-clicked Host)
	if tube.context == null:
		session_failed.emit("Network config missing or invalid: %s" % CONFIG_PATH)
		return
	tube.create_session()


# Singleplayer (D-063): Godot's offline peer (this game is the server, id 1, nobody can connect) and no Tube session.
func start_offline() -> void:
	if tube.state != TubeClient.State.IDLE:
		return
	get_tree().get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	session_started.emit.call_deferred()


# Leave the session (host: ends it for everyone; offline: just drops the offline peer). Main reloads afterwards.
func leave() -> void:
	if tube.state != TubeClient.State.IDLE:
		tube.leave_session()
	get_tree().get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	_set_lobby_code("")


# Save & Quit (D-068): leave, then swap Main for a fresh copy (start screen, empty world). Done here because Main
# (and the pause menu calling this) is freed on the way. Call deferred.
func leave_to_menu(main: Node) -> void:
	leave()
	var parent := main.get_parent()
	var path := main.scene_file_path
	var was_current := get_tree().current_scene == main
	main.free()
	var fresh := (load(path) as PackedScene).instantiate()
	parent.add_child(fresh)
	if was_current:
		get_tree().current_scene = fresh


func join(code: String) -> void:
	if tube.state != TubeClient.State.IDLE:
		return
	code = code.strip_edges().to_upper()
	if code.length() != CODE_LENGTH:
		session_failed.emit("Lobby codes are %d characters" % CODE_LENGTH)
		return
	if tube.context == null:
		session_failed.emit("Network config missing or invalid: %s" % CONFIG_PATH)
		return
	tube.join_session(code)


func _build_context(cfg: Dictionary) -> TubeContext:
	var ctx := TubeContext.new()
	ctx.app_id = cfg.app_id
	ctx.session_id_characters_set = cfg.session_code_characters
	ctx.trackers_urls.assign(cfg.trackers)
	ctx.stun_servers_urls.assign(cfg.stun_servers)
	ctx.turn_servers.assign(cfg.turn_servers)
	return ctx


func _on_session_ready() -> void:
	_set_lobby_code(tube.session_id)
	session_started.emit()


func _on_session_left() -> void:
	_set_lobby_code("")
	session_ended.emit()


func _on_error(code: TubeClient.SessionError, message: String) -> void:
	match code:
		TubeClient.SessionError.CREATE_SESSION_FAILED:
			session_failed.emit("Could not create lobby: %s" % message)
		TubeClient.SessionError.JOIN_SESSION_FAILED:
			session_failed.emit("Could not join (wrong code, host offline, or a network that blocks direct connections): %s" % message)
		TubeClient.SessionError.ONLINE_SIGNALING_FAILED, TubeClient.SessionError.SIGNALING_FAILED:
			push_warning("Net: %s. Current players stay connected; new players may not be able to join." % message)
			# Tube never emits session_created if every tracker fails while creating, even though
			# same-LAN joining still works. Start the session anyway so the host isn't stuck.
			if tube.state == TubeClient.State.CREATING_SESSION and tube.is_server:
				_on_session_ready()


func _set_lobby_code(code: String) -> void:
	lobby_code = code
	lobby_code_changed.emit(code)
