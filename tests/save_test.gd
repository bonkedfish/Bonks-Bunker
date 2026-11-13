# SaveTest — real level, real files: host a fresh world, change things (loot a crate, move, get hurt,
# move Bonk), save, scramble all of it, reload the save from disk and check everything came back.
# Deletes its world file at the end. Run this scene directly.
# Depends on: scenes/main.tscn, Net autoload, SaveDirector ("Saves"), SaveStore.
extends Node

const WORLD := "zz save test"

var _failures := 0


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new(WORLD)
	main._on_host_pressed()
	await get_tree().create_timer(3.0).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var saves: Node = main.saves
	var slug: String = saves.world_slug
	var me: Node3D = get_tree().get_first_node_in_group("local_player")
	var bonk: Node3D = get_tree().get_first_node_in_group("bonk")
	var crate: Node = main.get_node("Landmarks/bonk_bunker/Loot/AmmoCrate")
	var shelf: Node = main.get_node("Landmarks/bonk_bunker/Loot/Toolbox")
	_check("new world opened (%s)" % slug, slug.begins_with("zz_save_test"))

	# Change the world.
	me.global_position = crate.global_position + Vector3(-1.2, 0.1, 0)
	await get_tree().create_timer(0.3).timeout
	crate.request_open.rpc_id(1)
	await get_tree().create_timer(0.3).timeout
	crate.request_take_all.rpc_id(1)
	await get_tree().create_timer(0.3).timeout
	get_tree().get_first_node_in_group("loot_ui").close()
	me.health.current = 42.0
	var spot: Vector3 = me.global_position
	var items: Dictionary = me.inventory.net_items.duplicate()
	bonk.global_position = spot + Vector3(1.5, 0, 0)
	bonk.health.current = 99.0
	await get_tree().create_timer(0.2).timeout
	var bonk_spot: Vector3 = bonk.global_position
	_check("save writes the file", saves.host_save("test") and FileAccess.file_exists("user://saves/%s.json" % slug))
	_check("world shows in the list", SaveStore.list_worlds().any(func(w: Dictionary) -> bool: return w.slug == slug))

	# Scramble everything, then load the save back from disk.
	me.global_position = Vector3(-44, -3.9, -2.6)
	me.inventory.net_items = {"scrap_metal": 1}
	me.health.current = 100.0
	bonk.global_position = Vector3(-42, -3.9, 0)
	crate.host_load_state({"ammo_9mm": 99})
	_check("re-open from disk", saves.host_open_world(slug, ""))
	saves.host_start()
	saves.host_player_spawned(me)
	await get_tree().create_timer(0.3).timeout
	_check("player back where they saved (%s vs %s)" % [me.global_position.snapped(Vector3.ONE * 0.1), spot.snapped(Vector3.ONE * 0.1)],
		me.global_position.distance_to(spot) < 0.3)
	_check("player items back (%s)" % me.inventory.net_items, me.inventory.net_items == items)
	_check("player health back (%.0f)" % me.health.current, is_equal_approx(me.health.current, 42.0))
	_check("looted crate stays empty (left %d)" % crate.net_remaining, crate.net_remaining == 0)
	_check("unopened toolbox still unrolled", shelf.host_save_state() == null)
	_check("bonk back (%.1f m off, HP %.0f)" % [bonk.global_position.distance_to(bonk_spot), bonk.health.current],
		bonk.global_position.distance_to(bonk_spot) < 1.0 and is_equal_approx(bonk.health.current, 99.0))

	SaveStore.delete(slug)
	_check("test world deleted", not FileAccess.file_exists("user://saves/%s.json" % slug))
	print("SAVE TESTS: %s (%d failures)" % ["ALL PASS" if _failures == 0 else "FAILED", _failures])
	await get_tree().create_timer(20.0).timeout
	get_tree().quit()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print(("PASS  " if ok else "FAIL  ") + label)
