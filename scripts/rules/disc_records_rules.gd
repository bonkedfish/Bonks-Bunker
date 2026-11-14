# DiscRecordsRules — course records for one world (D-082): per player, per course — best full round, best score on
# each hole, and every ace. `rec` = { player_key: {"name": str, "best": int (0 = no full round yet),
# "holes": [best strokes per hole, 0 = not holed yet], "aces": [hole index, ...]} }. hole_done() / round_done()
# return an updated copy; board_text() lays out the records board (top rounds, hole records, aces).
# Pure: no scene or rendering dependencies. Depends on: DiscGolfRules (par_total, hole_label).
class_name DiscRecordsRules
extends RefCounted

const TOP_ROUNDS := 6
const HOLES_PER_LINE := 3


static func _entry(rec: Dictionary, key: String, player_name: String, holes_n: int) -> Dictionary:
	var e: Dictionary = rec.get(key, {}).duplicate(true)
	if e.is_empty():
		e = {"name": player_name, "best": 0, "holes": [], "aces": []}
	if player_name != "":
		e.name = player_name
	var holes: Array = e.holes
	while holes.size() < holes_n:
		holes.append(0)
	return e


# A player holed out on `hole` in `strokes`.
static func hole_done(rec: Dictionary, key: String, player_name: String, hole: int, strokes: int, holes_n: int) -> Dictionary:
	if key == "" or strokes <= 0 or hole < 0 or hole >= holes_n:
		return rec
	var out := rec.duplicate(true)
	var e := _entry(out, key, player_name, holes_n)
	if int(e.holes[hole]) == 0 or strokes < int(e.holes[hole]):
		e.holes[hole] = strokes
	if strokes == 1:
		e.aces.append(hole)
	out[key] = e
	return out


# A player finished a full round in `total`.
static func round_done(rec: Dictionary, key: String, player_name: String, total: int, holes_n: int) -> Dictionary:
	if key == "" or total <= 0:
		return rec
	var out := rec.duplicate(true)
	var e := _entry(out, key, player_name, holes_n)
	if int(e.best) == 0 or total < int(e.best):
		e.best = total
	out[key] = e
	return out


# The board: course name and par, the best rounds, who holds each hole record (ties: first to get it), the aces.
static func board_text(rec: Dictionary, course: Dictionary) -> String:
	var par := DiscGolfRules.par_total(course)
	var lines := PackedStringArray(["COURSE RECORDS", "%s  -  par %d" % [str(course.name), par], ""])
	var rounds: Array = []
	for key: String in rec:
		if int(rec[key].best) > 0:
			rounds.append([int(rec[key].best), str(rec[key].name)])
	rounds.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	lines.append("BEST ROUNDS")
	if rounds.is_empty():
		lines.append("  nobody has finished a round yet")
	for i in mini(rounds.size(), TOP_ROUNDS):
		var total := int(rounds[i][0])
		lines.append("  %d. %s  %d (%s)" % [i + 1, rounds[i][1], total, DiscGolfRules.to_par_text(total, par)])
	lines.append("")
	lines.append("HOLE RECORDS")
	var holes: Array = course.holes
	var row := PackedStringArray()
	for h in holes.size():
		var best := 0
		var who := ""
		for key: String in rec:
			var hs: Array = rec[key].holes
			if h < hs.size() and int(hs[h]) > 0 and (best == 0 or int(hs[h]) < best):
				best = int(hs[h])
				who = str(rec[key].name)
		row.append("%s: %s" % [DiscGolfRules.hole_label(course, h), ("%d %s" % [best, who]) if best > 0 else "-"])
		if row.size() == HOLES_PER_LINE or h == holes.size() - 1:
			lines.append("  " + "    ".join(row))
			row = PackedStringArray()
	lines.append("")
	lines.append("ACES")
	var aces := PackedStringArray()
	for key: String in rec:
		var a: Array = rec[key].aces
		if a.is_empty():
			continue
		var hs := PackedStringArray()
		for h: Variant in a:
			hs.append(DiscGolfRules.hole_label(course, int(h)))
		aces.append("%s: %s" % [str(rec[key].name), ", ".join(hs)])
	lines.append("  " + ("   ".join(aces) if not aces.is_empty() else "none yet"))
	return "\n".join(lines)
