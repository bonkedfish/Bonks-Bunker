# CreatorTest — the character creator (D-096).
# Pure: sanitize (junk, unknown keys, beards on women), random looks are valid, dress() gives outfit / hair /
# gear, every hat and extra resolves its colours.
# In game (offline world): the creator opens on load-in with a look filled in; the pickers change it; Play sends
# name + look to the host (net_look set, cleaned); the save keeps the look and gives it back; a lineup of looks
# (every hat and extra) is rendered for a visual check. Screenshots tests/_look/creator_*.png.
# Results: tests/_look/creator_result.txt (ends with the failure count).
# Depends on: scenes/main.tscn, AppearanceRules, CharacterAnimator, CharacterCreator (group "name_prompt").
extends Node

const OUT_DIR := "res://tests/_look"

var _log := PackedStringArray()
var _fails := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_pure()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz creator")
	main.menu.play_offline.emit()
	await get_tree().create_timer(5.0).timeout
	var me: Node3D = get_tree().get_first_node_in_group("local_player")
	var creator: Control = get_tree().get_first_node_in_group("name_prompt")
	_check(creator.visible and not (creator.look as Dictionary).is_empty(), "creator open on load-in with a look: %s" % creator.look)
	creator._step("body", 1)
	creator._step("hat", 1)
	creator._step("extra", 2)
	creator._step("shirt", 3)
	await get_tree().create_timer(0.6).timeout
	await _shot("creator_screen.png")
	var picked: Dictionary = creator.look.duplicate()
	creator.submit("Bonk")
	await get_tree().create_timer(0.4).timeout
	_check(me.net_name == "Bonk" and me.net_look == picked, "Play: host set the name and look (%s)" % me.net_look)
	me.submit_look("Bonk", {"body": "female", "beard": true, "hat": "crown", "skin": 99})
	_check(me.net_look.body == "female" and not me.net_look.beard and me.net_look.hat == "none" and int(me.net_look.skin) == 2,
		"host cleans a bad look (no beard on women, unknown hat, skin out of range)")
	me.submit_look("Bonk", picked)
	main.saves.host_save("test")
	var key: String = main.saves.key_of(multiplayer.get_unique_id())
	var entry: Dictionary = main.saves.world.players.get(key, {})
	me.net_look = AppearanceRules.default_look()
	main.saves._apply_player(me, key)
	_check(entry.get("look", {}) == picked and me.net_look == picked, "the save keeps the look and gives it back")
	await _lineup(me)
	_log.append("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/creator_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	get_tree().quit()


func _pure() -> void:
	var junk := AppearanceRules.sanitize({"body": "robot", "skin": "red", "hat": 7, "extra": "backpack", "zz": 1})
	_check(junk.body == "male" and int(junk.skin) == 2 and junk.hat == "none" and junk.extra == "backpack" and not junk.has("zz"),
		"sanitize: junk back to defaults, good keys kept, unknown keys dropped")
	_check(AppearanceRules.sanitize("nope") == AppearanceRules.default_look(), "sanitize: not a dictionary = default look")
	var rng := RandomNumberGenerator.new()
	rng.seed = 96
	var ok := true
	for i in 200:
		var l := AppearanceRules.random_look(rng)
		ok = ok and AppearanceRules.sanitize(l) == l
	_check(ok, "200 random looks are all valid")
	var all_ok := true
	for hat: String in AppearanceRules.choices("hat"):
		for extra: String in AppearanceRules.choices("extra"):
			var d := AppearanceRules.dress({"hat": hat, "extra": extra})
			for g: Dictionary in d.gear:
				all_ok = all_ok and typeof(g.color) == TYPE_ARRAY
	var dressed := AppearanceRules.dress({"body": "male", "hair": "long", "beard": true, "hat": "cap"})
	_check(all_ok and (dressed.hair as Array).size() == 3 and (dressed.gear as Array).size() == 2 and dressed.outfit.has("skin"),
		"dress: hair + beard + eyebrows, cap = 2 pieces, every hat / extra colour resolved")


# Six looks side by side in their own little lit world (no walls in the way): every hat and extra at least once.
func _lineup(_me: Node3D) -> void:
	var hats := AppearanceRules.choices("hat")
	var extras := AppearanceRules.choices("extra")
	var vp := SubViewport.new()
	vp.size = Vector2i(1400, 700)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.27, 0.3)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.0, 4.6)
	cam.fov = 40.0
	vp.add_child(cam)
	var nodes: Array[CharacterAnimator] = []
	for i in 6:
		var look := {"body": "male" if i % 2 == 0 else "female", "skin": i, "hair": AppearanceRules.choices("hair")[i % 6],
			"hair_color": i, "beard": i == 2, "shirt": i + 3, "pants": i, "shoes": 2, "hat": hats[i % hats.size()],
			"extra": extras[(i + 1) % extras.size()], "accent": 10 - i}
		var a := CharacterAnimator.new()
		vp.add_child(a)
		a.set_model(AppearanceRules.model_of(look), false, AppearanceRules.dress(look))
		a.position = Vector3((i - 2.5) * 0.9, 0, 0)
		nodes.append(a)
	for k in 20:
		await get_tree().process_frame
		for a in nodes:
			a.update(1.0 / 60.0, false, false, 100.0, false, false)
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR + "/creator_lineup_front.png"))
	for a in nodes:
		a.rotation.y = PI
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR + "/creator_lineup_back.png"))
	_log.append("shot creator_lineup_front.png / creator_lineup_back.png")
	vp.queue_free()


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR + "/" + file))
	_log.append("shot " + file)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	_log.append(("PASS " if ok else "FAIL ") + what)
	print("CREATOR: " + _log[-1])
