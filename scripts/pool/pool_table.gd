# PoolTable — a playable 7-ft pool table (D-084), placed by the Big Apple generator (scenes/pool_table.tscn, a
# landmark child, so its node path is the same on every peer). Table frame: local x = length (break end -x), local z
# = across (PoolRules' y), felt top at surface_h.
#   Host: E (group "sport_spots") takes a seat or gives it up; one player = practice on a full rack, two = a game of
#         8-ball (seat 0 breaks); walking leave_m away or leaving the game frees the seat. Shots: the shooter (their
#         turn, standing within shoot_range of the cue ball, balls at rest) sends power + look yaw; the host runs it with
#         PoolRules a slice per frame (sim_budget_ms), judges it (8-ball), and sends every peer the sampled ball paths +
#         sound events + the state after it. Ball in hand: the shooter clicks the felt (request_place). A finished game
#         re-racks after a few seconds.
#   Every peer: plays shots back (balls roll, drop, clack), shows a status sign; the local player in a seat gets
#         SportInput mode "pool" (left click charges, release shoots where you look) and, on their turn, the aim line,
#         ghost ball and cue stick; PoolHud shows power / whose shot / your group.
# Depends on: PoolRules, PoolHud, SportInput (Player child "sport"), Player (group "players": peer_id, net_name,
# camera, yaw, health), HUD (group "hud"), Sfx.
class_name PoolTable
extends Node3D

const RAIL := 0.11
const FRAME := 0.05
const RERACK_SECONDS := 5.0
const CHECK_SECONDS := 0.5

var table_id := ""

var state: Dictionary = {}  # synced: seats, names, groups, turn, ball_in_hand, over, winner, msg, break_shot, pos
var pos := PackedVector2Array()

var _t: Dictionary
var _body: StaticBody3D
var _balls: Array[MeshInstance3D] = []
var _sign: Label3D
var _aim_line: MeshInstance3D
var _ghost: MeshInstance3D
var _cue: MeshInstance3D
var _hud: PoolHud
var _shot: Dictionary = {}       # host: the shot being simulated
var _before := PackedVector2Array()
var _play_frames := PackedVector2Array()
var _play_events: Array = []
var _play_t := -1.0
var _play_next_event := 0
var _after: Dictionary = {}      # state to apply when playback ends
var _rerack_left := -1.0
var _check := 0.0
var _place_point := Vector2.INF  # local: where ball in hand would go
var _wait_release := false        # local: the click that placed the cue ball is still held (don't let it charge a shot)

static var _table_mesh: ArrayMesh
static var _ball_mesh: SphereMesh
static var _ball_mats: Array[StandardMaterial3D] = []


func _ready() -> void:
	_t = PoolRules.tuning()
	add_to_group("pool_tables")
	add_to_group("no_merge")  # its balls move
	_build()
	pos = PoolRules.rack(1, _t)
	state = _blank_state()
	_apply_pos(pos)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _blank_state() -> Dictionary:
	var g := PoolRules.new_game([0, 0])
	g.names = ["", ""]
	g.busy = false
	g.msg = "E to play pool"
	g.pos = pos
	return g


func busy() -> bool:
	return bool(state.get("busy", false)) or _play_t >= 0.0


func my_seat() -> int:
	var me := multiplayer.get_unique_id()
	var seats: Array = state.get("seats", [0, 0])
	return seats.find(me)


func my_turn() -> bool:
	var seat := my_seat()
	return seat >= 0 and int(state.turn) == seat and not bool(state.over) and not busy()


func placing() -> bool:
	return my_turn() and (bool(state.ball_in_hand) or _wait_release)


# --- host -----------------------------------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func request_use(_index: int) -> void:
	var p := _sender()
	if p == null:
		return
	var seats: Array = state.seats
	var seat := seats.find(int(p.peer_id))
	if seat >= 0:
		_host_leave(int(p.peer_id))
		return
	if busy():
		return
	var free := seats.find(0)
	if free < 0:
		_toast(int(p.peer_id), "This table is full")
		return
	seats[free] = int(p.peer_id)
	_host_new_game(seats)


