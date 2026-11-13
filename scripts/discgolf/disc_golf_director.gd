# DiscGolfDirector — disc golf rounds with the party (D-069), main.tscn node "DiscGolf", group "disc_golf".
#   Host:  E at a course box starts a round for every living player within start_radius_m (or joins / restarts the
#          one pressing it), handing out any missing discs. Validates throw intents (in the round, alive, carries
#          the disc, standing at their lie / tee, not already throwing), simulates the whole flight at once on the
#          fixed step (DiscFlightRules + physics rays for ground, walls and trunks, tree crowns from the planted
#          trees, DiscGolfRules for the basket), counts the stroke and sends the path to everyone; when the disc
#          has landed on screen it moves the lie, scores holed / picked-up holes and announces them. A finished card
#          rolls the reward tables (par or better / finish / ace) and updates the world best (quest flags
#          "dg_best_<course>", "dg_rounds_<course>", saved with the world). Players who wander leave_m outside the
#          course drop out. While a round runs, zombies in the park are cleared and none spawn there.
#   Every peer: the scorecard (`card`, synced whole on change), disc flights played back from the host's path
#          (one pooled disc per player, left lying at the lie), the disc golf HUD, minimap target.
# Depends on: DiscFlightRules, DiscGolfRules, DiscCourse (group "disc_courses"), LootDB, LootRules, ItemDB, LifeState,
# Players (group "players"), ZombieDirector (group "zombie_director"), WorldStreamer (group "world_streamer"),
# QuestDirector (group "quests"), HUD (group "hud"), DiscGolfHud.
class_name DiscGolfDirector
extends Node3D

signal card_changed

const DiscGolfHud := preload("res://scripts/ui/disc_golf_hud.gd")
const GROUND_MASK := 1
const CHECK_SECONDS := 0.5
const TREE_GRID := 12.0
const TOAST_SECONDS := 4.0

var round_active := false
var round_course := ""
# peer id -> {hole, throws, strokes: Array[int], lie: Vector3, done, left}
var card: Dictionary = {}

var _t: Dictionary
var _rng := RandomNumberGenerator.new()
var _check := 0.0
var _in_flight: Dictionary = {}  # host: peer -> [seconds left, rest: Vector3, holed: bool]
var _trees: Array = []           # host: [base: Vector3, height, bare], gathered again after cells load
var _tree_grid: Dictionary = {}  # host: Vector2i -> Array of indexes into _trees
var _trees_dirty := true         # host: a cell overlapping the course loaded since the trees were gathered
var _visual: Dictionary = {}     # peer -> {node: MeshInstance3D, path, rolls, t, hand}
var _disc_mesh: Dictionary = {}  # disc id -> CylinderMesh


func _ready() -> void:
	add_to_group("disc_golf")
	_t = DiscFlightRules.tuning()
	_rng.randomize()
	var streamer := get_tree().get_first_node_in_group("world_streamer")
	if streamer and streamer.has_signal("cell_loaded"):
		streamer.cell_loaded.connect(_on_cell_loaded.bind(streamer))
	multiplayer.peer_connected.connect(_on_peer_connected)
	var hud := get_node_or_null("../UI/HUD")
	if hud:
		hud.add_child.call_deferred(DiscGolfHud.new())


# --- queries (every peer) ---------------------------------------------------------------------

func course_node(id := "") -> DiscCourse:
	if id == "":
		id = round_course
	for c in get_tree().get_nodes_in_group("disc_courses"):
		if id == "" or c.course_id == id:
			return c
	return null


func my_entry() -> Dictionary:
	return card.get(multiplayer.get_unique_id(), {})


# Basket of the local player's current hole, or Vector3.INF when not playing.
func local_target() -> Vector3:
	var e := my_entry()
	var c := course_node()
	if not round_active or e.is_empty() or e.done or e.left or c == null:
		return Vector3.INF
	return c.basket_position(int(e.hole))


func is_flying(peer: int) -> bool:
	return _visual.has(peer) and float(_visual[peer].t) < _duration(_visual[peer].path)


# "You", "Host", "P2" ... for the scorecard.
func player_label(peer: int) -> String:
	if peer == multiplayer.get_unique_id():
		return "You"
	if peer == 1:
		return "Host"
	var ids := card.keys()
	ids.sort()
	return "P%d" % (ids.find(peer) + 1)


