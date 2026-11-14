# BuildKenwood — landmark builder for Kenwood Elementary (D-078; run this scene directly, no internet needed).
# Reads data/landmarks/kenwood.json and writes world/landmarks/kenwood.scn (placed by
# data/map/landmarks.json). Re-run after editing the data, then re-run build_cells (the navmesh enemies use inside
# the school is baked there). Log: tests/_look/kenwood_build.txt.
# Depends on: DataLoader, LandmarkKit, kenwood.gd (+ kenwood_rooms.gd).
extends Node

const DATA_PATH := "res://data/landmarks/kenwood.json"
const Kenwood := preload("res://tools/landmarks/kenwood.gd")


func _ready() -> void:
	var d := DataLoader.load_json(DATA_PATH)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d.seed)
	var k := LandmarkKit.new("Kenwood", d.materials)
	Kenwood.build(k, d, rng)
	var msg := k.save(str(d.out_path))
	print(msg)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/_look"))
	var f := FileAccess.open("res://tests/_look/kenwood_build.txt", FileAccess.WRITE)
	f.store_string(msg)
	f.close()
	get_tree().quit()
