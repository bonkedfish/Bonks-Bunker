# ListDownloads — writes the file list of the Quaternius zips in the user's Downloads folder (D-058) to
# tests/_look/downloads_list.txt so we know what to unpack. Depends on: nothing.
extends Node

const DIR := "C:/Users/Fishb/Downloads"


func _ready() -> void:
	var lines := PackedStringArray()
	for d in [DIR, "C:/Users/Fishb/OneDrive/Downloads", "C:/Users/Fishb/Desktop", "C:/Users/Fishb/OneDrive/Desktop"]:
		for f in DirAccess.get_files_at(d):
			if f.to_lower().ends_with(".zip") or f.ends_with(".crdownload") or f.ends_with(".part"):
				lines.append("%s/%s  %d" % [d, f, FileAccess.get_modified_time(d + "/" + f)])
	for f in DirAccess.get_files_at(DIR):
		if not f.begins_with("Universal") or not f.ends_with(".zip"):
			continue
		var z := ZIPReader.new()
		var err := z.open(DIR + "/" + f)
		lines.append("== %s (open %d)" % [f, err])
		if err == OK:
			for p in z.get_files():
				lines.append(p)
			z.close()
	var out := FileAccess.open("res://tests/_look/downloads_list.txt", FileAccess.WRITE)
	out.store_string("\n".join(lines))
	out.close()
	get_tree().quit()
