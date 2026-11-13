# FetchCharacters — asset import (run this scene directly, on a machine with internet) (D-045).
# Downloads the character glTFs listed in data/art/characters.json (Quaternius Zombie Apocalypse Kit, CC0, public
# Google Drive folder; file name -> Drive file id) into out_dir, skipping files already there, and checks each one
# parses as JSON with a "meshes" entry (Drive answers with an HTML page when a link is wrong). Writes
# <out_dir>/manifest.json. Open the editor once afterwards so Godot imports them. Depends on: DataLoader.
extends Node

const DATA_PATH := "res://data/art/characters.json"

var _http: HTTPRequest
var _cfg: Dictionary


func _ready() -> void:
	_cfg = DataLoader.load_json(DATA_PATH)
	_http = HTTPRequest.new()
	_http.timeout = 300.0
	_http.max_redirects = 10
	add_child(_http)
	var out_dir := str(_cfg.out_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var manifest := {"source": _cfg.source, "license": "CC0 1.0", "files": {}}
	var total := 0
	var failed := 0
	var names: Array = _cfg.files.keys()
	names.sort()
	for file_name: String in names:
		var path := "%s/%s" % [out_dir, file_name]
		if FileAccess.file_exists(path):
			print("CHARS: %s already downloaded, skipped" % file_name)
			manifest.files[file_name] = {"drive_id": _cfg.files[file_name]}
			continue
		var bytes := await _download(str(_cfg.download_url) % str(_cfg.files[file_name]))
		var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8()) if not bytes.is_empty() else null
		if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("meshes"):
			print("CHARS: %s: not a glTF (%d bytes), not saved: %s" % [file_name, bytes.size(), bytes.slice(0, 300).get_string_from_utf8().replace("\n", " ")])
			failed += 1
			continue
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(bytes)
		f.close()
		total += bytes.size()
		manifest.files[file_name] = {"drive_id": _cfg.files[file_name], "bytes": bytes.size()}
		print("CHARS: %s %.1f MB" % [file_name, bytes.size() / 1048576.0])
	var mf := FileAccess.open(out_dir + "/manifest.json", FileAccess.WRITE)
	mf.store_string(JSON.stringify(manifest, "\t"))
	mf.close()
	_finish("CHARS: %d files, %.1f MB downloaded, %d problems -> %s" % [names.size(), total / 1048576.0, failed, out_dir])


func _download(url: String) -> PackedByteArray:
	var err := _http.request(url, PackedStringArray(["User-Agent: " + str(_cfg.user_agent)]))
	if err != OK:
		print("CHARS: %s request error %d" % [url, err])
		return PackedByteArray()
	var res: Array = await _http.request_completed
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		print("CHARS: %s failed (result %d, HTTP %d)" % [url, res[0], res[1]])
		return PackedByteArray()
	return res[3]


func _finish(message: String) -> void:
	print(message)
	await get_tree().create_timer(20.0).timeout
	get_tree().quit()
