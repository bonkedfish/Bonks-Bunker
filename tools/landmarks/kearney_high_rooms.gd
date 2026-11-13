# KearneyHighRooms — furniture and set dressing for the Kearney High landmark (D-055), added to the same LandmarkKit:
# classrooms (desk grids, teacher's desk, chalkboard, some knocked over), corridor lockers, the front office turned
# holding cell (bars, mattresses), library shelves, science lab benches, cafeteria tables + serving counter, lobby,
# auditorium (stage, curtains, seat rows), gym (court, bleachers, hoops, Hunter's cages and trophy boards) and the
# weight room. Big pieces have collision (the navmesh bakes around them); small ones don't.
# Depends on: LandmarkKit.
extends RefCounted


static func build(k: LandmarkKit, d: Dictionary, rng: RandomNumberGenerator) -> void:
	var m: Dictionary = d.dims
	var fy := float(m.floor_y)
	var a: Array = m.wing_a
	var ca: Array = m.corridor_a
	var w := float(m.room_w)
	var n := roundi((float(a[2]) - float(a[0])) / w)
	for i in n:
		var x0 := float(a[0]) + w * i
		if i == 0:
			_holding_cell(k, x0, float(a[1]), w, float(ca[0]), fy)
		else:
			_classroom(k, x0, float(a[1]), float(ca[0]), w, fy, 1.0, rng)
		if i == 4 or i == 5:
			_library(k, x0, float(ca[1]), float(a[3]), w, fy)
		elif i == 8:
			_lab(k, x0, float(ca[1]), float(a[3]), w, fy)
		else:
			_classroom(k, x0, float(a[3]), float(ca[1]), w, fy, -1.0, rng)
		# Corridor lockers either side of each doorway.
		for z: float in [float(ca[0]) + 0.35, float(ca[1]) - 0.35]:
			k.box(Vector3(x0 + 2.2, fy + 0.95, z), Vector3(3.6, 1.9, 0.35), "locker", 0.0, false)
			k.box(Vector3(x0 + w - 2.2, fy + 0.95, z), Vector3(3.6, 1.9, 0.35), "locker", 0.0, false)
	_cafeteria(k, m, fy, rng)
	_lobby(k, m, fy)
	_auditorium(k, m, fy)
	_gym(k, m, fy)
	_weight_room(k, m, fy)
	_small_rooms(k, m, fy)
	# Litter and old blood down both corridors.
	var cc: Array = m.corridor_c
	var c: Array = m.wing_c
	for i in 70:
		var p := Vector3(rng.randf_range(float(a[0]) + 1.0, float(a[2]) - 1.0), fy + 0.02, rng.randf_range(float(ca[0]) + 0.6, float(ca[1]) - 0.6))
		if i % 2 == 1:
			p = Vector3(rng.randf_range(float(cc[0]) + 0.6, float(cc[1]) - 0.6), fy + 0.02, rng.randf_range(float(c[1]) + 1.0, float(c[3]) - 1.0))
		k.box(p, Vector3(rng.randf_range(0.2, 0.9), 0.02, rng.randf_range(0.2, 0.9)), "blood" if rng.randf() < 0.3 else "paper",
			rng.randf() * TAU, false)


# A classroom between the outer wall (z_out) and the corridor wall (z_in); side = +1 north rooms, -1 south rooms.
static func _classroom(k: LandmarkKit, x0: float, z_out: float, z_in: float, w: float, fy: float, side: float,
		rng: RandomNumberGenerator) -> void:
	var front := z_out + side * 1.6   # teacher's end, by the windows
	k.box(Vector3(x0 + w * 0.5, fy + 0.4, front), Vector3(1.6, 0.8, 0.7), "desk")
	k.block(Vector3(x0 + 0.18, fy + 1.0, minf(z_out + side * 3.0, z_out + side * 9.0)), Vector3(x0 + 0.22, fy + 2.4, maxf(z_out + side * 3.0, z_out + side * 9.0)), "board", false)
	for r in 3:
		for c in 3:
			var p := Vector3(x0 + 2.6 + c * 3.2, fy, front + side * (2.8 + r * 2.6))
			if rng.randf() < 0.2:
				k.box(p + Vector3(0.2, 0.3, 0.1), Vector3(0.75, 0.6, 0.55), "desk", rng.randf() * TAU, false)  # knocked over
				continue
			k.box(p + Vector3(0, 0.36, 0), Vector3(0.7, 0.72, 0.5), "desk")
			k.box(p + Vector3(0, 0.22, side * 0.6), Vector3(0.4, 0.44, 0.4), "steel", 0.0, false)


