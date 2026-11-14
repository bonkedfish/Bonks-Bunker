# DoorWalkTest — walks a player in through every outside door of the D-079 places and the Centennial pool, and up
# every deck ramp (the door-ramp fix). Doors come from the same data the builders use (LandmarkParts.outer_doors,
# CentennialPool.outer_doors, the pool's deck.ramps). For each: stand 3 m outside, walk straight in for 3 s; pass
# when the player gets >= 1 m past the outer face up on the inside floor (failures log rays at foot / knee / chest).
# Hosts a throwaway world (god mode).
# Results: tests/_look/door_walk_result.txt (ends with the failure count).
# Depends on: scenes/main.tscn, SaveStore, DataLoader, landmark_parts.gd, centennial_pool.gd, the landmark nodes.
extends Node

const Parts := preload("res://tools/landmarks/landmark_parts.gd")
const Pool := preload("res://tools/landmarks/centennial_pool.gd")
const OUT := "res://tests/_look/door_walk_result.txt"
const PLACES := ["big_apple", "merryman", "cope_stadium", "country_club", "rv_park", "centennial_pool"]

var _log := PackedStringArray()
var _fails := 0
var _me: Node3D


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz door walk")
	main._on_host_pressed()
	await get_tree().create_timer(4.0).timeout
	_me = get_tree().get_first_node_in_group("local_player")
	_me.health.damage_mult = 0.0
	var prompt := get_tree().get_first_node_in_group("name_prompt")
	if prompt and prompt.visible:
		prompt.submit("Door Tester")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for id: String in PLACES:
		var lm := get_tree().root.find_child(id, true, false) as Node3D
		if lm == null:
			_check(false, "%s placed" % id)
			continue
		var d := DataLoader.load_json("res://data/landmarks/%s.json" % id)
		var walks: Array = []  # [name, outside start (local xz), inward dir, outer face point, inside y]
		var doors: Array = Pool.outer_doors(d) if id == "centennial_pool" else Parts.outer_doors(d)
		for dr: Dictionary in doors:
			var at: Vector2 = dr.at
			walks.append(["door at (%.1f, %.1f)" % [at.x, at.y], at - dr.inward * 3.0, dr.inward, at, float(dr.inside_y)])
		if id == "centennial_pool":
			for r: Array in d.deck.ramps:
				var a := Vector2(r[0], r[1])
				var b := Vector2(r[2], r[3])
				var dir := (b - a).normalized()
				walks.append(["deck ramp to (%.1f, %.1f)" % [b.x, b.y], a - dir * 3.0, dir, b, float(d.dims.deck_y)])
		var xf := lm.global_transform
		var first: Array = walks[0]
		_me.global_position = xf * Vector3(first[1].x, 1.0, first[1].y)
		_me.velocity = Vector3.ZERO
		await get_tree().create_timer(4.0).timeout  # cells around it stream in
		for w: Array in walks:
			await _walk(id, xf, w)
	_log.append("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	get_tree().quit()


func _walk(id: String, xf: Transform3D, w: Array) -> void:
	var start: Vector2 = w[1]
	var dir: Vector2 = w[2]
	var face: Vector2 = w[3]
	var spot := xf * Vector3(start.x, 0.6, start.y)
	for i in 40:  # hold the player there until the ground under them has streamed in, then stand them on it
		_me.global_position = spot
		_me.velocity = Vector3.ZERO
		var g := _ray(spot + Vector3.UP * 2.5, spot + Vector3.DOWN * 6.0)
		if not g.is_empty():
			spot = (g.position as Vector3) + Vector3.UP * 0.1
			_me.global_position = spot
			break
		await get_tree().create_timer(0.1).timeout
	var gdir := xf.basis * Vector3(dir.x, 0, dir.y)
	_me.yaw = atan2(-gdir.x, -gdir.z)
	await get_tree().create_timer(0.5).timeout
	Input.action_press("move_forward")
	var made := false  # got >= 1 m past the outer face, up on the inside floor, at some point during the walk
	var t := 0.0
	while t < 3.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var p := xf.affine_inverse() * _me.global_position
		if (Vector2(p.x, p.z) - face).dot(dir) >= 1.0 and p.y >= float(w[4]) - 0.1:
			made = true
	Input.action_release("move_forward")
	await get_tree().create_timer(0.2).timeout
	var end := xf.affine_inverse() * _me.global_position
	var past := (Vector2(end.x, end.z) - face).dot(dir)
	var why := ""
	if not made:  # what stopped them: rays ahead at foot, knee and chest height
		for h: float in [0.1, 0.35, 1.0]:
			var from := _me.global_position + Vector3.UP * h
			var hit := _ray(from, from + gdir.normalized() * 1.5)
			why += "  ray@%.2f: %s" % [h, "clear" if hit.is_empty() else "%s at local %s" % [str(hit.collider.name),
				(xf.affine_inverse() * (hit.position as Vector3)).snapped(Vector3.ONE * 0.05)]]
	_check(made, "%s %s: ends %.1f m past the face, local y %.2f (end %s)%s" % [id, w[0], past, end.y,
		end.snapped(Vector3.ONE * 0.1), why])


func _ray(a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.exclude = [_me.get_rid()]
	return _me.get_world_3d().direct_space_state.intersect_ray(q)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	_log.append(("PASS " if ok else "FAIL ") + what)
	print("DOORS: " + _log[-1])
