# FivePoisTest — checks the D-079 landmarks in a throwaway hosted world (player in god mode): Big Apple Fun Center,
# Merryman, Cope Stadium, the RV park and the country club. For each: the landmark is placed, its lot sits on the
# ground (the terrain under its flattened pad is at the landmark's height), the player stands on an inside floor, EVERY loot
# container opens and rolls (a table with empty entries may roll nothing), lair enemies near it are awake, perf at an
# inside spot (frame time, draw calls, triangles, VRAM), and screenshots into tests/_look/five_pois_<id>_<n>.png.
# Results: tests/_look/five_pois_result.txt (ends with the failure count).
# Depends on: scenes/main.tscn, SaveStore, LootDB, the landmark nodes (Loot_* children).
extends Node

const OUT_DIR := "res://tests/_look"
const FLOOR_Y := 0.15
# id: {ground: pad spot outside the buildings, stand: inside spot (dropped from 1.5 m), shots: [[cam, look], ...]}
# (all landmark-local)
const POIS := {
	"big_apple": {"ground": Vector3(60, 0, 70), "stand": Vector3(-13, 1.5, -34),
		"shots": [[Vector3(110, 60, 90), Vector3(30, 0, 10)], [Vector3(-38, 1.7, -17), Vector3(-38, 1, 10)],
			[Vector3(11, 1.7, -20), Vector3(-5, 1, -36)], [Vector3(125, 10, 105), Vector3(122, 0, 64)]]},
	"merryman": {"ground": Vector3(-46.5, 0, -30.5), "stand": Vector3(10, 1.5, 16),
		"shots": [[Vector3(55, 30, 60), Vector3(0, 4, 0)], [Vector3(20, 6.6, -2), Vector3(-15, 3, -2)],
			[Vector3(-12, 1.9, -2), Vector3(18, 3, -2)], [Vector3(-2, 1.7, 19), Vector3(20, 1.5, 15)]]},
	"cope_stadium": {"ground": Vector3(50, 0, -70), "stand": Vector3(0, 1.5, 0),
		"shots": [[Vector3(90, 70, 110), Vector3(-20, 0, 0)], [Vector3(0, 1.7, 0), Vector3(-60, 8, 0)],
			[Vector3(-63, 9.8, -10), Vector3(0, 0, 10)], [Vector3(0, 2, 30), Vector3(0, 9, 72)]]},
	"rv_park": {"ground": Vector3(-138, 0, 130), "stand": Vector3(-112, 1.5, 118),
		"shots": [[Vector3(150, 120, 150), Vector3(0, 0, 0)], [Vector3(25, 2, 5), Vector3(7.9, 1, -13.1)],
			[Vector3(-118, 1.7, 125), Vector3(-95, 1.2, 125)], [Vector3(-105, 2, 75), Vector3(-125, 0.5, 100)]]},
	"country_club": {"ground": Vector3(-45, 0, -44), "stand": Vector3(5, 1.5, -3),
		"shots": [[Vector3(70, 60, 100), Vector3(10, 0, 10)], [Vector3(10, 1.7, -3), Vector3(-10, 1, -12)],
			[Vector3(20, 2, -10), Vector3(40, -1, -28)], [Vector3(150, 30, 60), Vector3(450, 0, -10)]]},
}

var _log := PackedStringArray()
var _player: Node3D
var _fails := 0
var _cam: Camera3D


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz five pois")
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
	for id: String in POIS:
		var poi: Dictionary = POIS[id]
		var lm := get_tree().root.find_child(id, true, false) as Node3D
		_check("%s placed" % id, lm != null)
		if lm == null:
			continue
		var xf := lm.global_transform
		_player.global_position = xf * (poi.stand as Vector3)
		_player.velocity = Vector3.ZERO
		await get_tree().create_timer(4.0).timeout  # cells around it stream in, the player lands
		var local_y: float = (xf.affine_inverse() * _player.global_position).y
		_check("%s: player stands on the inside floor (local y %.2f)" % [id, local_y], absf(local_y - FLOOR_Y) < 0.35)
		var gy := _terrain_y(xf * (poi.ground as Vector3))
		_check("%s: lot sits on the ground (terrain pad at local y %.2f)" % [id, gy - xf.origin.y], absf(gy - xf.origin.y) < 0.35)
		var awake := 0
		for z in lairs.get_children():
			if "net_enemy" in z and z.net_active and z.global_position.distance_to(_player.global_position) < 60.0:
				awake += 1
		_say("  %s: %d lair markers, %d lair enemies awake within 60 m of the inside spot" % [id,
			lm.find_children(id + "_*", "Marker3D", false, false).size(), awake])
		await _loot(id, lm)
		_player.global_position = xf * (poi.stand as Vector3)
		_player.velocity = Vector3.ZERO
		await get_tree().create_timer(3.0).timeout
		var worst := 0.0
		for i in 120:
			await get_tree().process_frame
			worst = maxf(worst, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_say("perf in %s: frame %.1f ms (worst process %.1f ms), draw calls %d, triangles %dk, VRAM %d MB" % [id,
			1000.0 / maxf(Engine.get_frames_per_second(), 1.0), worst,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
		var i := 0
		for s: Array in poi.shots:
			_cam.make_current()
			_cam.global_position = xf * (s[0] as Vector3)
			_cam.look_at(xf * (s[1] as Vector3))
			await _shot("five_pois_%s_%d.png" % [id, i])
			i += 1
		_cam.clear_current()
	_finish(main)


# Height of the Terrain body under p (rays skip landmark geometry, trees and anything else on top).
func _terrain_y(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 40.0, p + Vector3.DOWN * 60.0)
	for i in 8:
		var hit := _player.get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			return INF
		if str(hit.collider.name) == "Terrain":
			return (hit.position as Vector3).y
		q.exclude = q.exclude + [hit.rid]
	return INF


# Every Loot_* container: stand on it (reach is checked on the host), open, count what rolled.
func _loot(id: String, lm: Node3D) -> void:
	var boxes := lm.find_children("Loot_*", "", false, false)
	var opened := 0
	var items := 0
	var bad := PackedStringArray()
	for box: Node3D in boxes:
		_player.global_position = box.global_position
		_player.velocity = Vector3.ZERO
		box.request_open()
		var table: Dictionary = LootDB.get_table(str(box.loot_table))
		var may_be_empty := false
		for e: Dictionary in table.get("entries", []):
			may_be_empty = may_be_empty or str(e.item) == ""
		if box.net_remaining > 0 or (box.net_remaining == 0 and may_be_empty):
			opened += 1
			items += maxi(box.net_remaining, 0)
		else:
			bad.append("%s (%s: %d)" % [box.name, box.loot_table, box.net_remaining])
		box.request_close()
		await get_tree().physics_frame
	_check("%s: %d/%d loot containers open and roll (%d items)%s" % [id, opened, boxes.size(), items,
		"" if bad.is_empty() else " - failed: " + ", ".join(bad)], bad.is_empty() and boxes.size() > 0)


func _finish(main: Node) -> void:
	_say("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/five_pois_result.txt", FileAccess.WRITE)
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
	print("FIVE: " + s)
	_log.append(s)
