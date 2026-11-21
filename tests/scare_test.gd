# ScareTest — D-114 zombie scare features. Pure rules (traits from a seed, being watched, stalking, flank points,
# heartbeat, muffling, feigning Health), the sound files, then in a hosted world: a screamer's scream + sprint
# pulling in a zombie behind you, a feigner dropping and getting back up, a crawler's look and low hit capsule,
# a night stalker that freezes while watched and creeps while not, a lurker waiting at a wall until you're close,
# a flanker heading for your side, night eyes, the grab overlay / muffle / heartbeat / shake, nearest-zombie voices,
# a night screenshot and frame time with the whole pool out at night.
# Results: tests/_look/scare_result.txt (ends with the failure count); scare_eyes.png, scare_grab.png.
# Depends on: scenes/main.tscn, ZombieDirector, ZombieScare, ScareRules, Dread, ZombieVoices, EyeShine, Health, Sfx.
extends Node

const OUT_DIR := "res://tests/_look"
const ZombieScript := preload("res://scripts/ai/zombie.gd")

var _log := PackedStringArray()
var _fails := 0
var _me: Node3D
var _dir: Node
var _dn: Node
var _dread: Node
var _t: Dictionary


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_t = ZombieScare.load_tuning()
	_pure()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz scare")
	main.menu.play_offline.emit()
	await get_tree().create_timer(5.0).timeout
	_me = get_tree().get_first_node_in_group("local_player")
	var prompt := get_tree().get_first_node_in_group("name_prompt")
	if prompt and prompt.visible:
		prompt.submit("Bonk")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_dir = get_tree().get_first_node_in_group("zombie_director")
	_dn = get_tree().get_first_node_in_group("daynight")
	_dread = get_tree().get_first_node_in_group("dread")
	var weather := get_tree().get_first_node_in_group("weather")
	if weather:
		weather.request_mode("clear")
	for n: Node in get_tree().get_nodes_in_group("players"):  # park Bonk far away, still
		if n != _me and n.get_script() and str(n.get_script().resource_path).ends_with("bonk.gd"):
			n.global_position += Vector3(0, 400, 0)
			n.process_mode = Node.PROCESS_MODE_DISABLED
	_me.health.invulnerable = true
	_check(_dread != null and get_tree().root.find_child("ZombieVoices", true, false) != null, "Main has Dread and ZombieVoices")
	await _go_open()
	_quiet()
	_set_hour(13.0)
	await _scream()
	await _feign()
	await _crawler()
	await _stalker()
	await _lurker()
	await _flank()
	await _dread_fx()
	await _eyes()
	await _perf()
	_set_hour(13.0)
	_log.append("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/scare_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	get_tree().quit()


# --- pure ---------------------------------------------------------------------------------

func _pure() -> void:
	var ch: Dictionary = _t.roles.zombie_shambler
	_check(ScareRules.roles(42, ch, _t) == ScareRules.roles(42, ch, _t), "same seed, same traits")
	var counts := {}
	var bad := 0
	for i in 4000:
		var r := ScareRules.roles(i * 7919 + 3, ch, _t)
		for k: String in ScareRules.ROLE_KEYS:
			if r[k]:
				counts[k] = int(counts.get(k, 0)) + 1
		if r.crawler and (r.feigner or r.stumbler) or r.lurker and r.stalker:
			bad += 1
	_check(bad == 0, "a crawler never feigns or stumbles, a lurker never stalks")
	var crawl_share := float(counts.get("crawler", 0)) / 4000.0
	var scream_share := float(counts.get("screamer", 0)) / 4000.0
	_check(absf(crawl_share - float(ch.crawler)) < 0.03 and absf(scream_share - float(ch.screamer)) < 0.03,
		"shambler shares match the data (crawler %.2f, screamer %.2f)" % [crawl_share, scream_share])
	var plain := ScareRules.roles(5, {}, _t)
	_check(not plain.screamer and not plain.crawler and is_equal_approx(float(plain.speed), 1.0), "no chances = plain zombie")
	_check(ScareRules.is_watched(0.0, Vector3.ZERO, Vector3(0, 0, -10), 40.0) and not ScareRules.is_watched(0.0, Vector3.ZERO, Vector3(0, 0, 10), 40.0)
		and ScareRules.is_watched(0.0, Vector3.ZERO, Vector3(tan(deg_to_rad(15.0)) * 10.0, 0, -10), 40.0)
		and not ScareRules.is_watched(0.0, Vector3.ZERO, Vector3(tan(deg_to_rad(25.0)) * 10.0, 0, -10), 40.0),
		"watched: ahead yes, behind no, 15 deg off yes, 25 deg off no (40 deg cone)")
	var st: Dictionary = _t.stalk
	_check(ScareRules.stalk(5.0, true, 0.0, st) == ScareRules.Stalk.CHARGE and ScareRules.stalk(12.0, true, 0.0, st) == ScareRules.Stalk.HOLD
		and ScareRules.stalk(12.0, false, 0.0, st) == ScareRules.Stalk.CREEP and ScareRules.stalk(12.0, true, 99.0, st) == ScareRules.Stalk.CHARGE,
		"stalk: charge when close or bored, hold when watched, creep when not")
	var fp := ScareRules.flank_point(Vector3.ZERO, Vector3(0, 0, 10), 1, 5.0)
	_check(is_equal_approx(fp.length(), 5.0) and absf(fp.z) < 0.001, "flank point is 5 m to the side (%s)" % str(fp))
	var d: Dictionary = _t.dread
	_check(ScareRules.heartbeat_interval(20.0, d) == 0.0 and is_equal_approx(ScareRules.heartbeat_interval(2.0, d), 60.0 / 150.0)
		and ScareRules.heartbeat_interval(7.0, d) > 0.4 and ScareRules.heartbeat_interval(7.0, d) < 60.0 / 70.0,
		"heartbeat: none at 20 m, 150 bpm at 2 m, in between at 7 m")
	_check(is_equal_approx(ScareRules.muffle(0.0, d), 1.0) and ScareRules.muffle(3.5, d) == 0.0
		and is_equal_approx(ScareRules.muffle_cutoff(0.0, d), 20000.0) and is_equal_approx(ScareRules.muffle_cutoff(1.0, d), 900.0),
		"muffle: full at 0 m, none past 3 m, 20 kHz .. 900 Hz")
	var h := Health.new()
	h.max_health = 80.0
	h.reset()
	h.down_once = true
	var got := {"downed": 0, "died": 0}
	h.downed.connect(func() -> void: got.downed += 1)
	h.died.connect(func(_p: int) -> void: got.died += 1)
	h.apply_damage(200.0, 0)
	var after_down := h.current
	h.apply_damage(2.0, 0)
	_check(after_down == 1.0 and got.downed == 1 and got.died == 1 and h.is_dead(), "feigning Health: first lethal hit downs at 1 HP, the next kills")
	h.free()
	for ev: String in ["zombie_groan", "zombie_breath", "zombie_scream", "zombie_attack", "heartbeat"]:
		_check(Sfx.pick(ev) != null, "sound event '%s' has files" % ev)


# --- hosted world --------------------------------------------------------------------------

func _scream() -> void:
	var z := _spawn("zombie_shambler", _forward() * 15.0, {"screamer": true})
	var behind := _spawn("zombie_shambler", -_forward() * 22.0, {}, false)
	var screamed := false
	var sprinted := false
	var peak := 0.0
	var called := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
		screamed = screamed or z._scare._scream_left > 0.0
		sprinted = sprinted or z._scare._sprint_left > 0.0
		peak = maxf(peak, _dread.trauma)
		called = called or behind.brain.state != ZombieBrain.State.WANDER
	_check(screamed, "a screamer that spots you screams")
	_check(peak > 0.05, "the scream shakes the camera (peak trauma %.2f)" % peak)
	_check(called, "the scream pulls in a zombie 22 m behind you")
	_check(sprinted, "then it sprints")
	_quiet()


func _feign() -> void:
	var z := _spawn("zombie_shambler", _forward() * 6.0, {"feigner": true})
	await get_tree().create_timer(0.3).timeout
	var died := [0]
	z.health.died.connect(func(_p: int) -> void: died[0] += 1, CONNECT_ONE_SHOT)
	z.health.apply_damage(999.0, 1)
	await get_tree().create_timer(0.2).timeout
	_check(z.net_pose == ZombieScare.Pose.DOWN and not z.health.is_dead() and died[0] == 0 and z._hit_height() < 0.6,
		"a feigner drops at 1 HP, not dead, low hit capsule (%.2f m)" % z._hit_height())
	var f: Dictionary = _t.feign
	await get_tree().create_timer(float(f.down_max_s) + float(f.rise_s) + 0.5).timeout
	_check(z.net_pose == ZombieScare.Pose.NORMAL and is_equal_approx(z.health.current, z.health.max_health * float(f.revive_fraction)),
		"then gets back up with %.0f%% health" % (float(f.revive_fraction) * 100.0))
	z.health.apply_damage(999.0, 1)
	_check(z.health.is_dead(), "and the next lethal hit kills it")
	_quiet()


func _crawler() -> void:
	var z := _spawn("zombie_shambler", _forward() * 10.0, {"crawler": true})
	await get_tree().create_timer(0.5).timeout
	_check(str(z.body.clip_remap.get("walk", "")) == "crawl" and z.body.get("_hidden_bones").size() == 2
		and absf(z._hit_height() - float(_t.crawler.height_m)) < 0.01,
		"a crawler crawls, has no legs and a %.1f m hit capsule" % float(_t.crawler.height_m))
	var s := _spawn("zombie_shambler", _forward() * 12.0 + _right() * 3.0, {"stumbler": true})
	await get_tree().create_timer(0.2).timeout
	_check(str(s.body.clip_remap.get("walk", "")) == "stumble" and s.body.get("_hidden_bones").size() == 0, "a stumbler lurches (stumble walk)")
	_quiet()


func _stalker() -> void:
	_set_hour(23.5)
	var z := _spawn("zombie_shambler", _forward() * 14.0, {"stalker": true})
	await get_tree().create_timer(1.5).timeout
	var p0: Vector3 = z.global_position
	await get_tree().create_timer(1.5).timeout
	var held: float = z.global_position.distance_to(p0)
	_check(z.brain.state == ZombieBrain.State.CHASE and held < 0.4, "night stalker freezes while you look at it (moved %.2f m)" % held)
	var yaw0: float = _me.yaw
	_me.yaw += PI
	_me.rotation.y = _me.yaw
	var d0: float = z.global_position.distance_to(_me.global_position)
	await get_tree().create_timer(2.0).timeout
	var d1: float = z.global_position.distance_to(_me.global_position)
	_check(d0 - d1 > 0.8, "and creeps closer when you turn away (%.1f -> %.1f m)" % [d0, d1])
	_me.yaw = yaw0
	_me.rotation.y = yaw0
	_quiet()
	_set_hour(13.0)


func _lurker() -> void:
	var z: Node = null
	for i in 16:
		var a := TAU * float(i) / 16.0
		z = _spawn("zombie_shambler", Vector3(cos(a), 0, sin(a)) * (14.0 + float(i % 3) * 5.0), {"lurker": true}, false)
		if z._scare.lurking:
			break
		z.deactivate()
		z = null
	if z == null:
		_log.append("SKIP  lurker: no wall within reach of the test spot")
		return
	await get_tree().create_timer(5.0).timeout
	var p0: Vector3 = z.global_position
	await get_tree().create_timer(2.0).timeout
	_check(z._scare.lurking and z.global_position.distance_to(p0) < 0.3,
		"a lurker waits, still (%.1f m from its wall spot)" % z.global_position.distance_to(z._home))
	var back: Vector3 = _me.global_position
	_me.global_position = _ground(z.global_position + (z._scare.lurk_face as Vector3) * 2.5) + Vector3.UP * 0.2
	_me.velocity = Vector3.ZERO
	await get_tree().create_timer(2.0).timeout
	_check(not z._scare.lurking, "and comes for you when you're within %.0f m" % float(_t.lurk.wake_m))
	_me.global_position = back
	_me.velocity = Vector3.ZERO
	_quiet()
	await get_tree().create_timer(1.0).timeout


func _flank() -> void:
	var a := _spawn("zombie_shambler", _forward() * 16.0, {})
	var b := _spawn("zombie_shambler", _forward() * 16.0 + _right() * 2.0, {})
	var c := _spawn("zombie_shambler", _forward() * 16.0 - _right() * 2.0, {"flanker": true})
	await get_tree().create_timer(1.5).timeout
	var off_c: float = (c.nav.target_position as Vector3).distance_to(_me.global_position)
	var off_a: float = (a.nav.target_position as Vector3).distance_to(_me.global_position)
	_check(c.brain.state == ZombieBrain.State.CHASE and off_c > 3.0 and off_a < 1.5,
		"a flanker heads for your side when others chase you (%.1f m beside you vs %.1f m)" % [off_c, off_a])
	b.deactivate()
	_quiet()


func _dread_fx() -> void:
	ZombieScript.frozen = true
	var z := _spawn("zombie_shambler", _forward() * 1.2, {})
	z.net_attacking = true
	await get_tree().create_timer(1.2).timeout
	var bus := AudioServer.get_bus_index("SFX")
	var muffled := false
	for e in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, e) is AudioEffectLowPassFilter and AudioServer.is_bus_effect_enabled(bus, e):
			muffled = (AudioServer.get_bus_effect(bus, e) as AudioEffectLowPassFilter).cutoff_hz < 3000.0
	_check(_dread.grab > 0.9 and _dread.muffle > 0.9 and muffled, "grabbed: overlay on, hearing muffled (grab %.2f, cutoff low %s)" % [_dread.grab, muffled])
	_check(_dread.get("_beat_in") > 0.0 and _dread.nearest < 2.0, "heartbeat going with one at %.1f m" % _dread.nearest)
	await _shot("scare_grab.png")
	z.net_attacking = false
	_dread.add_trauma(0.6)
	await get_tree().process_frame
	await get_tree().process_frame
	var cam := get_viewport().get_camera_3d()
	_check(cam.h_offset != 0.0 or cam.v_offset != 0.0, "trauma shakes the camera")
	z.deactivate()
	await get_tree().create_timer(1.5).timeout
	_check(cam.h_offset == 0.0 and cam.v_offset == 0.0 and cam.rotation.z == 0.0 and _dread.grab < 0.01 and _dread.muffle < 0.01,
		"and it all settles once it's gone")
	var voices := get_tree().root.find_child("ZombieVoices", true, false)
	var y := _spawn("zombie_shambler", _forward() * 10.0, {})
	await get_tree().create_timer(0.5).timeout
	_check((voices.get("_near") as Array)[0] == y, "the nearest zombie gets a voice")
	ZombieScript.frozen = false
	_quiet()