# At the round's course (its bounds + 40 m): the scorecard only shows here (D-071).
func near_course(pos: Vector3) -> bool:
	var c := course_node()
	return c != null and c.bounds().grow(40.0).has_point(Vector2(pos.x, pos.z))


# Zombie spawns are refused inside a course while a round runs (ZombieDirector asks).
func blocks_spawn(point: Vector3) -> bool:
	var c := course_node()
	return round_active and c != null and c.bounds().grow(30.0).has_point(Vector2(point.x, point.z))


# --- requests (any peer -> host) ----------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func request_start(course_id: String) -> void:
	var p := _sender_player()
	var c := course_node(course_id)
	if p == null or c == null or _flat(p.global_position).distance_to(_flat(c.box_position())) > float(_t.box_use_m) + 1.0:
		return
	if round_active and round_course != course_id:  # one round at a time
		_say.rpc_id(p.peer_id, "A round is on at %s - finish it there first" % course_node().course.name)
		return
	if round_active and round_course == course_id:
		var e: Dictionary = card.get(p.peer_id, {})
		if e.is_empty() or e.done or e.left:
			_host_join(p, c)
			_say.rpc("%s joined the round at hole 1" % player_label(p.peer_id))
			_host_sync()
		return
	card.clear()
	_in_flight.clear()
	round_active = true
	round_course = course_id
	for q in get_tree().get_nodes_in_group("players"):
		if "disc" in q and not q.health.is_dead() and q.global_position.distance_to(c.box_position()) <= float(_t.start_radius_m):
			_host_join(q, c)
	_host_clear_zombies()
	if _trees_dirty:
		_gather_trees(c)  # once at the start (a few tens of ms), so throws don't hitch
	_host_sync()
	_say.rpc("Round on at %s: %d holes, par %d. Press 3 for your discs." % [c.course.name, c.hole_count(), DiscGolfRules.par_total(c.course)])


@rpc("any_peer", "call_local", "reliable")
func request_throw(disc_id: String, power: float, yaw: float, pitch: float, tilt: float, forehand: bool) -> void:
	var p := _sender_player()
	if p == null or not round_active or not card.has(p.peer_id) or _in_flight.has(p.peer_id):
		return
	var e: Dictionary = card[p.peer_id]
	var c := course_node()
	if e.done or e.left or c == null or p.life.net_state != LifeState.ALIVE:
		return
	if not DiscFlightRules.is_disc(disc_id) or p.inventory.count(disc_id) <= 0:
		return
	var reach := float(_t.tee_radius_m) if int(e.throws) == 0 else float(_t.lie_radius_m)
	if _flat(p.global_position).distance_to(_flat(e.lie)) > reach + 0.5:
		return
	var cl := DiscGolfRules.clamp_throw(power, tilt, _t)
	var from: Vector3 = p.global_position + Vector3.UP * float(_t.launch_height_m)
	var f := DiscFlightRules.launch(DiscFlightRules.discs()[disc_id], cl.x, from, yaw,
		DiscFlightRules.launch_pitch(clampf(pitch, -1.5, 1.5), _t), cl.y, forehand, _t)
	var out := _simulate(f, c.basket_position(int(e.hole)), c)
	e.throws = int(e.throws) + 1
	_in_flight[p.peer_id] = [_duration(out[0]) + 0.2, out[2], out[3]]
	_play.rpc(p.peer_id, disc_id, out[0], out[1], forehand)


# --- host ---------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not (multiplayer.has_multiplayer_peer() and multiplayer.is_server()):
		return
	for peer: int in _in_flight.keys():
		var fl: Array = _in_flight[peer]
		fl[0] = float(fl[0]) - delta
		if float(fl[0]) <= 0.0:
			_in_flight.erase(peer)
			_host_land(peer, fl[1], fl[2])
	_check -= delta
	if _check > 0.0:
		return
	_check = CHECK_SECONDS
	if round_active:
		_host_check_players()
		_host_clear_zombies()


func _host_join(p: Node, c: DiscCourse) -> void:
	for id: String in DiscFlightRules.discs():
		if p.inventory.count(id) <= 0:
			p.inventory.host_add(id, 1)
	var strokes: Array = []
	strokes.resize(c.hole_count())
	strokes.fill(0)
	card[p.peer_id] = {"hole": 0, "throws": 0, "strokes": strokes, "lie": c.tee_position(0), "done": false, "left": false}


