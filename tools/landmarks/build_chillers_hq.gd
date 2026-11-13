# BuildChillersHq — landmark builder for the Chillers' HQ in the UNK student union (D-053; run this scene directly,
# no internet needed). Reads data/landmarks/chillers_hq.json and writes world/landmarks/chillers_hq.scn (placed by
# data/map/landmarks.json). Re-run after editing the data, then re-run build_cells. Log: tests/_look/chillers_build.txt.
# Depends on: DataLoader, LandmarkKit, chillers_hq.gd.
extends Node

const DATA_PATH := "res://data/landmarks/chillers_hq.json"
const ChillersHq := preload("res://tools/landmarks/chillers_hq.gd")


func _ready() -> void:
	var d := DataLoader.load_json(DATA_PATH)
	var pal: Dictionary = {}
	for id: String in d.palettes:
		pal[id] = d.palettes[id]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d.seed)
	var k := LandmarkKit.new("ChillersHq", d.materials)
	ChillersHq.build(k, d, pal, rng)
	var msg := k.save(str(d.out_path))
	print(msg)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/_look"))
	var f := FileAccess.open("res://tests/_look/chillers_build.txt", FileAccess.WRITE)
	f.store_string(msg)
	f.close()
	get_tree().quit()
