# ResidentNpc — a stationary, talkable NPC who lives somewhere in the world (D-049; first: Evan in the Archway).
# Loads data/npcs/<npc_id>.json (display_name, dialogue_tree, bark_prefix, model, ranges, bark timings, hat_color).
# Never fights and can't be hurt (no Health child, not "hittable"; DialogueDirector treats it as never down).
# Host: idle barks on a timer and a greeting when a player first comes within greet_range, but only while some
# player is within subtitle_range. Every peer: plays the idle animation and turns toward the nearest player in
# face_range (presentation only). Optional tinfoil hat (hat_color) and a smoke wisp (smoke: true).
# Quest flags (D-054) can move NPCs around the story: "show_requires" (only present while the flag list holds) and
# "hide_requires" (gone once it holds) - a hidden NPC is invisible, has no collision and can't be talked to.
# Groups "talkable", "npcs". Depends on: DataLoader, DialogueDB, DialogueDirector (group "dialogue"),
# CharacterAnimator (Body), players (group "players"), QuestRules + QuestDirector (group "quests").
extends StaticBody3D

const DATA_DIR := "res://data/npcs/"
const URGENT := ["busy", "greet"]

@export var npc_id := "evan"

var def: Dictionary = {}
var display_name := ""
var dialogue_tree := ""

var _dialogue: Node
var _bark_timer := 0.0
var _idle_timer := 0.0
var _greeted: Dictionary = {}  # host: peer_id -> true
var _hidden := false
var _quests: Node
@onready var _body: CharacterAnimator = $Body


func _ready() -> void:
	add_to_group("talkable")
	add_to_group("npcs")
	def = DataLoader.load_json(DATA_DIR + npc_id + ".json")
	display_name = str(def.get("display_name", npc_id))
	dialogue_tree = str(def.get("dialogue_tree", ""))
	$Nameplate.text = display_name
	_dialogue = get_tree().get_first_node_in_group("dialogue")
	if _body.set_model(str(def.get("model", ""))) and def.has("hat_color"):
		_add_hat()
	if bool(def.get("smoke", false)):
		_add_smoke()
	_idle_timer = randf_range(float(def.get("idle_bark_min", 20.0)), float(def.get("idle_bark_max", 40.0)))
	_quests = get_tree().get_first_node_in_group("quests")
	if _quests and (def.has("show_requires") or def.has("hide_requires")):
		_quests.flags_changed.connect(_apply_flags)
		_apply_flags()


func _apply_flags() -> void:
	var flags: Dictionary = _quests.flags
	var hide_now := (def.has("show_requires") and not QuestRules.requires_met(def.show_requires, flags)) \
		or (def.has("hide_requires") and QuestRules.requires_met(def.hide_requires, flags))
	if hide_now == _hidden:
		return
	_hidden = hide_now
	visible = not hide_now
	$Collider.set_deferred("disabled", hide_now)
	if hide_now:
		remove_from_group("talkable")
	else:
		add_to_group("talkable")


func bark(context: String) -> void:
	if not multiplayer.is_server() or _dialogue == null or _hidden:
		return
	if _bark_timer > 0.0 and not context in URGENT:
		return
	var lines := DialogueDB.barks(str(def.get("bark_prefix", "")) + context)
	if lines.is_empty():
		return
	_bark_timer = float(def.get("bark_cooldown", 6.0))
	_dialogue.host_bark(self, str(lines[randi() % lines.size()]))


func _process(delta: float) -> void:
	_body.update(delta, false, false, 100.0)
	var near := _nearest_player(float(def.get("face_range", 8.0)))
	if near:
		var to := near.global_position - global_position
		rotation.y = rotate_toward(rotation.y, atan2(-to.x, -to.z), float(def.get("turn_speed", 4.0)) * delta)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _hidden:
		return
	_bark_timer = maxf(_bark_timer - delta, 0.0)
	var heard := float(def.get("subtitle_range", 20.0))
	var greet := float(def.get("greet_range", 12.0))
	var anyone := false
	for p in get_tree().get_nodes_in_group("players"):
		var d: float = p.global_position.distance_to(global_position)
		anyone = anyone or d <= heard
		if d <= greet and not _greeted.has(p.peer_id):
			_greeted[p.peer_id] = true
			bark("greet")
	if not anyone:
		return
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_idle_timer = randf_range(float(def.get("idle_bark_min", 20.0)), float(def.get("idle_bark_max", 40.0)))
		bark("idle")


func _nearest_player(within: float) -> Node3D:
	var best: Node3D = null
	var best_d := within
	for p: Node3D in get_tree().get_nodes_in_group("players"):
		var d := p.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


# A crumpled foil cone on top of the head (fixed height on the body; the idle sway is small).
func _add_hat() -> void:
	var hat := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.19
	cone.height = 0.34
	cone.radial_segments = 7
	cone.rings = 1
	var c: Array = def.get("hat_color", [0.75, 0.76, 0.78])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(c[0], c[1], c[2])
	mat.metallic = 0.9
	mat.roughness = 0.35
	cone.material = mat
	hat.mesh = cone
	add_child(hat)
	hat.position = Vector3(0, float(def.get("hat_y", 1.9)), 0)
	hat.rotation_degrees.z = 8.0


# A thin smoke wisp at hand height (presentation only, a handful of particles).
func _add_smoke() -> void:
	var p := CPUParticles3D.new()
	p.amount = 10
	p.lifetime = 3.0
	p.position = Vector3(0.25, 1.45, -0.2)
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3(0, 0.25, 0)
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.15
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	var puff := SphereMesh.new()
	puff.radius = 0.035
	puff.height = 0.07
	puff.radial_segments = 6
	puff.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.8, 0.8, 0.18)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = mat
	p.mesh = puff
	p.visibility_range_end = 40.0
	add_child(p)
