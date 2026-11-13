# SportInput — the local player's controls for the Drop Zone games (D-074), Player child "Sport". A game node puts
# its player into a mode with enter() (from its synced state) and out with leave():
#   "range": 3 cycles driver / 7-iron / wedge; hold left click to charge, release to swing where you look.
#   "putt":  hold left click to charge, release to putt where you look.
#   "pickle": left click hits (or serves) toward where you look.
# Right click cancels a charge. Sends only intents to the game node (request_shot / request_hit); the host decides.
# While a mode is on, the weapon is hidden and doesn't fire (Player checks `mode`), and the disc is put away.
# HUD reads mode / club_id() / charge. Depends on: GolfBallRules (tuning), Player (parent: is_local, yaw, viewmodel,
# disc, health), the game nodes (DzRange, DzPutting, DzCourt).
class_name SportInput
extends Node

var mode := ""
var game: Node = null
var club_index := 0
var charge := 0.0
var charging := false

@onready var player: Node = get_parent()


func enter(new_mode: String, node: Node) -> void:
	if mode == new_mode and game == node:
		return
	mode = new_mode
	game = node
	charging = false
	charge = 0.0
	if player.disc.active:
		player.disc._set_active(false)
	player.viewmodel.visible = false


func leave(node: Node) -> void:
	if game != node:
		return
	mode = ""
	game = null
	charging = false
	charge = 0.0
	player.viewmodel.visible = not player.disc.active


func club_id() -> String:
	var order: Array = GolfBallRules.tuning().club_order
	return str(order[club_index % order.size()])


func _unhandled_input(event: InputEvent) -> void:
	if not player.is_local or mode == "" or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if mode == "range" and event.is_action_pressed("disc_mode"):
		club_index = (club_index + 1) % GolfBallRules.tuning().club_order.size()
		get_viewport().set_input_as_handled()
	elif mode == "pickle" and event.is_action_pressed("fire"):
		game.request_hit.rpc_id(1, player.yaw)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		charging = false
		charge = 0.0


func _process(delta: float) -> void:
	if not player.is_local or (mode != "range" and mode != "putt") or game == null:
		return
	var t := GolfBallRules.tuning()
	var seconds := float(t.range.charge_seconds) if mode == "range" else float(t.putting.charge_seconds)
	var can: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not player.health.is_dead()
	if can and Input.is_action_pressed("fire"):
		charging = true
		charge = minf(1.0, charge + delta / seconds)
	elif charging:
		charging = false
		if can:
			game.request_shot.rpc_id(1, club_id(), charge, player.yaw)
		charge = 0.0