# Front office turned holding cell: a barred cage across the back half with a gap, mattresses, a desk.
static func _holding_cell(k: LandmarkKit, x0: float, z_out: float, w: float, z_in: float, fy: float) -> void:
	var zc := (z_out + z_in) * 0.5
	var x := x0 + 0.6
	while x < x0 + w - 0.4:
		if absf(x - (x0 + w * 0.5)) > 1.0:  # the cage door Hunter left open
			k.box(Vector3(x, fy + 1.4, zc + 2.5), Vector3(0.08, 2.8, 0.08), "steel", 0.0, false)
		x += 0.35
	k.block(Vector3(x0 + 0.3, fy, zc + 2.4), Vector3(x0 + w * 0.5 - 1.0, fy + 2.8, zc + 2.6), "", true)
	k.block(Vector3(x0 + w * 0.5 + 1.0, fy, zc + 2.4), Vector3(x0 + w - 0.3, fy + 2.8, zc + 2.6), "", true)
	k.box(Vector3(x0 + w * 0.5, fy + 2.75, zc + 2.5), Vector3(w - 0.6, 0.1, 0.1), "steel", 0.0, false)
	for i in 3:
		k.box(Vector3(x0 + 2.0 + i * 3.6, fy + 0.1, z_out + 1.6), Vector3(0.9, 0.2, 1.9), "mat", 0.1 * i, false)
	k.box(Vector3(x0 + w - 2.0, fy + 0.4, z_in - 1.4), Vector3(1.6, 0.8, 0.7), "desk")


static func _library(k: LandmarkKit, x0: float, z_in: float, z_out: float, w: float, fy: float) -> void:
	for i in 3:
		var x := x0 + 2.5 + i * 3.4
		k.box(Vector3(x, fy + 1.0, (z_in + z_out) * 0.5 + 1.0), Vector3(0.5, 2.0, 9.0), "book")


static func _lab(k: LandmarkKit, x0: float, z_in: float, z_out: float, w: float, fy: float) -> void:
	for i in 2:
		var z := z_in + 4.5 + i * 5.0
		k.box(Vector3(x0 + w * 0.5 - 1.0, fy + 0.45, z), Vector3(7.0, 0.9, 1.2), "table")
		for j in 4:
			k.cylinder(Vector3(x0 + 2.4 + j * 1.6, fy + 0.9, z), 0.06, 0.25, "glass", 6)


static func _cafeteria(k: LandmarkKit, m: Dictionary, fy: float, rng: RandomNumberGenerator) -> void:
	var b: Array = m.hub_b
	# Serving counter with the kitchen behind it (a gap at each end).
	k.block(Vector3(float(b[0]) + 6.0, fy, -99.0), Vector3(float(b[2]) - 6.0, fy + 1.05, -98.0), "table")
	k.block(Vector3(float(b[0]) + 14.0, fy, -109.6), Vector3(float(b[2]) - 14.0, fy + 0.9, -108.6), "steel")
	for r in 3:
		for c in 2:
			var p := Vector3(-45.0 + c * 28.0, fy, -88.0 + r * 14.0)
			var yaw := 0.0 if rng.randf() < 0.75 else rng.randf_range(-0.5, 0.5)
			k.box(p + Vector3(0, 0.38, 0), Vector3(9.0, 0.76, 1.0), "table", yaw)
			for s: float in [-0.9, 0.9]:
				k.box(p + Vector3(0, 0.22, s).rotated(Vector3.UP, yaw), Vector3(9.0, 0.44, 0.4), "locker", yaw, false)
	for i in 14:
		k.box(Vector3(rng.randf_range(-56.0, -4.0), fy + 0.03, rng.randf_range(-96.0, -44.0)), Vector3(0.45, 0.04, 0.35), "table",
			rng.randf() * TAU, false)
	# Darlene's spills.
	for i in 8:
		k.disc(Vector3(rng.randf_range(-52.0, -8.0), fy + 0.03, rng.randf_range(-108.0, -92.0)), rng.randf_range(0.5, 1.4), "blood", 9)