func _eyes() -> void:
	_set_hour(23.5)
	ZombieScript.frozen = true
	var z := _spawn("zombie_shambler", _forward() * 4.0, {})
	await get_tree().create_timer(1.2).timeout
	_check(EyeShine.is_on() and z._eyes != null and z._eyes.is_visible_in_tree(), "eyes shine at night")
	await _shot("scare_eyes.png")
	_set_hour(13.0)
	await get_tree().create_timer(1.2).timeout
	_check(not EyeShine.is_on(), "and not by day")
	ZombieScript.frozen = false
	_quiet()


func _perf() -> void:
	_set_hour(23.5)
	var pool: Array = _dir.get("_pool")
	var types := ["zombie_shambler", "zombie_runner", "zombie_bloater", "zombie_riot", "zombie_spitter"]
	var n := 0
	for z in pool:
		var a := TAU * float(n) / float(pool.size())
		var d := 18.0 + float(n % 4) * 7.0
		z.net_enemy = types[n % types.size()]
		z.activate(_ground(_me.global_position + Vector3(cos(a) * d, 0, sin(a) * d)))
		n += 1
	await get_tree().create_timer(4.0).timeout
	var frame := 0.0
	var phys := 0.0
	for i in 120:
		await get_tree().process_frame
		frame += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_log.append("perf, %d zombies with scare traits at night: frame %.1f ms, physics %.1f ms, %d draw calls, %d MB video memory" % [
		_dir.active_count, frame / 120.0, phys / 120.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)])
	_check(phys / 120.0 < 8.0, "physics stays under 8 ms")
	_quiet()


