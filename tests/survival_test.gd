# SurvivalTest — checks hunger/thirst and timed item use on a hosted throwaway world (D-046) and prints
# SURV PASS/FAIL lines: low needs halve a bandage's heal, beans fill hunger, a damaging hit cancels a use,
# an empty meter hurts, and needs survive a save round trip. Run this scene directly.
# Depends on: scenes/main.tscn, PlayerNeeds, ItemUse, SaveFormat, SaveStore.
extends Node

var _fails := 0


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz survival")
	main._on_host_pressed()
	await get_tree().create_timer(4.0).timeout
	var zd := get_tree().get_first_node_in_group("zombie_director")
	zd.set_physics_process(false)
	for z in zd.get_children():
		if z.net_active:
			z.deactivate()
	var me: Node = get_tree().get_first_node_in_group("local_player")
	me.inventory.host_add("bandage", 2)
	me.inventory.host_add("canned_beans", 1)

	me.needs.host_set(Vector2(20.0, 80.0))  # hungry -> low
	me.health.current = 50.0
	me.item_use.request("bandage")
	await get_tree().create_timer(2.5).timeout
	_check("low needs: bandage heals 12.5 not 25", absf(me.health.current - 62.5) < 0.6, "hp %.1f" % me.health.current)
	_check("bandage used up", me.inventory.count("bandage") == 1, "bandages %d" % me.inventory.count("bandage"))

	me.item_use.request("canned_beans")
	await get_tree().create_timer(2.0).timeout
	_check("beans add 35 food", absf(me.needs.net_hunger - 55.0) < 1.0, "hunger %.1f" % me.needs.net_hunger)

	me.item_use.request("bandage")
	await get_tree().create_timer(0.5).timeout
	me.health.apply_damage(5.0, 0)
	await get_tree().create_timer(0.1).timeout
	_check("a hit cancels the use", me.item_use.net_use_item == "", "using '%s'" % me.item_use.net_use_item)
	_check("cancelled bandage not spent", me.inventory.count("bandage") == 1, "bandages %d" % me.inventory.count("bandage"))

	me.needs.host_set(Vector2(0.0, 80.0))
	var hp: float = me.health.current
	await get_tree().create_timer(4.2).timeout
	_check("empty meter hurts ~0.5/s", hp - me.health.current >= 1.0 and hp - me.health.current <= 3.0, "lost %.1f" % (hp - me.health.current))

	var entry := SaveFormat.player_entry(Vector3.ZERO, 50.0, {}, [], Vector2(33.0, 66.0))
	var back := SaveFormat.needs_of(JSON.parse_string(JSON.stringify(entry)), 100.0)
	_check("needs survive save JSON", back.is_equal_approx(Vector2(33.0, 66.0)), str(back))
	_check("old saves load full", SaveFormat.needs_of({}, 100.0) == Vector2(100, 100), "")

	print("SURV: %s (%d failed)" % ["ALL PASS" if _fails == 0 else "FAILURES", _fails])
	SaveStore.delete(main.saves.world_slug)
	await get_tree().create_timer(20.0).timeout
	get_tree().quit()


func _check(label: String, ok: bool, detail: String) -> void:
	if not ok:
		_fails += 1
	print("SURV %s: %s  %s" % ["PASS" if ok else "FAIL", label, detail])
