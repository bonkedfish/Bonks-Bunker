# BuildRvPark — landmark builder for the Kearney RV Park & Campground (D-079; run this scene directly, no internet needed).
# Reads data/landmarks/rv_park.json and writes world/landmarks/rv_park.scn (placed by
# data/map/landmarks.json). Re-run after editing the data, then re-run build_cells (the navmesh enemies use inside
# the building is baked there). Log: tests/_look/rv_park_build.txt.
# Depends on: DataLoader, LandmarkKit, rv_park.gd, landmark_parts.gd.
extends Node

const DATA_PATH := "res://data/landmarks/rv_park.json"
const RvPark := preload("res://tools/landmarks/rv_park.gd")


func _ready() -> void:
	var d := DataLoader.load_json(DATA_PATH)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d.seed)
	var k := LandmarkKit.new("RvPark", d.materials)
	RvPark.build(k, d, rng)
	var msg := k.save(str(d.out_path))
	print(msg)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/_look"))
	var f := FileAccess.open("res://tests/_look/rv_park_build.txt", FileAccess.WRITE)
	f.store_string(msg)
	f.close()
	get_tree().quit()
