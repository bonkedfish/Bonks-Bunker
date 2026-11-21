# Release — one-run GitHub release (run this scene directly). Picks the next version from the repo's tags
# (alpha2.1 -> alpha2.2 ...; release.json "min_version" lifts it to a bigger jump like alpha3.0), exports Windows + macOS from the same commit, smoke-tests the Windows exe, zips,
# splits any file over split_mb (GitHub caps release files at 2 GiB), commits + pushes the source, then publishes
# ONE prerelease with both platforms. Creates the GitHub repo on first run. Nothing is published if any step fails.
# The real models (D-112): the Mixamo zombies are gitignored and fall back to CC0 cartoon ones when missing, so a
# release could quietly ship the wrong zombies. ModelCheck runs twice - in the editor before exporting, and inside
# the packaged Windows exe after (`-- --check-models`) - and any missing model or clip stops the release.
# release.json "force_version" rebuilds THAT version instead of picking the next one: if the release already
# exists its assets are replaced (gh release upload --clobber) and its notes are left alone, which is how a
# broken build gets fixed without burning a version number. Clear force_version afterwards.
# Log: tests/_look/release_result.txt.
# Depends on: data/release/release.json, export_presets.cfg (a "Windows Desktop" and a "macOS" preset),
# Godot export templates, Git and GitHub CLI (gh, logged in) on this PC.
extends Node

const CONFIG := "res://data/release/release.json"
const BUILD_DIR := "res://build"
const CHUNK := 16 * 1024 * 1024
const GIT_FALLBACK := "C:/Program Files/Git/cmd/git.exe"
const GH_FALLBACK := "C:/Program Files/GitHub CLI/gh.exe"

var _log := PackedStringArray()
var _root := ""
var _git := "git"
var _gh := "gh"


func _ready() -> void:
	await get_tree().process_frame
	_root = ProjectSettings.globalize_path("res://").trim_suffix("/")
	if not _run():
		_say("RELEASE FAILED - nothing was published.")
	_done()


func _run() -> bool:
	var cfg := _load_config()
	if cfg.is_empty():
		return false
	if not _preflight():
		return false
	var missing := ModelCheck.check(self)
	if not missing.is_empty():
		_say("STOPPED: the real models are not all here, so this build would ship fallback zombies:\n    "
			+ "\n    ".join(missing))
		return false
	_say("models: every Mixamo model and clip is present")
	if not _ensure_repo(cfg):
		return false
	var forced := str(cfg.get("force_version", ""))
	var ver := forced if forced != "" else _next_version(str(cfg.first_version))
	if ver == "":
		return false
	if forced == "":
		var floor_ver := _parse_version(str(cfg.get("min_version", "")))  # a version jump (alpha3.0): never below it
		var picked := _parse_version(ver)
		if not floor_ver.is_empty() and (floor_ver[0] > picked[0] or (floor_ver[0] == picked[0] and floor_ver[1] > picked[1])):
			ver = "alpha%d.%d" % [floor_ver[0], floor_ver[1]]
	_say("version: %s%s" % [ver, "  (force_version: rebuilding it in place)" if forced != "" else ""])

	var out_dir := ProjectSettings.globalize_path(BUILD_DIR) + "/" + ver
	var win_dir := out_dir + "/windows"
	DirAccess.make_dir_recursive_absolute(win_dir)
	_touch(ProjectSettings.globalize_path(BUILD_DIR) + "/.gdignore")
	var exe := str(cfg.exe_name)

	if not _export("Windows Desktop", win_dir + "/" + exe + ".exe"):
		return false
	var mac_zip := "%s/%s-%s-mac.zip" % [out_dir, exe, ver]
	if not _export("macOS", mac_zip):
		return false
	if not _smoke(win_dir + "/" + exe + ".exe"):
		return false
	if not _models_in_build(win_dir + "/" + exe + ".exe"):
		return false
	var win_zip := "%s/%s-%s-windows.zip" % [out_dir, exe, ver]
	if not _zip_dir(win_dir, exe, win_zip):
		return false

	var assets := PackedStringArray()
	for path in [win_zip, mac_zip]:
		assets.append_array(_split(path, int(cfg.split_mb) * 1048576))

	if not _git_cmd(["add", "-A"], "git add"):
		return false
	var msg := ["commit", "--allow-empty", "-m", "Release " + ver]
	if str(cfg.get("commit_trailer", "")) != "":  # attribution lines for the release commit
		msg.append_array(["-m", str(cfg.commit_trailer)])
	if not _git_cmd(msg, "git commit"):
		return false
	if not _git_cmd(["push", "-u", "origin", "HEAD:main"], "git push"):
		return false

	var exists: bool = int(_exec(_gh, ["release", "view", ver]).code) == 0
	var args: Array = []
	if exists:  # the release is already up: swap its files, leave its title and notes as they are
		args = ["release", "upload", ver, "--clobber"]
	else:
		args = ["release", "create", ver, "--target", "main", "--prerelease",
			"--title", "%s %s" % [cfg.title, ver], "--notes", _notes(ver, exe, assets)]
	args.append_array(Array(assets))
	var t0 := Time.get_ticks_msec()
	var r := _exec(_gh, args)
	if r.code != 0:
		_say("gh release %s failed:\n%s" % ["upload" if exists else "create", r.text])
		return false
	_say("%s %s in %.0f s: %s" % ["REPLACED THE FILES ON" if exists else "PUBLISHED", ver,
		(Time.get_ticks_msec() - t0) / 1000.0, r.text.strip_edges()])
	return true


