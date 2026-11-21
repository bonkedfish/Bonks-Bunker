# ZombieTypesTest — D-100 open-world zombie types: pure rules (type bands, armor, burst falloff), the data (enemies,
# drop tables, recipes), then in a hosted world: Riot Cop body vs head shots and melee, a Bloater's burst hurting a
# player and a nearby zombie, Runner hearing, a Spitter hitting from range, drops on death, spawn types by distance
# from the bunker, a lineup screenshot and frame time with the full pool (40) active.
# Results: tests/_look/zombie_types_result.txt (ends with the failure count); zombie_types_lineup.png.
# Depends on: scenes/main.tscn, ZombieDirector, CombatWorld, WorldDrops, ZombieTypeRules, EnemyDB, LootDB, LootRules.
extends Node

const OUT_DIR := "res://tests/_look"
const ZombieScript := preload("res://scripts/ai/zombie.gd")
const TYPES := ["zombie_shambler", "zombie_runner", "zombie_bloater", "zombie_riot", "zombie_spitter"]

var _log := PackedStringArray()
var _fails := 0
var _me: Node3D
var _dir: Node
var _combat: Node


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	ZombieScare.roles_off = true  # D-114 traits are random per activation; this test wants plain zombies
	_pure()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz zombie types")
	main.menu.play_offline.emit()
	await get_tree().create_timer(5.0).timeout
	_me = get_tree().get_first_node_in_group("local_player")
	var prompt := get_tree().get_first_node_in_group("name_prompt")
	if prompt and prompt.visible:
		prompt.submit("Bonk")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_dir = get_tree().get_first_node_in_group("zombie_director")
	_combat = get_tree().get_first_node_in_group("combat_world")
	var weather := get_tree().get_first_node_in_group("weather")
	if weather:
		weather.request_mode("clear")
	for n: Node in get_tree().get_nodes_in_group("players"):  # park Bonk far away, still
		if n != _me and n.get_script() and str(n.get_script().resource_path).ends_with("bonk.gd"):
			n.global_position += Vector3(0, 400, 0)
			n.process_mode = Node.PROCESS_MODE_DISABLED
	await _go_open()
	_quiet()
	await _riot()
	await _bloater()
	await _runner()
	await _spitter()
	_drops()
	_spawn_types()
	await _lineup()
	await _perf()
	_log.append("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/zombie_types_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	get_tree().quit()


func _pure() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var bands: Array = DataLoader.load_json("res://data/tuning/zombies.json").types_by_distance
	var near := {}
	var far := {}
	for i in 2000:
		var a := ZombieTypeRules.pick_type(bands, 100.0, rng)
		near[a] = int(near.get(a, 0)) + 1
		var b := ZombieTypeRules.pick_type(bands, 3000.0, rng)
		far[b] = int(far.get(b, 0)) + 1
	_check(near.keys() == ["zombie_shambler"], "100 m from the bunker: only Shamblers (%s)" % str(near))
	_check(far.size() == 5 and int(far.get("zombie_shambler", 0)) < 900, "3 km out: all five types, Shamblers a minority-ish (%s)" % str(far))
	var armor := {"body_mult": 0.25, "head_mult": 1.0, "melee_mult": 1.0, "head_from": 0.7}
	_check(is_equal_approx(ZombieTypeRules.armor_mult(armor, 0.5, false), 0.25) and is_equal_approx(ZombieTypeRules.armor_mult(armor, 0.85, false), 1.0)
		and is_equal_approx(ZombieTypeRules.armor_mult(armor, 0.5, true), 1.0) and is_equal_approx(ZombieTypeRules.armor_mult({}, 0.5, false), 1.0),
		"armor: body 25%, head 100%, melee 100%, no armor 100%")
	var burst := {"radius_m": 4.5, "damage": 50.0, "edge_frac": 0.35}
	_check(is_equal_approx(ZombieTypeRules.burst_damage(burst, 0.0), 50.0) and is_equal_approx(ZombieTypeRules.burst_damage(burst, 4.5), 17.5)
		and ZombieTypeRules.burst_damage(burst, 4.6) == 0.0, "burst: 50 at the centre, 17.5 at 4.5 m, 0 beyond")
	for id: String in TYPES:
		_check(not EnemyDB.get_enemy(id).is_empty(), "enemy '%s' loads" % id)
	for t: String in ["zombie_riot", "zombie_bloater", "zombie_spitter"]:
		_check(not LootDB.get_table(t).is_empty(), "drop table '%s' loads" % t)
	var recipes := DataLoader.load_json("res://data/crafting/recipes.json")
	_check(recipes.has("bile_shells") and recipes.has("bile_556"), "Caustic Bile recipes exist")


# Puts every street zombie back and stops new spawns, so the test controls who is where.
func _quiet() -> void:
	_dir.set("_spawn_timer", 1.0e9)
	for z in _dir.get("_pool"):
		if z.net_active:
			z.deactivate()


func _spawn(type: String, offset: Vector3, face_me := true) -> Node:
	for z in _dir.get("_pool"):
		if not z.net_active:
			z.net_enemy = type
			var p := _ground(_me.global_position + offset)
			var to := _me.global_position - p
			z.activate(p, atan2(-to.x, -to.z) if face_me else 0.0)
			return z
	return null


func _ground(p: Vector3) -> Vector3:
	var hit := _me.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 30.0, p + Vector3.DOWN * 30.0, 17))
	return (hit.position as Vector3) if not hit.is_empty() else p


