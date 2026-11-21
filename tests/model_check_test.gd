# ModelCheckTest — ModelCheck (D-112) in the editor: the real models all pass, and a made-up model whose file is
# missing, or whose animation set points at a missing clip, is reported. Results: tests/_look/model_check.txt.
# Depends on: ModelCheck.
extends Node

var _log := PackedStringArray()
var _fails := 0


func _ready() -> void:
	var real := ModelCheck.check(self)
	_check(real.is_empty(), "every model with a fallback is really here and fully animated" + (
		"" if real.is_empty() else ":\n    " + "\n    ".join(real)))
	var fake_sets := {"s": {"dir": "res://assets/characters/mixamo/animations",
		"files": {"walk": "Zombie Walk.fbx", "nope": "No Such Clip.fbx"}}}
	var gone := ModelCheck.check(self, {"ghost": {"path": "res://nowhere/ghost.fbx", "fallback": "zombie_basic"}}, {})
	_check(gone.size() == 1 and gone[0].contains("model file missing"), "a missing model file is reported")
	var clip := ModelCheck.check(self, {"half": {"path": "res://assets/characters/mixamo/characters/Warzombie F Pedroso.fbx",
		"fallback": "zombie_basic", "anim_set": "s"}}, fake_sets)
	_check(clip.size() == 1 and clip[0].contains("'nope'"), "a missing animation file is reported")
	var plain := ModelCheck.check(self, {"cc0": {"path": "res://nowhere/x.glb"}}, {})
	_check(plain.is_empty(), "models without a fallback are not its business")
	_log.append("%d failure(s)" % _fails)
	DirAccess.make_dir_recursive_absolute("res://tests/_look")
	var f := FileAccess.open("res://tests/_look/model_check.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	await get_tree().process_frame
	get_tree().quit()


func _check(ok: bool, what: String) -> void:
	_log.append("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1