func _load_config() -> Dictionary:
	var f := FileAccess.open(CONFIG, FileAccess.READ)
	if f == null:
		_say("missing " + CONFIG)
		return {}
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		_say(CONFIG + " is not valid JSON")
		return {}
	for k in ["repo", "visibility", "first_version", "title", "exe_name", "split_mb"]:
		if not d.has(k):
			_say(CONFIG + " missing key: " + k)
			return {}
	if not (str(d.visibility) in ["private", "public"]):
		_say("visibility must be private or public")
		return {}
	if _parse_version(str(d.first_version)).is_empty():
		_say("first_version must look like alpha2.1")
		return {}
	if int(d.split_mb) < 100 or int(d.split_mb) > 2000:
		_say("split_mb must be 100..2000")
		return {}
	return d


func _preflight() -> bool:
	var ok := true
	var v := Engine.get_version_info()
	var tdir := "%s/Godot/export_templates/%d.%d.%d.%s" % [OS.get_environment("APPDATA").replace("\\", "/"),
		v.major, v.minor, v.patch, v.status]
	for t in ["windows_release_x86_64.exe", "macos.zip"]:
		if not FileAccess.file_exists(tdir + "/" + t):
			_say("MISSING export template %s/%s (Editor > Manage Export Templates > Download)" % [tdir, t])
			ok = false
	# gh and git call each other by name, so make sure both install folders are on PATH (a Godot started
	# before they were installed doesn't see them).
	var path := OS.get_environment("PATH")
	for fb in [GIT_FALLBACK, GH_FALLBACK]:
		var dir: String = fb.get_base_dir().replace("/", "\\")
		if not (dir in path):
			path += ";" + dir
	OS.set_environment("PATH", path)
	_git = _find_tool("git", GIT_FALLBACK)
	_gh = _find_tool("gh", GH_FALLBACK)
	if _git == "":
		_say("MISSING Git - install from git-scm.com")
		ok = false
	if _gh == "":
		_say("MISSING GitHub CLI - install from cli.github.com, then run: gh auth login")
		ok = false
	elif _exec(_gh, ["auth", "status"]).code != 0:
		_say("GitHub CLI not logged in - run: gh auth login")
		ok = false
	return ok


func _find_tool(name: String, fallback: String) -> String:
	if _exec(name, ["--version"]).code == 0:
		return name
	if FileAccess.file_exists(fallback):
		return fallback
	return ""


