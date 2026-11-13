# MeepoRider — riding the Meepo electric longboard (D-057), Player child "Meepo".
# Owning client: the "ride" key (B) asks the host to hop on/off. Host: allows it while the player carries a "meepo",
# is alive, not swimming and the battery has charge; drains the battery while rolling, recharges it near a Meepo dock
# (group "meepo_chargers"), throws the rider off on a big hit, an empty battery, going down, or dropping the board.
# `net_riding` / `net_battery` replicate so the owner predicts ride speed with the host's state and everyone sees
# the board under the rider. While riding: ride_speed instead of walk/sprint, no firing (Player checks `riding`).
# Rules in MeepoRules. Depends on: MeepoRules, Player (parent: inventory, health, life, water, velocity, is_local).
class_name MeepoRider
extends Node3D

var net_riding := false
var net_battery := 100.0
var _level := 100.0  # host: exact battery level; net_battery publishes it in 0.5 steps

var _t: Dictionary
var _board: Node3D
var _ride: Dictionary = {}  # cached riding movement tuning

@onready var player: Node = get_parent()


func _ready() -> void:
	_t = MeepoRules.tuning()
	($"../Health" as Health).damaged.connect(_on_damaged)  # parent @onready vars are not set yet
	_board = _make_board()
	add_child(_board)
	_board.visible = false


# Movement tuning while riding (built once from the player's tuning, no per-tick allocation).
func movement(base: Dictionary) -> Dictionary:
	if _ride.is_empty():
		_ride = MeepoRules.ride_movement(base, _t)
	return _ride


func has_board() -> bool:
	return player.inventory.count("meepo") > 0


func _unhandled_input(event: InputEvent) -> void:
	if player.is_local and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event.is_action_pressed("ride"):
		if multiplayer.is_server():
			_host_toggle()
		else:
			_ask_toggle.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _ask_toggle() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == player.peer_id:
		_host_toggle()


func _host_toggle() -> void:
	if net_riding:
		net_riding = false
	elif MeepoRules.can_ride(has_board(), net_battery, player.life.net_state == LifeState.ALIVE,
			player.water == MovementRules.Water.SWIM, _t):
		net_riding = true


# Host, every physics tick.
func host_tick(delta: float) -> void:
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var rolling: bool = net_riding and speed > 1.0
	var boosting: bool = rolling and speed > float(_t.ride_speed) + 0.5
	var charging := false
	if not net_riding:
		for c: Node3D in get_tree().get_nodes_in_group("meepo_chargers"):
			if c.global_position.distance_to(player.global_position) <= float(_t.charger_range_m):
				charging = true
				break
	_level = MeepoRules.battery_after(_level, rolling, charging, delta, _t, boosting)
	if absf(_level - net_battery) >= 0.5 or (_level != net_battery and (_level == 0.0 or _level == 100.0)):
		net_battery = snappedf(_level, 0.5)
	if net_riding and (net_battery <= 0.0 or not has_board() or player.life.net_state != LifeState.ALIVE
			or player.water == MovementRules.Water.SWIM):
		net_riding = false


func _on_damaged(amount: float, _attacker: int) -> void:
	if multiplayer.is_server() and net_riding and MeepoRules.knocked_off(amount, _t):
		net_riding = false


func _process(_delta: float) -> void:
	if _board.visible != net_riding:
		_board.visible = net_riding


# Deck + two trucks + four wheels, built in code (visual only).
func _make_board() -> Node3D:
	var root := Node3D.new()
	var deck := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.26, 0.03, 0.95)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.12, 0.12, 0.13)
	wood.roughness = 0.8
	box.material = wood
	deck.mesh = box
	deck.position = Vector3(0, 0.1, 0)
	root.add_child(deck)
	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.85, 0.35, 0.1)
	for zs: float in [-0.33, 0.33]:
		for xs: float in [-0.14, 0.14]:
			var w := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.045
			cyl.bottom_radius = 0.045
			cyl.height = 0.04
			cyl.radial_segments = 10
			cyl.material = wheel_mat
			w.mesh = cyl
			w.rotation_degrees = Vector3(0, 0, 90)
			w.position = Vector3(xs, 0.045, zs)
			root.add_child(w)
	var light := MeshInstance3D.new()  # the battery strip glows
	var strip := BoxMesh.new()
	strip.size = Vector3(0.12, 0.012, 0.3)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.2, 0.9, 1.0)
	glow.emission_enabled = true
	glow.emission = Color(0.2, 0.9, 1.0)
	glow.emission_energy_multiplier = 2.0
	strip.material = glow
	light.mesh = strip
	light.position = Vector3(0, 0.08, 0)
	root.add_child(light)
	return root
