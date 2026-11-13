# KearneyHigh — builds Kearney High School into a LandmarkKit (D-055): the shell of all three blocks (floor slabs,
# brick outer walls up to the roof, inner walls with doorways, ceilings over the normal-height rooms, one flat roof,
# window bands, step-free ramps at the three outside doors), then signs, lights, loot containers, NPCs (ResidentNpc)
# and enemy spawn markers (Marker3D in group "lair_spawns", meta "enemy" / "requires") from the data file. Furniture
# is added by KearneyHighRooms. Layout (local, x east, z south): wing A = 20 classrooms either side of an east-west
# corridor (front office/detention = first north room, library = two south rooms, science lab near the east end);
# hub B = cafeteria + kitchen (north) and lobby with the main doors (east); wing C = north-south corridor with the
# auditorium, gym (Hunter's arena) and weight room on its west side and small rooms on its east side.
# Depends on: LandmarkKit, kearney_high_rooms.gd, scenes/loot_container.tscn, scenes/resident_npc.tscn.
extends RefCounted

const LOOT := preload("res://scenes/loot_container.tscn")
const NPC := preload("res://scenes/resident_npc.tscn")
const Rooms := preload("res://tools/landmarks/kearney_high_rooms.gd")
const DOOR := 1.2      # half-width of a normal doorway (m)