# First run: git init, set a commit identity if none, create the GitHub repo as origin.
func _ensure_repo(cfg: Dictionary) -> bool:
	if not DirAccess.dir_exists_absolute(_root + "/.git"):
		if not _git_cmd(["init", "-b", "main"], "git init"):
			return false
	if _exec(_git, ["-C", _root, "config", "user.email"]).text.strip_edges() == "":
		var login: String = _exec(_gh, ["api", "user", "--jq", ".login"]).text.strip_edges()
		_exec(_git, ["-C", _root, "config", "user.name", login])
		_exec(_git, ["-C", _root, "config", "user.email", login + "@users.noreply.github.com"])
	_exec(_gh, ["auth", "setup-git"])
	if _exec(_git, ["-C", _root, "remote", "get-url", "origin"]).code != 0:
		var r := _exec(_gh, ["repo", "create", str(cfg.repo), "--" + str(cfg.visibility),
			"--source", _root, "--remote", "origin"])
		if r.code != 0:
			_say("gh repo create failed:\n" + r.text)
			return false
		_say("created GitHub repo: " + r.text.strip_edges())
	return true


# Highest alphaX.Y tag on GitHub + 0.1, or first_version when there is none.
func _next_version(first: String) -> String:
	var r := _exec(_git, ["-C", _root, "ls-remote", "--tags", "origin"])
	if r.code != 0 and r.text.strip_edges() != "":
		_say("could not read tags from GitHub:\n" + r.text)
		return ""
	var best := []
	for line in r.text.split("\n"):
		var p := _parse_version(line.get_slice("refs/tags/", 1).trim_suffix("^{}").strip_edges())
		if not p.is_empty() and (best.is_empty() or p[0] > best[0] or (p[0] == best[0] and p[1] > best[1])):
			best = p
	if best.is_empty():
		return first
	return "alpha%d.%d" % [best[0], best[1] + 1]


func _parse_version(s: String) -> Array:
	var re := RegEx.create_from_string("^alpha(\\d+)\\.(\\d+)$")
	var m := re.search(s)
	return [] if m == null else [int(m.get_string(1)), int(m.get_string(2))]


func _export(platform: String, path: String) -> bool:
	var preset := _preset_for(platform)
	if preset == "":
		_say("no %s preset in export_presets.cfg" % platform)
		return false
	return _godot(["--export-release", preset, path], "export " + platform)


