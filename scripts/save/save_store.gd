# SaveStore — reads and writes world saves as JSON files in user://saves/<slug>.json (D-037).
# Writes go to a temp file first, the previous save is kept as <slug>.json.bak, then the temp file is
# renamed into place, so a crash mid-write never destroys the last good save.
# No nodes. Depends on: SaveFormat.
class_name SaveStore
extends RefCounted

const DIR := "user://saves"


# Newest first: [{ slug, name, saved }]. Unreadable or too-new files are skipped.
static func list_worlds() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(DIR):
		return out
	for file in DirAccess.get_files_at(DIR):
		if not file.ends_with(".json"):
			continue
		var data := read(file.trim_suffix(".json"))
		if not data.is_empty():
			out.append({"slug": file.trim_suffix(".json"), "name": str(data.name), "saved": int(data.get("saved", 0))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.saved > b.saved)
	return out


# The migrated, checked save, or {} (with a warning) if it can't be used.
static func read(slug: String) -> Dictionary:
	var path := _path(slug)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveStore: %s is not a save file" % path)
		return {}
	var data := SaveFormat.migrate(parsed)
	if data.is_empty():
		push_warning("SaveStore: %s is from an unknown or newer version" % path)
		return {}
	var problem := SaveFormat.check(data)
	if problem != "":
		push_warning("SaveStore: %s: %s" % [path, problem])
		return {}
	return data


static func write(slug: String, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := _path(slug)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SaveStore: cannot write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	if FileAccess.file_exists(path):
		var bak := path + ".bak"
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		DirAccess.rename_absolute(path, bak)
	return DirAccess.rename_absolute(tmp, path) == OK


static func delete(slug: String) -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(_path(slug) + suffix):
			DirAccess.remove_absolute(_path(slug) + suffix)


# A slug for a new world that doesn't overwrite an existing one ("kearney", "kearney_2", ...).
static func unique_slug(world_name: String) -> String:
	var base := SaveFormat.slug(world_name)
	var candidate := base
	var n := 2
	while FileAccess.file_exists(_path(candidate)):
		candidate = "%s_%d" % [base, n]
		n += 1
	return candidate


static func _path(slug: String) -> String:
	return "%s/%s.json" % [DIR, slug]
