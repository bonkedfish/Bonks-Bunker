# FetchModels — asset import (run this scene directly, on a machine with internet) (D-043).
# For each model in data/art/models.json: asks the Poly Haven API for its glTF at the configured resolution,
# downloads the .gltf and every file it includes (buffers, textures), checks each md5 and saves them under
# <out_dir>/<model key>/ keeping the glTF's relative paths. Models already on disk are skipped. Only the models
# listed in the data file are downloaded (every download list is approved first). Writes <out_dir>/manifest.json.
# Open the editor once afterwards so Godot imports the glTFs. Depends on: DataLoader.
extends Node

const DATA_PATH := "res://data/art/models.json"

var _http: HTTPRequest
var _cfg: Dictionary


func _ready() -> void:
	_cfg = DataLoader.load_json(DATA_PATH)
	_http = HTTPRequest.new()
	_http.timeout = 300.0
	add_child(_http)
	var out_dir := str(_cfg.out_dir)
	var manifest := {"source": _cfg.source, "license": "CC0 1.0", "models": {}}
	var old: Variant = DataLoader.load_json(out_dir + "/manifest.json") if FileAccess.file_exists(out_dir + "/manifest.json") else {}
	var total := 0
	var failed := 0
	var keys: Array = _cfg.models.keys()
	keys.sort()
	for key: String in keys:
		var id := str(_cfg.models[key].polyhaven_id)
		var gltf_path := "%s/%s/%s.gltf" % [out_dir, key, id]
		if typeof(old) == TYPE_DICTIONARY and old.get("models", {}).has(key) and FileAccess.file_exists(gltf_path):
			manifest.models[key] = old.models[key]
			print("MODELS: %s already downloaded, skipped" % key)
			continue
		var listing := await _download(str(_cfg.api_files_url) % id)
		var files: Variant = JSON.parse_string(listing.get_string_from_utf8()) if not listing.is_empty() else null
		var entry: Dictionary = {}
		if typeof(files) == TYPE_DICTIONARY:
			entry = files.get("gltf", {}).get(str(_cfg.resolution), {}).get("gltf", {})
		if not entry.has("url"):
			print("MODELS: %s (%s): no %s glTF" % [key, id, _cfg.resolution])
			failed += 1
			continue
		var parts := {gltf_path.get_file(): entry}
		for rel: String in entry.get("include", {}):
			parts[rel] = entry.include[rel]
		var saved := {}
		var ok := true
		for rel: String in parts:
			if rel.contains("..") or rel.begins_with("/"):
				print("MODELS: %s: unsafe path %s, skipped model" % [key, rel])
				ok = false
				break
			var e: Dictionary = parts[rel]
			var bytes := await _download(str(e.url))
			if bytes.is_empty() or (e.has("md5") and _md5(bytes) != str(e.md5)):
				print("MODELS: %s %s: download failed or md5 mismatch" % [key, rel])
				ok = false
				break
			var path := "%s/%s/%s" % [out_dir, key, rel]
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_buffer(bytes)
			f.close()
			total += bytes.size()
			saved[rel] = bytes.size()
		if not ok:
			failed += 1
			continue
		print("MODELS: %s (%s) %d files" % [key, id, saved.size()])
		manifest.models[key] = {"polyhaven_id": id, "page": "https://polyhaven.com/a/" + id, "gltf": gltf_path, "files": saved}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var mf := FileAccess.open(out_dir + "/manifest.json", FileAccess.WRITE)
	mf.store_string(JSON.stringify(manifest, "\t"))
	mf.close()
	_finish("MODELS: %d models, %.1f MB downloaded, %d problems -> %s" % [keys.size(), total / 1048576.0, failed, out_dir])


func _md5(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


func _download(url: String) -> PackedByteArray:
	var err := _http.request(url, PackedStringArray(["User-Agent: " + str(_cfg.user_agent)]))
	if err != OK:
		print("MODELS: %s request error %d" % [url, err])
		return PackedByteArray()
	var res: Array = await _http.request_completed
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		print("MODELS: %s failed (result %d, HTTP %d)" % [url, res[0], res[1]])
		return PackedByteArray()
	return res[3]


func _finish(message: String) -> void:
	print(message)
	await get_tree().create_timer(20.0).timeout
	get_tree().quit()
