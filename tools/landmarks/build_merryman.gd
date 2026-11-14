# BuildMerryman — landmark builder for the Merryman Performing Arts Center (D-079; run this scene directly, no internet needed).
# Reads data/landmarks/merryman.json and writes world/landmarks/merryman.scn (placed by
# data/map/landmarks.json). Re-run after editing the data, then re-run build_cells (the navmesh enemies use inside
# the building is baked there). Log: tests/_look/merryman_build.txt.
# Depends on: DataLoader, LandmarkKit, merryman.gd, landmark_parts.gd.
extends Node

const DATA_PATH := "res://data/landmarks/merryman.json"
const Merryman := preload("res://tools/landmarks/merryman.gd")


func _ready() -> void:
	var d := DataLoader.load_json(DATA_PATH)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d.seed)
	var k := LandmarkKit.new("Merryman", d.materials)
	Merryman.build(k, d, rng)
	var msg := k.save(str(d.out_path))
	print(msg)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/_look"))
	var f := FileAccess.open("res://tests/_look/merryman_build.txt", FileAccess.WRITE)
	f.store_string(msg)
	f.close()
	get_tree().quit()