func _host_new_game(seats: Array) -> void:
	pos = PoolRules.rack(randi(), _t)
	var g := PoolRules.new_game(seats)
	if PoolRules.players(g) == 1 and int(seats[0]) == 0:  # keep the lone player in seat 0
		g.seats = [seats[1], 0]
	g.names = [_name(int(g.seats[0])), _name(int(g.seats[1]))]
	g.busy = false
	g.msg = "%s breaks" % str(g.names[0]) if PoolRules.players(g) == 2 else "Practice - break when ready"
	g.pos = pos
	_rerack_left = -1.0
	_sync.rpc(g)


func _host_leave(peer: int) -> void:
	var seats: Array = (state.seats as Array).duplicate()
	var i := seats.find(peer)
	if i < 0:
		return
	seats[i] = 0
	if PoolRules.players({"seats": seats}) == 0:
		var g := _blank_state()
		g.pos = pos
		_sync.rpc(g)
	else:
		_host_new_game(seats)


@rpc("any_peer", "call_local", "reliable")
func request_place(p: Vector2) -> void:
	var pl := _sender()
	if pl == null or busy() or not bool(state.ball_in_hand) or not p.is_finite():
		return
	if (state.seats as Array).find(int(pl.peer_id)) != int(state.turn):
		return
	if not PoolRules.valid_place(pos, p, _t):
		return
	pos[0] = p
	var g := state.duplicate(true)
	g.pos = pos
	g.ball_in_hand = false
	_sync.rpc(g)


@rpc("any_peer", "call_local", "reliable")
func request_shot(_club: String, charge: float, yaw: float) -> void:
	var p := _sender()
	if p == null or busy() or bool(state.over) or not is_finite(charge) or not is_finite(yaw):
		return
	if (state.seats as Array).find(int(p.peer_id)) != int(state.turn):
		return
	var cue_w := _world(pos[0])
	if Vector2(p.global_position.x - cue_w.x, p.global_position.z - cue_w.z).length() > float(_t.shoot_range):
		_toast(int(p.peer_id), "Get closer to the cue ball")
		return
	var dir := _local_dir(yaw)
	var speed := lerpf(float(_t.min_speed), float(_t.max_speed), clampf(charge, 0.0, 1.0))
	_before = pos.duplicate()
	_shot = PoolRules.new_shot(pos, dir * speed)
	var g := state.duplicate(true)
	g.busy = true
	g.ball_in_hand = false
	_sync.rpc(g)


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not _shot.is_empty():
		var t0 := Time.get_ticks_usec()
		var budget := int(float(_t.sim_budget_ms) * 1000.0)
		while Time.get_ticks_usec() - t0 < budget:
			if PoolRules.advance(_shot, _t, 24):
				_host_finish_shot()
				break


func _host_finish_shot() -> void:
	var s := _shot
	_shot = {}
	var g := state.duplicate(true)
	PoolRules.judge(g, s, _before, _t, g.names)
	pos = s.pos
	g.pos = pos
	g.busy = false
	if bool(g.over):
		_rerack_left = RERACK_SECONDS + float((s.frames as PackedVector2Array).size() / PoolRules.BALLS) * float(_t.frame_dt)
	_play_shot.rpc(s.frames, s.events, g)


func _process(delta: float) -> void:
	_playback(delta)
	if multiplayer.is_server():
		if _rerack_left >= 0.0:
			_rerack_left -= delta
			if _rerack_left < 0.0:
				_host_new_game((state.seats as Array).duplicate())
		_check -= delta
		if _check <= 0.0:
			_check = CHECK_SECONDS
			for peer: int in (state.seats as Array):
				var p := _player(peer)
				if peer != 0 and (p == null or p.global_position.distance_to(global_position) > float(_t.leave_m)):
					_host_leave(peer)
					break
	_local(delta)


