# ExportLocal — one-run tool (run this scene directly): exports the Windows build of the project as it is now into
# DEST/dev-<date> (BonksBunker.exe + .pck), smoke-tests it (600 frames, script / load errors fail it) and checks the
# packaged models (-- --check-models, D-112). Nothing is committed, pushed or published - this is a playable copy for
# this PC (release.tscn makes real releases). Writes outside build/ so copy_build still picks the newest release.
# Log: tests/_look/export_local.txt. Depends on: export_presets.cfg ("Windows Desktop" preset), Godot export
# templates, data/release/release.json (exe_name).
extends Node

const DEST := "C:/Users/Fishb/BonksAlpha"
const NEEDLES := ["SCRIPT ERROR", "Parse Error", "Compile Error", "Failed to load script", "Failed to instantiate",
	"Condition \"!script.is_valid()\""]

var _log := PackedStringArray()


func _ready() -> void:
	await get_tree().process_frame
	var root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var exe_name := str(DataLoader.load_json("res://data/release/release.json").get("exe_name", "BonksBunker"))
	var day := Time.get_date_string_from_system()
	var dir := "%s/dev-%s" % [DEST, day]
	DirAccess.make_dir_recursive_absolute(dir)
	var exe := "%s/%s.exe" % [dir, exe_name]
	var preset := _preset("Windows Desktop")
	if preset == "":
		_say("FAILED: no Windows Desktop preset in export_presets.cfg")
		return _done()
	var t0 := Time.get_ticks_msec()
	var r := _exec(OS.get_executable_path(), ["--headless", "--path", root, "--export-release", preset, exe])
	_say("export: exit %d in %.0f s" % [r.code, (Time.get_ticks_msec() - t0) / 1000.0])
	if r.code != 0 or not FileAccess.file_exists(exe):
		for line: String in r.text.split("\n"):
			if line.contains("ERROR"):
				_say("  " + line.strip_edges())
		_say("FAILED: export")
		return _done()
	var smoke := _exec(exe, ["--quit-after", "600"])
	var bad := PackedStringArray()
	for n: String in NEEDLES:
		if smoke.text.contains(n):
			bad.append(n)
	_say("smoke test: exit %d%s" % [smoke.code, "" if bad.is_empty() else "  BROKEN: " + ", ".join(bad)])
	var models := _exec(exe, ["--headless", "--", "--check-models"])
	var models_ok: bool = models.text.contains("MODELS: OK")
	_say("models inside the build: %s" % ("OK" if models_ok else "NOT OK"))
	for f: String in DirAccess.get_files_at(dir):
		_say("  %s  %.0f MB" % [f, FileAccess.open(dir + "/" + f, FileAccess.READ).get_length() / 1048576.0])
	_say(("READY: " if bad.is_empty() and smoke.code == 0 and models_ok else "PROBLEM: ") + exe)
	_done()


func _preset(platform: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load("res://export_presets.cfg") != OK:
		return ""
	for section in cfg.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options") \
				and str(cfg.get_value(section, "platform", "")) == platform:
			return str(cfg.get_value(section, "name", ""))
	return ""


func _exec(cmd: String, args: Array) -> Dictionary:
	var out := []
	var code := OS.execute(cmd, args, out, true)
	return {"code": code, "text": "\n".join(PackedStringArray(out))}


func _say(s: String) -> void:
	print("EXPORT: " + s)
	_log.append(s)


func _done() -> void:
	DirAccess.make_dir_recursive_absolute("res://tests/_look")
	var f := FileAccess.open("res://tests/_look/export_local.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	get_tree().quit()
