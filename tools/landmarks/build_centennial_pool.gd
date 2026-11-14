# BuildCentennialPool — landmark builder for the drained Centennial Park pool (D-078; run this scene directly, no internet needed).
# Reads data/landmarks/centennial_pool.json and writes world/landmarks/centennial_pool.scn (placed by
# data/map/landmarks.json). Re-run after editing the data, then re-run build_cells (the navmesh enemies use inside
# the pool is baked there). Log: tests/_look/centennial_pool_build.txt.
# Depends on: DataLoader, LandmarkKit, centennial_pool.gd.
extends Node

const DATA_PATH := "res://data/landmarks/centennial_pool.json"
const CentennialPool := preload("res://tools/landmarks/centennial_pool.gd")


func _ready() -> void:
	var d := DataLoader.load_json(DATA_PATH)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d.seed)
	var k := LandmarkKit.new("CentennialPool", d.materials)
	CentennialPool.build(k, d, rng)
	var msg := k.save(str(d.out_path))
	print(msg)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/_look"))
	var f := FileAccess.open("res://tests/_look/centennial_pool_build.txt", FileAccess.WRITE)
	f.store_string(msg)
	f.close()
	get_tree().quit()
