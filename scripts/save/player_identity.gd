# PlayerIdentity — a random ID made once per game install (user://player_id.txt). Clients send it when
# they join so the host's save can give them back their character (D-037). It identifies, it doesn't
# authenticate: the host only uses it to pick which saved character to load.
# No nodes.
class_name PlayerIdentity
extends RefCounted

const PATH := "user://player_id.txt"

static var _uid := ""


static func uid() -> String:
	if _uid != "":
		return _uid
	var saved := FileAccess.get_file_as_string(PATH).strip_edges() if FileAccess.file_exists(PATH) else ""
	if is_valid(saved):
		_uid = saved
		return _uid
	_uid = Crypto.new().generate_random_bytes(16).hex_encode()
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(_uid)
	return _uid


# 32 lowercase hex characters.
static func is_valid(value: String) -> bool:
	if value.length() != 32:
		return false
	for ch in value:
		if not ((ch >= "0" and ch <= "9") or (ch >= "a" and ch <= "f")):
			return false
	return true
