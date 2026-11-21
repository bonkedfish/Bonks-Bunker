# ModelCheck — "are the real models actually in this build?" (D-112). The Mixamo files are kept out of the public
# repo and every Mixamo model has a CC0 "fallback", so a build made without them still runs - with cartoon zombies,
# and nothing says so. A release must never ship that. check() takes every model that has a fallback, reports the
# ones whose own file or any of whose animation files can't be loaded here, then builds each one once (under
# `parent`) and fails it if fewer clips came through retargeting than its animation set lists.
# Used twice by tools/release/release.gd: in the editor before exporting (fast fail), and inside the packaged exe
# after exporting (`exe -- --check-models`: main.gd prints "MODELS: OK" or "MODELS: MISSING" + the list, then quits).
# Depends on: DataLoader, CharacterAnimator.
class_name ModelCheck
extends RefCounted


# Problems found; empty when every model with a fallback is really there and fully animated.
# models / anim_sets default to data/art/character_models.json (tests pass their own).
static func check(parent: Node, models := {}, anim_sets := {}) -> PackedStringArray:
	var data := DataLoader.load_json(CharacterAnimator.DATA_PATH)
	var use_data := models.is_empty()
	if use_data:
		models = data.get("models", {})
		anim_sets = data.get("anim_sets", {})
	var problems := PackedStringArray()
	for id: String in models:
		var def: Dictionary = models[id]
		if not def.has("fallback") or not def.has("path"):
			continue
		if not ResourceLoader.exists(str(def.path)):
			problems.append("%s: model file missing - %s" % [id, def.path])
			continue
		var files := {}
		if def.has("anim_set"):
			var anim_set: Dictionary = anim_sets.get(str(def.anim_set), {})
			files = (anim_set.get("files", {}) as Dictionary).duplicate()
			files.merge(def.get("anim_override", {}), true)
			var missing := 0
			for key: String in files:
				var path := "%s/%s" % [anim_set.get("dir", ""), files[key]]
				if not ResourceLoader.exists(path):
					problems.append("%s: animation '%s' missing - %s" % [id, key, path])
					missing += 1
			if missing > 0:
				continue
		if not use_data:
			continue  # a test's made-up model: nothing real to build
		var body := CharacterAnimator.new()
		parent.add_child(body)
		if not body.set_model(id):
			problems.append("%s: would not load" % id)
		elif not files.is_empty():
			var players := body.find_children("*", "AnimationPlayer", true, false)
			var got := (players[0] as AnimationPlayer).get_animation_list().size() if players.size() > 0 else 0
			if got < files.size():
				problems.append("%s: only %d of %d clips came through" % [id, got, files.size()])
		body.queue_free()
	return problems
