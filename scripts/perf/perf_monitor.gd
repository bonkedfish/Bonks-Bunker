# Perf — autoload: samples performance once per interval and checks it against the budgets in
# data/tuning/graphics.json (D-038). The F3 overlay shows these numbers; over-budget ones turn red.
# While hosting it also appends one CSV line per sample to user://perf/<date_time>.csv (keeps the
# newest keep_files logs) so a slow session can be sent over and read.
# Per frame it only tracks the worst frame time; everything else happens once per sample.
# Depends on: GraphicsRules (budgets), Graphics autoload (tier), zombie director (group "zombie_director").
extends Node

const LOG_DIR := "user://perf"

var frame_ms := 0.0
var worst_ms := 0.0
var cpu_ms := 0.0
var physics_ms := 0.0
var draw_calls := 0.0
var primitives_k := 0.0
var ram_mb := 0.0
var vram_mb := 0.0
var nodes := 0.0
var players := 0
var zombies := 0
var over: Dictionary = {}  # "frame_ms" / "draw_calls" / ... -> true when over budget
var budgets: Dictionary = {}
var log_path := ""

var _interval := 1.0
var _log_enabled := true
var _keep_files := 10
var _accum := 0.0
var _worst_in_interval := 0.0
var _file: FileAccess
var _started_ms := 0


func _ready() -> void:
	var data := GraphicsRules.load_data()
	budgets = data.get("budgets", {})
	var log_cfg: Dictionary = data.get("perf_log", {})
	_interval = float(log_cfg.get("interval_seconds", 1.0))
	_log_enabled = bool(log_cfg.get("enabled", true))
	_keep_files = int(log_cfg.get("keep_files", 10))
	for key: String in budgets:
		over[key] = false
	_started_ms = Time.get_ticks_msec()


func _process(delta: float) -> void:
	_worst_in_interval = maxf(_worst_in_interval, delta)
	_accum += delta
	if _accum >= _interval:
		_sample()


func _sample() -> void:
	var fps := maxf(Engine.get_frames_per_second(), 1.0)
	frame_ms = 1000.0 / fps
	worst_ms = _worst_in_interval * 1000.0
	_worst_in_interval = 0.0
	_accum = 0.0
	cpu_ms = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	physics_ms = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	primitives_k = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0
	ram_mb = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	vram_mb = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	players = get_tree().get_nodes_in_group("players").size()
	var director := get_tree().get_first_node_in_group("zombie_director")
	zombies = director.active_count if director else 0
	_check("frame_ms", frame_ms)
	_check("draw_calls", draw_calls)
	_check("primitives_k", primitives_k)
	_check("ram_mb", ram_mb)
	_check("vram_mb", vram_mb)
	# Offline counts as "server" in Godot, so require a real session before logging.
	if _log_enabled and multiplayer.is_server() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		_write_line()


func _check(key: String, value: float) -> void:
	if budgets.has(key):
		over[key] = value > float(budgets[key])


func _write_line() -> void:
	if _file == null:
		_open_log()
		if _file == null:
			return
	_file.store_line("%.1f,%s,%.2f,%.2f,%.2f,%.2f,%d,%.0f,%.0f,%.0f,%d,%d,%d" % [
		(Time.get_ticks_msec() - _started_ms) / 1000.0, Graphics.tier, frame_ms, worst_ms, cpu_ms, physics_ms,
		int(draw_calls), primitives_k, ram_mb, vram_mb, int(nodes), players, zombies])
	_file.flush()


func _open_log() -> void:
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	var old := Array(DirAccess.get_files_at(LOG_DIR))
	old.sort()
	while old.size() >= _keep_files:
		DirAccess.remove_absolute("%s/%s" % [LOG_DIR, old.pop_front()])
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	log_path = "%s/%s.csv" % [LOG_DIR, stamp]
	_file = FileAccess.open(log_path, FileAccess.WRITE)
	if _file == null:
		push_warning("Perf: cannot write %s" % log_path)
		return
	_file.store_line("time_s,tier,frame_ms,worst_ms,cpu_ms,physics_ms,draw_calls,primitives_k,ram_mb,vram_mb,nodes,players,zombies")
	print("Perf: logging to %s" % ProjectSettings.globalize_path(log_path))
