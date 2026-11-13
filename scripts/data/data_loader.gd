# DataLoader — reads a JSON data file and validates it against a schema of { key: Variant.Type }.
# Missing or wrong-typed keys are errors (returns {}); unknown keys are warnings.
# Pure: no scene or rendering dependencies.
class_name DataLoader
extends RefCounted


static func load_validated(path: String, schema: Dictionary) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("DataLoader: cannot read %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("DataLoader: %s is not a JSON object" % path)
		return {}
	var data: Dictionary = parsed
	return data if validate(data, schema, path) else {}


static func load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("DataLoader: cannot read %s as a JSON object" % path)
		return {}
	return parsed


# label names the data in error messages (file path, or "file:entry_id").
static func validate(data: Dictionary, schema: Dictionary, label: String) -> bool:
	var ok := true
	for key: String in schema:
		if not data.has(key):
			push_error("DataLoader: %s is missing '%s'" % [label, key])
			ok = false
		elif typeof(data[key]) != schema[key]:
			push_error("DataLoader: %s '%s' should be %s" % [label, key, type_string(schema[key])])
			ok = false
	for key: String in data:
		if not schema.has(key):
			push_warning("DataLoader: %s has unknown key '%s'" % [label, key])
	return ok
