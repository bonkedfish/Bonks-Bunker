# EncounterDebug — F6 panel for the encounter systems (D-105..D-108). Lists every encounter definition with its
# rarity, weight, chance of being picked next and why it is or isn't eligible right now (its own cooldown, the
# global cooldown, hours, weather, distance from the bunker, quest flags), the open sites, the oddities that were
# skipped for want of ground, how many of each collectible the party holds, and the rare events with how many
# times each has happened and how long until it may happen again.
# Keys while it is open: W / S or Up / Down pick a line, TAB switches between the encounter and rare-event lists,
# ENTER force-triggers the picked one at the player (host only for encounters), C clears every cooldown, and
# O reports the oddity placement counts. Everything it does goes through debug_force / force / debug_report, so it
# cannot put the directors into a state normal play can't reach. Read-only otherwise; never shown to players
# unless they press F6.
# Group "encounter_debug". Depends on: EncounterDirector, RareEventDirector, WorldOddities, CollectibleManager,
# EncounterRules, QuestDirector, HUD (group "hud").
extends RichTextLabel

const REFRESH := 0.4
const ROWS := 22

var shown := false

var _tab := 0  # 0 = encounters, 1 = rare events
var _row := 0
var _accum := 0.0
var _note := ""


func _ready() -> void:
	add_to_group("encounter_debug")
	bbcode_enabled = true
	scroll_active = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = 18.0
	offset_top = 150.0
	offset_right = 700.0
	offset_bottom = 720.0


func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum < REFRESH:
		return
	_accum = 0.0
	_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: int = (event as InputEventKey).keycode
	if key == KEY_F6:
		shown = not shown
		visible = shown
		_accum = REFRESH
		return
	if not visible:
		return
	match key:
		KEY_UP, KEY_W:
			_row = maxi(0, _row - 1)
		KEY_DOWN, KEY_S:
			_row += 1
		KEY_TAB:
			_tab = 1 - _tab
			_row = 0
		KEY_ENTER, KEY_KP_ENTER:
			_fire()
		KEY_C:
			_clear()
		KEY_O:
			var odd := get_tree().get_first_node_in_group("oddities")
			_note = "oddities: %d built, %d skipped (no ground / blocked)" % [
				odd.built.size(), odd.skipped_count] if odd else "no oddities node"
	_accum = REFRESH


# --- actions -------------------------------------------------------------------------

func _fire() -> void:
	var ids := _ids()
	if ids.is_empty():
		return
	var id: String = ids[clampi(_row, 0, ids.size() - 1)]
	if _tab == 1:
		var rare := get_tree().get_first_node_in_group("rare_events")
		_note = "rare '%s': %s" % [id, "showing" if rare and rare.force(id) else "no spot for it here"]
		return
	var enc := get_tree().get_first_node_in_group("encounters")
	if enc == null:
		return
	if not multiplayer.is_server():
		_note = "encounters are opened by the host"
		return
	var me := get_tree().get_first_node_in_group("local_player")
	var slot: int = enc.debug_force(id, me)
	_note = "encounter '%s': %s" % [id, "opened in slot %d" % slot if slot >= 0 else "no spot free near you"]


func _clear() -> void:
	var enc := get_tree().get_first_node_in_group("encounters")
	if enc:
		enc.state = EncounterRules.new_state()
		enc._global_until = 0.0
	var rare := get_tree().get_first_node_in_group("rare_events")
	if rare:
		rare._last.clear()
	_note = "cooldowns cleared"


# --- readout -------------------------------------------------------------------------

func _ids() -> Array:
	var node := get_tree().get_first_node_in_group("rare_events" if _tab == 1 else "encounters")
	if node == null:
		return []
	var ids: Array = node.defs.keys()
	ids.sort()
	return ids


func _rebuild() -> void:
	var enc := get_tree().get_first_node_in_group("encounters")
	var rare := get_tree().get_first_node_in_group("rare_events")
	var odd := get_tree().get_first_node_in_group("oddities")
	var col := get_tree().get_first_node_in_group("collectibles")
	if enc == null:
		text = "no encounter director in this scene"
		return
	var ids := _ids()
	_row = clampi(_row, 0, maxi(0, ids.size() - 1))
	var head := "[b]ENCOUNTER DEBUG[/b]   F6 close   TAB %s   W/S pick   ENTER trigger   C clear cooldowns   O oddities\n" % [
		"encounters | [b]rare events[/b]" if _tab == 1 else "[b]encounters[/b] | rare events"]
	var lines := PackedStringArray([head])
	if _tab == 0:
		lines.append("active %d/%d   global cooldown %s   in-game hour %04.1f   %s" % [
			enc.sites.size(), int(enc._t.get("max_active", 3)), _wait(enc.global_left()), enc.hour(), enc.weather_now()])
		var reasons := {}
		var total: float = enc.debug_weights(reasons)
		lines.append("")
		for i in range(ids.size()):
			var id: String = ids[i]
			var d: Dictionary = enc.defs[id]
			var w := float(reasons.get(id + "#w", 0.0))
			var why := str(reasons.get(id, ""))
			var mark := ">" if i == _row else " "
			var open_mark := "[color=#8fe08f]OPEN[/color]" if enc.is_open(id) else ""
			if why == "":
				lines.append("%s %-20s %-9s w %4.1f  %4.1f%%  %s" % [mark, id, str(d.get("rarity", "common")), w,
					100.0 * w / maxf(total, 0.001), open_mark])
			else:
				lines.append("%s %-20s %-9s [color=#9a9a9a]%s[/color] %s" % [mark, id, str(d.get("rarity", "common")), why, open_mark])
		lines.append("")
		lines.append("oddities %s   collectibles %s" % [
			"%d built / %d skipped" % [odd.built.size(), odd.skipped_count] if odd else "-",
			_collect(col)])
	else:
		lines.append("chance %.2f every %.0f s per check; one player at a time" % [
			float(rare._t.get("chance", 0.3)), float(rare._t.get("check_seconds", 150.0))] if rare else "no rare events node")
		lines.append("")
		for i in range(ids.size()):
			var id: String = ids[i]
			var d: Dictionary = rare.defs[id]
			var mark := ">" if i == _row else " "
			lines.append("%s %-22s seen %2d/%-3s  cooldown %-9s %s" % [mark, id, int(rare.seen.get(id, 0)),
				str(d.get("max_times", 99)), _wait(rare._cooldown_left(id)),
				"[color=#8fe08f]SHOWING[/color]" if rare.showing == id else ""])
	if _note != "":
		lines.append("")
		lines.append("[color=#ffd36e]%s[/color]" % _note)
	text = "\n".join(lines)


func _collect(col: Node) -> String:
	if col == null:
		return "-"
	var counts: Dictionary = col.counts()
	var have := 0
	for id: String in counts:
		if int(counts[id]) > 0:
			have += 1
	return "%d / %d types, %d spots left" % [have, counts.size(), col.spots.size() - col.taken.size()]


func _wait(seconds: float) -> String:
	if seconds <= 0.0:
		return "ready"
	return "%d:%02d" % [floori(seconds / 60.0), int(seconds) % 60]