func _on_peer_connected(peer: int) -> void:
	if multiplayer.is_server():
		_sync.rpc_id(peer, state)


func _on_peer_disconnected(peer: int) -> void:
	if multiplayer.is_server() and (state.seats as Array).has(peer):
		_host_leave(peer)


# --- every peer -------------------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _sync(g: Dictionary) -> void:
	state = g
	pos = PackedVector2Array(g.pos)
	if _play_t < 0.0:
		_apply_pos(pos)
	_sign.text = _sign_text()


@rpc("authority", "call_local", "reliable")
func _play_shot(frames: PackedVector2Array, events: Array, after: Dictionary) -> void:
	_play_frames = frames
	_play_events = events
	_play_next_event = 0
	_play_t = 0.0
	_after = after
	state.busy = true
	Sfx.play_at("pool_cue", _world(frames[0]) if frames.size() > 0 else global_position)


func _playback(delta: float) -> void:
	if _play_t < 0.0:
		return
	_play_t += delta
	var fd := float(_t.frame_dt)
	var n := _play_frames.size() / PoolRules.BALLS
	if n == 0:
		_play_t = -1.0
		_sync(_after)
		return
	var f := _play_t / fd
	var i0 := mini(int(f), n - 1)
	var i1 := mini(i0 + 1, n - 1)
	var k := clampf(f - i0, 0.0, 1.0)
	for b in PoolRules.BALLS:
		var a := _play_frames[i0 * PoolRules.BALLS + b]
		var c := _play_frames[i1 * PoolRules.BALLS + b]
		_place_ball(b, c if a == PoolRules.OUT or c == PoolRules.OUT else a.lerp(c, k))
	while _play_next_event < _play_events.size() and float(_play_events[_play_next_event][0]) <= _play_t:
		var ev: Array = _play_events[_play_next_event]
		Sfx.play_at("pool_" + str(ev[1]), global_position + Vector3.UP * float(_t.surface_h))
		_play_next_event += 1
	if i0 >= n - 1:
		_play_t = -1.0
		_sync(_after)


func _apply_pos(p: PackedVector2Array) -> void:
	for b in PoolRules.BALLS:
		_place_ball(b, p[b])


func _place_ball(b: int, p: Vector2) -> void:
	var ball := _balls[b]
	if p == PoolRules.OUT:
		ball.visible = false
		return
	var r := float(_t.ball_r)
	var at := Vector3(p.x, float(_t.surface_h) + r, p.y)
	if ball.visible:
		var d := at - ball.position
		var dist := Vector2(d.x, d.z).length()
		if dist > 0.0001:
			var axis := Vector3(d.z, 0.0, -d.x).normalized()
			ball.basis = (Basis(axis, dist / r) * ball.basis).orthonormalized()
	ball.position = at
	ball.visible = true


func _sign_text() -> String:
	var seats: Array = state.get("seats", [0, 0])
	var names: Array = state.get("names", ["", ""])
	var n := PoolRules.players(state)
	if n == 0:
		return "POOL\nE to play"
	var lines := PackedStringArray()
	if n == 2:
		var groups: Array = state.groups
		for i in 2:
			lines.append("%s%s%s" % ["> " if int(state.turn) == i and not bool(state.over) else "  ", str(names[i]),
				"" if str(groups[i]) == "" else " (%s)" % str(groups[i])])
	else:
		lines.append("%s - practice" % str(names[0] if int(seats[0]) != 0 else names[1]))
	if str(state.msg) != "":
		lines.append(str(state.msg))
	return "\n".join(lines)


