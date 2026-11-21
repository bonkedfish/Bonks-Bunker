# WorldOddities — the authored odd little scenes scattered over Kearney (D-106): a skeleton still clocked in, the
# traffic cone kingdom, a bathtub of bottle caps, "DEFINITELY NOT A TRAP", and the rest. Main child "Oddities",
# group "oddities"; every peer has it at the same path.
# Each entry in data/encounters/oddities.json is placed by hand (map x / z, or a landmark plus a local offset), so
# nothing pops up in front of anybody: they are just out there to be found. An oddity is built when its cell loads
# and freed when the cell unloads, dropped onto the ground with a ray; one whose ground is missing or blocked is
# skipped and counted in skipped_count. Props are PropKits kits and the same prop dictionaries EncounterSite uses.
# An oddity with a "use" gets an E spot (group "sport_spots") routed here; the host runs its action once per world
# (gives, flag, say) and remembers it in the save, so the lottery ticket can only be pocketed one time.
# An oddity with "shuffle" re-places those props somewhere new every time its cell loads, so the mannequins are
# never quite where you left them. Shuffled props never collide, and each peer rolls its own arrangement.
# Depends on: PropKits, EncounterSite (prop building), WorldStreamer (group "world_streamer"), CellGrid,
# QuestDirector (group "quests"), HUD (group "hud"), SaveDirector (through host_save_state / host_load_state).
class_name WorldOddities
extends Node3D

const PATH := "res://data/encounters/oddities.json"
const GROUND_MASK := 17
const WORLD_MASK := 1

var defs: Dictionary = {}
var used: Dictionary = {}    # id -> true (saved)
var built: Dictionary = {}   # id -> Node3D
var skipped_count := 0
var visits: Dictionary = {}  # id -> how many times this peer has built it (drives "shuffle")

var _streamer: Node
var _by_cell: Dictionary = {}  # Vector2i -> [id, ...]
var _pending: Array = []       # ids waiting for their landmark to exist
var _quests: Node
var _retry := 2.0


func _ready() -> void:
	add_to_group("oddities")
	var raw := DataLoader.load_json(PATH)
	for id: String in raw.get("oddities", {}):
		var d: Dictionary = raw.oddities[id]
		d["id"] = id
		defs[id] = d
	_streamer = get_tree().get_first_node_in_group("world_streamer")
	if _streamer:
		_streamer.cell_loaded.connect(_on_cell_loaded)
		_streamer.cell_unloaded.connect(_on_cell_unloaded)
		for id: String in defs:
			if not defs[id].has("landmark"):
				var at: Array = defs[id].get("at", [0, 0])
				var cell: Vector2i = _streamer.grid.cell_of(Vector3(at[0], 0.0, at[1]))
				var list: Array = _by_cell.get(cell, [])
				list.append(id)
				_by_cell[cell] = list
			else:
				_pending.append(id)
		for cell: Vector2i in _streamer.near_loaded:
			_on_cell_loaded(cell)


func _process(delta: float) -> void:
	if _pending.is_empty():
		return
	_retry -= delta
	if _retry > 0.0:
		return
	_retry = 3.0
	for i in range(_pending.size() - 1, -1, -1):
		var id: String = _pending[i]
		var lm := get_tree().root.find_child(str(defs[id].landmark), true, false) as Node3D
		if lm == null:
			continue
		_pending.remove_at(i)
		var at: Array = defs[id].get("at", [0, 0, 0])
		_build(id, lm.global_transform * Vector3(at[0], at[1], at[2]), float(defs[id].get("yaw", 0.0)) + rad_to_deg(lm.rotation.y), false)


func _on_cell_loaded(cell: Vector2i) -> void:
	for id: String in _by_cell.get(cell, []):
		if built.has(id):
			continue
		var at: Array = defs[id].get("at", [0, 0])
		_build(id, Vector3(at[0], 0.0, at[1]), float(defs[id].get("yaw", 0.0)), true)


func _on_cell_unloaded(cell: Vector2i) -> void:
	for id: String in _by_cell.get(cell, []):
		if built.has(id):
			(built[id] as Node).queue_free()
			built.erase(id)


