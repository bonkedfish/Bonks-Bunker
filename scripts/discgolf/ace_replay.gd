# AceReplay — the kill-cam style replay of an ace (D-076), DiscGolfDirector child, run on every peer when the host
# announces an ace. play() locks every player (Player.cutscene: no moving, looking or using; the host also ignores
# their intents) and, on the host, makes players invulnerable and freezes every zombie (zombie.gd `frozen`); the HUD
# hides itself while you're in the cutscene. Shows the throw again from its own camera: a beat behind the thrower, a chase camera behind the disc
# with its tracer, then the last ace_slowmo_s of the flight in slow motion from beside the basket, then "ACE!" for a
# moment. Then everything goes back. Letterbox bars, a REPLAY tag, who / hole / distance.
# Depends on: DiscTracer, DiscFlightRules (tuning), zombie.gd, Player (group "players": cutscene, health, camera),
# HUD (hides itself while Player.cutscene), Sfx (chains as it lands, D-077).
class_name AceReplay
extends Node3D

const ZombieScript := preload("res://scripts/ai/zombie.gd")
const INTRO_S := 0.8
const OUTRO_S := 2.2
const BAR := 0.11  # letterbox bar height, fraction of the screen

var playing := false

var _path := PackedVector3Array()
var _rolls := PackedFloat32Array()
var _hand := 1.0
var _basket := Vector3.ZERO
var _title := ""
var _sub := ""
var _sample_hz := 30.0
var _slowmo := 0.35
var _slowmo_s := 0.8
var _wall := 0.0       # seconds since play()
var _ft := 0.0         # flight time shown
var _outro := 0.0
var _chimed := false  # the chains sound has played (D-077)
var _cam: Camera3D
var _prev_cam: Camera3D
var _disc: MeshInstance3D
var _tracer: DiscTracer
var _overlay: Control
var _font: Font


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.top_level = true
	_cam.fov = 70.0
	add_child(_cam)
	_disc = MeshInstance3D.new()
	_disc.top_level = true
	_disc.visible = false
	add_child(_disc)
	_tracer = DiscTracer.new()
	add_child(_tracer)
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	_overlay.draw.connect(_draw_overlay)
	layer.add_child(_overlay)
	_font = ThemeDB.fallback_font
	set_process(false)


func play(path: PackedVector3Array, rolls: PackedFloat32Array, disc_mesh: Mesh, forehand: bool, basket: Vector3,
		title: String, sub: String) -> void:
	if path.size() < 2:
		return
	var t := DiscFlightRules.tuning()
	_sample_hz = float(t.sample_hz)
	_slowmo = float(t.ace_slowmo)
	_slowmo_s = float(t.ace_slowmo_s)
	_path = path
	_rolls = rolls
	_hand = -1.0 if forehand else 1.0
	_basket = basket
	_title = title
	_sub = sub
	_wall = 0.0
	_ft = 0.0
	_outro = 0.0
	_chimed = false
	_disc.mesh = disc_mesh
	_disc.visible = true
	_tracer.show_path(path)
	if not playing:
		_prev_cam = get_viewport().get_camera_3d()
	playing = true
	_lock(true)
	var d := _flat_dir(0)
	_cam.global_position = path[0] - d * 3.0 + Vector3.UP * 1.0
	_cam.look_at(path[mini(6, path.size() - 1)], Vector3.UP)
	_cam.current = true
	_overlay.visible = true
	set_process(true)