func _shoot_at(target: Vector3, damage := 40.0) -> void:
	var eye: Vector3 = _me.eye_position()
	var w := {"id": "pistol_9mm", "damage": damage, "range": 60.0, "noise_radius": 0.0}
	_combat.host_fire(_me, w, eye, (target - eye).normalized(), float(get_tree().get_first_node_in_group("net_clock").tick))


func _riot() -> void:
	Zombie_frozen(true)
	var z := _spawn("zombie_riot", _forward() * 6.0)
	await get_tree().physics_frame
	var base: Vector3 = z.global_position
	var h: float = z.get("_height")
	var hp0: float = z.health.current
	_shoot_at(base + Vector3.UP * h * 0.45)
	var body_dmg := hp0 - float(z.health.current)
	var hp1: float = z.health.current
	_shoot_at(base + Vector3.UP * h * 0.88)
	var head_dmg := hp1 - float(z.health.current)
	var hp2: float = z.health.current
	var bat := {"id": "bat_baseball", "damage": 40.0, "range": 2.4, "arc_degrees": 80.0, "noise_radius": 0.0}
	var eye: Vector3 = _me.eye_position()
	z.global_position = _me.global_position + _forward() * 1.2
	_combat.host_melee(_me, bat, eye, (z.global_position + Vector3.UP * 1.0 - eye).normalized(), float(get_tree().get_first_node_in_group("net_clock").tick))
	var melee_dmg := hp2 - float(z.health.current)
	_log.append("riot cop: body shot %.1f, head shot %.1f, bat %.1f (of 40)" % [body_dmg, head_dmg, melee_dmg])
	_check(is_equal_approx(body_dmg, 10.0), "Riot Cop: a body shot does 25%")
	_check(is_equal_approx(head_dmg, 40.0), "Riot Cop: a head shot does full damage")
	_check(is_equal_approx(melee_dmg, 40.0), "Riot Cop: melee does full damage")
	z.deactivate()


func _bloater() -> void:
	var b := _spawn("zombie_bloater", _forward() * 3.0)
	var s := _spawn("zombie_shambler", _forward() * 3.0 + _right() * 2.0)
	await get_tree().physics_frame
	_me.health.damage_mult = 1.0
	_me.health.reset()
	var me0: float = _me.health.current
	var s0: float = s.health.current
	b.health.apply_damage(9999.0, 0)
	for i in 4:
		await get_tree().physics_frame
	var me_dmg := me0 - float(_me.health.current)
	var s_dmg := s0 - float(s.health.current)
	_log.append("bloater burst: player took %.1f, shambler 2 m from it took %.1f" % [me_dmg, s_dmg])
	_check(me_dmg > 15.0 and me_dmg < 50.0, "Bloater: its burst hurts a player 3 m away")
	_check(s_dmg > 15.0, "Bloater: its burst hurts a zombie next to it")
	_me.health.damage_mult = 0.0
	_me.health.reset()
	b.deactivate()
	s.deactivate()


func _runner() -> void:
	var r := _spawn("zombie_runner", _forward() * 50.0)
	var s := _spawn("zombie_shambler", _forward() * -50.0)
	await get_tree().physics_frame
	_dir.host_noise(_me.global_position, 35.0)
	_check(bool(r.get("_heard")), "Runner: hears a 35 m gunshot from 50 m away")
	_check(not bool(s.get("_heard")), "Shambler: doesn't hear it from 50 m")
	r.set("_heard", false)
	r.deactivate()
	s.deactivate()