# The local player: SportInput mode, aim visuals, HUD, ball in hand.
func _local(delta: float) -> void:
	var me := _local_player()
	if me == null:
		return
	var seated := my_seat() >= 0
	_sign.visible = not seated  # the seated player reads the HUD; the sign would cover the view
	var sport: Node = me.sport
	if seated and sport.mode != "pool":
		sport.enter("pool", self)
		if _hud == null:
			_hud = PoolHud.new()
			var hud := get_tree().get_first_node_in_group("hud")
			if hud:
				hud.add_child(_hud)
	elif not seated and sport.game == self:
		sport.leave(self)
	if not seated:
		if _hud:
			_hud.queue_free()
			_hud = null
		_aim_line.visible = false
		_ghost.visible = false
		_cue.visible = false
		return
	var turn := my_turn()
	if _wait_release and not Input.is_action_pressed("fire"):
		_wait_release = false
	if _hud:
		var groups: Array = state.groups
		_hud.show_state(turn, str(state.msg), str(groups[my_seat()]), float(sport.charge), placing(),
			str((state.names as Array)[int(state.turn)]))
	if not turn:
		_aim_line.visible = false
		_ghost.visible = false
		_cue.visible = false
		return
	if placing() and bool(state.ball_in_hand):
		_place_point = _crosshair_on_felt(me)
		var ok := _place_point != Vector2.INF and PoolRules.valid_place(pos, _place_point, _t)
		_ghost.visible = ok
		if ok:
			_ghost.position = Vector3(_place_point.x, float(_t.surface_h) + float(_t.ball_r), _place_point.y)
		_aim_line.visible = false
		_cue.visible = false
		return
	var dir := _local_dir(float(me.yaw))
	var probe := PoolRules.aim_probe(pos, dir, _t)
	var c := pos[0]
	var end: Vector2 = probe.end
	var y := float(_t.surface_h) + float(_t.ball_r)
	var length := c.distance_to(end)
	_aim_line.visible = length > 0.01
	_aim_line.position = Vector3((c.x + end.x) * 0.5, y, (c.y + end.y) * 0.5)
	_aim_line.basis = Basis(Vector3.UP, atan2(dir.x, dir.y)) * Basis.from_scale(Vector3(1, 1, maxf(length, 0.01)))
	_ghost.visible = int(probe.hit) >= 0
	_ghost.position = Vector3(end.x, y, end.y)
	_cue.visible = true
	var back := 0.04 + float(sport.charge) * 0.28
	var tip := c - dir * back
	var mid := tip - dir * 0.73
	_cue.position = Vector3(mid.x, y + 0.03, mid.y)
	_cue.basis = Basis(Vector3.UP, atan2(dir.x, dir.y)) * Basis(Vector3.RIGHT, PI * 0.5 - 0.06)


func _unhandled_input(event: InputEvent) -> void:
	if not placing() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action_pressed("fire") and bool(state.ball_in_hand) and _place_point != Vector2.INF:
		_wait_release = true
		request_place.rpc_id(1, _place_point)
		get_viewport().set_input_as_handled()


func _crosshair_on_felt(me: Node) -> Vector2:
	var cam: Camera3D = me.camera
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var plane := Plane(global_basis.y.normalized(), global_position + global_basis.y * float(_t.surface_h))
	var hit: Variant = plane.intersects_ray(from, dir)
	if hit == null:
		return Vector2.INF
	var l: Vector3 = global_transform.affine_inverse() * (hit as Vector3)
	if from.distance_to(hit as Vector3) > 4.0:
		return Vector2.INF
	return Vector2(l.x, l.z)


# --- helpers --------------------------------------------------------------------------------------

func _world(p: Vector2) -> Vector3:
	return global_transform * Vector3(p.x, float(_t.surface_h), p.y)


func _local_dir(yaw: float) -> Vector2:
	var w := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var l := global_basis.inverse() * w
	return Vector2(l.x, l.z).normalized()


func _sender() -> Node:
	if not multiplayer.is_server():
		return null
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
	var p := _player(peer)
	return null if p == null or p.health.is_dead() else p


