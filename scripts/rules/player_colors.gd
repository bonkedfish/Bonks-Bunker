# PlayerColors — which colour marks which player (D-092): the host picks the first free index from
# data/tuning/player_colors.json when a player spawns (Player.net_color, replicated), and every map / scorecard
# draws that player in color(index). Pure: no nodes.
class_name PlayerColors
extends RefCounted

const DATA_PATH := "res://data/tuning/player_colors.json"

static var _colors: Array[Color] = []


static func color(index: int) -> Color:
	_load()
	return _colors[posmod(index, _colors.size())] if not _colors.is_empty() else Color.WHITE


# First index not in `used` (wraps around once all are taken).
static func pick(used: Array) -> int:
	_load()
	for i in _colors.size():
		if not used.has(i):
			return i
	return used.size() % maxi(_colors.size(), 1)


static func _load() -> void:
	if not _colors.is_empty():
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if d is Dictionary:
		for c: Array in (d as Dictionary).get("colors", []):
			_colors.append(Color(float(c[0]), float(c[1]), float(c[2])))
