# CopyBuild — one-run tool (run this scene directly): copies the newest build/<version>/windows folder (the exported
# BonksBunker.exe + .pck + .dll) to DEST, so there's a playable copy outside the project folder. Overwrites what is
# already in the destination folder; makes the folders it needs. Log: tests/_look/copy_build.txt.
# Depends on: a finished export under build/ (tools/release/release.tscn writes it).
extends Node

const DEST := "C:/Users/Fishb/BonksAlpha"

var _log := PackedStringArray()


func _ready() -> void:
	var builds := DirAccess.get_directories_at("res://build")
	builds.sort()
	var version := builds[builds.size() - 1] if builds.size() > 0 else ""
	var from := ProjectSettings.globalize_path("res://build/%s/windows" % version)
	var to := "%s/%s" % [DEST, version]
	if version == "" or not DirAccess.dir_exists_absolute(from):
		_say("no windows build under build/ (newest: '%s')" % version)
		return _done()
	DirAccess.make_dir_recursive_absolute(to)
	var src := DirAccess.open(from)
	for file in src.get_files():
		var t0 := Time.get_ticks_msec()
		var err := DirAccess.copy_absolute(from + "/" + file, to + "/" + file)
		var mb := FileAccess.open(to + "/" + file, FileAccess.READ).get_length() / 1048576.0 if err == OK else 0.0
		_say("%s: err %d, %.0f MB in %.0f s" % [file, err, mb, (Time.get_ticks_msec() - t0) / 1000.0])
	_say("copied %s -> %s" % [version, to])
	_done()


func _say(s: String) -> void:
	print("COPY: " + s)
	_log.append(s)


func _done() -> void:
	DirAccess.make_dir_recursive_absolute("res://tests/_look")
	var f := FileAccess.open("res://tests/_look/copy_build.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	get_tree().quit()
