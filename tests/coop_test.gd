# CoopTest — two-player check on one PC: this scene hosts a throwaway world, then starts a SECOND copy of the
# game (OS.create_process, same scene, "--role=client --code=XXXXX") that joins through the real lobby flow
# (Tube/WebRTC). The host then walks the client through steps by RPC and both sides report what they see:
# spawn + world sync (Bonk, zombies, a drop made before joining), movement prediction vs host, timed item use,
# drop + pickup, crafting at the bunker workbench, Bonk in the same place on both, firing, swimming, then the client leaves and the host saves.
# Host log + client reports -> tests/_look/coop_result.txt; screenshots coop_client_*.png.
# Depends on: scenes/main.tscn, Net, WorldDrops, Workbench, ItemUse, MovementRules, SaveStore.
extends Node

const OUT := "res://tests/_look"
const STEP_TIMEOUT := 15.0

var _role := "host"
var _code := ""
var _log := PackedStringArray()
var _main: Node
var _reports: Dictionary = {}  # step -> text (host)
var _fails := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			_role = a.trim_prefix("--role=")
		elif a.begins_with("--code="):
			_code = a.trim_prefix("--code=")
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().create_timer(1.0).timeout
	if _role == "client":
		get_window().title = "CO-OP TEST CLIENT"
		_main.code_field.text = _code
		_main._on_join_pressed()
		await get_tree().create_timer(120.0).timeout
		get_tree().quit()  # safety: the host normally tells us to leave long before this
		return
	await _host_run()


# --- host ------------------------------------------------------------------------------

