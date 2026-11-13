# SignalingServer — tiny WebSocket lobby server for WebRTC co-op.
# Hands out 5-letter lobby codes, assigns peer IDs (host = 1, clients 2..6), and relays offers,
# answers and ICE candidates between a host and its clients. Never carries game traffic.
# Star topology: a client may only message the host; the host may message any member of its lobby.
# Run: godot --headless --path <project> -- --signaling-server
#      (in the editor: a Run Instance with launch argument "-- --signaling-server")
# Depends on: DataLoader, Net (for CONFIG_PATH / CONFIG_SCHEMA), data/net/network.json.
extends Node

const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 5
const MAX_PLAYERS := 6
const MAX_MESSAGE_BYTES := 16384


class Conn:
	var ws := WebSocketPeer.new()
	var lobby := ""
	var peer_id := 0


class Lobby:
	var members := {}  # peer_id -> Conn (host is 1)
	var next_id := 2


var _tcp := TCPServer.new()
var _conns: Array[Conn] = []
var _lobbies := {}  # code -> Lobby


func _ready() -> void:
	var cfg := DataLoader.load_validated(Net.CONFIG_PATH, Net.CONFIG_SCHEMA)
	var port := int(cfg.get("signaling_port", 9080))
	if _tcp.listen(port) != OK:
		push_error("Signaling server: could not listen on port %d" % port)
		get_tree().quit(1)
		return
	print("Signaling server listening on port %d" % port)


func _process(_delta: float) -> void:
	while _tcp.is_connection_available():
		var c := Conn.new()
		c.ws.accept_stream(_tcp.take_connection())
		_conns.append(c)
	for i in range(_conns.size() - 1, -1, -1):
		var c := _conns[i]
		c.ws.poll()
		var state := c.ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			while c.ws.get_available_packet_count() > 0:
				_handle(c, c.ws.get_packet())
		elif state == WebSocketPeer.STATE_CLOSED:
			_drop(c)
			_conns.remove_at(i)


func _handle(c: Conn, bytes: PackedByteArray) -> void:
	if bytes.size() > MAX_MESSAGE_BYTES:
		return
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var msg: Dictionary = parsed
	match str(msg.get("type", "")):
		"host":
			if c.lobby != "":
				return
			var code := _new_code()
			var lobby := Lobby.new()
			lobby.members[1] = c
			_lobbies[code] = lobby
			c.lobby = code
			c.peer_id = 1
			_send(c, {"type": "hosted", "code": code})
			print("Lobby %s opened" % code)
		"join":
			if c.lobby != "":
				return
			var code := str(msg.get("code", "")).to_upper()
			if not _lobbies.has(code):
				_send(c, {"type": "error", "message": "No lobby with code %s" % code})
				return
			var lobby: Lobby = _lobbies[code]
			if lobby.members.size() >= MAX_PLAYERS:
				_send(c, {"type": "error", "message": "Lobby %s is full" % code})
				return
			var id := lobby.next_id
			lobby.next_id += 1
			lobby.members[id] = c
			c.lobby = code
			c.peer_id = id
			_send(c, {"type": "joined", "id": id})
			_send(lobby.members[1], {"type": "peer_joined", "id": id})
			print("Lobby %s: peer %d joined" % [code, id])
		"offer", "answer", "candidate":
			_relay(c, msg)


func _relay(c: Conn, msg: Dictionary) -> void:
	if not _lobbies.has(c.lobby):
		return
	var lobby: Lobby = _lobbies[c.lobby]
	var to := int(msg.get("to", 0))
	if to == c.peer_id or not lobby.members.has(to) or (c.peer_id != 1 and to != 1):
		return
	var out := {"type": msg.type, "from": c.peer_id, "sdp": str(msg.get("sdp", ""))}
	if msg.type == "candidate":
		out.mid = str(msg.get("mid", ""))
		out.index = int(msg.get("index", 0))
	_send(lobby.members[to], out)


func _drop(c: Conn) -> void:
	if not _lobbies.has(c.lobby):
		return
	var lobby: Lobby = _lobbies[c.lobby]
	if c.peer_id == 1:
		for id: int in lobby.members:
			if id != 1:
				_send(lobby.members[id], {"type": "lobby_closed"})
		_lobbies.erase(c.lobby)
		print("Lobby %s closed" % c.lobby)
	else:
		lobby.members.erase(c.peer_id)
		_send(lobby.members[1], {"type": "peer_left", "id": c.peer_id})


func _new_code() -> String:
	var code := ""
	while code == "" or _lobbies.has(code):
		code = ""
		for i in CODE_LENGTH:
			code += CODE_CHARS[randi() % CODE_CHARS.length()]
	return code


func _send(c: Conn, msg: Dictionary) -> void:
	if c.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		c.ws.send_text(JSON.stringify(msg))
