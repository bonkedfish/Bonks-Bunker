# QuestDirector — the party's shared quest state (D-054), main.tscn node "Quests", group "quests".
# The state is one Dictionary of flags (see QuestRules); the host owns it and sends the whole thing to everyone when
# it changes (and to a peer when it joins). Host: host_set_flag / host_add_count (dialogue nodes, boss deaths, kill
# counters), and twice a second it checks the watched objectives: "reach_m" (a living player near the objective's
# landmark point) and "have" (a player carrying the items). When a quest's objectives are all met the host hands the
# reward to every player, sets "<quest>_done" (which starts the next quests) and announces it; new quests and
# finished objectives are announced as HUD toasts on every peer. Saved as world.quests (flags) by SaveDirector.
# Every peer: `flags` + flags_changed for the quest book, HUD tracker and NPCs; objective_position() for markers.
# Depends on: QuestRules, Players (group "players": inventory, health), Landmarks node, HUD (group "hud").
extends Node

signal flags_changed

const CHECK_SECONDS := 0.5
const TOAST_SECONDS := 5.0

var flags: Dictionary = {}

var _timer := 0.0
var _landmarks: Node


func _ready() -> void:
	add_to_group("quests")
	QuestRules.defs()
	multiplayer.peer_connected.connect(_on_peer_connected)


# --- host --------------------------------------------------------------------------------------

func host_set_flag(flag: String) -> void:
	if flag == "" or not multiplayer.is_server() or QuestRules.flag_met(flags, flag):
		return
	_host_change(flag, 1)


func host_add_count(flag: String, n := 1) -> void:
	if flag != "" and multiplayer.is_server():
		_host_change(flag, int(flags.get(flag, 0)) + n)


func host_save_state() -> Dictionary:
	return flags.duplicate()


func host_load_state(saved: Dictionary) -> void:
	var clean := {}
	for k: String in saved:
		clean[k] = int(saved[k])
	flags = clean
	_host_settle(flags.duplicate(), false)
	_sync.rpc(flags)


func _host_change(flag: String, value: int) -> void:
	var before := flags.duplicate()
	flags[flag] = value
	_host_settle(before, true)
	_sync.rpc(flags)


# Completes quests whose objectives are all met (rewards once), repeating until nothing changes, and announces
# what became active / moved on / finished compared with `before`.
func _host_settle(before: Dictionary, announce: bool) -> void:
	var defs := QuestRules.defs()
	var changed := true
	while changed:
		changed = false
		for id: String in QuestRules.order():
			var q: Dictionary = defs[id]
			if QuestRules.status(q, flags) == QuestRules.Status.DONE and not QuestRules.flag_met(flags, id + "_done"):
				flags[id + "_done"] = 1
				changed = true
				var reward: Dictionary = q.get("reward", {})
				for p in get_tree().get_nodes_in_group("players"):
					if p.peer_id > 0:
						for item: String in reward:
							p.inventory.host_add(item, int(reward[item]))
	if not announce:
		return
	for id: String in QuestRules.order():
		var q: Dictionary = defs[id]
		var was := QuestRules.status(q, before)
		var now := QuestRules.status(q, flags)
		if now == QuestRules.Status.DONE and was != QuestRules.Status.DONE:
			_announce.rpc("QUEST COMPLETE:  %s" % q.name)
		elif now == QuestRules.Status.ACTIVE and was == QuestRules.Status.LOCKED:
			_announce.rpc("NEW QUEST:  %s   (J = quest book)" % q.name)
		elif now == QuestRules.Status.ACTIVE and QuestRules.current(q, flags) != QuestRules.current(q, before):
			_announce.rpc("%s:  %s" % [q.name, q.objectives[QuestRules.current(q, flags)].text])


func _physics_process(delta: float) -> void:
	if not (multiplayer.has_multiplayer_peer() and multiplayer.is_server()):
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_SECONDS
	var defs := QuestRules.defs()
	for w: Array in QuestRules.watched(flags):
		var o: Dictionary = defs[w[0]].objectives[w[1]]
		for p in get_tree().get_nodes_in_group("players"):
			if p.peer_id <= 0 or p.health.is_dead():
				continue
			if o.has("reach_m"):
				var at := objective_position(o)
				if at != Vector3.INF and p.global_position.distance_to(at) <= float(o.reach_m):
					host_set_flag(str(o.flag))
					break
			elif o.has("have"):
				var has_all := true
				for item: String in o.have:
					has_all = has_all and p.inventory.count(item) >= int(o.have[item])
				if has_all:
					host_set_flag(str(o.flag))
					break


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		_sync.rpc_id(id, flags)


# --- everyone ----------------------------------------------------------------------------------

# World position of an objective's "at" (landmark origin + offset), or Vector3.INF if it has none.
func objective_position(o: Dictionary) -> Vector3:
	if not o.has("at"):
		return Vector3.INF
	if _landmarks == null:
		_landmarks = get_node_or_null("../Landmarks")
	var lm: Node3D = _landmarks.get_node_or_null(str(o.at.landmark)) if _landmarks else null
	if lm == null:
		return Vector3.INF
	var off: Array = o.at.get("offset", [0, 0, 0])
	return lm.global_transform * Vector3(off[0], off[1], off[2])


@rpc("authority", "call_local", "reliable")
func _sync(new_flags: Dictionary) -> void:
	flags = new_flags
	flags_changed.emit()


@rpc("authority", "call_local", "reliable")
func _announce(text: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_toast(text, TOAST_SECONDS)
