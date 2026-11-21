# MoveCarMesh — one-run throwaway (D-110 fix): removes the old tools/map_import/car_mesh.gd now that the same
# class lives in scripts/world/car_mesh.gd, which the export actually ships. Two files cannot both declare
# class_name CarMesh. Safe to delete this tool once it has run; it reports what it did and does nothing if the
# new file is not in place. Log: tests/_look/move_car_mesh.txt.
extends Node


func _ready() -> void:
	var log_lines := PackedStringArray()
	var moved := FileAccess.file_exists("res://scripts/world/car_mesh.gd")
	log_lines.append("scripts/world/car_mesh.gd present: %s" % moved)
	if moved:
		for path: String in ["res://tools/map_import/car_mesh.gd", "res://tools/map_import/car_mesh.gd.uid"]:
			if FileAccess.file_exists(path):
				var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
				log_lines.append("removed %s: err %d" % [path, err])
			else:
				log_lines.append("%s: already gone" % path)
	else:
		log_lines.append("the new file is not there - nothing removed")
	DirAccess.make_dir_recursive_absolute("res://tests/_look")
	var f := FileAccess.open("res://tests/_look/move_car_mesh.txt", FileAccess.WRITE)
	f.store_string("\n".join(log_lines))
	f.close()
	print("MOVE: ", "\n".join(log_lines))
	get_tree().quit()
