# ExportSafetyTest — catches the one bug the editor can never see: runtime code using something the EXPORT does
# not ship. export_presets.cfg excludes tests/*, tools/*, server/*, data/map/source/* and diary/*, so a global
# class declared in one of those folders exists in the editor and is MISSING in the packaged game - the script
# that uses it fails to compile, and everything that depends on it goes down with it. That is what broke
# alpha3.1 (EncounterSite used CarMesh, which lived in tools/map_import).
# This walks every shipped script and scene and fails if it names a class, preloads a path or loads a path that
# the export leaves out. Run it before any release.
# Results: tests/_look/export_safety_result.txt (ends with the failure count).
# Depends on: export_presets.cfg (it reads the real exclude_filter, so the check follows the preset).
extends Node

const OUT := "res://tests/_look/export_safety_result.txt"
const SHIPPED := ["res://scripts", "res://scenes", "res://shaders", "res://addons"]

var _log := PackedStringArray()
var _fails := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/_look"))
	var excluded := _excluded_dirs()
	_log.append("export excludes: %s" % ", ".join(excluded))
	_check(not excluded.is_empty(), "export_presets.cfg has an exclude_filter to check against")

	# every global class declared in a folder the export leaves out
	var risky: Dictionary = {}  # class name -> the file that declares it
	for dir: String in excluded:
		for path: String in _scripts_under("res://" + dir):
			var name := _class_name_in(path)
			if name != "":
				risky[name] = path
	_log.append("classes the export leaves out: %d" % risky.size())
	for name: String in risky:
		_log.append("    %-22s %s" % [name, risky[name]])

	# and every shipped file that names one, or reaches into an excluded folder by path
	var used := 0
	for root: String in SHIPPED:
		for path: String in _scripts_under(root) + _files_under(root, ".tscn"):
			var text := FileAccess.get_file_as_string(path)
			if text == "":
				continue
			for name: String in risky:
				if _names(text, name):
					_check(false, "%s uses %s, which the export leaves out (%s)" % [path, name, risky[name]])
					used += 1
			for dir: String in excluded:
				if text.contains('res://' + dir + '/'):
					_check(false, "%s loads a path under %s/, which the export leaves out" % [path, dir])
					used += 1
	_check(used == 0, "nothing the game ships reaches into a folder the export leaves out")
	_log.append("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	print("EXPORT SAFETY: %d failure(s)" % _fails)
	get_tree().quit()


func _check(ok: bool, what: String) -> void:
	_log.append("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1


# The top-level folders the export preset throws away ("tools/*" -> "tools").
func _excluded_dirs() -> PackedStringArray:
	var out := PackedStringArray()
	for line: String in FileAccess.get_file_as_string("res://export_presets.cfg").split("\n"):
		if not line.begins_with("exclude_filter="):
			continue
		for part: String in line.split("=", true, 1)[1].replace("\"", "").split(","):
			var dir := part.strip_edges().trim_suffix("*").trim_suffix("/")
			if dir != "" and not dir.contains("*") and DirAccess.dir_exists_absolute("res://" + dir) \
					and not out.has(dir):
				out.append(dir)
		break
	return out


func _scripts_under(root: String) -> PackedStringArray:
	return _files_under(root, ".gd")


func _files_under(root: String, suffix: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for f: String in dir.get_files():
		if f.ends_with(suffix):
			out.append(root + "/" + f)
	for sub: String in dir.get_directories():
		out.append_array(_files_under(root + "/" + sub, suffix))
	return out


func _class_name_in(path: String) -> String:
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("class_name "):
			return line.substr(11).strip_edges().split(" ")[0]
	return ""


# True if `text` uses `name` as an identifier (not inside a longer word and not in a comment-only mention).
func _names(text: String, name: String) -> bool:
	for line: String in text.split("\n"):
		var code := line.split("#")[0]
		var at := code.find(name)
		while at >= 0:
			var before := code[at - 1] if at > 0 else " "
			var after_at := at + name.length()
			var after := code[after_at] if after_at < code.length() else " "
			if not _wordish(before) and not _wordish(after):
				return true
			at = code.find(name, at + 1)
	return false


func _wordish(c: String) -> bool:
	return c == "_" or (c.to_lower() != c.to_upper()) or (c >= "0" and c <= "9")
