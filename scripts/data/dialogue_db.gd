# DialogueDB — dialogue data (D-033) from the files in FILES (one per NPC, D-049), merged and validated on load.
#   barks: { context: [line, ...] }            short one-liners, picked at random (NPCs prefix their contexts, e.g. "evan_idle")
#   trees: { tree_id: { start: node_id, nodes: { node_id: { speaker, text, choices: [{text, next}], end } } } }
# Optional: node "flag"/"flags", choice "requires", tree "starts" (quests, D-054); node "give" {item: n}; choice "cost" {item: n} + "cost_fail" node (D-049).
# Every choice's `next` (and cost_fail) must exist; a node with no choices must have "end": true.
# Pure: no scene or rendering dependencies. Depends on: DataLoader.
class_name DialogueDB
extends RefCounted

const FILES := ["res://data/dialogue/bonk.json", "res://data/dialogue/evan.json", "res://data/dialogue/meekachu.json", "res://data/dialogue/school.json",
	"res://data/dialogue/raiders.json"]

static var _data: Dictionary = {}
static var _valid := false


static func barks(context: String) -> Array:
	_ensure_loaded()
	return _data.get("barks", {}).get(context, [])


static func get_dialogue_tree(tree_id: String) -> Dictionary:
	_ensure_loaded()
	if not _valid:
		return {}
	return _data.get("trees", {}).get(tree_id, {})


static func is_valid() -> bool:
	_ensure_loaded()
	return _valid


static func _ensure_loaded() -> void:
	if not _data.is_empty():
		return
	_data = {"barks": {}, "trees": {}}
	var ok := true
	for path: String in FILES:
		var d := DataLoader.load_json(path)
		if typeof(d.get("barks")) != TYPE_DICTIONARY or typeof(d.get("trees")) != TYPE_DICTIONARY:
			push_error("DialogueDB: %s needs 'barks' and 'trees' objects" % path)
			ok = false
			continue
		_data.barks.merge(d.barks)
		_data.trees.merge(d.trees)
	_valid = _validate() and ok


static func _validate() -> bool:
	var ok := true
	for tree_id: String in _data.trees:
		var tree: Variant = _data.trees[tree_id]
		if typeof(tree) != TYPE_DICTIONARY or typeof(tree.get("nodes")) != TYPE_DICTIONARY:
			push_error("DialogueDB: tree '%s' has no nodes" % tree_id)
			ok = false
			continue
		var nodes: Dictionary = tree.nodes
		for s: Dictionary in tree.get("starts", []):
			if not nodes.has(str(s.get("node", ""))):
				push_error("DialogueDB: tree '%s' starts entry points to missing node '%s'" % [tree_id, s.get("node", "")])
				ok = false
		if not nodes.has(str(tree.get("start", ""))):
			push_error("DialogueDB: tree '%s' start node missing" % tree_id)
			ok = false
		for node_id: String in nodes:
			var node: Dictionary = nodes[node_id]
			if not node.has("speaker") or not node.has("text"):
				push_error("DialogueDB: %s/%s needs speaker and text" % [tree_id, node_id])
				ok = false
			var choices: Array = node.get("choices", [])
			if choices.is_empty() and not node.get("end", false):
				push_error("DialogueDB: %s/%s has no choices and isn't an end" % [tree_id, node_id])
				ok = false
			for c: Dictionary in choices:
				if c.has("cost") and not nodes.has(str(c.get("cost_fail", ""))):
					push_error("DialogueDB: %s/%s choice '%s' has a cost but no valid cost_fail" % [tree_id, node_id, c.get("text", "")])
					ok = false
				if not nodes.has(str(c.get("next", ""))):
					push_error("DialogueDB: %s/%s choice '%s' points to missing node '%s'" % [tree_id, node_id, c.get("text", ""), c.get("next", "")])
					ok = false
	return ok
