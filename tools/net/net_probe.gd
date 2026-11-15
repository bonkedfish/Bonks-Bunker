# NetProbe — one-run diagnostic (run this scene directly): how well this PC can reach the online lobby system.
#   1. Opens a WebSocket to every WebTorrent tracker in data/net/network.json plus a few known public ones, and
#      logs which open and how fast (the lobby code only works through trackers that answer).
#   2. Gathers WebRTC ICE candidates through the STUN servers and logs their types. Two server-reflexive
#      candidates with different ports = a symmetric NAT, which can't connect peer-to-peer without a TURN relay.
#   Logs counts and timings only, never addresses. Log: tests/_look/net_probe.txt.
# Depends on: data/net/network.json, addons/webrtc_native.
extends Node

const EXTRA_TRACKERS := ["wss://tracker.openwebtorrent.com", "wss://tracker.webtorrent.dev",
	"wss://tracker.novage.com.ua:443/announce", "wss://tracker.files.fm:7073/announce",
	"wss://tracker.ghostchu-services.top:443/announce", "wss://tracker.btorrent.xyz"]
const WAIT_S := 12.0

var _log := PackedStringArray()


func _ready() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/net/network.json"))
	var urls: Array = (cfg.trackers as Array).duplicate()
	for u in EXTRA_TRACKERS:
		if not urls.has(u):
			urls.append(u)
	await _trackers(urls, cfg.trackers)
	await _stun(cfg.stun_servers)
	DirAccess.make_dir_recursive_absolute("res://tests/_look")
	var f := FileAccess.open("res://tests/_look/net_probe.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	get_tree().quit()


func _trackers(urls: Array, configured: Array) -> void:
	var socks := {}
	var opened := {}
	var t0 := Time.get_ticks_msec()
	for u in urls:
		var s := WebSocketPeer.new()
		var err := s.connect_to_url(u)
		socks[u] = s if err == OK else null
		if err != OK:
			opened[u] = "connect error %s" % error_string(err)
	while Time.get_ticks_msec() - t0 < WAIT_S * 1000.0 and opened.size() < urls.size():
		await get_tree().process_frame
		for u in urls:
			if opened.has(u) or socks[u] == null:
				continue
			var s: WebSocketPeer = socks[u]
			s.poll()
			match s.get_ready_state():
				WebSocketPeer.STATE_OPEN:
					opened[u] = "OPEN in %d ms" % (Time.get_ticks_msec() - t0)
				WebSocketPeer.STATE_CLOSED:
					opened[u] = "closed after %d ms (code %d)" % [Time.get_ticks_msec() - t0, s.get_close_code()]
	for u in urls:
		_say("tracker %s%s: %s" % [u, " [configured]" if configured.has(u) else "", opened.get(u, "no answer in %d s" % WAIT_S)])
		if socks[u]:
			(socks[u] as WebSocketPeer).close()


func _stun(servers: Array) -> void:
	# One connection with every STUN server on the same local socket: an endpoint-independent NAT maps it to one
	# public port for all of them (one srflx candidate); a symmetric NAT gives each server a different port.
	var pc := WebRTCPeerConnection.new()
	var err := pc.initialize({"iceServers": [{"urls": servers}]})
	if err != OK:
		_say("stun: init error %s" % error_string(err))
		return
	var cands: Array[String] = []
	pc.ice_candidate_created.connect(func(_m: String, _i: int, sdp: String) -> void: cands.append(sdp))
	pc.session_description_created.connect(func(type: String, sdp: String) -> void: pc.set_local_description(type, sdp))
	pc.create_data_channel("probe")
	pc.create_offer()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
		pc.poll()
	var types := {}
	var by_base := {}  # local port -> public ports seen for it
	for c in cands:
		var parts := c.split(" ")
		var i := parts.find("typ")
		if i < 0 or i + 1 >= parts.size():
			continue
		types[parts[i + 1]] = int(types.get(parts[i + 1], 0)) + 1
		var r := parts.find("rport")
		if parts[i + 1] == "srflx" and i >= 2 and r >= 0 and r + 1 < parts.size():
			var base: String = parts[r + 1]
			if not by_base.has(base):
				by_base[base] = {}
			by_base[base][parts[i - 1]] = true
	_say("stun (all %d servers, one socket): candidates %s" % [servers.size(), types])
	var symmetric := false
	for base in by_base:
		_say("  local socket -> %d public port(s)" % (by_base[base] as Dictionary).size())
		if (by_base[base] as Dictionary).size() > 1:
			symmetric = true
	if by_base.is_empty():
		_say("NAT: no server-reflexive candidates - STUN blocked; only a TURN relay could connect this PC")
	elif symmetric:
		_say("NAT: SYMMETRIC - each STUN server saw a different public port; needs a TURN relay to connect reliably")
	else:
		_say("NAT: one public port for every STUN server (endpoint-independent) - peer-to-peer works from this side")
	pc.close()


func _say(s: String) -> void:
	print("NETPROBE: " + s)
	_log.append(s)