func _player(peer: int) -> Node:
	if peer == 0:
		return null
	for p in get_tree().get_nodes_in_group("players"):
		if "peer_id" in p and p.peer_id == peer:
			return p
	return null


func _local_player() -> Node:
	return get_tree().get_first_node_in_group("local_player")


func _name(peer: int) -> String:
	var p := _player(peer)
	if p == null:
		return ""
	return str(p.net_name) if str(p.net_name) != "" else "Player %d" % peer


func _toast(peer: int, text: String) -> void:
	_toast_rpc.rpc_id(peer, text)


@rpc("authority", "call_local", "reliable")
func _toast_rpc(text: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_toast(text, 2.5)


# --- building (meshes shared by every table) ---------------------------------------------------------

func _build() -> void:
	if _table_mesh == null:
		_table_mesh = _make_table_mesh(_t)
		_ball_mesh = SphereMesh.new()
		_ball_mesh.radius = float(_t.ball_r)
		_ball_mesh.height = float(_t.ball_r) * 2.0
		_ball_mesh.radial_segments = 14
		_ball_mesh.rings = 8
		_ball_mats = _make_ball_mats(_t)
	var mi := MeshInstance3D.new()
	mi.mesh = _table_mesh
	mi.visibility_range_end = 60.0
	add_child(mi)
	_body = StaticBody3D.new()
	_body.collision_layer = 9  # world + interactables: blocks walking, the look ray finds it
	_body.collision_mask = 0
	add_child(_body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var outer := Vector2(float(_t.length) + (RAIL + FRAME) * 2.0, float(_t.width) + (RAIL + FRAME) * 2.0)
	box.size = Vector3(outer.x, float(_t.surface_h) + 0.04, outer.y)
	cs.shape = box
	cs.position.y = box.size.y * 0.5
	_body.add_child(cs)
	_body.add_to_group("sport_spots")
	_body.set_meta("target", self)
	_body.set_meta("index", 0)
	_body.set_meta("display_name", "Play pool (E again to leave the table)")
	for b in PoolRules.BALLS:
		var ball := MeshInstance3D.new()
		ball.mesh = _ball_mesh
		ball.material_override = _ball_mats[b]
		ball.visibility_range_end = 30.0
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ball)
		_balls.append(ball)
	var line_mesh := BoxMesh.new()
	line_mesh.size = Vector3(0.004, 0.002, 1.0)
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.albedo_color = Color(1, 1, 1, 0.55)
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mesh.material = line_mat
	_aim_line = MeshInstance3D.new()
	_aim_line.mesh = line_mesh
	_aim_line.visible = false
	add_child(_aim_line)
	var ghost_mesh := SphereMesh.new()
	ghost_mesh.radius = float(_t.ball_r)
	ghost_mesh.height = float(_t.ball_r) * 2.0
	ghost_mesh.radial_segments = 12
	ghost_mesh.rings = 6
	ghost_mesh.material = line_mat
	_ghost = MeshInstance3D.new()
	_ghost.mesh = ghost_mesh
	_ghost.visible = false
	add_child(_ghost)
	var cue_mesh := CylinderMesh.new()
	cue_mesh.top_radius = 0.006
	cue_mesh.bottom_radius = 0.014
	cue_mesh.height = 1.45
	cue_mesh.radial_segments = 8
	var cue_mat := StandardMaterial3D.new()
	cue_mat.albedo_color = Color(0.55, 0.36, 0.2)
	cue_mesh.material = cue_mat
	_cue = MeshInstance3D.new()
	_cue.mesh = cue_mesh
	_cue.visible = false
	add_child(_cue)
	_sign = Label3D.new()
	_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sign.font_size = 34
	_sign.pixel_size = 0.004
	_sign.outline_size = 8
	_sign.position = Vector3(0, 1.75, 0)
	_sign.visibility_range_end = 14.0
	_sign.text = "POOL\nE to play"
	add_child(_sign)


static func _make_table_mesh(t: Dictionary) -> ArrayMesh:
	var L := float(t.length)
	var W := float(t.width)
	var h := float(t.surface_h)
	var felt := Color(0.08, 0.38, 0.2)
	var cushion := Color(0.06, 0.3, 0.16)
	var wood := Color(0.32, 0.17, 0.08)
	var dark := Color(0.04, 0.04, 0.04)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, Vector3(0, h - 0.03, 0), Vector3(L + RAIL, 0.06, W + RAIL), felt)  # bed
	var ox := L * 0.5 + RAIL * 0.5
	var oz := W * 0.5 + RAIL * 0.5
	for s: float in [-1.0, 1.0]:  # cushions (green) + wooden rails
		_box(st, Vector3(0, h + 0.018, s * (W * 0.5 + 0.02)), Vector3(L - 0.12, 0.036, 0.04), cushion)
		_box(st, Vector3(s * (L * 0.5 + 0.02), h + 0.018, 0), Vector3(0.04, 0.036, W - 0.12), cushion)
		_box(st, Vector3(0, h + 0.015, s * (oz + FRAME * 0.5)), Vector3(L + (RAIL + FRAME) * 2.0, 0.07, RAIL + FRAME - 0.04), wood)
		_box(st, Vector3(s * (ox + FRAME * 0.5), h + 0.015, 0), Vector3(RAIL + FRAME - 0.04, 0.07, W + RAIL * 2.0), wood)
	_box(st, Vector3(0, h - 0.2, 0), Vector3(L + RAIL * 2.0, 0.28, W + RAIL * 2.0), wood)  # apron
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			_box(st, Vector3(x * (L * 0.5 - 0.05), (h - 0.34) * 0.5, z * (W * 0.5 - 0.05)), Vector3(0.12, h - 0.34, 0.12), wood)
	for p: Vector2 in PoolRules.pockets(t):  # pocket holes: dark squares over the rail
		_box(st, Vector3(p.x, h + 0.052, p.y), Vector3(0.12, 0.004, 0.12), dark)
	for s: float in [-1.0, 1.0]:  # head string diamonds
		_box(st, Vector3(-L * 0.25, h + 0.052, s * (oz + FRAME * 0.5)), Vector3(0.02, 0.003, 0.02), Color(0.9, 0.88, 0.8))
	st.generate_normals()
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.8
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, m)
	return mesh


