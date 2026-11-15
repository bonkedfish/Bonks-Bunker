# UnstickTest — D-091 / D-092 checks in game (offline world): falling through the map for fall_rescue_seconds puts
# the player back on the last solid ground; the pause menu's "Respawn at Bunker" button moves a far-away player back
# to their spawn; the player gets a colour (PlayerColors) that the minimap uses. Results:
# tests/_look/unstick_result.txt (ends with the failure count). Depends on: scenes/main.tscn, Player, PauseMenu,
# PlayerColors.
extends Node

const OUT_DIR := "res://tests/_look"

var _log := PackedStringArray()
var _fails := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz unstick")
	main.menu.play_offline.emit()
	await get_tree().create_timer(5.0).timeout
	var me: Node3D = get_tree().get_first_node_in_group("local_player")
	var prompt := get_tree().get_first_node_in_group("name_prompt")
	if prompt and prompt.visible:
		prompt.submit("Bonk")
	me.health.damage_mult = 0.0
	await get_tree().create_timer(2.0).timeout  # stand still: the safe spot is recorded
	var safe: Vector3 = me.global_position
	me.global_position = safe + Vector3(0, -40, 0)  # under the map: nothing to land on
	var t0 := Time.get_ticks_msec()
	var rescued := false
	while Time.get_ticks_msec() - t0 < 14000:
		await get_tree().physics_frame
		if me.global_position.distance_to(safe) < 3.0:
			rescued = true
			break
	_check(rescued, "fell under the map: back on solid ground after %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	var spawn: Vector3 = me._spawn_point
	me.global_position = spawn + Vector3(150, 5, 150)
	await get_tree().create_timer(1.0).timeout
	var pause := get_tree().get_first_node_in_group("pause_menu")
	var btn: Button = null
	if pause:
		for b in pause.find_children("*", "Button", true, false):
			if (b as Button).text == "Respawn at Bunker":
				btn = b
	_check(btn != null, "pause menu has 'Respawn at Bunker'")
	if btn:
		btn.pressed.emit()
	await get_tree().create_timer(0.5).timeout
	_check(me.global_position.distance_to(spawn) < 2.0, "Respawn at Bunker: %.1f m from the spawn" % me.global_position.distance_to(spawn))
	var col := PlayerColors.color(int(me.net_color))
	_check(col != Color(0.85, 0.85, 0.85) and PlayerColors.pick([int(me.net_color)]) != int(me.net_color),
		"player colour %d (%s); the next player gets a different one" % [int(me.net_color), col.to_html(false)])
	_log.append("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/unstick_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	get_tree().quit()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	_log.append(("PASS " if ok else "FAIL ") + what)
	print("UNSTICK: " + _log[-1])
