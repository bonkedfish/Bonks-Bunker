# QuestRules — pure quest logic (D-054). The whole party shares one set of `flags` { name: int } (1 = set; counters
# count up); everything about quests is derived from them, so saving / syncing quests is just saving / syncing flags.
#   quest:     { name, act, main, summary, start: "auto" | flag, ordered (default true), objectives: [...],
#                reward: { item: n }, locked_note (story outline entries that aren't playable yet) }
#   objective: { text, flag, count (default 1), at: { landmark, offset: [x,y,z] } (map/HUD marker),
#                reach_m (host sets the flag when a living player is within reach_m of `at`),
#                have: { item: n } (host sets the flag when one player carries them) }
# A quest is LOCKED until its start flag is set, ACTIVE until every objective's flag reaches its count, then DONE.
# Requirement lists (dialogue "requires", NPC show/hide): "flag" must be set, "!flag" must not be.
# Pure: no scene or rendering dependencies. Depends on: DataLoader.
class_name QuestRules
extends RefCounted

const PATH := "res://data/quests/quests.json"
enum Status { LOCKED, ACTIVE, DONE }

static var _defs: Dictionary = {}
static var _order: Array = []


static func defs() -> Dictionary:
	if _defs.is_empty():
		var raw: Dictionary = DataLoader.load_json(PATH).get("quests", {})
		for id: String in raw:
			var q: Dictionary = raw[id]
			if not q.has("name") or typeof(q.get("objectives", [])) != TYPE_ARRAY:
				push_error("QuestRules: quest '%s' needs a name and an objectives list" % id)
				continue
			var ok := true
			for o: Dictionary in q.get("objectives", []):
				if not o.has("text") or not o.has("flag"):
					push_error("QuestRules: quest '%s' has an objective without text/flag" % id)
					ok = false
			if ok:
				_defs[id] = q
				_order.append(id)
	return _defs


# Quest IDs in file order (story order).
static func order() -> Array:
	defs()
	return _order


static func flag_met(flags: Dictionary, flag: String, count := 1) -> bool:
	return int(flags.get(flag, 0)) >= count


static func objective_done(o: Dictionary, flags: Dictionary) -> bool:
	return flag_met(flags, str(o.flag), int(o.get("count", 1)))


static func status(q: Dictionary, flags: Dictionary) -> Status:
	var start := str(q.get("start", "auto"))
	if q.has("locked_note") or (start != "auto" and not flag_met(flags, start)):
		return Status.LOCKED
	for o: Dictionary in q.objectives:
		if not objective_done(o, flags):
			return Status.ACTIVE
	return Status.DONE


# Index of the objective to work on now (first unfinished), or -1 if none.
static func current(q: Dictionary, flags: Dictionary) -> int:
	for i in q.objectives.size():
		if not objective_done(q.objectives[i], flags):
			return i
	return -1


# Which objectives the quest book shows: all of them when unordered, else everything up to the current one.
static func visible_count(q: Dictionary, flags: Dictionary) -> int:
	if not bool(q.get("ordered", true)):
		return q.objectives.size()
	var c := current(q, flags)
	return q.objectives.size() if c < 0 else c + 1


# Objectives the host should watch right now (reach / have): [[quest_id, index], ...].
static func watched(flags: Dictionary) -> Array:
	var out: Array = []
	for id: String in order():
		var q: Dictionary = _defs[id]
		if status(q, flags) != Status.ACTIVE:
			continue
		var ordered := bool(q.get("ordered", true))
		for i in q.objectives.size():
			var o: Dictionary = q.objectives[i]
			if objective_done(o, flags):
				continue
			if o.has("reach_m") or o.has("have"):
				out.append([id, i])
			if ordered:
				break
	return out


# The quest to show on the HUD when the player hasn't picked one: first active main quest, else first active.
static func default_tracked(flags: Dictionary) -> String:
	var first := ""
	for id: String in order():
		var q: Dictionary = _defs[id]
		if status(q, flags) == Status.ACTIVE:
			if bool(q.get("main", false)):
				return id
			if first == "":
				first = id
	return first


# requires: "flag" | "!flag" | [..] | null. True when every entry holds.
static func requires_met(requires: Variant, flags: Dictionary) -> bool:
	if requires == null:
		return true
	var list: Array = requires if typeof(requires) == TYPE_ARRAY else [requires]
	for r: String in list:
		if r.begins_with("!"):
			if flag_met(flags, r.substr(1)):
				return false
		elif not flag_met(flags, r):
			return false
	return true
