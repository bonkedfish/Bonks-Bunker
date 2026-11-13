# BuildArchway — landmark builder for the Great Platte River Road Archway (D-049; run this scene directly, no
# internet needed). Reads data/landmarks/archway.json and writes world/landmarks/archway.scn (placed over I-80 by
# data/map/landmarks.json). Re-run after editing the data, then re-run build_cells. Log: tests/_look/archway_build.txt.
# Depends on: DataLoader, LandmarkKit, archway.gd.
extends Node

const DATA_PATH := "res://data/landmarks/archway.json"
const Archway := preload("res://tools/landmarks/archway.gd")


func _ready() -> void:
	var d := DataLoader.load_json(DATA_PATH)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d.seed)
	var k := LandmarkKit.new("Archway", d.materials)
	Archway.build(k, d, rng)
	var msg := k.save(str(d.out_path))
	print(msg)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/_look"))
	var f := FileAccess.open("res://tests/_look/archway_build.txt", FileAccess.WRITE)
	f.store_string(msg)
	f.close()
	get_tree().quit()
