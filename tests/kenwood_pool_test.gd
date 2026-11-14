# KenwoodPoolTest — checks the D-078 landmarks in a throwaway hosted world (player in god mode): Kenwood Elementary and
# the drained Centennial pool are placed, the player stands on their floors (school floor, pool deep end - not through
# the terrain hole), lair shamblers wake and walk the navmesh, a loot container in each rolls items, screenshots into
# res://tests/_look/d078_*.png, and perf (frame time, draw calls, VRAM) inside each.
# Results: tests/_look/kenwood_pool_result.txt. Depends on: scenes/main.tscn, SaveStore, LairDirector, the landmark nodes.
extends Node

const OUT_DIR := "res://tests/_look"
const SHOTS := {
	# id: [[cam, look], ...] in landmark-local coordinates
	"kenwood": [[Vector3(70, 45, 80), Vector3(0, 0, -25)], [Vector3(-30, 1.8, -20.75), Vector3(10, 1.5, -20.75)],
		[Vector3(14, 4, -30), Vector3(45, 1, -12)], [Vector3(8, 1.8, -77), Vector3(-1, 1, -70)], [Vector3(-3, 1.8, 40), Vector3(-3, 2, 30)]],
	"centennial_pool": [[Vector3(30, 22, 38), Vector3(0, -1, -5)], [Vector3(-8, 1.8, 12), Vector3(2, -1.5, -12)],
		[Vector3(0, 0.1, -13.5), Vector3(-4, 0.5, 10)], [Vector3(-9, 2, 40), Vector3(-9, 1.5, 28)]],
}
# id: [floor spot (local), expected floor y (local), loot container, perf spot (local)]
const STANDS := {
	"kenwood": [Vector3(-3.5, 1.0, -60), 0.12, "Loot_nurse_cabinet", Vector3(-15, 1.0, -20.75)],
	"centennial_pool": [Vector3(0, -0.6, -12), -1.71, "Loot_first_aid", Vector3(15, 1.0, -18)],
}

var _log := PackedStringArray()
var _player: Node3D
var _fails := 0
var _cam: Camera3D


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz d078")
	main._on_host_pressed()
	await get_tree().create_timer(4.0).timeout
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for n: Node in get_tree().get_nodes_in_group("players"):
		if "water" in n:
			_player = n
	_player.health.damage_mult = 0.0
	_cam = Camera3D.new()
	_cam.fov = 75.0
	add_child(_cam)
	var lairs := get_tree().get_first_node_in_group("lair_director")
	for id: String in SHOTS:
		var lm := get_tree().root.find_child(id, true, false) as Node3D
		_check("%s placed (%s)" % [id, lm.global_position.snapped(Vector3.ONE * 0.1) if lm else "missing"], lm != null)
		if lm == null:
			continue
		_say("  %s: %d loot, %d spawn markers" % [id, lm.find_children("Loot_*", "", false, false).size(),
			lm.find_children(id + "_*", "Marker3D", false, false).size()])
		var st: Array = STANDS[id]
		_player.global_position = lm.global_transform * (st[0] as Vector3)
		_player.velocity = Vector3.ZERO
		await get_tree().create_timer(3.0).timeout
		var local_y: float = (lm.global_transform.affine_inverse() * _player.global_position).y
		_check("%s: player stands on the floor (local y %.2f, floor %.2f)" % [id, local_y, st[1]], absf(local_y - float(st[1])) < 0.35)
		_player.global_position = lm.global_transform * (st[3] as Vector3)  # step back so they have to walk to us
		_player.velocity = Vector3.ZERO
		await get_tree().create_timer(1.0).timeout
		var movers := {}
		for z in lairs.get_children():
			if "net_enemy" in z and z.net_active and z.global_position.distance_to(lm.global_position) < 110.0:
				movers[z] = z.global_position
		_check("%s: %d lair shamblers awake" % [id, movers.size()], movers.size() > 0)
		await get_tree().create_timer(4.0).timeout
		var moved := 0
		for z: Node3D in movers:
			if z.net_active and z.global_position.distance_to(movers[z]) > 0.5:
				moved += 1
			_say("    %s %s: active %s, hp %d, state %d, local %s -> %s" % [z.name, z.get_meta("spawn_key", ""), z.net_active,
				z.health.current, z.brain.state, (lm.global_transform.affine_inverse() * (movers[z] as Vector3)).snapped(Vector3.ONE * 0.1),
				(lm.global_transform.affine_inverse() * z.global_position).snapped(Vector3.ONE * 0.1)])
		_check("%s: %d of %d shamblers walked the navmesh" % [id, moved, movers.size()], moved > 0)
		var box := lm.get_node_or_null(str(st[2]))
		_check("%s: %s exists" % [id, st[2]], box != null)
		if box:
			var toward: Vector3 = lm.global_position - box.global_position  # 1 m from the box, into its room
			_player.global_position = box.global_position + Vector3(toward.x, 0, toward.z).normalized() + Vector3(0, 0.3, 0)
			await get_tree().create_timer(0.5).timeout
			box.request_open()
			await get_tree().create_timer(0.3).timeout
			_check("%s: %s rolled %d items" % [id, st[2], box.net_remaining], box.net_remaining > 0)
			box.request_close()
		_player.global_position = lm.global_transform * (st[3] as Vector3)
		_player.velocity = Vector3.ZERO
		await get_tree().create_timer(4.0).timeout
		var worst := 0.0
		for i in 120:
			await get_tree().process_frame
			worst = maxf(worst, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_say("perf in %s: frame %.1f ms (worst process %.1f ms), draw calls %d, VRAM %d MB, lair active %d" % [id,
			1000.0 / maxf(Engine.get_frames_per_second(), 1.0), worst,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, lairs.active_count])
		var i := 0
		for s: Array in SHOTS[id]:
			_cam.make_current()
			_cam.global_position = lm.global_transform * (s[0] as Vector3)
			_cam.look_at(lm.global_transform * (s[1] as Vector3))
			await _shot("d078_%s_%d.png" % [id, i])
			i += 1
		_cam.clear_current()
	_finish(main)


func _finish(main: Node) -> void:
	_say("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/kenwood_pool_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SaveStore.delete(main.saves.world_slug)
	await get_tree().create_timer(2.0).timeout
	get_tree().quit()


func _shot(file: String) -> void:
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT_DIR + "/" + file)
	_say("shot " + file)


func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	_say(("PASS " if ok else "FAIL ") + what)


func _say(s: String) -> void:
	print("D078: " + s)
	_log.append(s)
