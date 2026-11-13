# DropsTest — world drops (D-046 stage 2): pure DropRules checks, then a hosted world: drop one / a whole stack,
# per-cell cap (oldest removed), pick up, save/load round trip and SaveFormat.drops_of cleaning; screenshot of the
# pile at tests/_look/drops.png. Results to tests/_look/drops_result.txt. Depends on: scenes/main.tscn, WorldDrops,
# DropRules, SaveFormat, SaveStore.
extends Node

var _log := PackedStringArray()
var _fails := 0


func _ready() -> void:
	_check(DropRules.over_cap([5, 1, 3], 5).is_empty(), "under cap removes nothing")
	_check(DropRules.over_cap([7, 2, 9, 4], 2) == [2, 4], "over cap removes the oldest")
	_check(DropRules.drop_count(10, 1) == 1 and DropRules.drop_count(10, 0) == 10 and DropRules.drop_count(0, 3) == 0
		and DropRules.drop_count(2, 5) == 2, "drop counts")

	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz drops")
	main._on_host_pressed()
	await get_tree().create_timer(4.0).timeout
	var me: Node3D = get_tree().get_first_node_in_group("local_player")
	var drops: WorldDrops = get_tree().get_first_node_in_group("world_drops")
	var start: int = drops.drops.size()
	me.inventory.host_add("bandage", 30)
	me.inventory.host_add("canned_beans", 4)
	drops.request_drop.rpc_id(1, "bandage", 1)
	drops.request_drop.rpc_id(1, "canned_beans", 0)
	drops.request_drop.rpc_id(1, "car_battery", 1)  # not owned: refused
	await get_tree().physics_frame
	_check(me.inventory.count("bandage") == 29 and me.inventory.count("canned_beans") == 0, "inventory lost what was dropped")
	_check(drops.drops.size() == start + 2, "two drops in the world (got %d)" % (drops.drops.size() - start))
	var beans_id := 0
	for id: int in drops.drops:
		if drops.drops[id][0] == "canned_beans":
			beans_id = id
	_check(drops.display_name(beans_id) == "Canned Beans x4", "name shown: '%s'" % drops.display_name(beans_id))

	for i in 25:
		drops.request_drop.rpc_id(1, "bandage", 1)
	await get_tree().physics_frame
	_check(drops.drops.size() == 20, "per-cell cap keeps 20 (got %d)" % drops.drops.size())
	_check(not drops.drops.has(beans_id), "oldest (the beans) removed by the cap")

	me.inventory.host_add("pistol_9mm", 1)
	me.inventory.host_add("canned_beans", 2)
	for item: String in ["pistol_9mm", "canned_beans", "ammo_9mm"]:
		drops.request_drop.rpc_id(1, item, 1)
	await get_tree().physics_frame
	var ids: Array = drops.drops.keys()
	ids.sort()
	var newest: int = ids[-1]
	drops.request_pickup.rpc_id(1, newest)
	await get_tree().physics_frame
	_check(not drops.drops.has(newest), "picked up the newest drop")
	me.global_position += Vector3(40, 0, 0)
	var far_id: int = ids[0]
	drops.request_pickup.rpc_id(1, far_id)
	await get_tree().physics_frame
	_check(drops.drops.has(far_id), "pickup out of reach refused")
	me.global_position -= Vector3(40, 0, 0)

	var saved: Array = drops.host_save_state()
	for id: int in drops.drops.keys():
		drops._remove.rpc(id)
	await get_tree().physics_frame
	drops.host_load_state(SaveFormat.drops_of({"drops": saved + [["no_such_item", 1, 0, 0, 0], ["bandage", -2, 0, 0, 0], "junk"]}))
	await get_tree().physics_frame
	_check(drops.drops.size() == saved.size(), "save/load round trip keeps %d drops, bad entries dropped" % saved.size())

	var cam := Camera3D.new()
	add_child(cam)
	var d0: Array = drops.drops.values()[0]
	cam.global_position = d0[2] + Vector3(0.9, 1.3, 0.9)
	cam.look_at(d0[2])
	cam.make_current()
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/_look/drops.png")
	_say("RESULT: %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	var f := FileAccess.open("res://tests/_look/drops_result.txt", FileAccess.WRITE)
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
	print("DROPS: " + s)
	_log.append(s)
