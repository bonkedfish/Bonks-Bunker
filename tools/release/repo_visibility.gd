# RepoVisibility — sets the GitHub repo (origin of this project) to the "visibility" in data/release/release.json
# and logs the result. Log: tests/_look/repo_visibility.txt.
# Depends on: data/release/release.json, GitHub CLI (gh, logged in).
extends Node

const GH_FALLBACK := "C:/Program Files/GitHub CLI/gh.exe"
const GIT_DIR := "C:\\Program Files\\Git\\cmd"


func _ready() -> void:
	await get_tree().process_frame
	OS.set_environment("PATH", OS.get_environment("PATH") + ";" + GIT_DIR + ";" + GH_FALLBACK.get_base_dir().replace("/", "\\"))
	var cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/release/release.json"))
	var root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var gh := GH_FALLBACK if FileAccess.file_exists(GH_FALLBACK) else "gh"
	var lines := PackedStringArray()
	var out := []
	OS.execute("git", ["-C", root, "remote", "get-url", "origin"], out, true, false)
	var repo := "\n".join(PackedStringArray(out)).strip_edges().trim_suffix(".git")
	out = []
	var code := OS.execute(gh, ["repo", "edit", repo, "--visibility", str(cfg.visibility),
		"--accept-visibility-change-consequences"], out, true, false)
	lines.append("edit exit %d: %s" % [code, "\n".join(PackedStringArray(out)).strip_edges()])
	out = []
	OS.execute(gh, ["repo", "view", repo, "--json", "url,visibility"], out, true, false)
	lines.append("now: " + "\n".join(PackedStringArray(out)).strip_edges())
	DirAccess.make_dir_recursive_absolute("res://tests/_look")
	var f := FileAccess.open("res://tests/_look/repo_visibility.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	get_tree().quit()
