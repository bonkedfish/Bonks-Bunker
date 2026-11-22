# RefreshStreetMaterials — one-run tool (run this scene directly) (D-115): re-saves the shared ground and
# street_<surface> materials in world/generated/cells/materials/ from data/art/streets.json, exactly as
# build_cells does, so a change to how ground or streets look reaches the baked cells without a re-bake.
# Log: tests/_look/refresh_street_materials.txt. Depends on: StreetLooks, data/map/import_config.json.
extends Node


func _ready() -> void:
	var log := PackedStringArray()
	var looks := StreetLooks.new()
	if looks.error != "":
		log.append("STOPPED: " + looks.error)
	else:
		var dir := str(DataLoader.load_json("res://data/map/import_config.json").cells_dir) + "/materials"
		var mats := {"ground": looks.make_ground_material()}
		for id: String in looks.surface_ids():
			mats["street_" + id] = looks.make_surface_material(id)
		for mat_name: String in mats:
			var err := ResourceSaver.save(mats[mat_name], "%s/%s.tres" % [dir, mat_name], ResourceSaver.FLAG_CHANGE_PATH)
			log.append("%s.tres: %s" % [mat_name, "saved" if err == OK else "error %d" % err])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/_look"))
	var f := FileAccess.open("res://tests/_look/refresh_street_materials.txt", FileAccess.WRITE)
	f.store_string("\n".join(log))
	f.close()
	print("\n".join(log))
	get_tree().quit()
