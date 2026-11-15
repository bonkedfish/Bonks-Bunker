# DebugOverlay — F3 performance readout from the Perf autoload (D-038): graphics tier + GPU, frame time
# (average and worst in the last second), CPU/physics time, draw calls, primitives, RAM, VRAM, nodes,
# players, peers, zombies, and the CSV log path while hosting. Values over budget show in red with the budget.
# Rebuilds its text once per Perf sample, not every frame. On / off from F3 or the Settings menu, remembered per PC
# (user://settings.cfg [ui] debug_overlay); hidden while riding a bike (the bike HUD + controls use that corner).
# Group "debug_overlay". Depends on: Perf and Graphics autoloads, "toggle_debug" input action, group "bike_hud".
extends RichTextLabel

const RED := "#ff5a4a"
const SETTINGS_PATH := "user://settings.cfg"

var shown := true  # the player's choice (visible also drops while riding)
var _accum := 0.0


func _ready() -> void:
	add_to_group("debug_overlay")
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		shown = bool(cfg.get_value("ui", "debug_overlay", true))
	visible = shown
	bbcode_enabled = true
	fit_content = true
	scroll_active = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Bottom right, above the ammo line (the minimap has the top-left corner, D-067).
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -560.0
	offset_right = -12.0
	offset_top = -210.0
	offset_bottom = -64.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN


func _process(delta: float) -> void:
	_accum += delta
	if _accum < 0.5:
		return
	_accum = 0.0
	visible = shown and get_tree().get_first_node_in_group("bike_hud") == null
	if not visible:
		return
	var peers := multiplayer.get_peers().size() if multiplayer.has_multiplayer_peer() else 0
	text = "Graphics %s (%s)  %s\n" % [Graphics.tier.to_upper(), Graphics.choice, Graphics.adapter_name] \
		+ "FPS %d   frame %s   worst %.1f ms   cpu %.1f ms   physics %.1f ms\n" % [
			roundi(1000.0 / maxf(Perf.frame_ms, 0.001)), _val("frame_ms", Perf.frame_ms, "%.1f ms"),
			Perf.worst_ms, Perf.cpu_ms, Perf.physics_ms] \
		+ "draw calls %s   primitives %s\n" % [_val("draw_calls", Perf.draw_calls, "%d"), _val("primitives_k", Perf.primitives_k, "%dk")] \
		+ "RAM %s   VRAM %s   nodes %d\n" % [_val("ram_mb", Perf.ram_mb, "%d MB"), _val("vram_mb", Perf.vram_mb, "%d MB"), int(Perf.nodes)] \
		+ "players %d   peers %d   zombies %d" % [Perf.players, peers, Perf.zombies] \
		+ ("\nlog %s" % Perf.log_path if Perf.log_path != "" else "")


# "12.3 ms", or red "19.8 ms / 16.7" when over budget.
func _val(key: String, value: float, fmt: String) -> String:
	var shown := fmt % value
	if Perf.over.get(key, false):
		return "[color=%s]%s / %s[/color]" % [RED, shown, fmt % float(Perf.budgets[key])]
	return shown


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		set_shown(not shown)


# Turns the readout on / off and remembers it.
func set_shown(on: bool) -> void:
	shown = on
	visible = on
	_accum = 0.5  # refresh the text on the next frame
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("ui", "debug_overlay", on)
	cfg.save(SETTINGS_PATH)
