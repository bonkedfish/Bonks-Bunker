# PushRepo — one-run tool (run this scene directly): commits whatever has changed since the last release (diary,
# docs, data) and pushes it to GitHub main, then checks a release tag is live (gh release view). No build, no new
# release. Reads data/release/release.json (repo, commit_trailer) and data/release/push.json (the commit message
# to use, and a release tag to check is still live - leave check_tag "" to skip that).
# Log: tests/_look/push_repo_result.txt. Depends on: git + gh (logged in), the repo set up by release.tscn.
extends Node

const GIT_FALLBACK := "C:/Program Files/Git/cmd/git.exe"
const GH_FALLBACK := "C:/Program Files/GitHub CLI/gh.exe"

var _log := PackedStringArray()


func _ready() -> void:
	var root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var cfg := DataLoader.load_json("res://data/release/release.json")
	var push := DataLoader.load_json("res://data/release/push.json")
	var tag := str(push.get("check_tag", ""))
	var git := "git" if OS.execute("git", ["--version"]) == 0 else GIT_FALLBACK
	var gh := "gh" if OS.execute("gh", ["--version"]) == 0 else GH_FALLBACK
	_run(git, ["-C", root, "add", "-A"])
	var status := _run(git, ["-C", root, "status", "--porcelain"])
	if status.text.strip_edges() == "":
		_log.append("nothing new to commit")
	else:
		var message := str(push.get("message", ""))
		if message == "":
			message = "Diary and docs after the %s release" % tag
		var msg := ["-C", root, "commit", "-m", message]
		if str(cfg.get("commit_trailer", "")) != "":
			msg.append_array(["-m", str(cfg.commit_trailer)])
		_run(git, msg)
	_run(git, ["-C", root, "push", "origin", "HEAD:main"])
	_run(git, ["-C", root, "log", "-1", "--oneline"])
	if tag != "":
		_run(gh, ["release", "view", tag, "-R", "bonkedfish/" + str(cfg.repo), "--json", "name,isDraft,publishedAt,assets",
			"--jq", "{name, isDraft, publishedAt, assets: [.assets[].name]}"])
	var f := FileAccess.open("res://tests/_look/push_repo_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	get_tree().quit()


func _run(cmd: String, args: Array) -> Dictionary:
	var out := []
	var code := OS.execute(cmd, args, out, true)
	var text := "\n".join(PackedStringArray(out))
	_log.append("$ %s %s -> exit %d\n%s" % [cmd.get_file(), " ".join(PackedStringArray(args.slice(2 if args.size() > 2 and args[0] == "-C" else 0).map(func(a: Variant) -> String: return str(a)))), code, text.strip_edges()])
	return {"code": code, "text": text}