func _process(delta: float) -> void:
	_wall += delta
	var dur := (_path.size() - 1) / _sample_hz
	var slow_from := maxf(0.0, dur - _slowmo_s)
	if _wall > INTRO_S and _ft < dur:
		_ft = minf(dur, _ft + delta * (_slowmo if _ft >= slow_from else 1.0))
	elif _ft >= dur:
		if not _chimed:
			_chimed = true
			Sfx.play_at("disc_chains", _basket + Vector3.UP * 0.9)
		_outro += delta
		if _outro >= OUTRO_S:
			_finish()
			return
	var k := _ft * _sample_hz
	var i := mini(int(k), _path.size() - 2)
	var w := clampf(k - i, 0.0, 1.0)
	var pos := _path[i].lerp(_path[i + 1], w)
	var roll := lerpf(_rolls[mini(i, _rolls.size() - 1)], _rolls[mini(i + 1, _rolls.size() - 1)], w)
	var d := _flat_dir(i)
	var flying := _ft < dur
	_disc.global_position = pos
	_disc.basis = Basis(Vector3.UP, atan2(-d.x, -d.z)) * Basis(Vector3.FORWARD, -roll if flying else 0.0) \
		* Basis(Vector3.UP, _wall * 40.0 * _hand if flying else 0.0)
	_tracer.set_progress(_ft / dur if dur > 0.0 else 1.0)
	if _ft < slow_from:  # chase camera behind the disc
		var goal := pos - d * 3.5 + Vector3.UP * 1.1 + d.cross(Vector3.UP) * 0.6
		_cam.global_position = _cam.global_position.lerp(goal, minf(1.0, delta * (2.0 if _wall < INTRO_S else 6.0)))
		_cam.look_at(pos, Vector3.UP)
	else:  # beside the basket, watching it come in
		var approach := _flat_dir(_path.size() - 2)
		var side := approach.cross(Vector3.UP)
		_cam.global_position = _basket - approach * 1.5 + side * 3.2 + Vector3.UP * 1.3
		_cam.look_at(pos.lerp(_basket + Vector3.UP * 0.9, 0.35), Vector3.UP)
	_overlay.queue_redraw()


func _finish() -> void:
	playing = false
	set_process(false)
	_lock(false)
	_disc.visible = false
	_tracer.visible = false
	_overlay.visible = false
	if is_instance_valid(_prev_cam):
		_prev_cam.current = true
	else:
		var me := get_tree().get_first_node_in_group("local_player")
		if me and "camera" in me:
			me.camera.current = true


func _lock(on: bool) -> void:
	var host := multiplayer.has_multiplayer_peer() and multiplayer.is_server()
	for p in get_tree().get_nodes_in_group("players"):
		if "cutscene" in p:
			p.cutscene = on
		if host and "health" in p and p.health is Health:
			p.health.invulnerable = on
	if host:
		ZombieScript.frozen = on


# Horizontal direction of travel at path sample i.
func _flat_dir(i: int) -> Vector3:
	for j in range(i, mini(i + 8, _path.size() - 1)):
		var d := _path[j + 1] - _path[maxi(j - 1, 0)]
		d.y = 0.0
		if d.length() > 0.01:
			return d.normalized()
	return Vector3.FORWARD


func _draw_overlay() -> void:
	var s := _overlay.size
	var bar := s.y * BAR
	_overlay.draw_rect(Rect2(0, 0, s.x, bar), Color(0, 0, 0, 0.92))
	_overlay.draw_rect(Rect2(0, s.y - bar, s.x, bar), Color(0, 0, 0, 0.92))
	if fmod(_wall, 1.0) < 0.6:
		_overlay.draw_circle(Vector2(36, bar * 0.5), 7.0, Color(0.95, 0.15, 0.1))
	_overlay.draw_string(_font, Vector2(52, bar * 0.5 + 7.0), "REPLAY  -  ACE CAM", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.9))
	var size := 26
	var text := _sub
	var col := Color(0.9, 0.9, 0.85)
	if _outro > 0.0:
		_centred("ACE!", s.y * 0.42, 96, Color(1.0, 0.82, 0.2))
		size = 30
		text = _title
		col = Color(1.0, 0.92, 0.6)
	_centred(text, s.y - bar * 0.5 + size * 0.35, size, col)


func _centred(text: String, baseline: float, font_size: int, col: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := Vector2(_overlay.size.x * 0.5 - w * 0.5, baseline)
	_overlay.draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0, 0, 0, 0.9))
	_overlay.draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