# --- helpers --------------------------------------------------------------------------------

# A zombie of `type` at an offset from the player with exactly the traits in `want` (others off).
func _spawn(type: String, offset: Vector3, want: Dictionary, face_me := true) -> Node:
	for z in _dir.get("_pool"):
		if z.net_active:
			continue
		z.net_enemy = type
		var p := _ground(_me.global_position + offset)
		var to := _me.global_position - p
		z.activate(p, atan2(-to.x, -to.z) if face_me else atan2(to.x, to.z))
		z.net_style = _seed_for(type, want)
		z.nav.target_position = p
		z._scare.host_activate(z)
		return z
	return null


func _seed_for(type: String, want: Dictionary) -> int:
	var ch: Dictionary = _t.roles[type]
	for s in 200000:
		var r := ScareRules.roles(s, ch, _t)
		var ok := true
		for k: String in ScareRules.ROLE_KEYS:
			if bool(r[k]) != bool(want.get(k, false)):
				ok = false
				break
		if ok:
			return s
	push_error("no seed gives %s" % str(want))
	return 0


func _quiet() -> void:
	_dir.set("_spawn_timer", 1.0e9)
	for z in _dir.get("_pool"):
		if z.net_active:
			z.deactivate()


func _set_hour(h: float) -> void:
	_dn.hour = h


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT_DIR + "/" + file)


