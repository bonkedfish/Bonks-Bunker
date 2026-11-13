# BuildKearneyHigh — landmark builder for Kearney High School (D-055; run this scene directly, no internet needed).
# Reads data/landmarks/kearney_high.json and writes world/landmarks/kearney_high.scn (placed by
# data/map/landmarks.json). Re-run after editing the data, then re-run build_cells (the navmesh enemies use inside
# the school is baked there). Log: tests/_look/kearney_high_build.txt.
# Depends on: DataLoader, LandmarkKit, kearney_high.gd.
extends Node

const DATA_PATH := "res://data/landmarks/kearney_high.json"
const KearneyHigh := preload("res://tools/landmarks/kearney_high.gd")


func _ready() -> void:
	var d := DataLoader.load_json(DATA_PATH)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d.seed)
	var k := LandmarkKit.new("KearneyHigh", d.materials)
	KearneyHigh.build(k, d, rng)
	var msg := k.save(str(d.out_path))
	print(msg)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/_look"))
	var f := FileAccess.open("res://tests/_look/kearney_high_build.txt", FileAccess.WRITE)
	f.store_string(msg)
	f.close()
	get_tree().quit()
