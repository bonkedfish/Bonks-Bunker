# SmokeAlpha — launches the exported alpha (C:/Users/Fishb/BonksAlpha/BonksGame.exe) for ~600 frames and logs its
# output, to catch missing files / the WebRTC extension failing to load. Log: tests/_look/export_smoke.txt.
# Depends on: tools/export/export_alpha.tscn having been run.
extends Node

const EXE := "C:/Users/Fishb/BonksAlpha/BonksGame.exe"


func _ready() -> void:
	await get_tree().process_frame
	var out := []
	var code := OS.execute(EXE, ["--quit-after", "600", "--verbose"], out, true)
	var lines := PackedStringArray()
	lines.append("exit %d" % code)
	for line in "\n".join(PackedStringArray(out)).split("\n"):
		var l := line.strip_edges()
		if "ERROR" in l or "WebRTC" in l or "webrtc" in l or "extension" in l.to_lower() or "Graphics" in l:
			lines.append(l)
	var f := FileAccess.open("res://tests/_look/export_smoke.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	get_tree().quit()