func _host_land(peer: int, rest: Vector3, holed: bool) -> void:
	if not card.has(peer):
		return
	var e: Dictionary = card[peer]
	var c := course_node()
	var hole := int(e.hole)
	if holed or int(e.throws) >= int(_t.max_strokes):
		var par := int(c.course.holes[hole].par)
		e.strokes[hole] = int(e.throws)
		var what := DiscGolfRules.score_name(int(e.throws), par) if holed else "picked up at %d" % int(e.throws)
		_say.rpc("%s - hole %s: %s" % [player_label(peer), DiscGolfRules.hole_label(c.course, hole), what])
		e.hole = hole + 1
		e.throws = 0
		if int(e.hole) >= c.hole_count():
			e.done = true
			e.lie = c.basket_position(hole)
			_host_finish(peer, c)
		else:
			e.lie = c.tee_position(int(e.hole))
	else:
		e.lie = rest
	_host_settle()
	_host_sync()


func _host_finish(peer: int, c: DiscCourse) -> void:
	var e: Dictionary = card[peer]
	var total := 0
	for s: Variant in e.strokes:
		total += int(s)
	var par := DiscGolfRules.par_total(c.course)
	var got := {}
	var p := _player(peer)
	for tier: String in DiscGolfRules.reward_tiers(e.strokes, c.course):
		var items := LootRules.roll(LootDB.get_table(str(_t.rewards[tier])), _rng)
		for id: String in items:
			got[id] = int(got.get(id, 0)) + int(items[id])
			if p:
				p.inventory.host_add(id, int(items[id]))
	var names := PackedStringArray()
	for id: String in got:
		names.append("%s x%d" % [ItemDB.get_item(id).get("name", id), got[id]])
	_say.rpc("%s finished %s: %d (%s)%s" % [player_label(peer), c.course.name, total, DiscGolfRules.to_par_text(total, par),
		("  -  " + ", ".join(names)) if not names.is_empty() else ""])
	var quests := get_tree().get_first_node_in_group("quests")
	if quests:
		var best_flag := "dg_best_" + c.course_id
		var best := int(quests.flags.get(best_flag, 0))
		if best == 0 or total < best:
			quests.host_add_count(best_flag, total - best)
			if best > 0:
				_say.rpc("New course record: %d (%s)" % [total, DiscGolfRules.to_par_text(total, par)])
		quests.host_add_count("dg_rounds_" + c.course_id)


# Drops cards of players who left the game, drops out wanderers, ends the round when nobody is still playing.
func _host_check_players() -> void:
	var c := course_node()
	if c == null:
		return
	var area := c.bounds().grow(float(_t.leave_m))
	var changed := false
	for peer: int in card.keys():
		var p := _player(peer)
		var e: Dictionary = card[peer]
		if p == null:
			card.erase(peer)
			_in_flight.erase(peer)
			changed = true
		elif not e.done and not e.left and not area.has_point(_flat(p.global_position)):
			e.left = true
			_in_flight.erase(peer)
			_say.rpc("%s left the course - out of the round" % player_label(peer))
			changed = true
	if changed:
		_host_settle()
		_host_sync()


func _host_settle() -> void:
	for e: Dictionary in card.values():
		if not e.done and not e.left:
			return
	round_active = false


func _host_clear_zombies() -> void:
	var c := course_node()
	var zd := get_tree().get_first_node_in_group("zombie_director")
	if c == null or zd == null:
		return
	var area := c.bounds().grow(15.0)
	for z in zd.get_children():
		if z.get("net_active") and area.has_point(_flat(z.global_position)):
			z.deactivate()


func _host_sync() -> void:
	_sync_card.rpc(round_active, round_course, card)


func _on_peer_connected(peer: int) -> void:
	if multiplayer.is_server():
		_sync_card.rpc_id(peer, round_active, round_course, card)


