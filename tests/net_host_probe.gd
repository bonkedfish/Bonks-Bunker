# NetHostProbe — dev check: hosts a Tube lobby and prints which trackers accepted it, then quits.
# Run this scene directly. Safe to delete. Depends on: Net autoload.
extends Node


func _ready() -> void:
	Net.session_started.connect(func() -> void: print("PROBE: lobby created, code = ", Net.lobby_code))
	Net.session_failed.connect(func(reason: String) -> void: print("PROBE: failed: ", reason))
	Net.host()
	await get_tree().create_timer(10.0).timeout
	var open := 0
	for tracker in Net.tube._trackers:
		if tracker.is_open():
			open += 1
	print("PROBE: trackers open after 10s = %d of %d configured" % [open, Net.tube.context.trackers_urls.size()])
	get_tree().quit()
