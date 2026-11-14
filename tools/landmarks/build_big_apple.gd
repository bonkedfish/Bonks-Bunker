# BuildBigApple — landmark builder for the Big Apple Fun Center (D-079; run this scene directly, no internet needed).
# Reads data/landmarks/big_apple.json and writes world/landmarks/big_apple.scn (placed by
# data/map/landmarks.json). Re-run after editing the data, then re-run build_cells (the navmesh enemies use inside
# the building is baked there). Log: tests/_look/big_apple_build.txt.
# Depends on: DataLoader, LandmarkKit, big_apple.gd, landmark_parts.gd.
extends Node

const DATA_PATH := "res://data/landmarks/big_apple.json"
const BigApple := preload("res://tools/landmarks/big_apple.gd")


func _ready() -> void:
	var d := DataLoader.load_json(DATA_PATH)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d.seed)
	var k := LandmarkKit.new("BigApple", d.materials)
	BigApple.build(k, d, rng)
	var msg := k.save(str(d.out_path))
	print(msg)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/_look"))
	var f := FileAccess.open("res://tests/_look/big_apple_build.txt", FileAccess.WRITE)
	f.store_string(msg)
	f.close()
	get_tree().quit()
