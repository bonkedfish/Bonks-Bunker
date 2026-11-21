# BuildCoopElevator — landmark builder for the Kearney Co-op grain elevator (D-103; run this scene directly, no
# internet). Reads data/landmarks/coop_elevator.json, writes world/landmarks/coop_elevator.scn (placed by
# data/map/landmarks.json). Re-run after editing the data, then re-run build_cells (terrain pad + navmesh).
# Log: tests/_look/coop_elevator_build.txt. Depends on: DataLoader, LandmarkKit, coop_elevator.gd.
extends Node

const DATA_PATH := "res://data/landmarks/coop_elevator.json"
const Elevator := preload("res://tools/landmarks/coop_elevator.gd")


func _ready() -> void:
	var d := DataLoader.load_json(DATA_PATH)
	var k := LandmarkKit.new("CoopElevator", d.materials)
	Elevator.build(k, d)
	var msg := k.save(str(d.out_path))
	print(msg)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/_look"))
	var f := FileAccess.open("res://tests/_look/coop_elevator_build.txt", FileAccess.WRITE)
	f.store_string(msg)
	f.close()
	get_tree().quit()
