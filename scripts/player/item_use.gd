# ItemUse — timed use of aid/food/water items (D-046), Player child "ItemUse".
# Owning client: quick-use keys (quick_heal / quick_eat, in game or with the inventory open) or the inventory's Use
#   button call request(item_id),
#   which only asks the host. Host: checks the player is alive, owns the item and the item has a "use" block,
#   then runs the timer (`net_use_item`, `net_use_progress` replicate for the HUD). Moving faster than
#   cancel_move_speed (the owner gets a "stand still" note) or taking damage cancels it. On completion the host removes one item and applies heal /
#   food / water through SurvivalRules (healing halved while a meter is low), and starts the item's "effect" (D-052).
# Sound (D-077): the item's use sound (Sfx.use_event) plays for everyone when a use starts and stops if it's cancelled.
# Depends on: SurvivalRules, ItemDB, Sfx, Player (parent: inventory, health, life, needs, is_local).
class_name ItemUse
extends Node

var net_use_item := ""
var net_use_progress := 0.0

var _use: Dictionary = {}
var _left := 0.0
var _total := 1.0
var _sound := 0  # Sfx handle of the use sound (every peer)

@onready var player: Node = get_parent()


func _ready() -> void:
	($"../Health" as Health).damaged.connect(_on_damaged)  # parent @onready vars are not set yet


func _on_damaged(_amount: float, attacker: int) -> void:
	if attacker != -1:  # -1 = hunger/thirst, which shouldn't stop you eating
		_abort()


func _unhandled_input(event: InputEvent) -> void:
	if not player.is_local:
		return
	var inv := get_tree().get_first_node_in_group("inventory_ui") as CanvasItem
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not (inv and inv.visible):  # in game, or with the bag open
		return
	if event.is_action_pressed("quick_heal"):
		request(_pick("heal"))
	elif event.is_action_pressed("quick_eat"):
		request(_pick("eat"))


# Local player: ask the host to use one of `item_id`.
func request(item_id: String) -> void:
	if item_id == "":
		return
	if multiplayer.is_server():
		_host_start(item_id)
	else:
		_ask.rpc_id(1, item_id)


func _pick(kind: String) -> String:
	var owned: Dictionary = player.inventory.model.to_dict()
	var defs := {}
	for id: String in owned:
		defs[id] = ItemDB.get_item(id)
	return SurvivalRules.quick_pick(kind, owned, defs, player.needs.value())


@rpc("any_peer", "call_remote", "reliable")
func _ask(item_id: String) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == player.peer_id:
		_host_start(item_id)


func _host_start(item_id: String) -> void:
	if net_use_item != "" or player.life.net_state != LifeState.ALIVE or not ItemDB.has_item(item_id):
		return
	if player.inventory.count(item_id) <= 0:
		return
	var use := SurvivalRules.use_def(ItemDB.get_item(item_id))
	if use.is_empty():
		return
	_use = use
	_total = maxf(float(use.seconds), 0.05)
	_left = _total
	net_use_item = item_id
	net_use_progress = 0.0
	_fx_use.rpc(item_id, true)


# Host, every physics tick.
func host_tick(delta: float) -> void:
	if net_use_item == "":
		return
	var t := SurvivalRules.tuning()
	var horizontal := Vector2(player.velocity.x, player.velocity.z).length()
	if player.life.net_state != LifeState.ALIVE or horizontal > float(t.get("cancel_move_speed", 1.0)):
		if player.life.net_state == LifeState.ALIVE:
			_moved_note.rpc_id(player.peer_id)  # say why, instead of silently doing nothing
		_abort()
		return
	_left -= delta
	net_use_progress = clampf(1.0 - _left / _total, 0.0, 1.0)
	if _left > 0.0:
		return
	if player.inventory.host_remove(net_use_item, 1) == 1:
		var r := SurvivalRules.apply_use(_use, player.health.current, player.health.max_health, player.needs.value(), t)
		player.health.current = float(r.health)
		player.needs.host_set(r.needs)
		if _use.has("effect"):
			player.effects.host_add(str(_use.effect))
	_cancel()


@rpc("authority", "call_local", "reliable")
func _moved_note() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_toast("Stand still to eat, drink or heal", 2.0)


# Cancelled before it finished: cut the use sound too.
func _abort() -> void:
	if net_use_item != "":
		_fx_use.rpc("", false)
	_cancel()


@rpc("authority", "call_local", "reliable")
func _fx_use(item_id: String, start: bool) -> void:
	Sfx.stop(_sound)
	_sound = 0
	if not start:
		return
	var ev: String = Sfx.use_event(item_id, str(ItemDB.get_item(item_id).get("category", "")))
	if ev != "":
		_sound = Sfx.play_local(ev) if player.is_local else Sfx.play_at(ev, player.global_position + Vector3.UP)


func _cancel() -> void:
	net_use_item = ""
	net_use_progress = 0.0
	_use = {}