func _host_run() -> void:
	get_window().title = "CO-OP TEST HOST"
	_main.world_picker.choose_new("zz coop")
	_main._on_host_pressed()
	var t0 := Time.get_ticks_msec()
	while Net.lobby_code == "" and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().create_timer(0.5).timeout
	if Net.lobby_code == "":
		_check(false, "lobby created")
		await _finish()
		return
	_say("host: lobby %s after %.1f s" % [Net.lobby_code, (Time.get_ticks_msec() - t0) / 1000.0])
	var me: Node3D = get_tree().get_first_node_in_group("local_player")
	var drops: WorldDrops = get_tree().get_first_node_in_group("world_drops")
	drops.host_add("water_bottle", 1, me.global_position + Vector3(1.0, 0.0, 0.0))  # made before the client joins
	var pid := OS.create_process(OS.get_executable_path(), ["--path", ProjectSettings.globalize_path("res://"),
		"res://tests/coop_test.tscn", "--", "--role=client", "--code=" + Net.lobby_code])
	_say("host: started client process %d" % pid)
	t0 = Time.get_ticks_msec()
	var client: Node3D = null
	while client == null and Time.get_ticks_msec() - t0 < 90000:
		await get_tree().create_timer(0.5).timeout
		client = _client_body()
	_check(client != null, "client joined and got a body (%.1f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	if client == null:
		await _finish()
		return
	var peer: int = client.peer_id
	await get_tree().create_timer(4.0).timeout

	# 1. World sync.
	await _ask(peer, 1, null)
	# 3. Timed item use: hurt the client, give items, client bandages.
	client.health.apply_damage(50.0, -1)
	for item: String in ["bandage", "scrap_metal", "canned_beans"]:
		client.inventory.host_add(item, 3 if item == "bandage" else 2)
	await get_tree().create_timer(1.0).timeout
	await _ask(peer, 3, null)
	_check(client.health.current > 50.0 and client.inventory.count("bandage") == 2,
		"host: client healed to %d with 2 bandages left" % roundi(client.health.current))
	# 4. Drop + 5. pickup.
	await _ask(peer, 4, null)
	var found := false
	for id: int in drops.drops:
		found = found or drops.drops[id][0] == "canned_beans"
	_check(found and client.inventory.count("canned_beans") == 0, "host: client's beans are on the ground")
	await _ask(peer, 5, null)
	_check(client.inventory.count("canned_beans") == 2, "host: client picked the beans back up")
	# 6. Crafting at the bunker workbench.
	var bench: Node3D = get_tree().get_first_node_in_group("workbenches")
	_teleport(client, bench.global_position + Vector3(0, 0.1, -1.3))
	await get_tree().create_timer(1.5).timeout
	var ammo: int = client.inventory.count("ammo_9mm")
	await _ask(peer, 6, null)
	_check(client.inventory.count("ammo_9mm") == ammo + 10, "host: client crafted 10 rounds at the workbench")
	# 2. Movement (from the bench, north across the open room): client walks 2 s; host measures; client compares
	# its copy of the host body with the host's real position.
	var before := client.global_position
	await _ask(peer, 2, me.global_position)
	_check(client.global_position.distance_to(before) > 2.0, "host saw the client move %.1f m" % client.global_position.distance_to(before))
	# 10. Bonk: one Bonk, and the client's copy is where the host's is.
	var bonk: Node3D = get_tree().get_first_node_in_group("bonk")
	_teleport(bonk, bench.global_position + Vector3(0, 0.1, -3.0))  # move him off his spawn spot
	await get_tree().create_timer(0.3).timeout
	await _ask(peer, 10, bonk.global_position)
	# 7. Firing.
	await _ask(peer, 7, null)
	# 8. Swimming in Yanney Park Lake.
	_teleport(client, Vector3(-270, _surface(Vector3(-270, 0, 180)) + 0.3, 180))
	await get_tree().create_timer(5.0).timeout
	await _ask(peer, 8, null)
	_check(client.water == MovementRules.Water.SWIM, "host: client is swimming (mode %d)" % client.water)
	# 9. Leave + save.
	_step.rpc_id(peer, 9, null)
	await get_tree().create_timer(4.0).timeout
	_check(_client_body() == null, "client left cleanly, body removed")
	_check(_main.saves.host_save("test") and _main.saves.world.players.size() == 2,
		"save holds host + guest characters (%d)" % _main.saves.world.players.size())
	await _finish()


func _ask(peer: int, n: int, arg: Variant) -> void:
	_step.rpc_id(peer, n, arg)
	var t0 := Time.get_ticks_msec()
	while not _reports.has(n) and Time.get_ticks_msec() - t0 < STEP_TIMEOUT * 1000.0:
		await get_tree().create_timer(0.25).timeout
	if not _reports.has(n):
		_check(false, "client answered step %d" % n)


func _teleport(body: Node3D, pos: Vector3) -> void:
	body.global_position = pos
	body.net_position = pos
	body.velocity = Vector3.ZERO


func _client_body() -> Node3D:
	for p in get_tree().get_nodes_in_group("players"):
		if "water" in p and p.peer_id != 1:
			return p
	return null


func _surface(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 300, p.z), Vector3(p.x, -300, p.z), 32)
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else 0.0


