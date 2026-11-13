# DowntownTest — checks the downtown bars + raiders (D-059..D-062): hosts a throwaway world (player in god mode),
# checks the four bar landmarks are placed, screenshots each one (outside, ground floor, basement/upstairs) into
# res://tests/_look/bar_<id>_*.png, checks raiders wake at Copperfields and walk the navmesh, that a raider and a
# zombie fight each other, the Last Call quest (scout -> raider kills counted -> Copperhead in the Pit, enrage, death,
# drops, reward), opens Copperhead's strongbox, and reports perf at the 21st St camp.
# Results: tests/_look/downtown_result.txt. Depends on: scenes/main.tscn, SaveStore, QuestRules, LairDirector,
# ZombieDirector, WorldDrops, the bar landmark nodes.
extends Node

const OUT_DIR := "res://tests/_look"
const BARS := {
	# id: [outside cam, outside look, ground cam, ground look, second cam, second look]  (bar-local coordinates)
	"copperfields": [Vector3(6, 3, -30), Vector3(0, 4, 0), Vector3(-1, 1.7, -9.5), Vector3(-2, 1.0, 6), Vector3(8, -1.5, -9), Vector3(-2, -2.6, -3)],
	"brix": [Vector3(-4, 3, -28), Vector3(0, 4, 0), Vector3(-3, 1.7, -9.5), Vector3(0, 1.0, 6), Vector3(0, 6.1, 3), Vector3(0, 5.2, -10)],
	"the_other_side": [Vector3(4, 3, -26), Vector3(0, 4, 0), Vector3(3, 1.7, -10.5), Vector3(-2, 1.0, 6), Vector3(0, -1.5, -10), Vector3(0, -2.6, 8)],
	"gillies": [Vector3(5, 3, -30), Vector3(0, 4, 0), Vector3(0, 1.7, -11.5), Vector3(0, 1.0, 10), Vector3(-6, 6.1, 2), Vector3(2, 5.2, -12)],
}

