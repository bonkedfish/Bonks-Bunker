# BigAppleDoorCheck — dev check: can a player walk in through the Big Apple's front doors? Hosts a throwaway world,
# drops the player outside each doorway (landmark-local), walks them straight in for 3 s, and logs where they ended
# up plus whatever a knee-height ray from outside hits on the way in. Writes tests/_look/big_apple_doors.txt.
# Depends on: scenes/main.tscn, SaveStore, the "big_apple" landmark node.
extends Node

# [name, outside spot, walk direction] in landmark-local metres
const DOORS := [["main (front, x -12.5)", Vector3(-12.5, 0.6, -48.0), Vector3(0, 0, 1)],
	["bar (front, x -37)", Vector3(-37.0, 0.6, -48.5), Vector3(0, 0, 1)],
	["arcade side (front, x 2)", Vector3(2.0, 0.6, -45.0), Vector3(0, 0, 1)],
	["back (south, x 50.7)", Vector3(50.7, 0.6, 34.0), Vector3(0, 0, -1)],
	["annex (west, z 34.8)", Vector3(-39.0, 0.6, 34.8), Vector3(1, 0, 0)],
	["west (x -67, z 2)", Vector3(-70.0, 0.6, 2.0), Vector3(1, 0, 0)]]

var _log := PackedStringArray()


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz door check")
	main._on_host_pressed()
	await get_tree().create_timer(4.0).timeout
	var me: Node3D = get_tree().get_first_node_in_group("local_player")
	me.health.damage_mult = 0.0
	var prompt := get_tree().get_first_node_in_group("name_prompt")
	if prompt and prompt.visible:
		prompt.submit("Door Tester")
	var lm := get_tree().root.find_child("big_apple", true, false) as Node3D
	var xf := lm.global_transform
	me.global_position = xf * Vector3(-12.5, 0.6, -60.0)
	await get_tree().create_timer(4.0).timeout
	for d: Array in DOORS:
		var start := xf * (d[1] as Vector3)
		var dir := xf.basis * (d[2] as Vector3)
		var q := PhysicsRayQueryParameters3D.create(start + Vector3.UP * 0.3, start + Vector3.UP * 0.3 + dir * 8.0)
		q.exclude = [me.get_rid()]
		var hit := me.get_world_3d().direct_space_state.intersect_ray(q)
		var what := "nothing" if hit.is_empty() else "%s at %.1f m (local %s)" % [hit.collider.get_path(),
			start.distance_to(hit.position), (xf.affine_inverse() * (hit.position as Vector3)).snapped(Vector3.ONE * 0.1)]
		me.global_position = start
		me.velocity = Vector3.ZERO
		me.yaw = atan2(-dir.x, -dir.z)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		await get_tree().create_timer(0.5).timeout
		Input.action_press("move_forward")
		await get_tree().create_timer(3.0).timeout
		Input.action_release("move_forward")
		var end := xf.affine_inverse() * me.global_position
		_log.append("%s: walked from %s to %s; ray in hits %s" % [d[0], (d[1] as Vector3), end.snapped(Vector3.ONE * 0.1), what])
		print("DOOR: " + _log[-1])
	var f := FileAccess.open("res://tests/_look/big_apple_doors.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	get_tree().quit()
