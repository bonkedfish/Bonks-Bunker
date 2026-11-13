# CopyToNewHome — one-off: copies this project to C:/1Bonks_Bunker with robocopy (keeps .godot so nothing re-imports;
# skips old Alpha builds and Windows temp files). The OneDrive original is left untouched as a backup.
# Log: C:/1Bonks_Bunker/copy_result.txt. Depends on: nothing.
extends Node

const DEST := "C:\\1Bonks_Bunker"


func _ready() -> void:
	await get_tree().process_frame
	var src := ProjectSettings.globalize_path("res://").trim_suffix("/").replace("/", "\\")
	var args := [src, DEST, "/E", "/R:1", "/W:1", "/NFL", "/NDL", "/NP", "/MT:8",
		"/XF", "Bonks-Game-Alpha*", "~*.TMP", src + "\\libwebrtc_native.windows.template_debug.x86_64.dll"]
	var out := []
	var t0 := Time.get_ticks_msec()
	var code := OS.execute("robocopy", args, out, true)
	var text := "robocopy exit %d (0-7 = ok) in %.0f s\n%s" % [code, (Time.get_ticks_msec() - t0) / 1000.0,
		"\n".join(PackedStringArray(out))]
	print("COPY: ", text.left(4000))
	var f := FileAccess.open(DEST.replace("\\", "/") + "/copy_result.txt", FileAccess.WRITE)
	if f:
		f.store_string(text)
	get_tree().quit()
