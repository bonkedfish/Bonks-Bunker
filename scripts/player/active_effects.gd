# ActiveEffects — a player's timed effects (D-052, compounding chems + booze D-082), Player child "Effects".
# Host owns them: host_add(id, doses) (from ItemUse when a used item has "effect"), host_tick() counts down, chains
# comedowns, heals heal_per_second, pushes damage_taken / hunger+thirst drain multipliers into Health / Needs, and
# makes a very drunk player throw up now and then (loses food + water, stops for a moment). 10x a second it works
# out each effect's strength and sends the set to the owning client when it changes.
# `net_effects` {id: whole seconds left} replicates (on change) so every peer knows the set (status bar, Bonk).
# Owning client: predicts move_speed with the host's strengths; the screen tint + FOV; how impaired you are —
# camera sway, the view drifting (your aim with it), sudden lurches, double vision + blurred edges
# (shaders/impaired_view.gdshader, only drawn while needed) — and stumble() pushes your walking off line (Player
# calls it on its move input). impairment() (0-1) is used by DiscGolfDirector (host: throw error) and the disc HUD
# (power bar jitter). Math in EffectRules. Depends on: EffectRules, Health, PlayerNeeds (siblings), Player (parent:
# is_local, peer_id, camera, head, yaw, pitch, cutscene, PITCH_LIMIT), shaders/impaired_view.gdshader.
class_name ActiveEffects
extends Node

const STRENGTH_HZ := 10.0
const VIEW_SHADER := preload("res://shaders/impaired_view.gdshader")

var net_effects: Dictionary = {}

var _active: Dictionary = {}     # host: id -> {left, hold, peak}
var _str: Dictionary = {}        # strengths: host's own, or the host's numbers on the owning client
var _mods: Dictionary = EffectRules.mods({}, {})
var _look: Dictionary = EffectRules.look({}, {})
var _str_left := 0.0
var _vomit_left := 0.0
var _overlay: ColorRect
var _view: ColorRect
var _view_mat: ShaderMaterial
var _base_fov := 75.0
var _time := 0.0
var _lurch := Vector2.ZERO       # local: view kick still being applied (yaw, pitch rad)
var _stop_left := 0.0            # local: throwing up, can't move
var _rng := RandomNumberGenerator.new()

@onready var player: Node = get_parent()
@onready var health: Health = $"../Health"
@onready var needs: PlayerNeeds = $"../Needs"


func _ready() -> void:
	_rng.randomize()


func speed_mult() -> float:
	return float(_mods.move_speed)


# 0 (sober) .. 1 (can barely stand): disc throw error and power bar jitter.
func impairment() -> float:
	return float(_look.impair)


func host_add(id: String, doses := 1.0) -> void:
	if EffectRules.has_effect(id):
		_active = EffectRules.add(_active, id, doses, EffectRules.defs())
		_str_left = 0.0
		_publish()


func host_clear() -> void:
	_active = {}
	_str_left = 0.0
	_publish()


func host_tick(delta: float, alive: bool) -> void:
	if _active.is_empty():
		return
	var d := EffectRules.defs()
	_active = EffectRules.tick(_active, delta, d)
	if alive and float(_mods.heal_per_second) > 0.0:
		health.current = minf(health.current + float(_mods.heal_per_second) * delta, health.max_health)
	_str_left -= delta
	if _str_left <= 0.0 or _active.is_empty():
		_publish()
	if alive:
		_host_vomit(delta, d)


func _publish() -> void:
	_str_left = 1.0 / STRENGTH_HZ
	var d := EffectRules.defs()
	var whole := {}
	for id: String in _active:
		var e: Dictionary = _active[id]
		whole[id] = ceili(float(e.left) + float(e.hold))
	if whole != net_effects:
		net_effects = whole
	var s := EffectRules.strengths(_active, d)
	for id: String in s:
		s[id] = snappedf(float(s[id]), 0.05)
	if s != _str:
		_apply_strengths(s)
		if player.peer_id != multiplayer.get_unique_id():
			_set_strengths.rpc_id(player.peer_id, s)
	health.damage_mult = float(_mods.damage_taken)
	needs.drain_mult = Vector2(float(_mods.hunger_drain), float(_mods.thirst_drain))


func _apply_strengths(s: Dictionary) -> void:
	var d := EffectRules.defs()
	_str = s
	_mods = EffectRules.mods(s, d)
	_look = EffectRules.look(s, d)


@rpc("authority", "call_remote", "reliable")
func _set_strengths(s: Dictionary) -> void:
	_apply_strengths(s)


# Host: very drunk players throw up every so often.
func _host_vomit(delta: float, d: Dictionary) -> void:
	var v := EffectRules.vomit(_str, d)
	if v.is_empty():
		_vomit_left = 0.0
		return
	var every: Array = v.get("every_s", [20.0, 30.0])
	if _vomit_left <= 0.0:
		_vomit_left = _rng.randf_range(float(every[0]), float(every[1])) * 0.5  # the first one comes sooner
		return
	_vomit_left -= delta
	if _vomit_left > 0.0:
		return
	_vomit_left = _rng.randf_range(float(every[0]), float(every[1]))
	var n := needs.value()
	needs.host_set(Vector2(maxf(n.x - float(v.get("food", 5.0)), 0.0), maxf(n.y - float(v.get("water", 8.0)), 0.0)))
	_throw_up.rpc(float(v.get("stop_s", 1.5)))