# Builds one oddity. drop = find the ground with a ray (map-placed ones); landmark ones use the offset as given.
func _build(id: String, at: Vector3, yaw_deg: float, drop: bool) -> void:
	var def: Dictionary = defs[id]
	var pos := at
	if drop:
		var space := get_world_3d().direct_space_state
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 60.0, at + Vector3.DOWN * 60.0, GROUND_MASK))
		if hit.is_empty():
			skipped_count += 1
			return
		pos = hit.position
		var box := BoxShape3D.new()
		box.size = Vector3(float(def.get("clear_m", 2.0)) * 2.0, 2.2, float(def.get("clear_m", 2.0)) * 2.0)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = box
		q.collision_mask = WORLD_MASK
		q.transform = Transform3D(Basis(), pos + Vector3.UP * 1.4)
		if not space.intersect_shape(q, 1).is_empty():
			skipped_count += 1
			return
	var site := EncounterSite.new()
	site.name = "Odd_%s" % id
	add_child(site)
	site.global_position = pos
	site.rotation.y = deg_to_rad(yaw_deg)
	var props: Array = (def.get("props", []) as Array).duplicate()
	if def.has("shuffle"):
		props.append_array(_shuffled(id, def.shuffle))
	var build_def := {"props": props}
	if def.has("npc"):
		build_def["npc"] = def.npc
	if def.has("use") and not used.has(id):
		build_def["uses"] = [def.use]
	if def.has("loot"):
		build_def["loot"] = def.loot
	site.build(_slot_of(id), id, build_def, hash(id), self)
	built[id] = site
	visits[id] = int(visits.get(id, 0)) + 1


# The props that move: a fresh arrangement every build, so coming back is quietly wrong.
func _shuffled(id: String, spec: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) + int(visits.get(id, 0)) * 7919
	var out: Array = []
	var r := float(spec.get("radius_m", 2.4))
	for i in range(int(spec.get("count", 4))):
		out.append({
			"kit": str(spec.get("kit", "mannequin")),
			"at": [rng.randf_range(-r, r), 0.0, rng.randf_range(-r, r)],
			"yaw": rng.randf_range(0.0, 360.0),
			"collide": false,
		})
	return out


# E spots pass slot * 100 + use index; oddities only ever have one use, so the slot alone identifies them.
func _slot_of(id: String) -> int:
	return int(abs(hash(id))) % 100000


@rpc("any_peer", "call_local", "reliable")
func request_use(index: int) -> void:
	if not multiplayer.is_server():
		return
	var slot := floori(index / 100.0)
	for id: String in defs:
		if _slot_of(id) != slot or used.has(id) or not built.has(id):
			continue
		var player := _player()
		if player == null or player.global_position.distance_to((built[id] as Node3D).global_position) > 14.0:
			return
		var use: Dictionary = defs[id].use
		for item: String in use.get("needs", {}):
			if player.inventory.count(item) < int(use.needs[item]):
				_say.rpc_id(player.peer_id, str(use.get("fail_say", "Not without the right thing.")))
				return
		for item: String in use.get("needs", {}):
			player.inventory.host_remove(item, int(use.needs[item]))
		for item: String in use.get("gives", {}):
			player.inventory.host_add(item, int(use.gives[item]))
		if _quests == null:
			_quests = get_tree().get_first_node_in_group("quests")
		if _quests and use.has("flag"):
			_quests.host_set_flag(str(use.flag))
		_spent.rpc(id, str(use.get("say", "")), player.peer_id)
		return


func host_save_state() -> Dictionary:
	return {"used": used.duplicate()}


func host_load_state(saved: Variant) -> void:
	used.clear()
	if typeof(saved) == TYPE_DICTIONARY:
		for id: String in (saved as Dictionary).get("used", {}):
			used[id] = true


func _player() -> Node:
	var id := multiplayer.get_remote_sender_id()
	var peer := id if id != 0 else multiplayer.get_unique_id()
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == peer and not p.health.is_dead():
			return p
	return null


# Host -> everyone: the oddity is used up, so its E spot goes away on every peer.
@rpc("authority", "call_local", "reliable")
func _spent(id: String, say: String, peer: int) -> void:
	used[id] = true
	if built.has(id):
		var spot := (built[id] as Node).get_node_or_null("Use_0")
		if spot:
			spot.queue_free()
	if say != "" and peer == multiplayer.get_unique_id():
		var hud := get_tree().get_first_node_in_group("hud")
		if hud:
			hud.show_toast(say, 4.5)


@rpc("authority", "call_local", "reliable")
func _say(text: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_toast(text, 3.5)