static func build(k: LandmarkKit, d: Dictionary, rng: RandomNumberGenerator) -> void:
	var m: Dictionary = d.dims
	var a: Array = m.wing_a
	var b: Array = m.hub_b
	var c: Array = m.wing_c
	var ca: Array = m.corridor_a
	var cc: Array = m.corridor_c
	var fy := float(m.floor_y)
	var top := float(m.roof_y)
	var cy := float(m.ceiling_y)
	var aud: Array = m.auditorium_z
	var gym: Array = m.gym_z
	var w := float(m.room_w)
	var lobby_z := float(m.lobby_z)
	var mid_a := (float(ca[0]) + float(ca[1])) * 0.5
	var mid_c := (float(cc[0]) + float(cc[1])) * 0.5

	# Floors and roof.
	for r: Array in [a, b, c]:
		k.block(Vector3(r[0], -2.0, r[1]), Vector3(r[2], fy, r[3]), "floor")
		k.block(Vector3(r[0], top, r[1]), Vector3(r[2], top + 0.4, r[3]), "roof")
	k.block(Vector3(c[0] + 0.3, fy, float(gym[0]) + 0.3), Vector3(float(cc[0]) - 0.3, fy + 0.02, float(gym[1]) - 0.3), "court", false)
	# Ceilings over everything except the auditorium and gym.
	k.block(Vector3(a[0], cy, a[1]), Vector3(a[2], cy + 0.2, a[3]), "ceiling")
	k.block(Vector3(b[0], cy, b[1]), Vector3(b[2], cy + 0.2, b[3]), "ceiling")
	k.block(Vector3(cc[0], cy, c[1]), Vector3(c[2], cy + 0.2, c[3]), "ceiling")
	k.block(Vector3(c[0], cy, gym[1]), Vector3(cc[0], cy + 0.2, c[3]), "ceiling")

	var t := float(m.wall_m)
	var dh := float(m.door_h)
	# --- wing A ---
	_wall_x(k, a[0], a[2], a[1], top, t, dh, "brick", [])
	_wall_x(k, a[0], a[2], a[3], top, t, dh, "brick", [])
	_wall_z(k, a[1], a[3], a[2], top, t, dh, "brick", [[mid_a, 1.5]])
	_wall_z(k, a[1], a[3], a[0], top, t, dh, "brick", [[mid_a, 2.5]])
	var n := roundi((float(a[2]) - float(a[0])) / w)
	var doors: Array = []
	for i in n:
		doors.append([float(a[0]) + w * (i + 0.5), DOOR])
	_wall_x(k, a[0], a[2], ca[0], top, t, dh, "wall", doors)
	_wall_x(k, a[0], a[2], ca[1], top, t, dh, "wall", doors)
	for i in range(1, n):
		var x := float(a[0]) + w * i
		_wall_z(k, a[1], ca[0], x, top, t, dh, "wall", [])
		if i != 5:  # rooms 4 + 5 on the south side are the library
			_wall_z(k, ca[1], a[3], x, top, t, dh, "wall", [])
	# --- hub B ---
	_wall_x(k, b[0], b[2], b[1], top, t, dh, "brick", [])
	_wall_z(k, b[1], b[3], b[0], top, t, dh, "brick", [])
	_wall_z(k, a[3], b[3], b[2], top, t, dh, "brick", [[-25.0, 2.0]])
	_wall_x(k, b[0], b[2], b[3], top, t, dh, "brick", [[mid_c, 2.5]])
	_wall_x(k, b[0], b[2], lobby_z, top, t, dh, "wall", [[-30.0, 4.0]])
	# --- wing C ---
	_wall_x(k, c[0], b[0], c[1], top, t, dh, "brick", [])
	_wall_z(k, c[1], c[3], c[0], top, t, dh, "brick", [])
	_wall_z(k, c[1], c[3], c[2], top, t, dh, "brick", [])
	_wall_x(k, c[0], c[2], c[3], top, t, dh, "brick", [[mid_c, 1.5]])
	_wall_z(k, c[1], c[3], cc[0], top, t, dh, "wall", [[15.0, 2.0], [60.0, 2.0], [105.0, 2.0], [136.0, 1.5]])
	_wall_z(k, c[1], c[3], cc[1], top, t, dh, "wall", [[5.0, DOOR], [35.0, DOOR], [65.0, DOOR], [95.0, DOOR], [129.0, DOOR]])
	for z: float in [20.0, 50.0, 80.0, 110.0]:
		_wall_x(k, cc[1], c[2], z, top, t, dh, "wall", [])
	_wall_x(k, c[0], cc[0], aud[1], top, t, dh, "wall", [])
	_wall_x(k, c[0], cc[0], gym[1], top, t, dh, "wall", [])
	# Outside door ramps (step-free) and window bands on the long outer faces.
	k.ramp(Vector3(float(a[2]) + 3.0, -0.6, mid_a), Vector3(float(a[2]), fy, mid_a), 4.0, 0.4, "concrete")
	k.ramp(Vector3(float(b[2]) + 3.0, -0.6, -25.0), Vector3(float(b[2]), fy, -25.0), 5.0, 0.4, "concrete")
	k.ramp(Vector3(mid_c, -0.6, float(c[3]) + 3.0), Vector3(mid_c, fy, float(c[3])), 4.0, 0.4, "concrete")
	for y: float in [1.2, 5.2]:
		k.block(Vector3(a[0], y, float(a[1]) - 0.2), Vector3(a[2], y + 1.8, float(a[1]) - 0.17), "glass", false)
		k.block(Vector3(a[0], y, float(a[3]) + 0.17), Vector3(a[2], y + 1.8, float(a[3]) + 0.2), "glass", false)
		k.block(Vector3(float(c[0]) - 0.2, y + 2.0, c[1]), Vector3(float(c[0]) - 0.17, y + 3.0, c[3]), "glass", false)
		k.block(Vector3(float(b[0]) - 0.2, y, b[1]), Vector3(float(b[0]) - 0.17, y + 1.8, b[3]), "glass", false)
	for i in n:  # the same windows seen from inside the classrooms
		var x0 := float(a[0]) + w * i + 1.5
		k.block(Vector3(x0, 1.2, float(a[1]) + 0.17), Vector3(x0 + w - 3.0, 3.0, float(a[1]) + 0.2), "glass", false)
		k.block(Vector3(x0, 1.2, float(a[3]) - 0.2), Vector3(x0 + w - 3.0, 3.0, float(a[3]) - 0.17), "glass", false)

	Rooms.build(k, d, rng)
	_place(k, d)


