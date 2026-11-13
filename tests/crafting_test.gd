# CraftingTest — bunker workbench crafting (D-046 stage 3): RecipeDB loads + validates, CraftingRules.missing,
# then a hosted world: craft each recipe at the bunker workbench (ingredients taken, result given), refused when
# short or out of reach; opens the crafting window and screenshots it to tests/_look/crafting.png.
# Results to tests/_look/crafting_result.txt. Depends on: scenes/main.tscn, RecipeDB, CraftingRules, SaveStore.
extends Node

var _log := PackedStringArray()
var _fails := 0


func _ready() -> void:
	_check(RecipeDB.ids().size() == 5, "5 recipes load (%s)" % ", ".join(RecipeDB.ids()))
	var have := {"scrap_metal": 1}
	var miss := CraftingRules.missing(RecipeDB.get_recipe("taped_bat"), func(i: String) -> int: return int(have.get(i, 0)))
	_check(miss == {"scrap_metal": 2, "duct_tape": 1}, "missing lists the shortfall %s" % miss)

	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz craft")
	main._on_host_pressed()
	await get_tree().create_timer(4.0).timeout
	var me: Node3D = get_tree().get_first_node_in_group("local_player")
	var bench: Node3D = get_tree().get_first_node_in_group("workbenches")
	_check(bench != null, "workbench is in the bunker")
	if bench == null:
		_finish(main)
		return
	me.global_position = bench.global_position + Vector3(0, 0.1, -1.3)  # room side (the bench backs onto the south wall)
	me.velocity = Vector3.ZERO
	await get_tree().create_timer(0.5).timeout
	var inv: InventoryHolder = me.inventory
	var ammo0 := inv.count("ammo_9mm")
	bench.request_craft.rpc_id(1, "handload_9mm")  # no scrap yet
	await get_tree().physics_frame
	_check(inv.count("ammo_9mm") == ammo0, "refused without ingredients")
	inv.host_add("scrap_metal", 2)
	inv.host_add("duct_tape", 2)
	inv.host_add("wrench", 1)
	inv.host_add("car_battery", 1)
	bench.request_craft.rpc_id(1, "handload_9mm")
	await get_tree().physics_frame
	_check(inv.count("ammo_9mm") == ammo0 + 10 and inv.count("scrap_metal") == 0, "hand-loaded 10 rounds from 2 scrap")
	bench.request_craft.rpc_id(1, "scrap_wrench")
	bench.request_craft.rpc_id(1, "scrap_battery")
	await get_tree().physics_frame
	_check(inv.count("scrap_metal") == 5 and inv.count("wrench") == 0 and inv.count("car_battery") == 0, "broke down junk into 5 scrap")
	bench.request_craft.rpc_id(1, "taped_bat")
	bench.request_craft.rpc_id(1, "bandage_from_tape")
	await get_tree().physics_frame
	_check(inv.count("bat_baseball") >= 1 and inv.count("bandage") >= 1 and inv.count("duct_tape") == 0
		and inv.count("scrap_metal") == 2, "made a bat and a bandage")
	inv.host_add("duct_tape", 1)
	bench.global_position += Vector3(30, 0, 0)  # move the bench, not the player (the player would be inside the ground)
	var band := inv.count("bandage")
	bench.request_craft.rpc_id(1, "bandage_from_tape")
	await get_tree().physics_frame
	_check(inv.count("bandage") == band, "refused out of reach")
	bench.global_position -= Vector3(30, 0, 0)
	await get_tree().create_timer(0.5).timeout
	var ui := get_tree().get_first_node_in_group("crafting_ui")
	ui.open(bench)
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/_look/crafting.png")
	_check(ui.visible, "crafting window opens (player %.1f m from the bench)" % me.global_position.distance_to(bench.global_position))
	_finish(main)


func _finish(main: Node) -> void:
	_say("RESULT: %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	var f := FileAccess.open("res://tests/_look/crafting_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	await get_tree().create_timer(20.0).timeout
	get_tree().quit()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	_say(("ok   " if ok else "FAIL ") + what)


func _say(s: String) -> void:
	print("CRAFT: " + s)
	_log.append(s)