func _preset_for(platform: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load("res://export_presets.cfg") != OK:
		return ""
	for section in cfg.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options") \
				and str(cfg.get_value(section, "platform", "")) == platform:
			return str(cfg.get_value(section, "name", ""))
	return ""


func _godot(extra: Array, what: String) -> bool:
	var args := ["--headless", "--path", _root]
	args.append_array(extra)
	var t0 := Time.get_ticks_msec()
	var r := _exec(OS.get_executable_path(), args)
	_say("%s: exit %d in %.0f s" % [what, r.code, (Time.get_ticks_msec() - t0) / 1000.0])
	for line in r.text.split("\n"):
		if "ERROR" in line:
			_say("  " + line.strip_edges())
	return r.code == 0


# Runs the built game for 600 frames. Exit code alone is NOT enough: a script that fails to compile still quits
# 0, which is how alpha3.1 shipped unplayable (EncounterSite used CarMesh, and the export leaves tools/ out).
# So the output is read too, and any script or load error fails the release.
func _smoke(exe_path: String) -> bool:
	var r := _exec(exe_path, ["--quit-after", "600"])
	var bad := PackedStringArray()
	for needle: String in ["SCRIPT ERROR", "Parse Error", "Compile Error", "Failed to load script",
			"Failed to instantiate", "Condition \"!script.is_valid()\""]:
		if r.text.contains(needle) and not bad.has(needle):
			bad.append(needle)
	_say("smoke test Windows build: exit %d%s" % [r.code, "" if bad.is_empty() else "  BROKEN: " + ", ".join(bad)])
	if bad.is_empty():
		return r.code == 0
	var shown := 0
	for line: String in r.text.split("\n"):
		if (line.contains("ERROR") or line.contains("Error")) and shown < 25:
			_say("    " + line.strip_edges())
			shown += 1
	return false


# The packaged game checks its own models (D-112): proves the Mixamo zombies really went into the .pck.
func _models_in_build(exe_path: String) -> bool:
	var r := _exec(exe_path, ["--headless", "--", "--check-models"])
	var ok: bool = r.text.contains("MODELS: OK")
	_say("models inside the build: %s" % ("OK" if ok else "NOT OK (exit %d)" % r.code))
	if not ok:
		for line: String in r.text.split("\n"):
			if line.contains("MODELS") or line.contains("missing") or line.contains("clips") or line.contains("ERROR"):
				_say("    " + line.strip_edges())
	return ok


func _zip_dir(dir: String, folder: String, zip_path: String) -> bool:
	var zip := ZIPPacker.new()
	if zip.open(zip_path) != OK:
		_say("zip: cannot open " + zip_path)
		return false
	for f in DirAccess.get_files_at(dir):
		var src := FileAccess.open(dir + "/" + f, FileAccess.READ)
		zip.start_file(folder + "/" + f)
		while src.get_position() < src.get_length():
			zip.write_file(src.get_buffer(CHUNK))
		zip.close_file()
	zip.close()
	_say("zip: %s %.0f MB" % [zip_path.get_file(), _mb(zip_path)])
	return true


# Files over the limit become name.001, name.002 ... (7-Zip / The Unarchiver open them directly). Returns asset paths.
func _split(path: String, limit: int) -> PackedStringArray:
	var src := FileAccess.open(path, FileAccess.READ)
	if src.get_length() <= limit:
		return PackedStringArray([path])
	var parts := PackedStringArray()
	while src.get_position() < src.get_length():
		var part := "%s.%03d" % [path, parts.size() + 1]
		var dst := FileAccess.open(part, FileAccess.WRITE)
		var written := 0
		while written < limit and src.get_position() < src.get_length():
			var buf := src.get_buffer(mini(CHUNK, limit - written))
			dst.store_buffer(buf)
			written += buf.size()
		dst.close()
		parts.append(part)
	src.close()
	DirAccess.remove_absolute(path)
	_say("split %s into %d parts" % [path.get_file(), parts.size()])
	return parts


func _notes(ver: String, exe: String, assets: PackedStringArray) -> String:
	var split := false
	for a in assets:
		if a.ends_with(".001"):
			split = true
	var n := "Alpha build %s.\n\n" % ver
	n += "**Windows:** unzip and run `%s.exe`.\n\n" % exe
	n += "**Mac:** unzip, then right-click `%s.app` > Open the first time (the app isn't notarized). " % exe
	n += "If macOS says it's damaged, run `xattr -cr ` followed by the app's path in Terminal.\n"
	if split:
		n += "\n**Split downloads:** download every `.001`, `.002` ... part into one folder and open the `.001` "
		n += "with 7-Zip (Windows) or The Unarchiver (Mac). Or join them first - Windows: "
		n += "`copy /b file.zip.001+file.zip.002 file.zip`, Mac: `cat file.zip.0* > file.zip`.\n"
	return n


func _git_cmd(args: Array, what: String) -> bool:
	var full := ["-C", _root]
	full.append_array(args)
	var r := _exec(_git, full)
	if r.code != 0:
		_say(what + " failed:\n" + r.text)
		return false
	return true


func _exec(cmd: String, args: Array) -> Dictionary:
	var out := []
	var code := OS.execute(cmd, args, out, true)
	return {"code": code, "text": "\n".join(PackedStringArray(out))}


func _touch(path: String) -> void:
	if not FileAccess.file_exists(path):
		FileAccess.open(path, FileAccess.WRITE).close()


func _mb(path: String) -> float:
	return FileAccess.open(path, FileAccess.READ).get_length() / 1048576.0


func _say(s: String) -> void:
	print("RELEASE: " + s)
	_log.append(s)


func _done() -> void:
	DirAccess.make_dir_recursive_absolute("res://tests/_look")
	var f := FileAccess.open("res://tests/_look/release_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	get_tree().quit()
