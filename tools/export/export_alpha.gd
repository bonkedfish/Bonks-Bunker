# ExportAlpha — one-click alpha build (run this scene directly). Checks the Windows export templates are installed,
# runs the editor headless with --export-release <the project's Windows preset, whatever it's named in the editor>
# into OUT_DIR (exe + pck + WebRTC DLL), then zips that folder for sending. Log: tests/_look/export_result.txt.
# Depends on: export_presets.cfg.
extends Node

const OUT_DIR := "C:/Users/Fishb/BonksAlpha"
const EXE_NAME := "BonksGame.exe"
const ZIP_PATH := "C:/Users/Fishb/BonksAlpha.zip"
const CHUNK := 16 * 1024 * 1024

var _log := PackedStringArray()


func _ready() -> void:
	await get_tree().process_frame
	var v := Engine.get_version_info()
	var tdir := "%s/Godot/export_templates/%d.%d.%d.%s" % [OS.get_environment("APPDATA").replace("\\", "/"),
		v.major, v.minor, v.patch, v.status]
	var template := tdir + "/windows_release_x86_64.exe"
	if not FileAccess.file_exists(template):
		_say("MISSING export templates: %s not found" % template)
		_done()
		return
	_say("templates ok: " + tdir)
	var preset := _windows_preset()
	if preset == "":
		_say("no Windows Desktop preset in export_presets.cfg")
		_done()
		return
	_say("preset: " + preset)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var t0 := Time.get_ticks_msec()
	var out := []
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--export-release", preset,
		OUT_DIR + "/" + EXE_NAME]
	var code := OS.execute(OS.get_executable_path(), args, out, true)
	_say("export exit %d in %.0f s" % [code, (Time.get_ticks_msec() - t0) / 1000.0])
	var text := "\n".join(PackedStringArray(out))
	for line in text.split("\n"):
		if "ERROR" in line or "error" in line.to_lower().left(12):
			_say("  " + line.strip_edges())
	var files := DirAccess.get_files_at(OUT_DIR)
	for f in files:
		_say("  %s  %.1f MB" % [f, FileAccess.open(OUT_DIR + "/" + f, FileAccess.READ).get_length() / 1048576.0])
	if code == 0 and files.size() >= 2:
		_zip(files)
	_done()


# Name of the first Windows Desktop preset (renaming it in the editor doesn't break this tool).
func _windows_preset() -> String:
	var cfg := ConfigFile.new()
	if cfg.load("res://export_presets.cfg") != OK:
		return ""
	for section in cfg.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options") \
				and str(cfg.get_value(section, "platform", "")) == "Windows Desktop":
			return str(cfg.get_value(section, "name", ""))
	return ""


func _zip(files: PackedStringArray) -> void:
	var t0 := Time.get_ticks_msec()
	var zip := ZIPPacker.new()
	if zip.open(ZIP_PATH) != OK:
		_say("zip: cannot open " + ZIP_PATH)
		return
	for f in files:
		var src := FileAccess.open(OUT_DIR + "/" + f, FileAccess.READ)
		zip.start_file("BonksAlpha/" + f)
		while src.get_position() < src.get_length():
			zip.write_file(src.get_buffer(CHUNK))
		zip.close_file()
	zip.close()
	_say("zip: %s  %.1f MB in %.0f s" % [ZIP_PATH, FileAccess.open(ZIP_PATH, FileAccess.READ).get_length() / 1048576.0,
		(Time.get_ticks_msec() - t0) / 1000.0])


func _say(s: String) -> void:
	print("EXPORT: " + s)
	_log.append(s)


func _done() -> void:
	var f := FileAccess.open("res://tests/_look/export_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	get_tree().quit()