func _spitter() -> void:
	Zombie_frozen(false)
	var sp := _spawn("zombie_spitter", _forward() * 9.0)
	_me.health.damage_mult = 1.0
	_me.health.reset()
	var hp0: float = _me.health.current
	var attacks := 0
	var seen := 0
	var was := false
	for i in 150:  # 15 s: ~6 spits; each can miss (3.5 deg spread)
		await get_tree().create_timer(0.1).timeout
		if sp.net_attacking and not was:
			attacks += 1
		was = sp.net_attacking
		if bool(sp.get("_sees_target")):
			seen += 1
	var took := hp0 - float(_me.health.current)
	var eye: Vector3 = sp.global_position + Vector3.UP * 1.6
	var blocked := _me.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye, _me.eye_position(), 1))
	_log.append("spitter: the player took %.1f in 15 s (state %d, %d wind-ups, saw the player %d/150 ticks, %.1f m, line of sight %s)" % [took,
		sp.brain.state, attacks, seen, sp.global_position.distance_to(_me.global_position), "clear" if blocked.is_empty() else "blocked by " + str(blocked.collider)])
	_check(took > 0.0, "Spitter: hits a player from range")
	_me.health.damage_mult = 0.0
	_me.health.reset()
	sp.deactivate()
	Zombie_frozen(true)


func _drops() -> void:
	var drops := get_tree().get_first_node_in_group("world_drops")
	var before: int = drops.drops.size()
	var b := _spawn("zombie_bloater", _forward() * 4.0)
	for i in 10:
		_dir.call("_on_zombie_died", 0, b)
	_check(drops.drops.size() > before, "Bloater deaths leave Caustic Bile (%d drops from 10)" % (drops.drops.size() - before))
	b.deactivate()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var got := {}
	for i in 400:
		var r := LootRules.roll(LootDB.get_table("zombie_riot"), rng)
		for k: String in r:
			got[k] = int(got.get(k, 0)) + 1
	_log.append("400 Riot Cop drops: %s" % str(got))
	_check(got.has("helmet_riot") and got.has("ammo_9mm"), "Riot Cop drops ammo and riot armor")


func _spawn_types() -> void:
	var home := get_tree().root.find_child("bonk_bunker", true, false) as Node3D
	_check(home != null, "the bunker landmark is found")
	if home == null:
		return
	var near := {}
	var far := {}
	for i in 200:
		var a: String = _dir.call("_type_at", home.global_position + Vector3(150, 0, 0))
		near[a] = int(near.get(a, 0)) + 1
		var b: String = _dir.call("_type_at", home.global_position + Vector3(2000, 0, 1500))
		far[b] = int(far.get(b, 0)) + 1
	_log.append("spawn types 150 m out: %s; 2.5 km out: %s" % [str(near), str(far)])
	_check(near.keys() == ["zombie_shambler"], "spawns near the bunker are Shamblers")
	_check(far.size() >= 4, "spawns 2.5 km out mix the special types")


func _lineup() -> void:
	var i := 0
	for t: String in TYPES:
		_spawn(t, _forward() * 6.0 + _right() * (float(i) - 2.0) * 1.6)
		i += 1
	_me.pitch = -0.05
	_me.head.rotation.x = _me.pitch
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR + "/zombie_types_lineup.png"))
	_log.append("shot zombie_types_lineup.png (left to right: %s)" % ", ".join(TYPES))
	for z in _dir.get("_pool"):
		if z.net_active:
			z.deactivate()


# The whole pool awake and chasing around the player (worst case: 40 active with 10 per cell).
func _perf() -> void:
	Zombie_frozen(false)
	var base_phys := 0.0
	for i in 120:
		await get_tree().process_frame
		base_phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_log.append("perf with no zombies: physics %.1f ms" % (base_phys / 120.0))
	var pool: Array = _dir.get("_pool")
	var n := 0
	for z in pool:
		var a := TAU * float(n) / float(pool.size())
		var d := 25.0 + float(n % 4) * 8.0
		z.net_enemy = TYPES[n % TYPES.size()]
		z.activate(_ground(_me.global_position + Vector3(cos(a) * d, 0, sin(a) * d)))
		n += 1
	await get_tree().create_timer(4.0).timeout
	var phys := 0.0
	var frame := 0.0
	var worst := 0.0
	for i in 120:
		await get_tree().process_frame
		var p := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		phys += p
		frame += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		worst = maxf(worst, p)
	_log.append("perf with %d zombies active: frame %.1f ms, physics %.1f ms (worst %.1f), %d draw calls" % [_dir.active_count,
		frame / 120.0, phys / 120.0, worst, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	_check(phys / 120.0 < 8.0, "physics stays under 8 ms with the full pool chasing")


func Zombie_frozen(on: bool) -> void:
	ZombieScript.frozen = on


# Moves the player to the first candidate spot that has a flat, open line of sight (60 m ahead, 55 m behind, 12 m to
# the right with the ground within 0.6 m of the player's feet over the first 12 m ahead).
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
	return _forward().cross(Vector3.UP).normalized()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	_log.append(("PASS " if ok else "FAIL ") + what)
