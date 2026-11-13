# TrainingDummy — test target for weapons. Optional side-to-side sweep is a pure function of the host
# tick, so clients render it at their view tick and the host rewinds it exactly (lag-comp test).
# Dies at 0 HP, hides, and the host resets it after dummy_reset_seconds.
# Hittable interface: health, team, hit_radius, hit_capsule_at(tick). Depends on: Health, NetClock, CombatRules.
extends AnimatableBody3D

const HEIGHT := 1.8

@export var sweep_distance := 0.0  # metres either side; 0 = stationary
@export var sweep_speed := 1.2     # radians of sine per second

var team := &"targets"
var hit_radius := 0.35

@onready var health: Health = $Health
@onready var collider: CollisionShape3D = $Collider
@onready var mesh: MeshInstance3D = $Mesh

var _origin: Vector3
var _clock: NetClock
var _was_dead := false


func _ready() -> void:
	add_to_group("hittable")
	_origin = global_position
	_clock = get_tree().get_first_node_in_group("net_clock")
	health.max_health = CombatRules.load_tuning().get("dummy_max_health", 150.0)
	health.reset()
	health.died.connect(_on_died)


func _physics_process(_delta: float) -> void:
	if sweep_distance > 0.0 and multiplayer.has_multiplayer_peer():
		var t := float(_clock.tick) if multiplayer.is_server() else _clock.view_tick()
		global_position = _position_at(t)
	var dead := health.is_dead()
	if dead != _was_dead:
		_was_dead = dead
		mesh.visible = not dead
		collider.set_deferred("disabled", dead)


func hit_capsule_at(tick: float) -> Vector4:
	var p := _position_at(tick) if sweep_distance > 0.0 else _origin
	return Vector4(p.x, p.y, p.z, HEIGHT)


func _position_at(tick: float) -> Vector3:
	var seconds := tick / Engine.physics_ticks_per_second
	return _origin + Vector3.RIGHT * sin(seconds * sweep_speed) * sweep_distance


func _on_died(_attacker_peer: int) -> void:
	if multiplayer.is_server():
		get_tree().create_timer(CombatRules.load_tuning().get("dummy_reset_seconds", 3.0)).timeout.connect(health.reset)
