# NetRecoveryTest — the lobby recovers without restarting the game (D-091). In one run:
#   1. Join a lobby code nobody is hosting -> fails with a reason and lands on a FRESH start screen (new Main,
#      new TubeClient) instead of hanging on "Connecting...".
#   2. Host from that same screen -> gets a lobby code (online trackers) within the host wait.
#   3. Save & Quit to the menu, host again -> a new lobby code again (the old bug: a second attempt did nothing).
# Results: tests/_look/net_recovery_result.txt (ends with the failure count).
# Depends on: scenes/main.tscn, Net (autoload), SaveStore.
extends Node

const OUT := "res://tests/_look"

var _log := PackedStringArray()
var _fails := 0


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	var first_tube := Net.tube
	# 1. Bogus code.
	main.code_field.text = "ZQ9XW"
	main._on_join_pressed()
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(main) and Time.get_ticks_msec() - t0 < 40000:
		await get_tree().process_frame
	main = get_child(0) if get_child_count() > 0 else null
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	_check(main != null and Net.tube != first_tube and main.menu.visible,
		"bogus code: back on a fresh start screen with a new lobby client after %.1f s" % secs)
	if main:
		_check(main.status_label.text.length() > 10, "it says why: '%s'" % main.status_label.text.left(90))
	# 2 + 3. Host twice.
	for round in 2:
		main = get_child(0)
		main.world_picker.choose_new("zz net %d" % round)
		t0 = Time.get_ticks_msec()
		main._on_host_pressed()
		while Net.lobby_code == "" and Time.get_ticks_msec() - t0 < 15000:
			await get_tree().process_frame
		_check(Net.lobby_code.length() == 5 and multiplayer.is_server(),
			"host #%d: lobby %s after %.1f s" % [round + 1, Net.lobby_code, (Time.get_ticks_msec() - t0) / 1000.0])
		await get_tree().create_timer(2.0).timeout
		var slug: String = main.saves.world_slug
		Net.leave_to_menu.call_deferred(main)
		await get_tree().create_timer(1.5).timeout
		SaveStore.delete(slug)
		_check(Net.lobby_code == "" and get_child(0).menu.visible, "left: fresh start screen, no lobby")
	_say("%d failure(s)" % _fails)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var f := FileAccess.open(OUT + "/net_recovery_result.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	get_tree().quit()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	_say(("PASS " if ok else "FAIL ") + what)


func _say(s: String) -> void:
	print("NETRECOVERY: " + s)
	_log.append(s)
