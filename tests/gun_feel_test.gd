# GunFeelTest — D-122 weapon realism. Pure: the recoil pattern repeats; kick and bloom recover to zero; bloom caps;
# aiming tightens the spread; reload cues come in order; a casing lands and stays on the floor; every gun has its
# feel data, its own shot sound and its cue sounds; damage is unchanged from D-121.
# In game (offline world, god mode, AR in slot 2): a held burst kicks the view up and it comes back; the host's
# bloom grows and recovers; the host's cone is the gun's spread unaimed and ads_spread x that aimed; aiming zooms and
# slides the gun to the middle; a shot shows a muzzle flash and ejects casings that land and vanish; a reload shows
# the HUD bar and plays its three cues; sustained fire allocates nothing (object count); perf while firing.
# Screenshots tests/_look/gun_*.png. Results: tests/_look/gun_feel_result.txt (ends with the failure count).
# Depends on: scenes/main.tscn, scenes/training_dummy.tscn, GunFeelRules, GunFx, WeaponHolder, WeaponDB, Sfx.
extends Node

const OUT_DIR := "res://tests/_look"
const DUMMY := preload("res://scenes/training_dummy.tscn")
const GUNS := ["pistol_9mm", "revolver_44", "smg_9mm", "shotgun_pump", "rifle_hunting", "rifle_ar", "rifle_sniper"]
const DAMAGE := {"pistol_9mm": 25.0, "revolver_44": 70.0, "smg_9mm": 27.0, "shotgun_pump": 16.0, "rifle_hunting": 110.0,
	"rifle_ar": 38.0, "rifle_sniper": 200.0}

