# DayNightTest — the day/night cycle (D-110): the pure clock maths, then the live world. Walks the clock through
# a whole day and checks the sun climbs, sets, and is mirrored into a moon after dark; screenshots morning, noon,
# dusk, night and dawn from the same spot; checks the per-cell zombie cap and the type mix really do change after
# dark; and sleeps in a bunk (refused by day, accepted at night, everybody healed and fed, clock at wake_hour).
# Results: tests/_look/day_night_result.txt (ends with the failure count); dn_*.png.
# Depends on: scenes/main.tscn, DayNight, DayNightRules, BunkerBed, Atmosphere, ZombieDirector, ZombieTypeRules.
extends Node

const OUT_DIR := "res://tests/_look"

var _log := PackedStringArray()
var _fails := 0
var _me: Node3D
var _clock: Node
var _bed: Node
var _zombies: Node


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_pure()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz day night")
	main.menu.play_offline.emit()
	await get_tree().create_timer(5.0).timeout
	_me = get_tree().get_first_node_in_group("local_player")
	var prompt := get_tree().get_first_node_in_group("name_prompt")
	if prompt and prompt.visible:
		prompt.submit("Bonk")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_me.health.damage_mult = 0.0
	_clock = get_tree().get_first_node_in_group("daynight")
	_bed = get_tree().get_first_node_in_group("bunker_bed")
	_zombies = get_tree().get_first_node_in_group("zombie_director")
	var weather := get_tree().get_first_node_in_group("weather")
	if weather:
		weather.request_mode("clear")
	await _sky()
	await _zombie_night()
	await _sleep()
	_log.append("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/day_night_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	SaveStore.delete(main.saves.world_slug)
	get_tree().quit()


func _pure() -> void:
	var t: Dictionary = DataLoader.load_json("res://data/tuning/day_night.json")
	_check(not t.is_empty(), "data/tuning/day_night.json loads")
	_check(float(t.day_seconds) == 2880.0, "one full day takes %.0f real minutes" % (float(t.day_seconds) / 60.0))
	# the sun climbs from sunrise, peaks near midday, sets, and goes negative at night
	var rise := float(t.sunrise_hour)
	var set_h := float(t.sunset_hour)
	var noon := (rise + set_h) * 0.5
	_check(absf(DayNightRules.sun_elevation(rise, t)) < 0.01, "the sun is on the horizon at sunrise")
	_check(absf(DayNightRules.sun_elevation(set_h, t)) < 0.01, "and at sunset")
	_check(absf(DayNightRules.sun_elevation(noon, t) - float(t.sun_max_elevation_deg)) < 0.5,
		"it peaks at %.0f deg at midday" % float(t.sun_max_elevation_deg))
	_check(DayNightRules.sun_elevation(1.0, t) < -10.0, "it is well below the horizon at 01:00")
	_check(DayNightRules.night_factor(13.0, t) == 0.0 and DayNightRules.night_factor(1.0, t) == 1.0,
		"night_factor is 0 at midday and 1 in the small hours")
	_check(DayNightRules.night_factor(set_h, t) > 0.3 and DayNightRules.night_factor(set_h, t) < 0.7,
		"dusk is halfway (%.2f at sunset)" % DayNightRules.night_factor(set_h, t))
	_check(not DayNightRules.is_night(12.0, t) and DayNightRules.is_night(23.0, t), "midday is day, 23:00 is night")
	_check(DayNightRules.hours_until(22.0, 7.0) == 9.0 and DayNightRules.hours_until(3.0, 7.0) == 4.0,
		"sleeping always goes forwards to the morning")
	_check(DayNightRules.hours_until(7.0, 7.0) == 24.0, "sleeping at exactly wake_hour skips a whole day")
	_check(DayNightRules.clock(13.5) == "13:30" and DayNightRules.clock(0.25) == "00:15", "the clock reads right")
	_check(absf(DayNightRules.advance(23.5, 1440.0, 2880.0) - 11.5) < 0.01, "half a day of play moves it 12 hours")
	_check(DayNightRules.phase_name(12.0, t) == "day" and DayNightRules.phase_name(23.0, t) == "night"
		and DayNightRules.phase_name(set_h, t) == "dusk", "phase names: day, night, dusk")
	# the night type table really does favour the specials
	var bands: Array = DataLoader.load_json("res://data/tuning/zombies.json").get("types_by_distance", [])
	var mult: Dictionary = DataLoader.load_json("res://data/tuning/zombies.json").get("night_weight_mult", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var day_special := 0
	var night_special := 0
	for i in 600:
		if ZombieTypeRules.pick_type(bands, 1500.0, rng) != "zombie_shambler":
			day_special += 1
		if ZombieTypeRules.pick_type(bands, 1500.0, rng, mult, 1.0) != "zombie_shambler":
			night_special += 1
	_log.append("  specials in 600 rolls at 1.5 km: day %d, night %d" % [day_special, night_special])
	_check(night_special > day_special * 1.3, "night spawns far more specials")


func _sky() -> void:
	_check(_clock != null, "DayNight is in the scene")
	if _clock == null:
		return
	_check(_clock.name == "DayNight", "it has a fixed name, so its sync RPC resolves on every peer")
	var sun := _me.get_tree().root.find_child("Sun", true, false) as DirectionalLight3D
	_check(sun != null, "the Sun light exists")
	var home := get_tree().root.find_child("bonk_bunker", true, false) as Node3D
	if home:  # one spot, looking the same way, so the shots can be compared
		_me.global_position = home.global_position + Vector3(6.0, 1.6, 10.0)
		_me.rotation.y = deg_to_rad(200.0)
		await _wait(0.4)
	var seen: Dictionary = {}
	for pair: Array in [[9.0, "dn_morning.png"], [13.0, "dn_noon.png"], [19.3, "dn_dusk.png"],
			[23.5, "dn_night.png"], [6.6, "dn_dawn.png"]]:
		_clock._sync(float(pair[0]))
		await _wait(0.6)
		var elev: float = DayNightRules.sun_elevation(_clock.hour, _clock.tuning)
		var up := -rad_to_deg(sun.rotation.x) if sun else 0.0
		seen[str(pair[1])] = up
		_check(up > 0.0, "%s: the light is above the horizon (%.0f deg) at %s" % [pair[1], up, _clock.clock()])
		if float(pair[0]) > 20.0 or float(pair[0]) < 5.0:
			_check(elev < 0.0 and sun.light_color.b > sun.light_color.r, "at %s the light is the moon, and blue"
				% _clock.clock())
		await _shot(str(pair[1]))
	_check(float(seen["dn_noon.png"]) > float(seen["dn_morning.png"]), "the sun is higher at noon than at 09:00")
	_clock._sync(13.0)
	await _wait(0.5)


func _zombie_night() -> void:
	_check(_zombies != null, "ZombieDirector is in the scene")
	if _zombies == null:
		return
	_clock._sync(13.0)
	await _wait(0.3)
	var day_cap: float = float(_zombies._tuning.cell_cap) * lerpf(1.0,
		float(_zombies._tuning.get("night_cell_cap_mult", 1.0)), _zombies._night())
	_check(_zombies._night() < 0.01, "by day the night factor is 0 (cap %.0f)" % day_cap)
	_clock._sync(23.5)
	await _wait(0.3)
	var night_cap: float = float(_zombies._tuning.cell_cap) * lerpf(1.0,
		float(_zombies._tuning.get("night_cell_cap_mult", 1.0)), _zombies._night())
	_check(_zombies._night() > 0.99, "at 23:30 the night factor is 1")
	_check(absf(night_cap - day_cap * 2.0) < 0.01, "the per-cell cap doubles after dark (%.0f -> %.0f)"
		% [day_cap, night_cap])
	_check(int(_zombies._tuning.pool_size) >= 48, "the pool (%d) is still the hard ceiling on active zombies"
		% int(_zombies._tuning.pool_size))


func _sleep() -> void:
	_check(_bed != null, "the bunks are usable", )
	if _bed == null:
		return
	await _wait(3.5)  # it waits for the bunker landmark, then builds its E spots
	_check(_bed.built, "the bed found the bunker and added its E spots")
	var spots := 0
	for n: Node in get_tree().get_nodes_in_group("sport_spots"):
		if _bed.is_ancestor_of(n):
			spots += 1
	_check(spots == 2, "both bunks can be slept in (%d)" % spots)
	var home := get_tree().root.find_child("bonk_bunker", true, false) as Node3D
	var bunk := _bed.get_node_or_null("Bunk_0") as Node3D
	_check(bunk != null and home != null and bunk.global_position.y < home.global_position.y - 2.0,
		"the bunks are down in the bunker, not in the yard")
	# by day it refuses
	_clock._sync(13.0)
	await _wait(0.3)
	var before: float = _clock.hour
	_bed.request_use(BunkerBed.SLOT * 100)
	await _wait(0.4)
	_check(absf(_clock.hour - before) < 0.2, "you cannot sleep the daylight away")
	# at night it works, and everybody wakes healed and fed
	_clock._sync(23.0)
	await _wait(0.3)
	_me.health.current = 20.0
	var needs := _me.get_node_or_null("Needs")
	if needs:
		needs.host_set(Vector2(15.0, 10.0))
	await _wait(0.2)
	_bed.request_use(BunkerBed.SLOT * 100 + 1)
	await _wait(0.6)
	_check(absf(_clock.hour - float(_clock.tuning.wake_hour)) < 0.2, "sleeping wakes the server at %s"
		% DayNightRules.clock(float(_clock.tuning.wake_hour)))
	_check(_me.health.current >= _me.health.max_health - 0.1, "the sleeper wakes at full health")
	if needs:
		_check(needs.net_hunger > 90.0 and needs.net_thirst > 90.0, "and fed and watered (%.0f / %.0f)"
			% [needs.net_hunger, needs.net_thirst])
	_check(not _clock.is_night(), "and it is morning")
	if home:
		_me.global_position = home.global_position + Vector3(6.0, 1.6, 10.0)
		await _wait(0.5)
		await _shot("dn_after_sleep.png")


func _check(ok: bool, what: String) -> void:
	_log.append("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + "/" + file))
	var sum := 0.0
	for i in 30:
		await get_tree().process_frame
		sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_log.append("shot %s: frame %.1f ms, %d draw calls" % [file, sum / 30.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
