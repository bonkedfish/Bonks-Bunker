# Viewmodel — local player's first-person view (D-045): the player's survivor model in first-person mode ("Arms",
# a CharacterAnimator showing only arms + the selected weapon), recoil kick on shots, slash clip on melee.
# D-122: the kick is per gun (feel.vm_kick: back, up, tilt) and eases back each frame with no tween; aiming down
# sights slides the gun to gun_feel.json ads_offset.
# Visual only. The old box Pistol/Bat stay hidden: Pistol/Muzzle still marks where tracers start.
# D-123: the arms hold the weapon with its GunPose animations - draw / holster on a switch, reload, kick, melee swing.
# With a golf disc out (D-117) the weapon is put away and DiscThrower drives the arms' throw pose (hide_weapon).
# Depends on: children Arms (CharacterAnimator), Pistol (with Muzzle) and Bat.
extends Node3D

@onready var pistol: Node3D = $Pistol
@onready var bat: Node3D = $Bat
@onready var muzzle: Marker3D = $Pistol/Muzzle
@onready var arms: CharacterAnimator = $Arms

var _rest_position: Vector3
var _bat_rest: Vector3
var _tween: Tween
var _armed := true
var _mesh := "Pistol"
var _weapon_id := ""
var _disc_out := false
var _kick_amt := 0.0            # 1 right after a shot, easing to 0
var _kick := Vector3.ZERO        # back, up (m), tilt (deg) of the last gun
var _ads := 0.0
var _ads_on := false
var _ads_offset := Vector3.ZERO
var _ads_speed := 14.0
var _kick_return := 14.0


func _ready() -> void:
	_rest_position = position
	_bat_rest = bat.rotation
	var t := GunFeelRules.tuning()
	var o: Array = t.get("ads_offset", [0.0, 0.0, 0.0])
	_ads_offset = Vector3(float(o[0]), float(o[1]), float(o[2]))
	_ads_speed = float(t.get("ads_speed", 14.0))
	_kick_return = float(t.get("vm_kick_return", 14.0))


func set_arms_model(id: String) -> void:
	arms.set_model(str(CharacterAnimator.model_def(id).get("fp_model", id)), true)  # base-body models use a survivor's arms + guns


# The weapon in hand (D-087): its kit mesh name ("" = empty hands) and whether it's a gun (gun idle / walk clips).
func show_weapon(mesh: String, armed: bool, weapon_id := "") -> void:
	_mesh = mesh
	_armed = armed
	_weapon_id = weapon_id
	arms.set_weapon("" if _disc_out else mesh, weapon_id)


# A golf disc is out (D-117): no weapon in the hand, empty-hand clips; put away: the weapon comes back.
func hide_weapon(on: bool) -> void:
	_disc_out = on
	if not on:
		arms.stop_throw()
	arms.set_weapon("" if on else _mesh, _weapon_id)


func _process(delta: float) -> void:
	_ads = move_toward(_ads, 1.0 if _ads_on else 0.0, delta * _ads_speed * 0.25)
	_kick_amt = maxf(_kick_amt - delta * _kick_return * _kick_amt - delta, 0.0)
	if _tween == null or not _tween.is_running():
		position = _rest_position + _ads_offset * _ads + Vector3(0.0, _kick.y, _kick.x) * _kick_amt
		rotation.x = deg_to_rad(_kick.z) * _kick_amt
	if visible:
		arms.riding = owner != null and "riding" in owner and owner.riding  # on the Meepo: no walk/run bob (D-065)
		arms.update(delta, false, false, 100.0, _armed and not _disc_out, false)


# One shot (D-122): feel.vm_kick = [back m, up m, tilt deg]; _process eases it back.
func kick(feel: Dictionary) -> void:
	var k: Array = feel.get("vm_kick", [0.05, 0.012, 4.0])
	_kick = Vector3(float(k[0]), float(k[1]), float(k[2]))
	_kick_amt = 1.0
	arms.gun_kick()


# A reload started (D-123): the arms' reload clip over the weapon's reload time.
func reload(seconds: float) -> void:
	arms.gun_action("reload", seconds)


# Where shots leave the gun in hand (the old Pistol/Muzzle marker when nothing is shown).
func muzzle_point() -> Vector3:
	var tip := arms.weapon_tip(-global_basis.z.normalized())
	return muzzle.global_position if tip == Vector3.INF else tip


# Aiming down sights (D-122): the gun slides to the middle of the view.
func set_aim(on: bool) -> void:
	_ads_on = on


func swing(windup: float) -> void:
	if arms.has_gun_action("swing"):  # D-123: the weapon's own hand-made swing
		arms.gun_action("swing")
		return
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
