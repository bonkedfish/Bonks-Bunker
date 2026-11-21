# CrashLog — one-run tool (run this scene directly): copies the game's own logs out of user://logs into
# tests/_look/crash_log.txt, newest first, so a crash in an exported build can be read from the project folder.
# Also lists what is in user:// (saves, settings) with sizes and dates. Reads only; changes nothing.
# Log: tests/_look/crash_log.txt. Depends on: nothing.
extends Node

const OUT := "res://tests/_look/crash_log.txt"
const TAIL_LINES := 260
const FILES := 3

var _log := PackedStringArray()


func _ready() -> void:
	_log.append("user:// is %s" % ProjectSettings.globalize_path("user://"))
	for dir: String in ["user://logs", "user://saves", "user://"]:
		var d := DirAccess.open(dir)
		if d == null:
			_log.append("\n--- %s: not there" % dir)
			continue
		var files := Array(d.get_files())
		files.sort()
		_log.append("\n--- %s: %d file(s)" % [dir, files.size()])
		for f: String in files:
			var fa := FileAccess.open(dir + "/" + f, FileAccess.READ)
			var size := fa.get_length() if fa else 0
			_log.append("    %-44s %8d bytes   %s" % [f, size,
				Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(dir + "/" + f))])
	var logs := DirAccess.open("user://logs")
	if logs:
		var files := Array(logs.get_files()).filter(func(f: String) -> bool: return f.ends_with(".log"))
		files.sort()
		files.reverse()
		for i in mini(FILES, files.size()):
			var path: String = "user://logs/" + str(files[i])
			var text := FileAccess.get_file_as_string(path)
			var lines := text.split("\n")
			var from := maxi(0, lines.size() - TAIL_LINES)
			_log.append("\n==================== %s  (last %d of %d lines) ===================="
				% [files[i], lines.size() - from, lines.size()])
			for j in range(from, lines.size()):
				_log.append(str(lines[j]).strip_edges(false, true))
	DirAccess.make_dir_recursive_absolute("res://tests/_look")
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	print("CRASHLOG: wrote ", OUT)
	get_tree().quit()
