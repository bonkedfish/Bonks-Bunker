# BuildCollectionPoint — landmark builder for the Act 1 finale spot (D-102; run this scene directly, no internet).
# Reads data/landmarks/collection_point.json, writes world/landmarks/collection_point.scn (placed by
# data/map/landmarks.json). Re-run after editing the data, then re-run build_cells (terrain pad + navmesh).
# Log: tests/_look/collection_point_build.txt. Depends on: DataLoader, LandmarkKit, collection_point.gd.
extends Node

const DATA_PATH := "res://data/landmarks/collection_point.json"
const Spot := preload("res://tools/landmarks/collection_point.gd")


func _ready() -> void:
	var d := DataLoader.load_json(DATA_PATH)
	var k := LandmarkKit.new("CollectionPoint", d.materials)
	Spot.build(k, d)
	var msg := k.save(str(d.out_path))
	print(msg)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/_look"))
	var f := FileAccess.open("res://tests/_look/collection_point_build.txt", FileAccess.WRITE)
	f.store_string(msg)
	f.close()
	get_tree().quit()
