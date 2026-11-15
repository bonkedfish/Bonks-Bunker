# ReleaseNotes — one-run tool (run this scene directly): sets the GitHub release body for every tag that has a
# notes file in data/release/notes/<tag>.md (gh release edit <tag> --notes-file). Safe to re-run.
# Log: tests/_look/release_notes_result.txt.
# Depends on: data/release/release.json (repo), GitHub CLI (gh, logged in) on this PC.
extends Node

const NOTES_DIR := "res://data/release/notes"
const GH_FALLBACK := "C:/Program Files/GitHub CLI/gh.exe"

var _log := PackedStringArray()


func _ready() -> void:
	var gh := "gh" if OS.execute("gh", ["--version"]) == 0 else GH_FALLBACK
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/release/release.json"))
	var out := []
	OS.execute(gh, ["api", "user", "--jq", ".login"], out, false)  # stdout only (gh may log to stderr)
	var repo := "%s/%s" % ["\n".join(PackedStringArray(out)).strip_edges(), str(cfg.repo)]
	for file in DirAccess.get_files_at(NOTES_DIR):
		if not file.ends_with(".md"):
			continue
		var tag := file.get_basename()
		out = []
		var code := OS.execute(gh, ["release", "edit", tag, "-R", repo, "--notes-file",
			ProjectSettings.globalize_path(NOTES_DIR + "/" + file)], out, true)
		_log.append("%s %s: exit %d %s" % [repo, tag, code, "\n".join(PackedStringArray(out)).strip_edges()])
	DirAccess.make_dir_recursive_absolute("res://tests/_look")
	var f := FileAccess.open("res://tests/_look/release_notes_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	get_tree().quit()
