# WeatherTest — sky and weather (D-099).
# Pure: the schedule never repeats a state and follows the weights; state levels; blending; zombies hear less in
# storms; strike damage falls off with distance; storm wind is stronger but capped.
# In game (offline world, outdoors near the bunker): clear sky with clouds (screenshot); the host forces rain then a
# storm from the weather mode; rain falls outside and stops indoors; a lightning strike next to a player outside
# hurts, under the bunker roof it doesn't; the pause menu shows the weather button; perf in a storm.
# Screenshots tests/_look/weather_*.png. Results: tests/_look/weather_result.txt (ends with the failure count).
# Depends on: scenes/main.tscn, WeatherRules, WeatherDirector, Atmosphere.
extends Node

const OUT_DIR := "res://tests/_look"

var _log := PackedStringArray()
var _fails := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keeps running while the solo pause menu is open
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_pure()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz weather")
	main.menu.play_offline.emit()
	await get_tree().create_timer(5.0).timeout
	var prompt := get_tree().get_first_node_in_group("name_prompt")
	if prompt and prompt.visible:
		prompt.submit("Bonk")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var me: Node3D = get_tree().get_first_node_in_group("local_player")
	var w: WeatherDirector = get_tree().get_first_node_in_group("weather")
	_check(w != null and w.state == "clear", "Weather node up, starts clear")
	var spawn: Vector3 = me.global_position
	var outside := await _go_outside(me)
	_check(outside != Vector3.INF, "found open sky near the bunker at %s" % outside)
	me.pitch = 0.35
	me.head.rotation.x = 0.35
	await get_tree().create_timer(1.5).timeout
	await _shot("weather_clear.png")
	w.request_mode("rain")
	w.levels = WeatherRules.levels("rain", w._t)
	await get_tree().create_timer(1.2).timeout
	_check(w.mode == "rain" and w._rain.emitting and not w._indoors, "forced rain: falling outside (%.0f%% of max)" % (w._rain.amount_ratio * 100.0))
	await _shot("weather_rain.png")
	w.request_mode("storm")
	w.levels = WeatherRules.levels("storm", w._t)
	await get_tree().create_timer(0.6).timeout
	_check(is_equal_approx(w.hearing_mult(), 0.55), "storm: zombies hear at %.2f x" % w.hearing_mult())
	me.health.damage_mult = 1.0
	var hp: float = me.health.current
	w._host_strike(me.global_position + Vector3(1.0, 0, 0))
	await get_tree().create_timer(0.15).timeout
	await _shot("weather_storm_strike.png")
	_check(me.health.current < hp - 30.0, "a strike 1 m away outside: %.0f -> %.0f hp" % [hp, me.health.current])
	me.health.current = me.health.max_health
	me.global_position = spawn
	await get_tree().create_timer(1.2).timeout
	hp = me.health.current
	w._host_strike(me.global_position + Vector3(1.0, 0, 0))
	await get_tree().create_timer(0.2).timeout
	_check(is_equal_approx(me.health.current, hp) and w._indoors and not w._rain.emitting, "under the bunker roof: no damage, no rain inside")
	var pause := get_tree().get_first_node_in_group("pause_menu")
	pause.open()
	await get_tree().process_frame
	_check(pause._weather.visible and pause._weather.text.contains("Storm"), "pause menu: '%s'" % pause._weather.text)
	pause._cycle_weather()
	_check(w.mode == "auto", "the button cycles back to Auto")
	pause.close()
	me.global_position = outside
	w.request_mode("storm")
	await get_tree().create_timer(1.0).timeout
	var sum := 0.0
	for i in 120:
		await get_tree().process_frame
		sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_log.append("perf in a storm: frame %.1f ms, draw calls %d" % [sum / 120.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	_log.append("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/weather_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	get_tree().quit()


# Walks a ring out from the spawn until a spot with open sky above (not under the bunker roof).
func _go_outside(me: Node3D) -> Vector3:
	var w: WeatherDirector = get_tree().get_first_node_in_group("weather")
	var base := me.global_position
	for r in [12.0, 20.0, 30.0, 45.0]:
		for k in 8:
			var p: Vector3 = base + Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 8.0) * r
			var hit := me.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 60.0, p + Vector3.DOWN * 60.0, 17))
			if hit.is_empty():
				continue
			var at: Vector3 = hit.position + Vector3.UP * 0.2
			if not w._under_roof(at):
				me.global_position = at
				await get_tree().create_timer(0.5).timeout
				return at
	return Vector3.INF


func _pure() -> void:
	var t := WeatherRules.tuning()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var counts := {}
	var repeat := false
	var s := "clear"
	for i in 4000:
		var n := WeatherRules.pick_next(s, rng, t)
		repeat = repeat or n == s
		counts[n] = int(counts.get(n, 0)) + 1
		s = n
	_check(not repeat and int(counts.get("storm", 0)) > 200, "schedule: never the same twice, all states come up %s" % counts)
	_check(WeatherRules.levels("storm", t) == Vector3(1, 1, 0.1) and WeatherRules.levels("fog", t).z == 1.0, "state levels")
	var b := WeatherRules.blend(Vector3.ZERO, Vector3.ONE, 5.0, t)
	_check(absf(b.x - 0.2) < 0.01, "blend: 5 s of 25 = %.2f" % b.x)
	_check(is_equal_approx(WeatherRules.strike_damage(0.0, t), 70.0) and WeatherRules.strike_damage(5.0, t) == 0.0
		and absf(WeatherRules.strike_damage(2.25, t) - 35.0) < 0.1, "strike damage: 70 at the centre, half at 2.25 m, none past 4.5 m")
	var sw := WeatherRules.storm_wind(Vector2(8.0, 0.0), 1.0, rng, t)
	_check(is_equal_approx(sw.length(), 9.0) and WeatherRules.storm_wind(Vector2(3, 0), 0.0, rng, t) == Vector2(3, 0),
		"storm wind: 8 -> 9 m/s (capped), calm weather unchanged")


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR + "/" + file))
	_log.append("shot " + file)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	_log.append(("PASS " if ok else "FAIL ") + what)
	print("WEATHER: " + _log[-1])
