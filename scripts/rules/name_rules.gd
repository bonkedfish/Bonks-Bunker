# NameRules — cleans a player's typed character name (D-081): printable characters only, runs of spaces collapsed,
# trimmed, cut to max_length. "" means not a usable name. Pure: no nodes.
extends RefCounted


static func clean(raw: String, max_length: int) -> String:
	var out := ""
	var space := false
	for ch in raw:
		var c := ch.unicode_at(0)
		if c < 32 or c == 127:
			continue
		if ch == " ":
			space = out != ""
			continue
		if space:
			out += " "
			space = false
		out += ch
	return out.substr(0, max_length).strip_edges()