static func _lobby(k: LandmarkKit, m: Dictionary, fy: float) -> void:
	# Bearcat floor emblem, banners, benches.
	k.disc(Vector3(-22.0, fy + 0.02, -25.0), 3.2, "gold", 20)
	k.disc(Vector3(-22.0, fy + 0.03, -25.0), 2.4, "locker", 20)
	for z: float in [-36.0, -14.0]:
		k.box(Vector3(-12.0, fy + 0.25, z), Vector3(4.0, 0.5, 0.6), "desk")
	for x: float in [-52.0, -44.0, -8.0]:
		k.block(Vector3(x - 1.0, fy + 1.4, float(m.lobby_z) + 0.17), Vector3(x + 1.0, fy + 3.6, float(m.lobby_z) + 0.2), "gold", false)


static func _auditorium(k: LandmarkKit, m: Dictionary, fy: float) -> void:
	var c: Array = m.wing_c
	var cc: Array = m.corridor_c
	var az: Array = m.auditorium_z
	var x0 := float(c[0]) + 0.3
	# Stage (1 m) across the west end with a ramp up each side, curtains behind.
	k.block(Vector3(x0, fy, float(az[0]) + 0.3), Vector3(x0 + 13.0, fy + 1.0, float(az[1]) - 0.3), "desk")
	for z: float in [float(az[0]) + 2.0, float(az[1]) - 2.0]:
		k.ramp(Vector3(x0 + 17.0, fy, z), Vector3(x0 + 13.0, fy + 1.0, z), 3.0, 0.3, "desk")
	k.block(Vector3(x0 + 0.05, fy + 1.0, float(az[0]) + 0.3), Vector3(x0 + 0.15, 8.0, float(az[1]) - 0.3), "curtain", false)
	for z: float in [float(az[0]) + 0.5, float(az[1]) - 4.5]:
		k.block(Vector3(x0 + 11.5, fy + 1.0, z), Vector3(x0 + 11.8, 8.0, z + 4.0), "curtain", false)
	# Seat rows with a centre aisle.
	var zc := (float(az[0]) + float(az[1])) * 0.5
	var x := x0 + 19.0
	while x < float(cc[0]) - 2.5:
		k.block(Vector3(x, fy, float(az[0]) + 2.0), Vector3(x + 0.7, fy + 0.9, zc - 1.6), "seat")
		k.block(Vector3(x, fy, zc + 1.6), Vector3(x + 0.7, fy + 0.9, float(az[1]) - 2.0), "seat")
		x += 2.3


