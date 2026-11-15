# JohnPorkSavesCheck — can you talk to John Pork and buy from him on every saved world? For each save in
# user://saves (skipping zz_* test worlds) plus one brand-new world as a control: copies it to a scratch slot
# (zz_jpcheck; the real save is never opened or written), loads it offline, walks to the front of each John Pork
# tent (Centennial, Cottonmill), looks at him and presses E the way a player does (Player._update_look +
# _try_open_container), then shop -> food -> buy 3 waters for 1 scrap. Logs which step fails and why.
# Results: tests/_look/john_pork_saves.txt (ends with the failure count). Depends on: scenes/main.tscn, Net,
# SaveStore, DiscGolfDirector, DiscCourse, VendorCamp, DialogueDirector, Player.
extends Node

const OUT := "res://tests/_look"
const SCRATCH := "zz_jpcheck"

var _log := PackedStringArray()
var _fails := 0


func _ready() -> void:
	var worlds := []
	for w: Dictionary in SaveStore.list_worlds():
		if not str(w.slug).begins_with("zz"):
			worlds.append(w)
	_say("%d saved world(s): %s" % [worlds.size(), ", ".join(worlds.map(func(w: Dictionary) -> String: return "%s (%s)" % [w.name, w.slug]))])
	worlds.append({"slug": "", "name": "(new world control)"})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	for w: Dictionary in worlds:
		main = get_child(0)
		var slug := str(w.slug)
		if slug != "":
			var data := SaveStore.read(slug)
			if data.is_empty():
				_check(false, "%s: save can't be read" % w.name)
				continue
			_say("== %s: version %s, saved %s, %d characters" % [w.name, data.get("version", "?"), data.get("saved", "?"),
				(data.get("characters", {}) as Dictionary).size()])
			SaveStore.write(SCRATCH, data)
			main.saves.host_open_world(SCRATCH, "")
		else:
			_say("== new world control")
			main.saves.host_open_world("", "zz jpcheck new")
		Net.start_offline()
		await get_tree().create_timer(5.0).timeout
		var prompt: Control = get_tree().get_first_node_in_group("name_prompt")
		if prompt and prompt.visible:
			prompt.submit("Bonk")
		var player: Node3D = get_tree().get_first_node_in_group("local_player")
		if player == null:
			_check(false, "%s: no player spawned" % w.name)
		else:
			player.health.damage_mult = 0.0
			for course_id in ["centennial", "cottonmill"]:
				await _try_course(str(w.name), course_id, player)
		var scratch_slug: String = main.saves.world_slug
		Net.leave_to_menu.call_deferred(main)
		await get_tree().create_timer(1.5).timeout
		SaveStore.delete(scratch_slug)
	_say("%d failure(s)" % _fails)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var f := FileAccess.open(OUT + "/john_pork_saves.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	get_tree().quit()


func _try_course(world: String, course_id: String, player: Node3D) -> void:
	var tag := "%s / %s" % [world, course_id]
	var dg: DiscGolfDirector = get_tree().get_first_node_in_group("disc_golf")
	var course: DiscCourse = dg.course_node(course_id) if dg else null
	if course == null:
		_check(false, "%s: no disc course" % tag)
		return
	player.global_position = course.box_position() + Vector3(2.5, 1.5, 0)
	for i in 30:
		await get_tree().create_timer(0.5).timeout
		if course.is_snapped():
			break
	await get_tree().create_timer(1.5).timeout
	var camp: VendorCamp = course.camp
	if camp == null or not camp.is_inside_tree():
		_check(false, "%s: John Pork's camp missing" % tag)
		return
	var npc: Node3D = null
	for n in get_tree().get_nodes_in_group("npcs"):
		if "npc_id" in n and n.npc_id == "john_pork" and camp.is_ancestor_of(n):
			npc = n
	if npc == null:
		_check(false, "%s: camp is there but John Pork isn't" % tag)
		return
	var dlg: Node = get_tree().get_first_node_in_group("dialogue")
	_say("%s: dialogue talker before = %d, John Pork in groups %s" % [tag, int(dlg._talker), npc.get_groups()])
	# Walk up to the front of the table (local z -1.35) and look at his chest.
	var front := -camp.global_basis.z
	var stand := camp.global_position + front * 1.85 + Vector3(0, 0.3, 0)
	player.global_position = stand
	player.velocity = Vector3.ZERO
	var target := npc.global_position + Vector3(0, 1.3, 0)
	await get_tree().create_timer(0.8).timeout  # settle on the ground
	var eye: Vector3 = player.camera.global_position
	var d := target - eye
	player.yaw = atan2(-d.x, -d.z)
	player.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	player.rotation.y = player.yaw
	player.head.rotation.x = player.pitch
	await get_tree().create_timer(0.5).timeout
	player._update_look(1.0)
	if player.looked_talkable != npc:
		var from: Vector3 = player.camera.global_position
		var to: Vector3 = from - player.camera.global_basis.z * 4.0
		var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [player.get_rid()]))
		var what := "nothing within 4 m"
		if not hit.is_empty():
			what = "%s (groups %s) at %.2f m" % [hit.collider.name, hit.collider.get_groups(), from.distance_to(hit.position)]
		_check(false, "%s: E can't target him from the table (looking at %s; he's %.2f m from the eye; interact range %.1f)" % [
			tag, what, eye.distance_to(target), float(player._carry.get("interact_range", 2.5))])
		return
	player.inventory.host_add("scrap_metal", 1)
	var water0: int = player.inventory.count("water_bottle")
	player._try_open_container()
	await get_tree().create_timer(0.4).timeout
	var me := multiplayer.get_unique_id()
	if int(dlg._talker) != me:
		_check(false, "%s: pressed E on him, no conversation (talker %d, player %.2f m from him, talk range %.1f)" % [
			tag, int(dlg._talker), player.global_position.distance_to(npc.global_position), float(npc.def.get("talk_range", 3.0))])
		return
	for step in [0, 0, 0]:  # What've you got? -> Food and water. -> 1 scrap for 3 waters
		dlg.request_choice(step)
		await get_tree().create_timer(0.25).timeout
	var bought: bool = player.inventory.count("water_bottle") == water0 + 3
	_check(bought, "%s: E talks, shop works (water %d -> %d, at node '%s')" % [tag, water0,
		player.inventory.count("water_bottle"), dlg._node_id])
	dlg.request_leave()
	await get_tree().create_timer(0.3).timeout


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	_say(("PASS " if ok else "FAIL ") + what)


func _say(s: String) -> void:
	print("JPCHECK: " + s)
	_log.append(s)