# Wall along x at z (thickness t, floor to `top`) with doorways: gaps = [[centre, half_width], ...] (lintel above).
static func _wall_x(k: LandmarkKit, x0: float, x1: float, z: float, top: float, t: float, door_h: float, mat: String,
		gaps: Array) -> void:
	var at := x0
	for g: Array in gaps:
		var g0 := float(g[0]) - float(g[1])
		var g1 := float(g[0]) + float(g[1])
		if g0 > at:
			k.block(Vector3(at, -2.0, z - t * 0.5), Vector3(g0, top, z + t * 0.5), mat)
		k.block(Vector3(g0, door_h, z - t * 0.5), Vector3(g1, top, z + t * 0.5), mat)
		at = g1
	if x1 > at:
		k.block(Vector3(at, -2.0, z - t * 0.5), Vector3(x1, top, z + t * 0.5), mat)


static func _wall_z(k: LandmarkKit, z0: float, z1: float, x: float, top: float, t: float, door_h: float, mat: String,
		gaps: Array) -> void:
	var at := z0
	for g: Array in gaps:
		var g0 := float(g[0]) - float(g[1])
		var g1 := float(g[0]) + float(g[1])
		if g0 > at:
			k.block(Vector3(x - t * 0.5, -2.0, at), Vector3(x + t * 0.5, top, g0), mat)
		k.block(Vector3(x - t * 0.5, door_h, g0), Vector3(x + t * 0.5, top, g1), mat)
		at = g1
	if z1 > at:
		k.block(Vector3(x - t * 0.5, -2.0, at), Vector3(x + t * 0.5, top, z1), mat)


# Signs, lights, loot containers, NPCs and enemy spawn markers from the data file.
static func _place(k: LandmarkKit, d: Dictionary) -> void:
	var fy := float(d.dims.floor_y)
	var i := 0
	for s: Dictionary in d.signs:
		var p: Array = s.pos
		var c: Array = s.color
		var l := Label3D.new()
		l.name = "Sign_%d" % i
		l.text = str(s.text)
		l.font_size = int(s.size)
		l.pixel_size = 0.01
		l.outline_size = 8
		l.modulate = Color(c[0], c[1], c[2])
		l.shaded = true
		l.double_sided = false
		l.position = Vector3(p[0], p[1], p[2])
		l.rotation.y = deg_to_rad(float(s.yaw_deg))
		l.visibility_range_end = 250.0
		k.root.add_child(l)
		i += 1
	i = 0
	for ld: Dictionary in d.lights:
		var p: Array = ld.pos
		var c: Array = ld.color
		var light := OmniLight3D.new()
		light.name = "Light_%d" % i
		light.position = Vector3(p[0], p[1], p[2])
		light.light_color = Color(c[0], c[1], c[2])
		light.light_energy = float(ld.energy)
		light.omni_range = float(ld.range)
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 55.0
		light.distance_fade_length = 15.0
		k.root.add_child(light)
		i += 1
	for l: Dictionary in d.loot:
		var p: Array = l.pos
		var sz: Array = l.size
		k.place(LOOT, Transform3D(Basis(), Vector3(p[0], p[1], p[2])), {"container_id": "khs_" + str(l.id),
			"display_name": str(l.name), "loot_table": str(l.table), "size": Vector3(sz[0], sz[1], sz[2]),
			"color": Color(0.32, 0.34, 0.4)}, "Loot_" + str(l.id))
	for n: Dictionary in d.npcs:
		var p: Array = n.pos
		k.place(NPC, Transform3D(Basis(Vector3.UP, deg_to_rad(float(n.yaw_deg))), Vector3(p[0], p[1], p[2])),
			{"npc_id": str(n.npc_id)}, str(n.name))
	for s: Array in d.spawns:
		var mk := Marker3D.new()
		mk.name = "khs_" + str(s[0])
		var xz: Array = s[2]
		mk.position = Vector3(xz[0], (1.1 if str(s[0]) == "aud_boss" else fy) + 0.05, xz[1])
		mk.set_meta("enemy", str(s[1]))
		if s.size() > 3:
			mk.set_meta("requires", str(s[3]))
		mk.add_to_group("lair_spawns", true)
		k.root.add_child(mk)