var _log := PackedStringArray()
var _fails := 0
var _me: Node3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_pure()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz gunfeel")
	main.menu.play_offline.emit()
	await get_tree().create_timer(4.0).timeout
	_me = get_tree().get_first_node_in_group("local_player")
	var prompt := get_tree().get_first_node_in_group("name_prompt")
	if prompt and prompt.visible:
		prompt.submit("Bonk")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _game()
	_log.append("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/gun_feel_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	get_tree().quit()


func _pure() -> void:
	var ar: Dictionary = WeaponDB.get_weapon("rifle_ar").feel
	var pat: Array = ar.pattern
	_check(GunFeelRules.kick(ar, 0) == GunFeelRules.kick(ar, pat.size()) and GunFeelRules.kick(ar, 0) != GunFeelRules.kick(ar, 1),
		"recoil pattern repeats every %d shots and varies inside it" % pat.size())
	var left := GunFeelRules.recover(Vector2(3, 1), 8.0, 0.1)
	_check(absf(left.length() - (Vector2(3, 1).length() - 0.8)) < 0.001 and GunFeelRules.recover(Vector2(3, 1), 8.0, 1.0) == Vector2.ZERO,
		"view kick recovers at its rate and stops at zero")
	var b := 0.0
	for i in 60:
		b = GunFeelRules.bloom_after_shot(b, ar)
	var cap := float(ar.bloom[1])
	var back := b
	for i in 120:
		back = GunFeelRules.bloom_recover(back, ar, 1.0 / 60.0)
	_check(is_equal_approx(b, cap) and back == 0.0, "AR bloom caps at %.1f deg and is gone 2 s later" % cap)
	_check(is_equal_approx(GunFeelRules.shot_spread(1.4, 0.6, true, ar), 1.0) and is_equal_approx(GunFeelRules.shot_spread(1.4, 0.6, false, ar), 2.0),
		"spread: 1.4 + 0.6 bloom = 2.0 deg, aimed 1.0 deg")
	var cues: Array = WeaponDB.get_weapon("rifle_ar").reload_cues
	var order := PackedInt32Array()
	var played := 0
	for k in 11:
		var i := GunFeelRules.due_cue(cues, played, k / 10.0)
		if i >= 0:
			played += 1
			order.append(i)
	_check(order == PackedInt32Array([0, 1, 2]), "reload cues play once each, in order")
	var pos := PackedVector3Array([Vector3(0, 1.4, 0)])
	var vel := PackedVector3Array([Vector3(1.8, 1.4, 0)])
	var moving := true
	var steps := 0
	var lowest := INF
	while moving and steps < 600:
		moving = GunFeelRules.casing_step(pos, vel, 0, 0.0, 1.0 / 60.0, 9.8, 0.35)
		lowest = minf(lowest, pos[0].y)
		steps += 1
	_check(not moving and lowest >= 0.0 and steps < 180, "a casing lands and settles on the floor in %.2f s" % (steps / 60.0))
	var data_ok := true
	var snd_ok := true
	var dmg_ok := true
	for id: String in GUNS:
		var w := WeaponDB.get_weapon(id)
		data_ok = data_ok and w.has("feel") and w.has("reload_cues") and w.has("eject")
		snd_ok = snd_ok and Sfx.pick(id + "_fire") != null
		for c: Array in w.get("reload_cues", []):
			snd_ok = snd_ok and Sfx.pick(str(c[1])) != null and float(c[0]) > 0.0 and float(c[0]) < 1.0
		dmg_ok = dmg_ok and is_equal_approx(float(w.damage), float(DAMAGE[id]))
	_check(data_ok, "all 7 guns have feel, reload cues and an eject type")
	_check(snd_ok and Sfx.pick("casing_drop") != null and Sfx.pick("gun_pump") != null, "every gun has its own shot and its cue sounds")
	_check(dmg_ok, "damage unchanged (pistol 25 ... long rifle 200)")


func _game() -> void:
	var inv: InventoryHolder = _me.inventory
	var w: WeaponHolder = _me.weapons
	var fx: GunFx = get_tree().get_first_node_in_group("gun_fx")
	var hud: Node = get_tree().get_first_node_in_group("hud")
	_me.health.damage_mult = 0.0
	inv.host_add("rifle_ar", 1)
	inv.host_add("ammo_556", 240)
	var ar := inv.equipped("gun2")
	ar = {"uid": ar.uid, "id": "rifle_ar", "rarity": "standard", "cond": 1.0, "mods": [], "perk": "", "mag": 30}
	inv.host_set_gears({int(ar.uid): ar})
	for n in get_tree().get_nodes_in_group("players"):
		if n != _me:
			n.process_mode = Node.PROCESS_MODE_DISABLED
			n.global_position += Vector3(0, 0, 40)
	var bench: Node3D = get_tree().get_first_node_in_group("workbenches")
	_me.global_position = bench.global_position + Vector3(0, 0.1, -1.3)
	await get_tree().create_timer(0.5).timeout
	var dummy := DUMMY.instantiate()
	dummy.position = _me.global_position + Vector3(0, -0.1, -6.0)
	add_child(dummy)
	_aim_at(dummy.global_position + Vector3(0, 1.1, 0))
	_me._select_slot(1)
	await get_tree().create_timer(0.4).timeout
	Input.action_press("reload")  # a looted gun comes with an empty mag (its roll keeps mag 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("reload")
	await get_tree().create_timer(2.6).timeout
	_check(w.net_mesh != "" and str(w.weapon_in_slot(1).id) == "rifle_ar" and w.net_mag == 30, "AR in hand, 30 rounds")
	# Unaimed first shot: the host's cone is the gun's spread.
	var pitch0: float = _me.pitch
	Input.action_press("fire")
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var cone_hip: float = w.last_cone
	var lit := 0
	for k in 30:  # a flash lasts 0.05 s between AR shots 0.11 s apart: catch one lit frame
		await get_tree().process_frame
		lit = fx.active_flashes()
		if lit > 0:
			break
	_check(lit > 0, "a shot shows a muzzle flash (%d lit)" % lit)
	await _shot("gun_flash.png")
	await get_tree().create_timer(0.4).timeout
	Input.action_release("fire")
	var kicked := rad_to_deg(float(_me.pitch) - pitch0)
	var bloom_peak: float = w._bloom
	var mag_after: int = w.net_mag
	_check(kicked > 1.0, "a held burst kicks the view up %.1f deg (%d shots)" % [kicked, 30 - mag_after])
	_check(bloom_peak > 0.5 and bloom_peak <= 3.0 + 0.001, "host bloom grew to %.2f deg (cap 3.0)" % bloom_peak)
	_check(absf(cone_hip - 1.4) < 0.01, "unaimed first shot: host cone %.2f deg (spread 1.4)" % cone_hip)
	await get_tree().create_timer(0.3).timeout
	_check(fx.active_casings() >= 3, "casings in the air / on the floor: %d" % fx.active_casings())
	await _shot("gun_casings.png")
	await get_tree().create_timer(1.5).timeout
	_check(absf(rad_to_deg(float(_me.pitch) - pitch0)) < 0.3 and w._bloom < 0.01,
		"1.8 s later the view is back (%.2f deg off) and the bloom gone (%.2f)" % [rad_to_deg(float(_me.pitch) - pitch0), w._bloom])
	await get_tree().create_timer(1.5).timeout
	_check(fx.active_casings() == 0, "casings vanish after their life (%d left)" % fx.active_casings())
	# Aim down sights.
	var fov0: float = _me.camera.fov
	Input.action_press("aim")
	await get_tree().create_timer(0.6).timeout
	_check(_me.camera.fov < fov0 - 3.0 and _me.viewmodel._ads > 0.9, "aiming zooms (fov %.0f -> %.0f) and centres the gun" % [fov0, _me.camera.fov])
	await _shot("gun_ads.png")
	Input.action_press("fire")
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("fire")
	var cone_ads: float = w.last_cone
	_check(absf(cone_ads - 0.7) < 0.01, "aimed first shot: host cone %.2f deg (1.4 x 0.5)" % cone_ads)
	Input.action_release("aim")
	await get_tree().create_timer(1.0).timeout
	# Reload: bar + cues.
	Input.action_press("reload")
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("reload")
	await get_tree().create_timer(0.5).timeout
	var bar_on: bool = hud._reload_bg.visible
	var mid: float = w.reload_progress()
	await _shot("gun_reload.png")
	await get_tree().create_timer(2.2).timeout
	_check(bar_on and mid > 0.1 and mid < 0.4, "reload bar shows (%.0f%% at 0.5 s of 2.2)" % (mid * 100.0))
	_check(w._cues_played == 3 and w.net_mag == 30 and not hud._reload_bg.visible,
		"reload played its 3 cues (%d), mag full again (%d), bar gone" % [w._cues_played, w.net_mag])
	# Allocation: two identical bursts after a warm-up; the second must not add objects (steady state, no leak or
	# per-shot / per-frame nodes). The first time anything plays can still create things (voices, caches).
	await get_tree().create_timer(0.5).timeout
	var counts := PackedFloat32Array()
	var frames := 0
	var sum := 0.0
	var dc := 0.0
	for burst in 3:
		Input.action_press("fire")
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 900:
			await get_tree().process_frame
			if burst == 2:
				sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
				frames += 1
		dc = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		Input.action_release("fire")
		await get_tree().create_timer(3.0).timeout  # casings gone, reload done
		counts.append(Performance.get_monitor(Performance.OBJECT_COUNT))
		_log.append("  objects %d nodes %d resources %d orphans %d" % [Performance.get_monitor(Performance.OBJECT_COUNT),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
			Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)])
		Input.action_press("reload")
		await get_tree().physics_frame
		await get_tree().physics_frame
		await get_tree().physics_frame
		Input.action_release("reload")
		await get_tree().create_timer(2.6).timeout
	_check(counts[2] <= counts[1], "repeated bursts add no objects (after each: %d, %d, %d)" % [counts[0], counts[1], counts[2]])
	_log.append("perf firing the AR in the bunker: frame %.1f ms, %d draw calls, %d MB video memory, %d MB static memory" % [
		sum / maxf(frames, 1), dc, int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)])


func _aim_at(target: Vector3) -> void:
	var eye: Vector3 = _me.camera.global_position
	var d := target - eye
	_me.yaw = atan2(-d.x, -d.z)
	_me.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	_me.rotation.y = _me.yaw
	_me.head.rotation.x = _me.pitch


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR + "/" + file))
	_log.append("shot " + file)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	_log.append(("PASS " if ok else "FAIL ") + what)