# The whole flight at once: returns [path, rolls, rest position, holed].
func _simulate(f: DiscFlightRules.Flight, basket: Vector3, c: DiscCourse) -> Array:
	var dt := 1.0 / float(_t.step_hz)
	var every := maxi(1, roundi(float(_t.step_hz) / float(_t.sample_hz)))
	var path := PackedVector3Array([f.pos])
	var rolls := PackedFloat32Array([f.roll])
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = GROUND_MASK
	q.exclude = c.body_rids()
	if _trees_dirty:
		_gather_trees(c)
	var holed := false
	var landed := false
	var slide := 0.0
	var cooldown := 0.0
	var floor_y := f.pos.y - 60.0
	var restitution := float(_t.restitution)
	var steps := 0
	while f.time < float(_t.max_flight_s):
		var prev := f.pos
		if not landed:
			DiscFlightRules.step(f, dt, _t)
			var contact := DiscGolfRules.basket_contact(f.pos - basket, prev - basket, f.vel.length(), _t)
			if contact == DiscGolfRules.Basket.CATCH:
				f.pos = basket + Vector3(0.0, 0.62, 0.0) + Vector3(f.vel.x, 0.0, f.vel.z).normalized() * 0.08
				holed = true
				break
			elif contact == DiscGolfRules.Basket.SPIT:
				f.pos = prev
				f.vel = Vector3(-f.vel.x, 0.0, -f.vel.z) * 0.2
			elif contact == DiscGolfRules.Basket.BOUNCE:
				var radial := Vector3(prev.x - basket.x, 0.0, prev.z - basket.z).normalized()
				f.pos = prev
				f.vel = f.vel.bounce(radial if radial != Vector3.ZERO else Vector3.BACK) * restitution
			cooldown -= dt
			if cooldown <= 0.0 and _canopy_hit(f, prev.distance_to(f.pos)):
				cooldown = 0.2
			q.from = prev
			q.to = f.pos
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				var n: Vector3 = hit.normal
				f.pos = hit.position + n * 0.03
				if n.y > 0.6:
					landed = true
					f.vel = Vector3(f.vel.x, 0.0, f.vel.z) * 0.35
				else:
					f.vel = f.vel.bounce(n) * restitution
					f.roll *= 0.5
			if f.pos.y < floor_y:
				break
		else:
			var v := f.vel.length()
			if v < 0.2 or slide > float(_t.max_slide_s):
				break
			f.vel *= maxf(0.0, v - float(_t.slide_friction) * dt) / v
			var next := f.pos + f.vel * dt
			q.from = f.pos + Vector3.UP * 0.15
			q.to = next + Vector3.UP * 0.15
			if not space.intersect_ray(q).is_empty():
				break  # slid into something
			q.from = next + Vector3.UP
			q.to = next + Vector3.DOWN * 2.0
			var ground := space.intersect_ray(q)
			if not ground.is_empty():
				next.y = ground.position.y + 0.03
			f.pos = next
			f.time += dt
			slide += dt
		steps += 1
		if steps % every == 0:
			path.append(f.pos)
			rolls.append(f.roll)
	path.append(f.pos)
	rolls.append(f.roll)
	return [path, rolls, f.pos, holed]


# Tree crowns: true (and the disc knocked down) when this step clips a branch.
func _canopy_hit(f: DiscFlightRules.Flight, metres: float) -> bool:
	var key := Vector2i(floori(f.pos.x / TREE_GRID), floori(f.pos.z / TREE_GRID))
	for i: int in _tree_grid.get(key, []):
		var tree: Array = _trees[i]
		if not DiscFlightRules.in_canopy(f.pos, tree[0], tree[1], tree[2]):
			continue
		if _rng.randf() >= DiscFlightRules.canopy_hit_chance(metres, tree[2], _t):
			return false
		var slow: Array = _t.canopy_slow
		var speed := f.vel.length() * _rng.randf_range(float(slow[0]), float(slow[1]))
		var kick := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 0.3), _rng.randf_range(-1.0, 1.0)) * 0.9
		f.vel = (f.vel.normalized() + kick).normalized() * speed
		f.roll += _rng.randf_range(-0.6, 0.6)
		return true
	return false


# Planted trees near the course from the loaded cells' vegetation (base, height = instance scale), bucketed by crown.
func _gather_trees(c: DiscCourse) -> void:
	_trees_dirty = false
	_trees.clear()
	_tree_grid.clear()
	var streamer := get_tree().get_first_node_in_group("world_streamer")
	if streamer == null:
		return
	var area := c.bounds().grow(40.0)
	for cell: Vector2i in streamer.near_loaded:
		if not streamer.grid.rect_of(cell).intersects(area):
			continue
		var veg: Node = streamer.near_loaded[cell].get_node_or_null("Vegetation")
		if veg == null:
			continue
		for mmi in veg.get_children():
			if not (mmi is MultiMeshInstance3D and str(mmi.name).begins_with("tree_")):
				continue
			var bare := str(mmi.name).begins_with("tree_bare")
			var mm: MultiMesh = mmi.multimesh
			for i in mm.instance_count:
				var xf: Transform3D = mmi.global_transform * mm.get_instance_transform(i)
				if not area.has_point(_flat(xf.origin)):
					continue
				var h := xf.basis.y.length()
				var idx := _trees.size()
				_trees.append([xf.origin, h, bare])
				var r := 0.42 * h
				for gx in range(floori((xf.origin.x - r) / TREE_GRID), floori((xf.origin.x + r) / TREE_GRID) + 1):
					for gz in range(floori((xf.origin.z - r) / TREE_GRID), floori((xf.origin.z + r) / TREE_GRID) + 1):
						var k := Vector2i(gx, gz)
						if not _tree_grid.has(k):
							_tree_grid[k] = []
						_tree_grid[k].append(idx)


