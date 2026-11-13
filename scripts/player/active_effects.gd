# ActiveEffects — a player's timed effects (D-052), Player child "Effects".
# Host owns them: host_add(id) (from ItemUse when a used item has "effect"), host_tick() counts down, chains comedowns,
# heals heal_per_second, and pushes damage_taken / hunger+thirst drain multipliers into Health / Needs.
# `net_effects` {id: whole seconds left} replicates (on change) so every peer knows the set: the owning client
# predicts move_speed with the host's numbers, and the local player gets the screen tint + FOV change. Not saved.
# Math in EffectRules. Depends on: EffectRules, Health, PlayerNeeds (siblings), Player (parent: is_local, camera).
class_name ActiveEffects
extends Node

var net_effects: Dictionary = {}:
	set(value):
		net_effects = value
		_mods = EffectRules.mods(value.keys(), EffectRules.defs())

var _active: Dictionary = {}  # host: id -> seconds left (float)
var _mods: Dictionary = EffectRules.mods([], {})
var _overlay: ColorRect
var _base_fov := 75.0
var _time := 0.0

@onready var player: Node = get_parent()
@onready var health: Health = $"../Health"
@onready var needs: PlayerNeeds = $"../Needs"


func speed_mult() -> float:
	return float(_mods.move_speed)


func host_add(id: String) -> void:
	if EffectRules.has_effect(id):
		_active = EffectRules.add(_active, id, EffectRules.defs())
		_publish()


func host_clear() -> void:
	_active = {}
	_publish()


func host_tick(delta: float, alive: bool) -> void:
	if _active.is_empty():
		return
	_active = EffectRules.tick(_active, delta, EffectRules.defs())
	if alive and float(_mods.heal_per_second) > 0.0:
		health.current = minf(health.current + float(_mods.heal_per_second) * delta, health.max_health)
	_publish()


func _publish() -> void:
	var whole := {}
	for id: String in _active:
		whole[id] = ceili(float(_active[id]))
	if whole != net_effects:
		net_effects = whole
	health.damage_mult = float(_mods.damage_taken)
	needs.drain_mult = Vector2(float(_mods.hunger_drain), float(_mods.thirst_drain))


# Local player only: tint + FOV.
func _process(delta: float) -> void:
	if not player.is_local:
		return
	var cam: Camera3D = player.camera
	if _overlay == null:
		_base_fov = cam.fov
		var layer := CanvasLayer.new()
		layer.layer = 0
		add_child(layer)
		_overlay = ColorRect.new()
		_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay.color = Color(0, 0, 0, 0)
		layer.add_child(_overlay)
	_time += delta
	var tint := Color(0, 0, 0, 0)
	var defs := EffectRules.defs()
	for id: String in net_effects:
		var e: Dictionary = defs.get(id, {})
		var t: Array = e.get("tint", [0, 0, 0, 0])
		var c := Color(t[0], t[1], t[2], t[3])
		var hz := float(e.get("pulse_hz", 0.0))
		if hz > 0.0:
			c.h = fposmod(c.h + _time * hz, 1.0)
			c.a *= 0.75 + 0.25 * sin(_time * TAU * hz * 2.0)
		tint = c if tint.a == 0.0 else tint.lerp(c, 0.5)
	_overlay.color = _overlay.color.lerp(tint, minf(delta * 2.0, 1.0))
	cam.fov = lerpf(cam.fov, _base_fov + float(_mods.fov_add), minf(delta * 2.0, 1.0))
