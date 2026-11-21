# SmokeExe — one-run tool (run this scene directly): launches the newest exported build/<version>/windows exe for
# 600 frames and reads its output, so a packaged build can be checked without publishing anything. Fails loudly
# on script or load errors, which a plain exit code hides (that is how alpha3.1 shipped unplayable).
# Log: tests/_look/smoke_exe.txt. Depends on: a finished Windows export under build/.
extends Node

const NEEDLES := ["SCRIPT ERROR", "Parse Error", "Compile Error", "Failed to load script", "Failed to instantiate"]

var _log := PackedStringArray()


func _ready() -> void:
	var builds := DirAccess.get_directories_at("res://build")
	builds.sort()
	var version := builds[builds.size() - 1] if builds.size() > 0 else ""
	var exe := ProjectSettings.globalize_path("res://build/%s/windows" % version)
	var found := ""
	var dir := DirAccess.open(exe)
	if dir:
		for f: String in dir.get_files():
			if f.ends_with(".exe"):
				found = exe + "/" + f
	if found == "":
		_say("no exported .exe under build/%s/windows" % version)
		return _done()
	_say("running %s" % found)
	var out := []
	var t0 := Time.get_ticks_msec()
	var code := OS.execute(found, ["--quit-after", "600"], out, true)
	var text := "\n".join(PackedStringArray(out))
	_say("exit %d after %.0f s" % [code, (Time.get_ticks_msec() - t0) / 1000.0])
	var bad := PackedStringArray()
	for needle: String in NEEDLES:
		if text.contains(needle) and not bad.has(needle):
			bad.append(needle)
	if bad.is_empty():
		_say("CLEAN: no script or load errors in the packaged build")
	else:
		_say("BROKEN: " + ", ".join(bad))
		for line: String in text.split("\n"):
			if line.contains("ERROR") or line.contains("Error"):
				_say("    " + line.strip_edges())
	_done()


func _say(s: String) -> void:
	print("SMOKE: " + s)
	_log.append(s)


func _done() -> void:
	DirAccess.make_dir_recursive_absolute("res://tests/_look")
	var f := FileAccess.open("res://tests/_look/smoke_exe.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	get_tree().quit()