func _finish() -> void:
	_say("RESULT: %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	var f := FileAccess.open(OUT + "/coop_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(_main.saves.world_slug)
	await get_tree().create_timer(15.0).timeout
	get_tree().quit()


@rpc("any_peer", "call_remote", "reliable")
func _report(n: int, ok: bool, text: String) -> void:
	_reports[n] = text
	_check(ok, "client %d: %s" % [n, text])


# --- client ------------------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _step(n: int, arg: Variant) -> void:
	var me: Node3D = get_tree().get_first_node_in_group("local_player")
	var drops: WorldDrops = get_tree().get_first_node_in_group("world_drops")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	match n:
		1:
			var bonk := get_tree().get_first_node_in_group("bonk")
			var waters := 0
			for id: int in drops.drops:
				waters += 1 if drops.drops[id][0] == "water_bottle" else 0
			var zombies := 0
			for z in get_tree().get_nodes_in_group("hittable"):
				zombies += 1 if z.has_method("hear") else 0
			await _shot("coop_client_spawn.png")
			_report.rpc_id(1, n, me != null and bonk != null and waters == 1,
				"spawned at %s, sees %d bodies, Bonk %s, %d active zombies, pre-join drop seen %d" % [
				me.global_position.snapped(Vector3.ONE * 0.1) if me else "-", get_tree().get_nodes_in_group("players").size(),
				"yes" if bonk else "NO", zombies, waters])
		2:
			var host_body: Node3D = null
			for p in get_tree().get_nodes_in_group("players"):
				if "water" in p and p.peer_id == 1:
					host_body = p
			var err: float = host_body.global_position.distance_to(arg) if host_body else -1.0
			var start := me.global_position
			me.yaw = 0.0  # face north, away from the workbench across the open room
			Input.action_press("move_forward")
			await get_tree().create_timer(2.0).timeout
			Input.action_release("move_forward")
			await get_tree().create_timer(0.5).timeout
			_report.rpc_id(1, n, err >= 0.0 and err < 0.5 and me.global_position.distance_to(start) > 2.0,
				"moved %.1f m by prediction; my copy of the host is %.2f m off" % [me.global_position.distance_to(start), err])
		3:
			var hp0: float = me.health.current
			var band0: int = me.inventory.count("bandage")
			me.item_use.request("bandage")
			await get_tree().create_timer(3.0).timeout
			_report.rpc_id(1, n, me.health.current > hp0 and me.inventory.count("bandage") == band0 - 1,
				"bandaged: HP %d -> %d, bandages %d -> %d" % [roundi(hp0), roundi(me.health.current), band0, me.inventory.count("bandage")])
		4:
			drops.request_drop.rpc_id(1, "canned_beans", 0)
			await get_tree().create_timer(1.0).timeout
			var seen := false
			for id: int in drops.drops:
				seen = seen or drops.drops[id][0] == "canned_beans"
			_report.rpc_id(1, n, seen and me.inventory.count("canned_beans") == 0, "dropped beans; I see them on the ground: %s" % seen)
		5:
			var beans := 0
			for id: int in drops.drops:
				if drops.drops[id][0] == "canned_beans":
					beans = id
			drops.request_pickup.rpc_id(1, beans)
			await get_tree().create_timer(1.0).timeout
			_report.rpc_id(1, n, me.inventory.count("canned_beans") == 2 and not drops.drops.has(beans),
				"picked up beans: have %d, drop gone %s" % [me.inventory.count("canned_beans"), not drops.drops.has(beans)])
		6:
			var bench: Node3D = get_tree().get_first_node_in_group("workbenches")
			var d := me.global_position.distance_to(bench.global_position)
			var a0: int = me.inventory.count("ammo_9mm")
			bench.request_craft.rpc_id(1, "handload_9mm")
			await get_tree().create_timer(1.0).timeout
			_report.rpc_id(1, n, me.inventory.count("ammo_9mm") == a0 + 10,
				"at the bench (%.1f m, synced after host teleport), crafted: ammo %d -> %d" % [d, a0, me.inventory.count("ammo_9mm")])
		7:
			var mag0: int = me.weapons.net_mag
			Input.action_press("fire")
			await get_tree().create_timer(0.8).timeout
			Input.action_release("fire")
			await get_tree().create_timer(0.8).timeout
			_report.rpc_id(1, n, me.weapons.net_mag < mag0, "fired: magazine %d -> %d (host-confirmed)" % [mag0, me.weapons.net_mag])
		8:
			var surf := _surface(me.global_position)
			await _shot("coop_client_swim.png")
			_report.rpc_id(1, n, me.water == MovementRules.Water.SWIM,
				"in the lake: water mode %d (2 = swim), eyes %.2f m above water" % [me.water, me.eye_position().y - surf])
		10:
			var bonks := get_tree().get_nodes_in_group("bonk")
			var d: float = bonks[0].global_position.distance_to(arg) if bonks.size() > 0 else -1.0
			_report.rpc_id(1, n, bonks.size() == 1 and d >= 0.0 and d < 1.5,
				"I see %d Bonk(s); my Bonk is %.2f m from the host's Bonk (%s vs %s)" % [bonks.size(), d,
				bonks[0].global_position.snapped(Vector3.ONE * 0.1) if bonks.size() > 0 else "-", (arg as Vector3).snapped(Vector3.ONE * 0.1)])
		9:
			get_tree().quit()


func _shot(file: String) -> void:
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "/" + file)


# --- shared ------------------------------------------------------------------------------

func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	_say(("ok   " if ok else "FAIL ") + what)


func _say(s: String) -> void:
	print("COOP: " + s)
	_log.append(s)