func _on_cell_loaded(cell: Vector2i, streamer: Node) -> void:
	var c := course_node()
	if c != null and streamer.grid.rect_of(cell).intersects(c.bounds().grow(40.0)):
		_trees_dirty = true


func _sender_player() -> Node:
	if not multiplayer.is_server():
		return null
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
	var p := _player(peer)
	return null if p == null or p.health.is_dead() else p


func _player(peer: int) -> Node:
	for p in get_tree().get_nodes_in_group("players"):
		if "disc" in p and p.peer_id == peer:  # people, not Bonk
			return p
	return null


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func _duration(path: PackedVector3Array) -> float:
	return maxf(0.0, path.size() - 1) / float(_t.sample_hz)


# --- every peer -------------------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _sync_card(active: bool, course_id: String, new_card: Dictionary) -> void:
	round_active = active
	round_course = course_id
	card = new_card
	for peer: int in _visual.keys():  # a disc teed off a new hole, or a player out of the round: put it away
		var e: Dictionary = card.get(peer, {})
		if (e.is_empty() or e.left or int(e.throws) == 0) and not is_flying(peer):
			_visual[peer].node.visible = false
	card_changed.emit()


@rpc("authority", "call_local", "reliable")
func _play(peer: int, disc_id: String, path: PackedVector3Array, rolls: PackedFloat32Array, forehand: bool) -> void:
	if not _visual.has(peer):
		var mi := MeshInstance3D.new()
		add_child(mi)
		_visual[peer] = {"node": mi}
	var v: Dictionary = _visual[peer]
	v.node.mesh = _mesh_for(disc_id)
	v.node.visible = true
	v.path = path
	v.rolls = rolls
	v.t = 0.0
	v.hand = -1.0 if forehand else 1.0


@rpc("authority", "call_local", "reliable")
func _say(text: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_toast(text, TOAST_SECONDS)


func _process(delta: float) -> void:
	for peer: int in _visual:
		var v: Dictionary = _visual[peer]
		if not v.node.visible or not v.has("path"):
			continue
		var path: PackedVector3Array = v.path
		var dur := _duration(path)
		if float(v.t) >= dur + 1.0:
			continue
		v.t = float(v.t) + delta
		var k := clampf(float(v.t) / dur, 0.0, 1.0) * (path.size() - 1) if dur > 0.0 else float(path.size() - 1)
		var i := mini(int(k), path.size() - 2) if path.size() > 1 else 0
		var a := path[i]
		var b := path[mini(i + 1, path.size() - 1)]
		var w := clampf(k - i, 0.0, 1.0)
		var rolls: PackedFloat32Array = v.rolls
		var roll := lerpf(rolls[i], rolls[mini(i + 1, rolls.size() - 1)], w)
		var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var yaw: float = atan2(-dir.x, -dir.z) if dir.length() > 0.001 else v.node.rotation.y
		var moving := float(v.t) < dur
		v.node.global_position = a.lerp(b, w)
		v.node.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, -roll if moving else 0.0) \
			* Basis(Vector3.UP, float(v.t) * 40.0 * float(v.hand) if moving else 0.0)


func _mesh_for(disc_id: String) -> CylinderMesh:
	if not _disc_mesh.has(disc_id):
		var m := CylinderMesh.new()
		m.top_radius = 0.105
		m.bottom_radius = 0.1
		m.height = 0.025
		m.radial_segments = 16
		m.rings = 1
		var mat := StandardMaterial3D.new()
		var col: Array = DiscFlightRules.discs().get(disc_id, {}).get("color", [1, 1, 1])
		mat.albedo_color = Color(col[0], col[1], col[2])
		mat.roughness = 0.4
		m.material = mat
		_disc_mesh[disc_id] = m
	return _disc_mesh[disc_id]
