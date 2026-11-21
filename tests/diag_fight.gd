# DiagFight — throwaway diagnostic: a raider vs a street zombie at the 21st St camp, logging what each one perceives.
# Results: tests/_look/diag_fight.txt.
extends Node

var _log := PackedStringArray()


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz diag")
	main._on_host_pressed()
	await get_tree().create_timer(5.0).timeout
	var prompt := get_tree().get_first_node_in_group("name_prompt")
	if prompt and prompt.visible:
		prompt.submit("Bonk")
	var me: Node3D = get_tree().get_first_node_in_group("local_player")
	me.health.damage_mult = 0.0
	var cf := get_tree().root.find_child("copperfields", true, false) as Node3D
	me.global_position = cf.global_transform * Vector3(0, 1.0, -60)
	await get_tree().create_timer(4.0).timeout
	var raiders: Array = []
	for z in get_tree().get_first_node_in_group("lair_director").get_children():
		if "net_enemy" in z and z.net_active and z.team == &"raiders" and not z.health.is_dead():
			raiders.append(z)
	var r: Node3D = null
	for x: Node3D in raiders:  # the same pick as downtown_test: the raider FARTHEST from the player
		if r == null or x.global_position.distance_to(me.global_position) > r.global_position.distance_to(me.global_position):
			r = x
	_log.append("raiders awake: %s" % str(raiders.map(func(x): return "%s %s %s %.0fm" % [x.name, x.net_enemy, str(x.global_position.round()), x.global_position.distance_to(me.global_position)])))
	var zd := get_tree().get_first_node_in_group("zombie_director")
	var z: Node3D = null
	for b in zd.get_children():
		if "net_active" in b and not b.net_active:
			z = b
			break
	_log.append("picked %s (type %s)" % [z.name, z.net_enemy])
	z.activate(r.global_position + r.global_basis.z * -4.0 + Vector3(0, 0.3, 0))
	var safe := get_tree().get_first_node_in_group("safe_zones")
	_log.append("raider %s at %s, zombie %s at %s, safe(r)=%s safe(z)=%s, frozen %s, paused %s" % [r.name, str(r.global_position.round()), z.name,
		str(z.global_position.round()), str(safe.contains(r.global_position)), str(safe.contains(z.global_position)), str(load("res://scripts/ai/zombie.gd").frozen), str(get_tree().paused)])
	for i in 8:
		await get_tree().create_timer(1.0).timeout
		_log.append("t=%d: zombie sees %s target %s state %d hp %.0f active %s | raider sees %s target %s state %d hp %.0f | d %.1f" % [i,
			str(z.get("_sees_target")), str(z.get("_target").name if z.get("_target") else "-"), z.brain.state, z.health.current, str(z.net_active),
			str(r.get("_sees_target")), str(r.get("_target").name if r.get("_target") else "-"), r.brain.state, r.health.current,
			z.global_position.distance_to(r.global_position)])
	var f := FileAccess.open("res://tests/_look/diag_fight.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	get_tree().quit()
