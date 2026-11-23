# DiscThrower — throwing golf discs (D-069), Player child "Disc"; only the local player's does anything.
# 3 takes out a disc (the ones you carry, fastest first - DiscFlightRules.bag_order, then back to your weapon; 1 / 2 also put
# it away) - only on a disc golf course (inside a course's bounds + leave_m); walking off one puts it away.
# With a disc out: hold left click to charge power (0 -> full over charge_seconds), release to throw where
# you look; right click cancels; Z / X or the mouse wheel tilt the disc (left edge down curves left), F picks the
# throw style (D-117: backhand, forehand, putt, tomahawk, roller). The throw goes to the host as an intent
# (DiscGolfDirector.request_throw) — the host decides everything. The weapon is put away and your first-person arms
# hold the disc (D-117): charging draws it back through the style's reach-back, releasing plays the pull-through and
# follow-through (CharacterAnimator.pose_throw / start_throw on the Viewmodel's arms) and the disc leaves your hand at
# the release; it stops the gun firing (Player checks `active`).
# In a round you can only charge on your turn (D-076); clicking early shows whose throw it is.
# HUD reads active / disc_id / charge / tilt_deg / style_id. Depends on: DiscFlightRules, DiscGolfDirector
# (group "disc_golf"), Player (parent: is_local, inventory, yaw, pitch, riding, health, viewmodel), ThrowPose.
class_name DiscThrower
extends Node


var active := false
var disc_id := ""
var charge := 0.0
var charging := false
var tilt_deg := 0.0
var style_id := "backhand"

var _t: Dictionary
var _swing_left := 0.0  # s: the release swing is playing on the arms

@onready var player: Node = get_parent()


func _ready() -> void:
	_t = DiscFlightRules.tuning()


func carried() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in DiscFlightRules.bag_order():  # fastest first (D-119 catalog)
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
	elif event.is_action_pressed("disc_grip"):  # next throw style (D-117)
		var order := DiscFlightRules.style_order()
		if not order.is_empty():
			style_id = order[(order.find(style_id) + 1) % order.size()]
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		charging = false
		charge = 0.0


# True inside any course's bounds grown by leave_m (data/tuning/disc_golf.json).
func on_course() -> bool:
	var p := Vector2(player.global_position.x, player.global_position.z)
	for c in get_tree().get_nodes_in_group("disc_courses"):
		if c.bounds().grow(float(_t.leave_m)).has_point(p):
			return true
	return false


func _next_disc() -> void:
	if not active and not on_course():
		return  # 3 does nothing off a course
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
	_swing_left = 0.0
	player.viewmodel.hide_weapon(on)


# Seconds until the disc leaves your hand in the swing playing now (the director starts its flight then).
func time_to_release() -> float:
	return player.viewmodel.arms.time_to_release()


func _process(delta: float) -> void:
	if not player.is_local or not active:
		return
	if player.inventory.count(disc_id) <= 0 or not on_course():  # dropped / traded it away, or walked off the course
		_set_active(false)
		return
	var can: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not player.riding and not player.health.is_dead() \
		and not player.cutscene
	var dg := get_tree().get_first_node_in_group("disc_golf")
	if can and dg and dg.waiting_turn():
		if Input.is_action_just_pressed("fire"):
			var hud := get_tree().get_first_node_in_group("hud")
			if hud:
				hud.show_toast(dg.wait_text(), 2.0)
		can = false
	if can and Input.is_action_pressed("fire"):
		charging = true
		charge = minf(1.0, charge + delta / float(_t.charge_seconds))
	elif charging:
		charging = false
		if can:
			if dg:
				var arms: CharacterAnimator = player.viewmodel.arms
				var clip := ThrowPose.clip(style_id)
				var from := _wind_up_t(clip)
				arms.start_throw(style_id, disc_id, from)
				_swing_left = (1.0 - from) * clip.seconds
				dg.request_throw.rpc_id(1, disc_id, charge, player.yaw, player.pitch, tilt_deg, style_id)
		charge = 0.0
	_swing_left = maxf(0.0, _swing_left - delta)
	if _swing_left <= 0.0:  # address, or drawn back through the reach-back while charging (D-117)
		player.viewmodel.arms.pose_throw(style_id, disc_id, _wind_up_t(ThrowPose.clip(style_id)))


# Point of the swing the charge has drawn the disc back to: address at 0, full reach-back at full power.
func _wind_up_t(clip: ThrowPose.Clip) -> float:
	return clip.reach * (1.0 - pow(1.0 - charge, 2.0))