static func _make_ball_mats(t: Dictionary) -> Array[StandardMaterial3D]:
	var cols: Array = t.colors
	var out: Array[StandardMaterial3D] = []
	for b in PoolRules.BALLS:
		var m := StandardMaterial3D.new()
		m.roughness = 0.2
		m.metallic_specular = 0.7
		if b == 0:
			m.albedo_color = Color(0.95, 0.94, 0.88)
		elif b == 8:
			m.albedo_color = Color(0.05, 0.05, 0.05)
		else:
			var c: Array = cols[b - 1 if b < 8 else b - 9]
			var col := Color(c[0], c[1], c[2])
			if b < 8:
				m.albedo_color = col
			else:  # stripe: white ball with a coloured band round the middle
				var img := Image.create(32, 16, false, Image.FORMAT_RGB8)
				for y in 16:
					for x in 32:
						img.set_pixel(x, y, col if y >= 5 and y <= 10 else Color(0.95, 0.94, 0.88))
				m.albedo_texture = ImageTexture.create_from_image(img)
		out.append(m)
	return out


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	st.set_color(col)
	var h := s * 0.5
	var p := [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1),
		Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]
	var faces := [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]
	for f: Array in faces:
		var q: Array[Vector3] = []
		for k: int in f:
			q.append(c + p[k] * h)
		for v: Vector3 in [q[0], q[1], q[2], q[0], q[2], q[3]]:
			st.add_vertex(v)
