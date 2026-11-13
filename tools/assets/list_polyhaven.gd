# ListPolyhaven — asset import helper (run this scene directly, on a machine with internet) (D-043).
# Read-only: downloads Poly Haven's asset listings (no asset files), prints textures whose id matches TEXTURE_WORDS
# and models in MODEL_CATEGORIES, each with its exact download size (textures: 2K jpg albedo + normal + ARM;
# models: 2K glTF incl. its textures), so a download list can be approved before fetch_textures runs.
# Also writes the lines to OUT_PATH. Depends on: data/art/textures.json (API URL, user agent).
extends Node

const DATA_PATH := "res://data/art/textures.json"
const ASSETS_URL := "https://api.polyhaven.com/assets?t=%s"
const TEXTURE_WORDS := []
const OUT_PATH := "res://tests/_look/polyhaven_list.txt"
const MODEL_CATEGORIES := ["props", "industrial", "urban", "outdoor", "furniture", "electronics", "decorative", "containers", "tools", "vehicles", "street", "debris", "construction", "barriers", "appliances", "lighting", "seating", "shelves", "table", "signs"]
const MODEL_EXCLUDE := ["nature", "food", "rocks", "plants"]

var _http: HTTPRequest
var _cfg: Dictionary
var _lines: PackedStringArray = []


func _ready() -> void:
	_cfg = DataLoader.load_json(DATA_PATH)
	_http = HTTPRequest.new()
	_http.timeout = 120.0
	add_child(_http)
	var tex: Variant = _json(await _fetch(ASSETS_URL % "textures"))
	var mod: Variant = _json(await _fetch(ASSETS_URL % "models"))
	if typeof(tex) != TYPE_DICTIONARY or typeof(mod) != TYPE_DICTIONARY:
		_finish("PH: could not read the asset listings")
		return
	var ids: Array = tex.keys()
	ids.sort()
	for id: String in ids:
		for w: String in TEXTURE_WORDS:
			if id.contains(w):
				var files: Variant = _json(await _fetch(str(_cfg.api_files_url) % id))
				_out("PH tex %s | %s | %.1f MB | %s" % [id, tex[id].get("name", ""), _tex_mb(files), tex[id].get("categories", [])])
				break
	ids = mod.keys()
	ids.sort()
	for id: String in ids:
		var cats: Array = mod[id].get("categories", [])
		var skip := false
		for c: String in MODEL_EXCLUDE:
			skip = skip or c in cats
		if skip:
			continue
		for c: String in MODEL_CATEGORIES:
			if c in cats:
				var files: Variant = _json(await _fetch(str(_cfg.api_files_url) % id))
				_out("PH model %s | %s | %.1f MB | %s" % [id, mod[id].get("name", ""), _model_mb(files), cats])
				break
	_finish("PH: listing done")


func _tex_mb(files: Variant) -> float:
	if typeof(files) != TYPE_DICTIONARY:
		return -1.0
	var total := 0.0
	for m: String in ["Diffuse", "nor_gl", "arm"]:
		total += float(files.get(m, {}).get("2k", {}).get("jpg", {}).get("size", 0))
	return total / 1048576.0


func _model_mb(files: Variant) -> float:
	if typeof(files) != TYPE_DICTIONARY:
		return -1.0
	var g: Dictionary = files.get("gltf", {}).get("2k", {}).get("gltf", {})
	var total := float(g.get("size", 0))
	for k in g.get("include", {}):
		total += float(g.include[k].get("size", 0))
	return total / 1048576.0


func _json(bytes: PackedByteArray) -> Variant:
	return JSON.parse_string(bytes.get_string_from_utf8()) if not bytes.is_empty() else null


func _fetch(url: String) -> PackedByteArray:
	if _http.request(url, PackedStringArray(["User-Agent: " + str(_cfg.user_agent)])) != OK:
		return PackedByteArray()
	var res: Array = await _http.request_completed
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		print("PH: %s failed (result %d, HTTP %d)" % [url, res[0], res[1]])
		return PackedByteArray()
	return res[3]


func _out(line: String) -> void:
	print(line)
	_lines.append(line)


func _finish(message: String) -> void:
	_out(message)
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	f.store_string("\n".join(_lines))
	f.close()
	await get_tree().create_timer(20.0).timeout
	get_tree().quit()
