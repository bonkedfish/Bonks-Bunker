# DropZone — root of the Drop Zone landmark scene (D-074; geometry from tools/landmarks/build_dropzone.tscn).
# At load (every peer, same order, so node paths match): reads data/dropzone/dropzone.json and adds the game nodes
# "Range" (DzRange: the 32 bays' target game), "Putting" (DzPutting: the 18-hole putting course) and "Court0..3"
# (DzCourt: pickleball vs the CPU), plus the "sport spots" players press E at: one per bay screen, the putting start
# sign, one per court post (StaticBody on the interactable layer, group "sport_spots", metas target / index /
# display_name), and the Drop Zone HUD under the HUD. Group "drop_zone".
# Depends on: DataLoader, DzRange, DzPutting, DzCourt, DzHud, Player (E on "sport_spots").
class_name DropZone
extends Node3D

const DATA_PATH := "res://data/dropzone/dropzone.json"
const SPOT_LAYER := 8  # interactables only (the look ray finds it, nobody bumps into it)
const DzHud := preload("res://scripts/ui/drop_zone_hud.gd")

var data: Dictionary = {}


func _ready() -> void:
	add_to_group("drop_zone")
	data = DataLoader.load_json(DATA_PATH)
	if data.is_empty():
		return
	var rng_node := DzRange.new()
	rng_node.name = "Range"
	add_child(rng_node)
	var putt := DzPutting.new()
	putt.name = "Putting"
	add_child(putt)
	for i in data.courts.size():
		var court := DzCourt.new()
		court.name = "Court%d" % i
		court.index = i
		add_child(court)
	for i in data.bays.size():
		var bay: Dictionary = data.bays[i]
		_spot(Vector3(float(data.bay_face_x) - 7.4, float(bay.y) + 1.0, float(bay.z)), Vector3(0.6, 2.0, 1.0), rng_node, i,
			"Start a Drop Zone target game (bay %d)" % (i + 1))
	var s: Array = data.putting.start
	_spot(Vector3(s[0], 0.9, s[1]), Vector3(1.6, 1.8, 0.6), putt, 0, "Play the 18-hole putting course")
	var hw := float(data.court_size[0]) * 0.5
	var hl := float(data.court_size[1]) * 0.5
	for i in data.courts.size():
		var c: Array = data.courts[i].c
		_spot(Vector3(float(c[0]) + hw + 1.0, 0.7, float(c[1]) + hl - 1.0), Vector3(0.6, 1.4, 0.6), get_node("Court%d" % i), 0,
			"Play pickleball vs the CPU (court %d)" % (i + 1))
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.add_child.call_deferred(DzHud.new())


# Host: the living player who sent the current RPC (or the host's own), else null. Shared by the game nodes.
static func sender_player(n: Node) -> Node:
	if not n.multiplayer.is_server():
		return null
	var peer := n.multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = n.multiplayer.get_unique_id()
	return player_by_peer(n, peer)


static func player_by_peer(n: Node, peer: int) -> Node:
	for p in n.get_tree().get_nodes_in_group("players"):
		if "sport" in p and p.peer_id == peer:
			return null if p.health.is_dead() else p
	return null


static func toast(n: Node, text: String, seconds := 3.5) -> void:
	var hud := n.get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_toast(text, seconds)


func to_world(local: Vector3) -> Vector3:
	return global_transform * local


func to_local_pos(world: Vector3) -> Vector3:
	return global_transform.affine_inverse() * world


func _spot(pos: Vector3, size: Vector3, target: Node, index: int, label: String) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = SPOT_LAYER
	body.collision_mask = 0
	body.position = pos
	body.add_to_group("sport_spots")
	body.set_meta("target", target)
	body.set_meta("index", index)
	body.set_meta("display_name", label)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
