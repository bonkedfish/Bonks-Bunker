# BuildCopeStadium — landmark builder for Cope Stadium at Foster Field (D-079; run this scene directly, no internet needed).
# Reads data/landmarks/cope_stadium.json and writes world/landmarks/cope_stadium.scn (placed by
# data/map/landmarks.json). Re-run after editing the data, then re-run build_cells (the navmesh enemies use inside
# the building is baked there). Log: tests/_look/cope_stadium_build.txt.
# Depends on: DataLoader, LandmarkKit, cope_stadium.gd, landmark_parts.gd.
extends Node

const DATA_PATH := "res://data/landmarks/cope_stadium.json"
const CopeStadium := preload("res://tools/landmarks/cope_stadium.gd")


func _ready() -> void:
	var d := DataLoader.load_json(DATA_PATH)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d.seed)
	var k := LandmarkKit.new("CopeStadium", d.materials)
	CopeStadium.build(k, d, rng)
	var msg := k.save(str(d.out_path))
	print(msg)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/_look"))
	var f := FileAccess.open("res://tests/_look/cope_stadium_build.txt", FileAccess.WRITE)
	f.store_string(msg)
	f.close()
	get_tree().quit()
