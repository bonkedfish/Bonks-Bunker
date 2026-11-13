# BuildDowntownBars — landmark builder for the four downtown bars (D-059; run this scene directly, no internet
# needed). Reads data/landmarks/downtown_bars.json and writes world/landmarks/<bar>.scn for each bar (placed by
# data/map/landmarks.json). Re-run after editing the data, then re-run build_cells (the navmesh raiders use inside
# is baked there). Log: tests/_look/downtown_bars_build.txt. Depends on: DataLoader, LandmarkKit, bar_building.gd.
extends Node

const DATA_PATH := "res://data/landmarks/downtown_bars.json"
const BarBuilding := preload("res://tools/landmarks/bar_building.gd")


func _ready() -> void:
	var d := DataLoader.load_json(DATA_PATH)
	var lines := PackedStringArray()
	for id: String in d.bars:
		var bar: Dictionary = d.bars[id]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(id) + int(d.seed)
		var k := LandmarkKit.new(id.to_pascal_case(), d.materials)
		var counts := BarBuilding.build(k, id, bar, rng)
		var msg := "%s  %s" % [k.save("%s/%s.scn" % [d.out_dir, id]), counts]
		print(msg)
		lines.append(msg)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/_look"))
	var f := FileAccess.open("res://tests/_look/downtown_bars_build.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	get_tree().quit()