@rpc("authority", "call_local", "reliable")
func _throw_up(seconds: float) -> void:
	if player.is_local:
		_stop_left = seconds
		_lurch += Vector2(0.0, -0.55)  # head goes down
		var hud := get_tree().get_first_node_in_group("hud")
		if hud:
			hud.show_toast("You threw up.", 2.0)


# Owning client: the move input after stumbling (none at all while throwing up).
func stumble(move: Vector2) -> Vector2:
	if _stop_left > 0.0:
		return Vector2.ZERO
	var s := float(_look.stumble)
	if s <= 0.0 or move == Vector2.ZERO:
		return move
	var side := sin(_time * 1.3) + 0.6 * sin(_time * 2.9 + 1.0)
	var fwd := 0.35 * sin(_time * 1.7 + 2.0)
	var out := move + Vector2(move.y, -move.x) * side * s + move * fwd * s
	return out.limit_length(1.0)


# Local player only: tint, FOV, sway, drift, lurches, double vision + blur.
func _process(delta: float) -> void:
	if not player.is_local:
		return
	var cam: Camera3D = player.camera
	if _overlay == null:
		_make_overlays(cam)
	_time += delta
	_stop_left = maxf(_stop_left - delta, 0.0)
	var defs := EffectRules.defs()
	var tint := Color(0, 0, 0, 0)
	for id: String in _str:
		var e: Dictionary = defs.get(id, {})
		var t: Array = e.get("tint", [0, 0, 0, 0])
		var c := Color(t[0], t[1], t[2], minf(float(t[3]) * minf(float(_str[id]), 8.0), 0.4))
		var hz := float(e.get("pulse_hz", 0.0))
		if hz > 0.0:
			c.h = fposmod(c.h + _time * hz, 1.0)
			c.a *= 0.75 + 0.25 * sin(_time * TAU * hz * 2.0)
		tint = c if tint.a == 0.0 else tint.lerp(c, 0.5)
	if _stop_left > 0.0:
		tint = tint.lerp(Color(0.35, 0.45, 0.1, 0.35), 0.7)
	_overlay.color = _overlay.color.lerp(tint, minf(delta * 2.0, 1.0))
	var punch := 6.0 if _stop_left > 0.0 else 0.0
	cam.fov = lerpf(cam.fov, _base_fov + float(_mods.fov_add) + punch, minf(delta * 2.0, 1.0))
	var sway := deg_to_rad(float(_look.sway_deg))
	cam.rotation.z = lerpf(cam.rotation.z, sway * (sin(_time * 0.55) + 0.4 * sin(_time * 1.37)), minf(delta * 4.0, 1.0))
	_drift(delta)
	var dbl := float(_look.double_px) * (1.0 + 0.35 * sin(_time * 0.8))
	var blur := float(_look.blur)
	var on := dbl > 0.5 or blur > 0.01
	if _view.visible != on:
		_view.visible = on
	if on:
		_view_mat.set_shader_parameter("double_px", dbl * get_viewport().get_visible_rect().size.y / 1080.0)
		_view_mat.set_shader_parameter("blur", blur)
		_view_mat.set_shader_parameter("phase", _time)


# The view wanders (so does your aim) and sometimes lurches; you fight it with the mouse.
func _drift(delta: float) -> void:
	if player.cutscene or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var rate := deg_to_rad(float(_look.drift_deg_s))
	var lurch := float(_look.lurch)
	if lurch > 0.0 and _rng.randf() < lurch * 0.35 * delta:
		var k := deg_to_rad(_rng.randf_range(4.0, 10.0)) * lurch
		_lurch += Vector2(k * (1.0 if _rng.randf() < 0.5 else -1.0), k * _rng.randf_range(-0.5, 0.5))
	var step := _lurch * minf(delta * 6.0, 1.0)
	_lurch -= step
	if rate <= 0.0 and step == Vector2.ZERO:
		return
	var dy := rate * (sin(_time * 0.43) + 0.7 * sin(_time * 1.11 + 0.5)) * delta + step.x
	var dp := rate * 0.45 * sin(_time * 0.61 + 1.3) * delta + step.y
	player.yaw = wrapf(player.yaw + dy, -PI, PI)
	player.pitch = clampf(player.pitch + dp, -player.PITCH_LIMIT, player.PITCH_LIMIT)
	player.rotation.y = player.yaw
	player.head.rotation.x = player.pitch


func _make_overlays(cam: Camera3D) -> void:
	_base_fov = cam.fov
	var under := CanvasLayer.new()  # under the HUD: the screen grab holds only the world
	under.layer = -1
	add_child(under)
	_view = ColorRect.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view_mat = ShaderMaterial.new()
	_view_mat.shader = VIEW_SHADER
	_view.material = _view_mat
	_view.visible = false
	under.add_child(_view)
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.color = Color(0, 0, 0, 0)
	layer.add_child(_overlay)
