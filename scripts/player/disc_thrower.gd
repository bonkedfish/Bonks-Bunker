# DiscThrower — throwing golf discs (D-069), Player child "Disc"; only the local player's does anything.
# 3 takes out a disc (driver -> mid-range -> putter of the ones you carry, then back to your weapon; 1 / 2 also put
# it away). With a disc out: hold left click to charge power (0 -> full over charge_seconds), release to throw where
# you look; right click cancels; Z / X or the mouse wheel tilt the disc (left edge down curves left), F swaps
# backhand / forehand. The throw goes to the host as an intent (DiscGolfDirector.request_throw) — the host decides
# everything. Shows the disc in your hand instead of the weapon, and stops the gun firing (Player checks `active`).
# HUD reads active / disc_id / charge / tilt_deg / forehand. Depends on: DiscFlightRules, DiscGolfDirector
# (group "disc_golf"), Player (parent: is_local, inventory, yaw, pitch, riding, health, viewmodel, camera).
class_name DiscThrower
extends Node

const ORDER := ["disc_driver", "disc_mid", "disc_putter"]

var active := false
var disc_id := ""
var charge := 0.0
var charging := false
var tilt_deg := 0.0
var forehand := false

var _t: Dictionary
var _hand: MeshInstance3D
var _hand_mat: StandardMaterial3D

@onready var player: Node = get_parent()


func _ready() -> void:
	_t = DiscFlightRules.tuning()


func carried() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in ORDER:
		if player.inventory.count(id) > 0:
			out.append(id)
	return out


func _unhandled_input(event: InputEvent) -> void:
	if not player.is_local or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or player.sport.mode != "":
		return  # (in a Drop Zone game, 3 changes the club instead)
	if event.is_action_pressed("disc_mode"):
		_next_disc()
		get_viewport().set_input_as_handled()
		return
	if not active:
		return
	if event.is_action_pressed("weapon_1") or event.is_action_pressed("weapon_2"):
		_set_active(false)
	elif event.is_action_pressed("disc_tilt_left"):
		tilt_deg = minf(tilt_deg + float(_t.tilt_step_deg), float(_t.tilt_max_deg))
	elif event.is_action_pressed("disc_tilt_right"):
		tilt_deg = maxf(tilt_deg - float(_t.tilt_step_deg), -float(_t.tilt_max_deg))
	elif event.is_action_pressed("disc_grip"):
		forehand = not forehand
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		charging = false
		charge = 0.0


func _next_disc() -> void:
	var have := carried()
	if have.is_empty():
		var hud := get_tree().get_first_node_in_group("hud")
		if hud:
			hud.show_toast("No discs - get a set at a disc golf course box", 3.0)
		return
	var i := have.find(disc_id) if active else -1
	if i + 1 >= have.size():
		_set_active(false)
	else:
		disc_id = have[i + 1]
		_set_active(true)


func _set_active(on: bool) -> void:
	active = on
	charging = false
	charge = 0.0
	player.viewmodel.visible = not on
	if on:
		_show_hand()
	elif _hand:
		_hand.visible = false


func _process(delta: float) -> void:
	if not player.is_local or not active:
		return
	if player.inventory.count(disc_id) <= 0:  # dropped or traded it away
		_set_active(false)
		return
	var can: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not player.riding and not player.health.is_dead()
	if can and Input.is_action_pressed("fire"):
		charging = true
		charge = minf(1.0, charge + delta / float(_t.charge_seconds))
	elif charging:
		charging = false
		if can:
			var dg := get_tree().get_first_node_in_group("disc_golf")
			if dg:
				dg.request_throw.rpc_id(1, disc_id, charge, player.yaw, player.pitch, tilt_deg, forehand)
		charge = 0.0
	if _hand:  # wind up: the disc comes back across the body while charging; tilt shows on it
		var side := -1.0 if forehand else 1.0
		_hand.position = Vector3(0.4 * side - charge * 0.3 * side, -0.3, -0.85 + charge * 0.15)
		_hand.rotation = Vector3(0.55, 0.0, deg_to_rad(tilt_deg))


func _show_hand() -> void:
	if _hand == null:
		_hand = MeshInstance3D.new()
		var m := CylinderMesh.new()
		m.top_radius = 0.105
		m.bottom_radius = 0.1
		m.height = 0.025
		m.radial_segments = 20
		m.rings = 1
		_hand_mat = StandardMaterial3D.new()
		_hand_mat.roughness = 0.4
		m.material = _hand_mat
		_hand.mesh = m
		_hand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		player.camera.add_child(_hand)
	var col: Array = DiscFlightRules.discs()[disc_id].color
	_hand_mat.albedo_color = Color(col[0], col[1], col[2])
	_hand.visible = true