static func _gym(k: LandmarkKit, m: Dictionary, fy: float) -> void:
	var c: Array = m.wing_c
	var cc: Array = m.corridor_c
	var gz: Array = m.gym_z
	var x0 := float(c[0]) + 0.3
	var x1 := float(cc[0]) - 0.3
	var z0 := float(gz[0]) + 0.3
	var z1 := float(gz[1]) - 0.3
	var zc := (z0 + z1) * 0.5
	var xc := (x0 + x1) * 0.5
	# Court lines + centre circle.
	k.disc(Vector3(xc, fy + 0.04, zc), 3.6, "gold", 24)
	k.disc(Vector3(xc, fy + 0.05, zc), 3.3, "court", 24)
	for z: float in [z0 + 6.0, zc, z1 - 6.0]:
		k.block(Vector3(x0 + 8.0, fy + 0.03, z - 0.06), Vector3(x1 - 4.0, fy + 0.04, z + 0.06), "gold", false)
	# Hoops at both ends.
	for z: float in [z0 + 1.0, z1 - 1.0]:
		k.box(Vector3(xc, fy + 3.6, z), Vector3(1.8, 1.1, 0.08), "table", 0.0, false)
		k.cylinder(Vector3(xc, fy, z), 0.1, 3.3, "steel", 6)
	# Bleachers along the west wall (5 steps).
	for i in 5:
		k.block(Vector3(x0, fy, z0 + 12.0), Vector3(x0 + 5.0 - i * 1.0, fy + 0.45 * (i + 1), z1 - 12.0), "desk")
	# Hunter's cages (empty now) in the north-west corner and his trophy boards on the east wall.
	for cage in 3:
		var cz := z0 + 1.5 + cage * 3.4
		var x := x0 + 7.0
		while x < x0 + 10.4:
			k.box(Vector3(x, fy + 1.1, cz), Vector3(0.07, 2.2, 0.07), "steel", 0.0, false)
			k.box(Vector3(x, fy + 1.1, cz + 3.0), Vector3(0.07, 2.2, 0.07), "steel", 0.0, false)
			x += 0.3
		k.box(Vector3(x0 + 8.7, fy + 2.2, cz + 1.5), Vector3(3.5, 0.08, 3.1), "steel", 0.0, false)
		k.box(Vector3(x0 + 8.7, fy + 1.1, cz + 1.5), Vector3(3.4, 2.2, 3.0), "", 0.0, true)
	for i in 4:
		k.block(Vector3(x1 - 0.05, fy + 1.2, zc - 9.0 + i * 5.0), Vector3(x1, fy + 2.8, zc - 6.0 + i * 5.0), "board", false)
		for j in 6:
			k.box(Vector3(x1 - 0.07, fy + 1.5 + (j % 2) * 0.7, zc - 8.6 + i * 5.0 + (j / 2) * 0.9), Vector3(0.01, 0.4, 0.3), "paper", 0.0, false)
	# Sandbag cover the fight is played around.
	for p: Vector3 in [Vector3(xc - 8.0, fy, zc - 14.0), Vector3(xc + 9.0, fy, zc - 6.0), Vector3(xc - 4.0, fy, zc + 10.0),
			Vector3(xc + 10.0, fy, zc + 18.0), Vector3(xc - 12.0, fy, zc + 22.0)]:
		k.box(p + Vector3(0, 0.6, 0), Vector3(3.0, 1.2, 0.9), "mat", 0.4 * (int(p.x) % 3))


static func _weight_room(k: LandmarkKit, m: Dictionary, fy: float) -> void:
	var c: Array = m.wing_c
	var gz: Array = m.gym_z
	for i in 4:
		var p := Vector3(float(c[0]) + 6.0 + i * 9.0, fy, float(gz[1]) + 8.0)
		k.box(p + Vector3(0, 0.25, 0), Vector3(0.5, 0.5, 1.8), "mat")
		k.box(p + Vector3(0, 1.1, -0.7), Vector3(1.9, 0.06, 0.06), "steel", 0.0, false)
		for s: float in [-0.85, 0.85]:
			k.box(p + Vector3(s, 0.55, -0.7), Vector3(0.06, 1.1, 0.06), "steel", 0.0, false)
			k.box(p + Vector3(s * 1.08, 1.1, -0.7), Vector3(0.08, 0.5, 0.5), "roof", 0.0, false)
	k.block(Vector3(float(c[0]) + 3.0, fy, float(gz[1]) + 16.0), Vector3(float(c[0]) + 20.0, fy + 0.05, float(gz[1]) + 22.0), "mat", false)


# East-side rooms of wing C: nurse, storage, locker rooms: benches and lockers.
static func _small_rooms(k: LandmarkKit, m: Dictionary, fy: float) -> void:
	var cc: Array = m.corridor_c
	var c: Array = m.wing_c
	var x0 := float(cc[1]) + 0.3
	var x1 := float(c[2]) - 0.3
	k.box(Vector3(x0 + 2.0, fy + 0.3, 12.0), Vector3(0.9, 0.6, 2.0), "table")  # nurse's cot
	for z: float in [58.0, 72.0, 88.0, 102.0]:
		k.box(Vector3((x0 + x1) * 0.5, fy + 0.22, z), Vector3(0.5, 0.44, 3.0), "desk")
		k.box(Vector3(x1 - 0.2, fy + 0.95, z), Vector3(0.35, 1.9, 4.0), "locker", 0.0, false)
	k.box(Vector3(x1 - 0.5, fy + 0.5, 140.0), Vector3(0.8, 1.0, 3.0), "steel")
