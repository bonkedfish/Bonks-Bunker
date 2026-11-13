# ControlsList — the keybind list shown on the start screen and in the pause menu (D-063, D-068): each action's
# keys read live from the InputMap, two action/key pairs per row. Depends on: the project's InputMap actions.
extends RefCounted

const CONTROLS := [
	["move_forward", "Move forward"], ["move_back", "Move back"], ["move_left", "Move left"], ["move_right", "Move right"],
	["jump", "Jump"], ["sprint", "Sprint"], ["crouch", "Crouch"], ["fire", "Shoot / swing"], ["reload", "Reload"],
	["weapon_1", "Pistol"], ["weapon_2", "Bat"], ["interact", "Use / talk / loot / revive"], ["inventory", "Inventory"],
	["quick_heal", "Quick heal (bandage)"], ["quick_eat", "Quick eat"], ["ride", "Hop on / off the Meepo (Shift = boost)"],
	["disc_mode", "Next disc (disc golf) / next club (Drop Zone)"], ["disc_tilt_left", "Disc: tilt left (curve left)"],
	["disc_tilt_right", "Disc: tilt right (curve right)"], ["disc_grip", "Disc: backhand / forehand"], ["scorecard", "Disc golf scorecard"],
	["quest_book", "Quest book"], ["world_map", "Map"], ["quicksave", "Quicksave (host)"], ["toggle_debug", "Performance overlay"],
]

const EXTRA := [["Look around", "Mouse"], ["Pause / settings", "Esc"], ["Take all from a container", "R"],
	["Disc: charge / throw", "Hold / release left click"], ["Disc: cancel throw", "Right click"]]


static func build() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 24)
	var rows: Array = []
	for c: Array in CONTROLS:
		rows.append([str(c[1]), keys_for(str(c[0]))])
	rows.append_array(EXTRA)  # [what, key] already
	for r: Array in rows:
		var what := Label.new()
		what.text = str(r[0])
		grid.add_child(what)
		var key := Label.new()
		key.text = str(r[1])
		key.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
		grid.add_child(key)
	return grid


static func keys_for(action: String) -> String:
	if not InputMap.has_action(action):
		return "-"
	var names := PackedStringArray()
	for e: InputEvent in InputMap.action_get_events(action):
		var t := e.as_text().replace(" (Physical)", "").replace(" - Physical", "").replace("Left Mouse Button", "Left click").replace("Right Mouse Button", "Right click")
		if t != "" and not names.has(t):
			names.append(t)
	return " / ".join(names) if not names.is_empty() else "-"
