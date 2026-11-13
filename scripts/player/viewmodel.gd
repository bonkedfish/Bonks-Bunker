# Viewmodel — local player's first-person view (D-045): the player's survivor model in first-person mode ("Arms",
# a CharacterAnimator showing only arms + the selected weapon), recoil kick on shots, slash clip on melee.
# Visual only. The old box Pistol/Bat stay hidden: Pistol/Muzzle still marks where tracers start.
# Depends on: children Arms (CharacterAnimator), Pistol (with Muzzle) and Bat.
extends Node3D

@onready var pistol: Node3D = $Pistol
@onready var bat: Node3D = $Bat
@onready var muzzle: Marker3D = $Pistol/Muzzle
@onready var arms: CharacterAnimator = $Arms

var _rest_position: Vector3
var _bat_rest: Vector3
var _tween: Tween
var _slot := 0


func _ready() -> void:
	_rest_position = position
	_bat_rest = bat.rotation


func set_arms_model(id: String) -> void:
	arms.set_model(str(CharacterAnimator.model_def(id).get("fp_model", id)), true)  # base-body models use a survivor's arms + guns


func show_slot(slot: int) -> void:
	_slot = slot
	arms.set_weapon_slot(slot)


func _process(delta: float) -> void:
	if visible:
		arms.riding = owner != null and "riding" in owner and owner.riding  # on the Meepo: no walk/run bob (D-065)
		arms.update(delta, false, false, 100.0, _slot == 0, false)


func kick() -> void:
	_restart()
	position = _rest_position + Vector3(0.0, 0.012, 0.06)
	_tween.tween_property(self, "position", _rest_position, 0.12)


func swing(windup: float) -> void:
	arms.one_shot("attack", windup + 0.4)
	_restart()
	_tween.tween_property(bat, "rotation", _bat_rest + Vector3(0.5, -0.6, 0.0), maxf(windup, 0.05))
	_tween.tween_property(bat, "rotation", _bat_rest + Vector3(-0.9, 1.4, 0.0), 0.1)
	_tween.tween_property(bat, "rotation", _bat_rest, 0.3)


func _restart() -> void:
	if _tween:
		_tween.kill()
	position = _rest_position
	bat.rotation = _bat_rest
	_tween = create_tween()
