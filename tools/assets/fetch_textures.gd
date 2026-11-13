# FetchTextures — asset import (run this scene directly, on a machine with internet) (D-041).
# For each texture in data/art/textures.json: asks the Poly Haven API which files exist, downloads the albedo,
# normal (OpenGL) and ARM (AO/roughness/metal) maps at the configured resolution, checks each file's md5,
# and saves them as <out_dir>/<texture key>/<map>.jpg. If a texture has no ARM map, its roughness map is saved
# instead. Only the textures listed in the data file are downloaded (every download list is approved first).
# Textures already on disk (albedo present and in the old manifest) are skipped, not downloaded again.
# Writes <out_dir>/manifest.json (keys, Poly Haven ids, files, sizes, licence). Depends on: DataLoader.
extends Node

const DATA_PATH := "res://data/art/textures.json"

var _http: HTTPRequest
var _cfg: Dictionary


func _ready() -> void:
	_cfg = DataLoader.load_json(DATA_PATH)
	_http = HTTPRequest.new()
	_http.timeout = 300.0
	add_child(_http)
	var res := str(_cfg.resolution)
	var fmt := str(_cfg.format)
	var out_dir := str(_cfg.out_dir)
	var manifest := {"source": _cfg.source, "license": "CC0 1.0", "textures": {}}
	var old: Variant = DataLoader.load_json(out_dir + "/manifest.json") if FileAccess.file_exists(out_dir + "/manifest.json") else {}
	var total := 0
	var failed := 0
	var keys: Array = _cfg.textures.keys()
	keys.sort()
	for key: String in keys:
		var t: Dictionary = _cfg.textures[key]
		var id := str(t.polyhaven_id)
		if typeof(old) == TYPE_DICTIONARY and old.get("textures", {}).has(key) \
				and FileAccess.file_exists("%s/%s/albedo.%s" % [out_dir, key, fmt]):
			manifest.textures[key] = old.textures[key]
			print("TEX: %s already downloaded, skipped" % key)
			continue
		var listing := await _download(str(_cfg.api_files_url) % id)
		var files: Variant = JSON.parse_string(listing.get_string_from_utf8()) if not listing.is_empty() else null
		if typeof(files) != TYPE_DICTIONARY:
			print("TEX: %s (%s): no file listing" % [key, id])
			failed += 1
			continue
		var dir := "%s/%s" % [out_dir, key]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var saved := {}
		for map: String in ["albedo", "normal", "arm"]:
			var entry := _pick(files, map, res, fmt)
			var map_name := map
			if entry.is_empty() and map == "arm":
				entry = _pick(files, "roughness", res, fmt)
				map_name = "roughness"
			if entry.is_empty():
				print("TEX: %s (%s): no %s map at %s %s" % [key, id, map, res, fmt])
				failed += 1
				continue
			var bytes := await _download(str(entry.url))
			if bytes.is_empty():
				failed += 1
				continue
			if entry.has("md5") and _md5(bytes) != str(entry.md5):
				print("TEX: %s %s: md5 mismatch, not saved" % [key, map_name])
				failed += 1
				continue
			var path := "%s/%s.%s" % [dir, map_name, fmt]
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_buffer(bytes)
			f.close()
			total += bytes.size()
			saved[map_name] = {"file": path.get_file(), "bytes": bytes.size(), "url": entry.url}
			print("TEX: %s %s %.1f MB" % [key, map_name, bytes.size() / 1048576.0])
		manifest.textures[key] = {"polyhaven_id": id, "page": "https://polyhaven.com/a/" + id, "maps": saved}
	var mf := FileAccess.open(out_dir + "/manifest.json", FileAccess.WRITE)
	mf.store_string(JSON.stringify(manifest, "\t"))
	mf.close()
	_finish("TEX: %d textures, %.1f MB downloaded, %d problems -> %s" % [keys.size(), total / 1048576.0, failed, out_dir])


# The Poly Haven API entry {url, size, md5} for one of our map names, or {} if it has none.
func _pick(files: Dictionary, map: String, res: String, fmt: String) -> Dictionary:
	for ph_name: String in _cfg.maps.get(map, []):
		var m: Dictionary = files.get(ph_name, {})
		var r: Dictionary = m.get(res, {})
		var e: Dictionary = r.get(fmt, {})
		if e.has("url"):
			return e
	return {}


func _md5(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


func _download(url: String) -> PackedByteArray:
	var err := _http.request(url, PackedStringArray(["User-Agent: " + str(_cfg.user_agent)]))
	if err != OK:
		print("TEX: %s request error %d" % [url, err])
		return PackedByteArray()
	var res: Array = await _http.request_completed
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		print("TEX: %s failed (result %d, HTTP %d)" % [url, res[0], res[1]])
		return PackedByteArray()
	return res[3]


func _finish(message: String) -> void:
	print(message)
	await get_tree().create_timer(20.0).timeout
	get_tree().quit()
