# UnpackQuaternius — copies the parts of the two Quaternius CC0 packs the game uses (D-058) from the zips in the
# user's Downloads folder into assets/characters/: the Universal Animation Library Godot .glb (animations on the
# universal humanoid rig) -> ual/, the Universal Base Characters Godot/UE full-body characters + textures -> ubc/,
# and the head-bone-rigged hairstyles -> ubc/hair/. Re-runnable. Log: tests/_look/unpack_quaternius.txt.
# Depends on: nothing (run tools/refresh_classes.tscn afterwards so Godot imports the new files).
extends Node

const DL := "C:/Users/Fishb/Downloads/"
const JOBS := [
	["Universal Animation Library[Standard].zip", "Universal Animation Library[Standard]/Unreal-Godot/", "res://assets/characters/ual/", ["UAL1_Standard.glb"]],
	["Universal Base Characters[Standard].zip", "Universal Base Characters[Standard]/Base Characters/Godot - UE/", "res://assets/characters/ubc/", []],
	["Universal Base Characters[Standard].zip", "Universal Base Characters[Standard]/Hairstyles/Rigged to Head Bone/glTF (Godot -Unreal)/", "res://assets/characters/ubc/hair/", []],
]


func _ready() -> void:
	var log := PackedStringArray()
	for job: Array in JOBS:
		var z := ZIPReader.new()
		if z.open(DL + str(job[0])) != OK:
			log.append("cannot open " + str(job[0]))
			continue
		var prefix := str(job[1])
		var out_dir := str(job[2])
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
		var only: Array = job[3]
		for p in z.get_files():
			if not p.begins_with(prefix) or p.ends_with("/"):
				continue
			var rel := p.substr(prefix.length())
			if rel.contains("/") or (not only.is_empty() and not rel in only):
				continue
			var f := FileAccess.open(out_dir + rel, FileAccess.WRITE)
			var data := z.read_file(p)
			f.store_buffer(data)
			f.close()
			log.append("%s%s  %d bytes" % [out_dir, rel, data.size()])
		z.close()
	var lf := FileAccess.open("res://tests/_look/unpack_quaternius.txt", FileAccess.WRITE)
	lf.store_string("\n".join(log))
	lf.close()
	get_tree().quit()
