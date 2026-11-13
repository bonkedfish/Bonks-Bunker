# DialogueDirector — host-run conversations with any talkable NPC (D-034; generalised for Evan, D-049), plus barks.
# A player presses E on an NPC (group "talkable") → request_talk(npc_path) (host checks alive, in range, NPC up,
# nobody else talking). The NPC supplies display_name, dialogue_tree and def (talk_range, subtitle_range); NPCs
# without a `health` child (Evan) are never "down". The host walks the JSON tree (DialogueDB) and broadcasts each
# line, the chooser's last reply and the choice texts; only the talker gets clickable choices, everyone within the
# NPC's subtitle_range sees subtitles. Trades/gifts (D-049): a node's "give" {item: n} is handed to the talker the
# first time they reach it this session (every time with "give_every_time", for trades); a choice's "cost" {item: n} is taken from the talker, or the choice goes
# to "cost_fail" if they can't pay. Quests (D-054): a node's "flag" / "flags" are set on the party's QuestDirector
# when reached; a choice with "requires" (flag / "!flag" list) is only offered when it holds; a tree's "starts"
# [{requires, node}] picks a different opening node by flags. The conversation ends on an "end" node, if the talker leaves (Esc), walks
# off, goes down, or the NPC goes down.
# Group "dialogue". Depends on: DialogueDB, QuestRules, QuestDirector (group "quests"), talkable NPCs, Player inventory (InventoryHolder), SubtitleUI (group "subtitles").
extends Node

var _talker := 0
var _tree: Dictionary = {}
var _node_id := ""
var _npc: Node
var _given: Dictionary = {}  # host: "peer/tree/node" -> true
var _ui: Node
var _quests: Node


func _ready() -> void:
	add_to_group("dialogue")
	_ui = get_tree().get_first_node_in_group("subtitles")
	_quests = get_tree().get_first_node_in_group("quests")


# --- requests (any peer -> host) -------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func request_talk(npc_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var npc := get_node_or_null(npc_path)
	if npc == null or not npc.is_in_group("talkable"):
		return
	var peer := _sender()
	var player := _player(peer)
	if player == null or player.health.is_dead() or _is_down(npc):
		return
	if player.global_position.distance_to(npc.global_position) > _talk_range(npc):
		return
	if _talker != 0:
		if _talker != peer:
			npc.bark("busy")
		return
	_tree = DialogueDB.get_dialogue_tree(str(npc.dialogue_tree))
	if _tree.is_empty():
		return
	_npc = npc
	_talker = peer
	_node_id = str(_tree.start)
	for s: Dictionary in _tree.get("starts", []):
		if QuestRules.requires_met(s.get("requires"), _flags()):
			_node_id = str(s.node)
			break
	_send_node("")


@rpc("any_peer", "call_local", "reliable")
func request_choice(index: int) -> void:
	if not multiplayer.is_server() or _talker == 0 or _sender() != _talker:
		return
	var choices := _choices()
	if index < 0 or index >= choices.size():
		return
	var c: Dictionary = choices[index]
	_node_id = str(c.next)
	if c.has("cost"):
		var inv: InventoryHolder = _player(_talker).inventory
		var can_pay := true
		for id: String in c.cost:
			can_pay = can_pay and inv.count(id) >= int(c.cost[id])
		if can_pay:
			for id: String in c.cost:
				inv.host_remove(id, int(c.cost[id]))
		else:
			_node_id = str(c.cost_fail)
	_send_node(str(c.text))


@rpc("any_peer", "call_local", "reliable")
func request_leave() -> void:
	if multiplayer.is_server() and _talker != 0 and _sender() == _talker:
		_end()


# --- host ----------------------------------------------------------------------

func host_bark(npc: Node3D, text: String) -> void:
	_show_bark.rpc(str(npc.display_name), text, npc.global_position, _subtitle_range(npc))


func _physics_process(_delta: float) -> void:
	if _talker == 0 or not multiplayer.is_server():
		return
	var player := _player(_talker)
	if player == null or player.health.is_dead() or not is_instance_valid(_npc) or _is_down(_npc) \
			or player.global_position.distance_to(_npc.global_position) > _talk_range(_npc) * 2.5:
		_end()


func _send_node(reply: String) -> void:
	var node: Dictionary = _tree.nodes[_node_id]
	if node.has("give"):
		var key := "%d/%s/%s" % [_talker, _npc.dialogue_tree, _node_id]
		if node.get("give_every_time", false) or not _given.has(key):
			_given[key] = true
			var inv: InventoryHolder = _player(_talker).inventory
			for id: String in node.give:
				inv.host_add(id, int(node.give[id]))
	if _quests:
		if node.has("flag"):
			_quests.host_set_flag(str(node.flag))
		for f: String in node.get("flags", []):
			_quests.host_set_flag(f)
	var texts := PackedStringArray()
	for c: Dictionary in _choices():
		texts.append(str(c.text))
	var talker := _talker
	if node.get("end", false) or texts.is_empty():
		_talker = 0
	_show_line.rpc(str(node.speaker), str(node.text), reply, texts, talker, _npc.global_position, _subtitle_range(_npc))


func _end() -> void:
	_talker = 0
	_show_end.rpc()


func _flags() -> Dictionary:
	return _quests.flags if _quests else {}


# The current node's choices that the party's flags allow.
func _choices() -> Array:
	var out: Array = []
	for c: Dictionary in _tree.nodes[_node_id].get("choices", []):
		if QuestRules.requires_met(c.get("requires"), _flags()):
			out.append(c)
	return out


func _is_down(npc: Node) -> bool:
	return "health" in npc and npc.health.is_dead()


func _talk_range(npc: Node) -> float:
	return float(npc.def.get("talk_range", 3.0))


func _subtitle_range(npc: Node) -> float:
	return float(npc.def.get("subtitle_range", 25.0))


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()


func _player(peer: int) -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == peer:
			return p
	return null


# --- host -> everyone ----------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _show_line(speaker: String, text: String, reply: String, choices: PackedStringArray, talker: int,
		at: Vector3, heard_m: float) -> void:
	if _ui:
		_ui.show_line(speaker, text, reply, choices, talker, at, heard_m)


@rpc("authority", "call_local", "reliable")
func _show_end() -> void:
	if _ui:
		_ui.end_conversation()


@rpc("authority", "call_local", "reliable")
func _show_bark(speaker: String, text: String, at: Vector3, heard_m: float) -> void:
	if _ui:
		_ui.show_bark(speaker, text, at, heard_m)
