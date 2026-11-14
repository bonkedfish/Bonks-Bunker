# SfxCheck — dev helper (D-077): prints how many sound files the Sfx autoload found for each event in
# data/audio/sounds.json, and writes the list to tests/_look/sfx_check.txt. Depends on: Sfx autoload.
extends Node


func _ready() -> void:
	var lines := PackedStringArray()
	var empty := 0
	for id: String in Sfx.data.get("events", {}):
		var n: int = Sfx._streams.get(id, []).size()
		if n == 0:
			empty += 1
		lines.append("%-22s %d" % [id, n])
	lines.append("events with no files: %d" % empty)
	print("SFX: " + "\nSFX: ".join(lines))
	DirAccess.make_dir_recursive_absolute("res://tests/_look")
	var f := FileAccess.open("res://tests/_look/sfx_check.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	get_tree().quit()