func _ground(p: Vector3) -> Vector3:
	var hit := _me.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 30.0, p + Vector3.DOWN * 30.0, 17))
	return (hit.position as Vector3) if not hit.is_empty() else p


func _go_open() -> void:
	var spots := [["bonk_house", Vector3(0, 0, 40)], ["bonk_house", Vector3(40, 0, 40)], ["dropzone", Vector3(0, 0, 60)],
		["country_club", Vector3(100, 0, -150)]]
	for spot: Array in spots:
		var lm := get_tree().root.find_child(str(spot[0]), true, false) as Node3D
		if lm == null:
			continue
		var at: Vector3 = lm.global_transform * (spot[1] as Vector3)
		_me.global_position = at + Vector3.UP * 40.0
		_me.velocity = Vector3.ZERO
		await get_tree().create_timer(4.0).timeout
		_me.global_position = _ground(at) + Vector3.UP * 0.2
		_me.velocity = Vector3.ZERO
		await get_tree().create_timer(1.0).timeout
		var space := _me.get_world_3d().direct_space_state
		for i in 16:
			_me.yaw = TAU * float(i) / 16.0
			_me.rotation.y = _me.yaw
			var eye: Vector3 = _me.eye_position()
			var open := true
			for ray: Vector3 in [_forward() * 60.0, _right() * 12.0, -_forward() * 55.0]:
				if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + ray, 1)).is_empty():
					open = false
			for d in [3.0, 6.0, 9.0, 12.0]:
				if absf(_ground(_me.global_position + _forward() * d).y - _me.global_position.y) > 0.6:
					open = false
			if open:
				_log.append("test spot %s %s, facing %.0f deg" % [spot[0], str(_me.global_position.round()), rad_to_deg(_me.yaw)])
				return
	_log.append("no flat open spot found; last tried %s" % str(_me.global_position.round()))


func _forward() -> Vector3:
	var f: Vector3 = -_me.global_basis.z
	f.y = 0.0
	return f.normalized()


func _right() -> Vector3:
	var r: Vector3 = _me.global_basis.x
	r.y = 0.0
	return r.normalized()


func _check(ok: bool, what: String) -> void:
	_log.append(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_fails += 1