var _log := PackedStringArray()
var _player: Node3D
var _fails := 0
var _q: Node
var _cam: Camera3D


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz downtown")
	main._on_host_pressed()
	await get_tree().create_timer(4.0).timeout
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for n: Node in get_tree().get_nodes_in_group("players"):
		if "water" in n:
			_player = n
	_player.health.damage_mult = 0.0
	_q = get_tree().get_first_node_in_group("quests")
	var defs := QuestRules.defs()
	_check("Last Call active from the start", QuestRules.status(defs.sq_last_call, _q.flags) == QuestRules.Status.ACTIVE)
	_cam = Camera3D.new()
	_cam.fov = 75.0
	add_child(_cam)
	var bars := {}
	for id: String in BARS:
		var b := get_tree().root.find_child(id, true, false) as Node3D
		bars[id] = b
		_check("%s placed (%s)" % [id, b.global_position.snapped(Vector3.ONE * 0.1) if b else "missing"], b != null)
		if b == null:
			continue
		_say("  %s: %d loot, %d raider spawns" % [id, b.find_children("Loot_*", "", false, false).size(),
			b.find_children(id + "_*", "Marker3D", false, false).size()])
		var v: Array = BARS[id]
		for i in 3:
			var cam_l: Vector3 = v[i * 2]
			_player.global_position = b.global_transform * (cam_l + Vector3(0, -1.0 if i > 0 else -2.0, -1.5 if i > 0 else -4.0))
			_player.velocity = Vector3.ZERO
			await get_tree().create_timer(2.5).timeout
			_cam.make_current()
			_cam.global_position = b.global_transform * cam_l
			_cam.look_at(b.global_transform * (v[i * 2 + 1] as Vector3))
			await _shot("bar_%s_%s.png" % [id, ["outside", "ground", "second"][i]])
		_cam.clear_current()
	var cf: Node3D = bars.get("copperfields")
	if cf == null:
		_finish(main)
		return
	var lairs := get_tree().get_first_node_in_group("lair_director")
	# Scout the barricade (quest objective 1).
	_player.global_position = cf.global_transform * Vector3(27, 1.0, -118)
	await get_tree().create_timer(4.0).timeout
	_check("scouted the barricade -> lc_scouted", QuestRules.flag_met(_q.flags, "lc_scouted"))
	# Raiders vs a zombie at the 21st St camp, player out of the way.
	_player.global_position = cf.global_transform * Vector3(0, 1.0, -60)
	await get_tree().create_timer(4.0).timeout
	var raiders := _raiders()
	_check("raiders awake near the camp: %d" % raiders.size(), raiders.size() > 0)
	var zd := get_tree().get_first_node_in_group("zombie_director")
	var zombie: Node3D = null
	var near_raider: Node3D = null
	for r: Node3D in raiders:
		if near_raider == null or r.global_position.distance_to(_player.global_position) > near_raider.global_position.distance_to(_player.global_position):
			near_raider = r
	for z in zd.get_children():
		if not z.net_active:
			zombie = z
			break
	if zombie and near_raider:
		zombie.activate(near_raider.global_position + near_raider.global_basis.z * -4.0 + Vector3(0, 0.3, 0))
		var zh: float = zombie.health.current
		var rh: float = near_raider.health.current
		await get_tree().create_timer(8.0).timeout
		_check("raider and zombie fought (zombie HP %d -> %d, raider HP %d -> %d)" % [zh, zombie.health.current, rh, near_raider.health.current],
			zombie.health.current < zh or not zombie.net_active or near_raider.health.current < rh)
		if zombie.net_active:
			zombie.deactivate()
	# Raider kills count for Last Call.
	var k0: int = int(_q.flags.get("kills_raider", 0))
	raiders = _raiders()
	for r: Node3D in raiders:
		r.health.apply_damage(r.health.max_health, 1)
	await get_tree().create_timer(1.0).timeout
	_check("killed %d raiders -> kills_raider %d -> %d" % [raiders.size(), k0, int(_q.flags.get("kills_raider", 0))],
		int(_q.flags.get("kills_raider", 0)) == k0 + raiders.size())
	while int(_q.flags.get("kills_raider", 0)) < 12:
		_q.host_add_count("kills_raider")
	# Down into the Pit.
	_player.global_position = cf.global_transform * Vector3(-2, -3.0, -9.5)
	_player.velocity = Vector3.ZERO
	await get_tree().create_timer(3.0).timeout
	var boss: Node3D = null
	for b in get_tree().get_nodes_in_group("bosses"):
		if b.net_enemy == "copperhead":
			boss = b
	_check("Copperhead spawned in the Pit", boss != null)
	var mover: Node3D = null
	var start := Vector3.ZERO
	for r: Node3D in _raiders():
		if r != boss and r.global_position.y < cf.global_position.y - 1.0:
			mover = r
			start = r.global_position
	await get_tree().create_timer(3.0).timeout
	if mover:
		_check("a basement raider moves on the navmesh (%.1f m in 3 s)" % mover.global_position.distance_to(start),
			mover.global_position.distance_to(start) > 0.5)
	if boss:
		_cam.make_current()
		_cam.global_position = cf.global_transform * Vector3(6, -1.4, -9.5)
		_cam.look_at(boss.global_position + Vector3(0, 1.2, 0))
		await _shot("bar_copperhead.png")
		_cam.clear_current()
		boss.health.apply_damage(boss.health.max_health * 0.6, 1)
		await get_tree().create_timer(0.5).timeout
		_check("Copperhead enrages below half", boss._enraged)
		var ammo0: int = _player.inventory.count("ammo_9mm")
		boss.health.apply_damage(boss.health.max_health, 1)
		await get_tree().create_timer(1.5).timeout
		_check("boss_copperhead_dead set", QuestRules.flag_met(_q.flags, "boss_copperhead_dead"))
		_check("Last Call done -> reward ammo %d -> %d" % [ammo0, _player.inventory.count("ammo_9mm")],
			QuestRules.status(defs.sq_last_call, _q.flags) == QuestRules.Status.DONE and _player.inventory.count("ammo_9mm") >= ammo0 + 60)
		var drops: WorldDrops = get_tree().get_first_node_in_group("world_drops")
		var n := 0
		for id: int in drops.drops:
			if (drops.drops[id][2] as Vector3).distance_to(boss.global_position) < 3.0:
				n += 1
		_check("Copperhead dropped loot (%d drops)" % n, n >= 3)
	var box := cf.get_node_or_null("Loot_strongbox")
	if box:
		_player.global_position = box.global_position + box.global_basis.x * 1.4 + Vector3(0, 0.5, 0)
		await get_tree().create_timer(0.5).timeout
		box.request_open()
		await get_tree().create_timer(0.3).timeout
		_check("Copperhead's strongbox rolled %d items" % box.net_remaining, box.net_remaining > 0)
		box.request_close()
	# Perf at the camp.
	_player.global_position = cf.global_transform * Vector3(0, 1.0, -20)
	_player.yaw = cf.rotation.y
	await get_tree().create_timer(5.0).timeout
	var worst := 0.0
	for i in 120:
		await get_tree().process_frame
		worst = maxf(worst, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	await _shot("bar_camp.png")
	_say("perf at the 21st St camp: frame %.1f ms (worst process %.1f ms), draw calls %d, VRAM %d MB, lair active %d" % [
		1000.0 / maxf(Engine.get_frames_per_second(), 1.0), worst,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, lairs.active_count])
	_finish(main)


func _raiders() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for z in get_tree().get_first_node_in_group("lair_director").get_children():
		if "net_enemy" in z and z.net_active and z.team == &"raiders" and not z.health.is_dead():
			out.append(z)
	return out


func _finish(main: Node) -> void:
	_say("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/downtown_result.txt", FileAccess.WRITE)
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
	print("DOWNTOWN: " + s)
	_log.append(s)
