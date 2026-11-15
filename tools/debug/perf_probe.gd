# PerfProbe — dev tool: finds what eats frame time. Loads an offline world, measures the average process time, then
# for each child of Main, of the HUD and of the local player turns off _process / _physics_process on that subtree
# for 40 frames and reports how much time dropped. Results: tests/_look/perf_probe.txt.
# Depends on: scenes/main.tscn.
extends Node

var _log := PackedStringArray()


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz perf")
	main.menu.play_offline.emit()
	await get_tree().create_timer(8.0).timeout
	var prompt := get_tree().get_first_node_in_group("name_prompt")
	if prompt and prompt.visible:
		prompt.submit("Bonk")
	await get_tree().create_timer(2.0).timeout
	var base := await _measure(90)
	_log.append("baseline: process %.2f ms, physics %.2f ms, fps %d" % [base.x, base.y, Engine.get_frames_per_second()])
	var groups: Array[Node] = []
	groups.append_array(main.get_children())
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		groups.append_array(hud.get_children())
	var me := get_tree().get_first_node_in_group("local_player")
	if me:
		groups.append_array(me.get_children())
	for n: Node in groups:
		var off: Array[Node] = []
		_collect(n, off)
		if off.is_empty():
			continue
		for x in off:
			x.set_process(false)
			x.set_physics_process(false)
		var t := await _measure(40)
		for x in off:
			x.set_process(true)
			x.set_physics_process(true)
		var gain := (base.x + base.y) - (t.x + t.y)
		if gain > 0.3:
			_log.append("%-40s saves %.2f ms (%d nodes)" % [str(n.get_path()).replace("/root/PerfProbe/", ""), gain, off.size()])
	SaveStore.delete(main.saves.world_slug)
	var f := FileAccess.open("res://tests/_look/perf_probe.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	get_tree().quit()


func _collect(n: Node, out: Array[Node]) -> void:
	if n.is_processing() or n.is_physics_processing():
		out.append(n)
	for c in n.get_children():
		_collect(c, out)


func _measure(frames: int) -> Vector2:
	var p := 0.0
	var ph := 0.0
	for i in frames:
		await get_tree().process_frame
		p += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		ph += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	return Vector2(p / frames, ph / frames)
