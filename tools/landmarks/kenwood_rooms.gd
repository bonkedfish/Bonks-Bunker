# KenwoodRooms — furniture and set dressing for Kenwood Elementary (D-078), added to the same LandmarkKit from the
# "rooms" list in data/landmarks/kenwood.json (type + rect [x0, z0, x1, z1] in the building's local frame + optional
# "board" wall n/s/e/w). Kid-sized classrooms (desk clusters, little chairs, rug, whiteboard, cubbies), library,
# music risers, art tables + sink, restrooms, gym (court lines, hoops, mats), cafeteria (folding lunch tables, stage),
# kitchen, office, principal, nurse, Pre-K, conference, sensory room, lobby; corridors get coat hooks, backpacks and
# bulletin boards. Post-apocalypse: knocked-over desks, paper litter, old blood, a barricade at the front doors.
# Big pieces have collision (the navmesh bakes around them); small ones don't.
# Depends on: LandmarkKit.
extends RefCounted


static func build(k: LandmarkKit, d: Dictionary, rng: RandomNumberGenerator) -> void:
	var fy := float(d.dims.floor_y)
	for r: Dictionary in d.rooms:
		var a: Array = r.rect
		var lo := Vector2(minf(a[0], a[2]), minf(a[1], a[3]))
		var hi := Vector2(maxf(a[0], a[2]), maxf(a[1], a[3]))
		match str(r.type):
			"classroom": _classroom(k, lo, hi, fy, str(r.get("board", "n")), rng, str(r.get("rug", "rug_blue")))
			"prek": _prek(k, lo, hi, fy, rng)
			"library": _library(k, lo, hi, fy, rng)
			"music": _music(k, lo, hi, fy, rng)
			"art": _art(k, lo, hi, fy, rng)
			"restroom": _restroom(k, lo, hi, fy, str(r.get("board", "n")))
			"gym": _gym(k, lo, hi, fy, rng)
			"cafeteria": _cafeteria(k, lo, hi, fy, rng)
			"kitchen": _kitchen(k, lo, hi, fy)
			"office": _office(k, lo, hi, fy, rng)
			"nurse": _nurse(k, lo, hi, fy)
			"conference": _conference(k, lo, hi, fy)
			"sensory": _sensory(k, lo, hi, fy, rng)
			"corridor": _corridor(k, lo, hi, fy, rng)
			"lobby": _lobby(k, lo, hi, fy, rng)
		_litter(k, lo, hi, fy, rng, float(r.get("litter", 0.04)))
	for b: Dictionary in d.get("barricades", []):
		var p: Array = b.pos
		for i in 6:
			k.box(Vector3(p[0] + rng.randf_range(-1.2, 1.2), fy + 0.4 + (i % 3) * 0.45, p[1] + rng.randf_range(-0.6, 0.6)),
				Vector3(1.2, 0.7, 0.6), "desk" if i % 2 == 0 else "table", rng.randf_range(-0.6, 0.6), i < 3)


# Classroom: 2x3 clusters of 4 kid desks, little chairs, teacher desk, whiteboard on the `board` wall, rug,
# cubbies along the opposite wall, a reading shelf. Some desks knocked over.
static func _classroom(k: LandmarkKit, lo: Vector2, hi: Vector2, fy: float, board: String, rng: RandomNumberGenerator,
		rug: String) -> void:
	var c := (lo + hi) * 0.5
	var sz := hi - lo
	var front := _wall_point(lo, hi, board, 0.12)
	var back := _wall_point(lo, hi, _opposite(board), 0.12)
	var along_x := board == "n" or board == "s"
	# Whiteboard + teacher's desk near the board wall.
	var bw := minf(5.5, (sz.x if along_x else sz.y) - 3.0)
	k.box(Vector3(front.x, fy + 1.55, front.y), Vector3(bw if along_x else 0.05, 1.2, 0.05 if along_x else bw), "porcelain", 0.0, false)
	var td := front.lerp(c, 0.28) + (Vector2(2.2, 0) if along_x else Vector2(0, 2.2))
	k.box(Vector3(td.x, fy + 0.38, td.y), Vector3(1.5 if along_x else 0.75, 0.76, 0.75 if along_x else 1.5), "desk")
	# Rug + reading corner by the back wall.
	var rp := back.lerp(c, 0.35)
	k.box(Vector3(rp.x, fy + 0.01, rp.y), Vector3(3.6, 0.02, 2.6) if along_x else Vector3(2.6, 0.02, 3.6), rug, 0.0, false)
	var cub := _wall_point(lo, hi, _opposite(board), 0.3)
	k.box(Vector3(cub.x, fy + 0.7, cub.y), Vector3(sz.x - 1.6, 1.4, 0.4) if along_x else Vector3(0.4, 1.4, sz.y - 1.6), "shelf", 0.0, true)
	for i in 6:  # backpacks still in the cubbies
		var t := (float(i) + 0.5) / 6.0 - 0.5
		var bp := cub + (Vector2(t * (sz.x - 2.0), 0) if along_x else Vector2(0, t * (sz.y - 2.0)))
		if rng.randf() < 0.6:
			k.box(Vector3(bp.x, fy + 1.0, bp.y), Vector3(0.3, 0.35, 0.22), _pick(rng, ["plastic_red", "plastic_blue", "plastic_green", "plastic_yellow"]), rng.randf() * 0.4, false)
	# Desk clusters: 2 x 3 groups of four.
	for gx in 3:
		for gz in 2:
			var u := lerpf(-0.3, 0.3, gx / 2.0)
			var v := lerpf(-0.05, 0.25, gz / 1.0)
			var g := c + (Vector2(u * sz.x, v * sz.y * (1.0 if board == "n" else -1.0)) if along_x else Vector2(v * sz.x * (1.0 if board == "w" else -1.0), u * sz.y))
			for q in 4:
				var o := Vector2(0.33 if q % 2 == 1 else -0.33, 0.25 if q >= 2 else -0.25)
				var p := g + o
				if rng.randf() < 0.18:  # knocked over
					k.box(Vector3(p.x, fy + 0.18, p.y), Vector3(0.6, 0.36, 0.45), "desk", rng.randf() * TAU, false)
					continue
				k.box(Vector3(p.x, fy + 0.31, p.y), Vector3(0.62, 0.62, 0.48), "desk")
				var ch := p + o * 1.9
				k.box(Vector3(ch.x, fy + 0.18, ch.y), Vector3(0.36, 0.36, 0.36), _pick(rng, ["plastic_red", "plastic_blue", "plastic_green", "plastic_yellow"]), rng.randf_range(-0.4, 0.4), false)
	_board_papers(k, lo, hi, fy, _side_wall(board), rng)


static func _prek(k: LandmarkKit, lo: Vector2, hi: Vector2, fy: float, rng: RandomNumberGenerator) -> void:
	var c := (lo + hi) * 0.5
	k.box(Vector3(c.x, fy + 0.01, c.y), Vector3(4.0, 0.02, 4.0), "rug_red", 0.0, false)
	for i in 4:  # little round tables (as low boxes) with stools
		var p := c + Vector2(cos(i * TAU / 4.0 + 0.4), sin(i * TAU / 4.0 + 0.4)) * 3.4
		k.box(Vector3(p.x, fy + 0.27, p.y), Vector3(1.1, 0.54, 1.1), "table")
		for j in 3:
			var s := p + Vector2(cos(j * 2.1), sin(j * 2.1)) * 0.8
			k.box(Vector3(s.x, fy + 0.14, s.y), Vector3(0.3, 0.28, 0.3), _pick(rng, ["plastic_red", "plastic_blue", "plastic_yellow"]), 0.0, false)
	# Play kitchen + block shelf along the east wall.
	k.box(Vector3(hi.x - 0.5, fy + 0.45, c.y - 2.0), Vector3(0.6, 0.9, 1.6), "plastic_red")
	k.box(Vector3(hi.x - 0.5, fy + 0.4, c.y + 1.5), Vector3(0.6, 0.8, 2.2), "shelf")
	for i in 14:
		k.box(Vector3(rng.randf_range(lo.x + 1, hi.x - 1), fy + 0.06, rng.randf_range(lo.y + 1, hi.y - 1)), Vector3(0.12, 0.12, 0.12),
			_pick(rng, ["plastic_red", "plastic_blue", "plastic_green", "plastic_yellow"]), rng.randf() * TAU, false)


static func _library(k: LandmarkKit, lo: Vector2, hi: Vector2, fy: float, rng: RandomNumberGenerator) -> void:
	k.box(Vector3((lo.x + hi.x) * 0.5, fy + 0.01, (lo.y + hi.y) * 0.5), Vector3(hi.x - lo.x - 0.4, 0.02, hi.y - lo.y - 0.4), "carpet", 0.0, false)
	# Low shelves around the walls, two free-standing rows, a circulation desk, reading tables.
	for side: String in ["n", "e"]:
		var p := _wall_point(lo, hi, side, 0.3)
		var ln := (hi.x - lo.x - 2.0) if side == "n" else (hi.y - lo.y - 2.0)
		k.box(Vector3(p.x, fy + 0.65, p.y), Vector3(ln, 1.3, 0.35) if side == "n" else Vector3(0.35, 1.3, ln), "shelf")
		_books(k, p, side, ln, fy + 1.32, rng)
	for i in 2:
		var x := lerpf(lo.x + 3.0, hi.x - 3.5, i / 1.0)
		k.box(Vector3(x, fy + 0.6, lo.y + 5.0), Vector3(3.5, 1.2, 0.5), "shelf")
		if rng.randf() < 0.5:  # books spilled on the floor
			for j in 8:
				k.box(Vector3(x + rng.randf_range(-1.6, 1.6), fy + 0.03, lo.y + 5.8 + rng.randf_range(0, 1.0)), Vector3(0.2, 0.04, 0.28), "book", rng.randf() * TAU, false)
	k.box(Vector3(lo.x + 2.0, fy + 0.5, hi.y - 2.0), Vector3(2.6, 1.0, 0.8), "desk")
	for i in 2:
		k.box(Vector3(lerpf(lo.x + 4.0, hi.x - 3.0, i / 1.0), fy + 0.33, hi.y - 3.6), Vector3(1.6, 0.66, 1.0), "table")


static func _music(k: LandmarkKit, lo: Vector2, hi: Vector2, fy: float, rng: RandomNumberGenerator) -> void:
	k.box(Vector3((lo.x + hi.x) * 0.5, fy + 0.01, (lo.y + hi.y) * 0.5), Vector3(hi.x - lo.x - 0.4, 0.02, hi.y - lo.y - 0.4), "carpet", 0.0, false)
	for i in 3:  # stepped risers against the west wall
		k.block(Vector3(lo.x + 0.2 + i * 1.2, fy, lo.y + 1.5), Vector3(lo.x + 1.4 + i * 1.2, fy + 0.45 - i * 0.15, hi.y - 1.5), "stage")
	k.box(Vector3(hi.x - 2.5, fy + 0.65, lo.y + 2.0), Vector3(1.6, 1.3, 0.7), "roof")
	for i in 14:
		var p := Vector2(lerpf(lo.x + 5.0, hi.x - 3.0, (i % 5) / 4.0), lerpf(lo.y + 3.5, hi.y - 3.0, (i / 5) / 2.0))
		k.box(Vector3(p.x, fy + 0.2, p.y), Vector3(0.38, 0.4, 0.38), "plastic_blue", rng.randf_range(-0.3, 0.3), false)
	k.box(Vector3(hi.x - 0.3, fy + 1.6, (lo.y + hi.y) * 0.5), Vector3(0.05, 1.2, 4.5), "porcelain", 0.0, false)


static func _art(k: LandmarkKit, lo: Vector2, hi: Vector2, fy: float, rng: RandomNumberGenerator) -> void:
	for i in 4:
		var p := Vector2(lerpf(lo.x + 3.0, hi.x - 3.0, (i % 2) / 1.0), lerpf(lo.y + 3.0, hi.y - 3.5, (i / 2) / 1.0))
		k.box(Vector3(p.x, fy + 0.35, p.y), Vector3(2.4, 0.7, 1.2), "table")
		for j in 6:
			k.box(Vector3(p.x + rng.randf_range(-1, 1), fy + 0.71, p.y + rng.randf_range(-0.5, 0.5)), Vector3(0.3, 0.01, 0.22),
				_pick(rng, ["paper", "paint_yellow", "plastic_red", "plastic_blue"]), rng.randf() * TAU, false)
	var sink := _wall_point(lo, hi, "w", 0.4)
	k.box(Vector3(sink.x, fy + 0.45, sink.y), Vector3(0.7, 0.9, 4.0), "table")
	var paint := _wall_point(lo, hi, "e", 0.3)
	k.box(Vector3(paint.x, fy + 1.0, paint.y), Vector3(0.4, 2.0, 3.0), "shelf")
	for i in 10:  # paint spatter on the floor
		k.box(Vector3(rng.randf_range(lo.x + 1, hi.x - 1), fy + 0.012, rng.randf_range(lo.y + 1, hi.y - 1)), Vector3(0.4, 0.01, 0.3),
			_pick(rng, ["paint_yellow", "plastic_red", "plastic_blue", "plastic_green"]), rng.randf() * TAU, false)


# Restroom: tiled floor, a row of stalls along the `board` wall, sinks on the opposite wall.
static func _restroom(k: LandmarkKit, lo: Vector2, hi: Vector2, fy: float, wall: String) -> void:
	k.box(Vector3((lo.x + hi.x) * 0.5, fy + 0.01, (lo.y + hi.y) * 0.5), Vector3(hi.x - lo.x - 0.3, 0.02, hi.y - lo.y - 0.3), "tile", 0.0, false)
	var n := 4
	var w := (hi.x - lo.x - 0.6) / n
	for i in n + 1:
		var x := lo.x + 0.3 + w * i
		k.box(Vector3(x, fy + 0.95, lo.y + 0.85), Vector3(0.05, 1.6, 1.5), "stall", 0.0, false)
	for i in n:
		var x := lo.x + 0.3 + w * (i + 0.5)
		k.box(Vector3(x, fy + 0.95, lo.y + 1.6), Vector3(w - 0.7, 1.6, 0.04), "stall", 0.0, false)
		k.box(Vector3(x, fy + 0.2, lo.y + 0.45), Vector3(0.4, 0.4, 0.55), "porcelain", 0.0, false)
	for i in 3:  # sinks + mirrors on the west wall, clear of the corridor door
		var z := lerpf(lo.y + 4.0, hi.y - 3.0, i / 2.0)
		k.box(Vector3(lo.x + 0.35, fy + 0.7, z), Vector3(0.45, 0.12, 0.6), "porcelain", 0.0, false)
		k.box(Vector3(lo.x + 0.12, fy + 1.6, z), Vector3(0.03, 0.7, 0.5), "glass", 0.0, false)


static func _gym(k: LandmarkKit, lo: Vector2, hi: Vector2, fy: float, rng: RandomNumberGenerator) -> void:
	var c := (lo + hi) * 0.5
	var y := fy + 0.02
	# Court lines: boundary, centre line, centre circle, keys at both ends.
	var cx0 := lo.x + 3.0
	var cx1 := hi.x - 3.0
	var cz0 := lo.y + 3.0
	var cz1 := hi.y - 3.0
	for l: Array in [[cx0, cz0, cx1, cz0], [cx0, cz1, cx1, cz1], [cx0, cz0, cx0, cz1], [cx1, cz0, cx1, cz1], [c.x, cz0, c.x, cz1]]:
		k.block(Vector3(minf(l[0], l[2]) - 0.05, y, minf(l[1], l[3]) - 0.05), Vector3(maxf(l[0], l[2]) + 0.05, y + 0.005, maxf(l[1], l[3]) + 0.05), "porcelain", false)
	k.disc(Vector3(c.x, y + 0.006, c.y), 1.8, "porcelain", 24)
	k.disc(Vector3(c.x, y + 0.007, c.y), 1.7, "court", 24)
	for e: float in [-1.0, 1.0]:
		var bx := cx0 + 1.2 if e < 0 else cx1 - 1.2
		k.block(Vector3(minf(bx, bx - e * 5.0), y, c.y - 1.8), Vector3(maxf(bx, bx - e * 5.0), y + 0.004, c.y + 1.8), "plastic_blue", false)
		var hoop := Vector3((lo.x + 0.6) if e < 0 else (hi.x - 0.6), fy, c.y)
		k.box(hoop + Vector3(-e * 0.3, 3.4, 0), Vector3(0.05, 1.05, 1.8), "backboard", 0.0, false)
		k.box(hoop + Vector3(-e * 0.7, 3.05, 0), Vector3(0.46, 0.03, 0.46), "ball_orange", 0.0, false)
		k.box(hoop + Vector3(0, 5.0, 0), Vector3(0.12, 3.0, 0.12), "steel", 0.0, false)
	# Folded bleachers on the north wall, a stack of mats and a ball cart.
	k.block(Vector3(lo.x + 6.0, fy, lo.y + 0.3), Vector3(hi.x - 6.0, fy + 2.6, lo.y + 1.3), "bleacher")
	for i in 4:
		k.box(Vector3(hi.x - 3.0, fy + 0.1 + i * 0.12, hi.y - 2.0), Vector3(1.8, 0.11, 1.2), "mat", rng.randf_range(-0.2, 0.2), i == 0)
	k.box(Vector3(lo.x + 2.0, fy + 0.45, hi.y - 1.5), Vector3(1.0, 0.9, 0.6), "steel")
	for i in 12:
		k.cylinder(Vector3(rng.randf_range(lo.x + 2, hi.x - 2), fy, rng.randf_range(lo.y + 2, hi.y - 2)), 0.12, 0.24, _pick(rng, ["plastic_red", "ball_orange"]), 6)


static func _cafeteria(k: LandmarkKit, lo: Vector2, hi: Vector2, fy: float, rng: RandomNumberGenerator) -> void:
	# Stage along the west wall with a curtain.
	k.block(Vector3(lo.x, fy, lo.y + 1.0), Vector3(lo.x + 5.0, fy + 0.9, hi.y - 1.0), "stage")
	k.ramp(Vector3(lo.x + 6.6, fy, hi.y - 2.0), Vector3(lo.x + 5.0, fy + 0.9, hi.y - 2.0), 1.4, 0.15, "stage")
	k.block(Vector3(lo.x + 5.0, fy + 0.9, lo.y + 1.0), Vector3(lo.x + 5.1, fy + 5.5, hi.y - 1.0), "curtain", false)
	# Rows of folding lunch tables with attached stools; some folded up, some tipped.
	for row in 4:
		for col in 3:
			var p := Vector2(lerpf(lo.x + 9.0, hi.x - 3.5, col / 2.0), lerpf(lo.y + 3.5, hi.y - 3.5, row / 3.0))
			var roll := rng.randf()
			if roll < 0.15:
				k.box(Vector3(p.x, fy + 0.9, p.y), Vector3(4.0, 1.8, 0.3), "table", 0.0, true)  # folded up
				continue
			var yaw := rng.randf_range(-0.6, 0.6) if roll < 0.3 else 0.0
			k.box(Vector3(p.x, fy + 0.36, p.y), Vector3(4.0, 0.06, 0.75), "table", yaw, false)
			k.box(Vector3(p.x, fy + 0.18, p.y), Vector3(3.6, 0.36, 0.3), "steel", yaw, true)
			for s: float in [-0.65, 0.65]:
				k.box(Vector3(p.x, fy + 0.22, p.y + s), Vector3(3.6, 0.05, 0.28), "plastic_blue", yaw, false)
			for j in 3:  # trays and cartons left behind
				k.box(Vector3(p.x + rng.randf_range(-1.6, 1.6), fy + 0.4, p.y + rng.randf_range(-0.2, 0.2)), Vector3(0.45, 0.02, 0.32), "plastic_yellow", rng.randf() * 0.6, false)
	# Hanging pennants.
	for i in 10:
		k.box(Vector3(lerpf(lo.x + 7, hi.x - 2, i / 9.0), fy + 5.8, (lo.y + hi.y) * 0.5), Vector3(0.5, 0.7, 0.01),
			_pick(rng, ["plastic_red", "plastic_blue", "paint_yellow", "plastic_green"]), 0.0, false)


static func _kitchen(k: LandmarkKit, lo: Vector2, hi: Vector2, fy: float) -> void:
	k.box(Vector3((lo.x + hi.x) * 0.5, fy + 0.01, (lo.y + hi.y) * 0.5), Vector3(hi.x - lo.x - 0.3, 0.02, hi.y - lo.y - 0.3), "tile", 0.0, false)
	# Serving line along the west wall (the window into the cafeteria), steel counters, ovens, walk-in cooler.
	k.block(Vector3(lo.x + 0.3, fy, lo.y + 5.0), Vector3(lo.x + 1.2, fy + 0.95, lo.y + 12.0), "steel")
	k.block(Vector3(lo.x + 3.0, fy, lo.y + 6.0), Vector3(lo.x + 4.0, fy + 0.9, lo.y + 13.0), "steel")
	k.block(Vector3(hi.x - 1.2, fy, lo.y + 1.0), Vector3(hi.x - 0.3, fy + 1.1, lo.y + 5.0), "steel")
	k.block(Vector3(hi.x - 3.4, fy, hi.y - 5.0), Vector3(hi.x - 0.3, fy + 2.6, hi.y - 0.3), "steel")
	k.block(Vector3(lo.x + 0.3, fy, hi.y - 3.0), Vector3(lo.x + 3.0, fy + 1.8, hi.y - 2.5), "shelf")


static func _office(k: LandmarkKit, lo: Vector2, hi: Vector2, fy: float, rng: RandomNumberGenerator) -> void:
	k.box(Vector3((lo.x + hi.x) * 0.5, fy + 0.01, (lo.y + hi.y) * 0.5), Vector3(hi.x - lo.x - 0.4, 0.02, hi.y - lo.y - 0.4), "carpet", 0.0, false)
	# Reception counter facing the lobby wall (east), desks, filing cabinets, a copier.
	k.block(Vector3(hi.x - 2.4, fy, lo.y + 2.0), Vector3(hi.x - 1.8, fy + 1.1, hi.y - 2.0), "table")
	for i in 3:
		var p := Vector2(lerpf(lo.x + 2.0, hi.x - 4.5, i / 2.0), lerpf(lo.y + 3.0, hi.y - 3.0, (i % 2) / 1.0))
		k.box(Vector3(p.x, fy + 0.38, p.y), Vector3(1.6, 0.76, 0.8), "desk", rng.randf_range(-0.2, 0.2))
	for i in 4:
		k.box(Vector3(lo.x + 0.5, fy + 0.7, lo.y + 1.2 + i * 0.6), Vector3(0.7, 1.4, 0.5), "steel")
	k.box(Vector3(lo.x + 1.0, fy + 0.55, hi.y - 1.0), Vector3(1.2, 1.1, 0.8), "steel")
	for i in 16:
		k.box(Vector3(rng.randf_range(lo.x + 0.5, hi.x - 0.5), fy + 0.03, rng.randf_range(lo.y + 0.5, hi.y - 0.5)), Vector3(0.25, 0.01, 0.32), "paper", rng.randf() * TAU, false)


static func _nurse(k: LandmarkKit, lo: Vector2, hi: Vector2, fy: float) -> void:
	k.box(Vector3((lo.x + hi.x) * 0.5, fy + 0.01, (lo.y + hi.y) * 0.5), Vector3(hi.x - lo.x - 0.3, 0.02, hi.y - lo.y - 0.3), "tile", 0.0, false)
	for i in 2:
		k.box(Vector3(lo.x + 1.0 + i * 1.6, fy + 0.35, hi.y - 1.2), Vector3(0.8, 0.7, 1.9), "porcelain")
	k.box(Vector3(hi.x - 0.4, fy + 1.4, lo.y + 1.4), Vector3(0.5, 0.05, 0.4), "plastic_red", 0.0, false)  # red cross box


static func _conference(k: LandmarkKit, lo: Vector2, hi: Vector2, fy: float) -> void:
	var c := (lo + hi) * 0.5
	k.box(Vector3(c.x, fy + 0.01, c.y), Vector3(hi.x - lo.x - 0.4, 0.02, hi.y - lo.y - 0.4), "carpet", 0.0, false)
	k.box(Vector3(c.x, fy + 0.38, c.y), Vector3(4.0, 0.76, 1.4), "desk")
	for i in 6:
		k.box(Vector3(c.x - 1.6 + (i % 3) * 1.6, fy + 0.25, c.y + (1.1 if i < 3 else -1.1)), Vector3(0.5, 0.5, 0.5), "plastic_blue", 0.0, false)


static func _sensory(k: LandmarkKit, lo: Vector2, hi: Vector2, fy: float, rng: RandomNumberGenerator) -> void:
	k.box(Vector3((lo.x + hi.x) * 0.5, fy + 0.05, (lo.y + hi.y) * 0.5), Vector3(hi.x - lo.x - 0.4, 0.1, hi.y - lo.y - 0.4), "mat", 0.0, false)
	for side: String in ["n", "s", "e"]:  # padded walls
		var p := _wall_point(lo, hi, side, 0.15)
		k.box(Vector3(p.x, fy + 1.0, p.y), Vector3(hi.x - lo.x - 0.4, 1.8, 0.1) if side != "e" else Vector3(0.1, 1.8, hi.y - lo.y - 0.4), "mat", 0.0, false)
	for i in 4:  # bean bags
		k.box(Vector3(rng.randf_range(lo.x + 1, hi.x - 1), fy + 0.3, rng.randf_range(lo.y + 1, hi.y - 1)), Vector3(0.9, 0.5, 0.9),
			_pick(rng, ["plastic_red", "plastic_green"]), rng.randf() * TAU, false)


static func _corridor(k: LandmarkKit, lo: Vector2, hi: Vector2, fy: float, rng: RandomNumberGenerator) -> void:
	var along_x := (hi.x - lo.x) > (hi.y - lo.y)
	var length := (hi.x - lo.x) if along_x else (hi.y - lo.y)
	var n := int(length / 7.0)
	for i in n:
		var t := (i + 0.5) / n
		for side: float in [-1.0, 1.0]:
			if rng.randf() < 0.45:
				continue
			var p := Vector2(lerpf(lo.x, hi.x, t), lo.y + 0.1 if side < 0 else hi.y - 0.1) if along_x else Vector2(lo.x + 0.1 if side < 0 else hi.x - 0.1, lerpf(lo.y, hi.y, t))
			# Bulletin board with paper cut-outs.
			k.box(Vector3(p.x, fy + 1.6, p.y), Vector3(2.4, 1.0, 0.04) if along_x else Vector3(0.04, 1.0, 2.4), "corkboard", 0.0, false)
			for j in 4:
				var o := rng.randf_range(-1.0, 1.0)
				var q := p + (Vector2(o, side * -0.02) if along_x else Vector2(side * -0.02, o))
				k.box(Vector3(q.x, fy + 1.6 + rng.randf_range(-0.3, 0.3), q.y), Vector3(0.3, 0.3, 0.01) if along_x else Vector3(0.01, 0.3, 0.3),
					_pick(rng, ["paper", "paint_yellow", "plastic_red", "plastic_blue"]), 0.0, false)
	for i in int(length / 5.0):  # dropped backpacks
		if rng.randf() < 0.35:
			var p := Vector2(rng.randf_range(lo.x + 0.4, hi.x - 0.4), rng.randf_range(lo.y + 0.4, hi.y - 0.4))
			k.box(Vector3(p.x, fy + 0.12, p.y), Vector3(0.35, 0.22, 0.28), _pick(rng, ["plastic_red", "plastic_blue", "plastic_green"]), rng.randf() * TAU, false)


static func _lobby(k: LandmarkKit, lo: Vector2, hi: Vector2, fy: float, rng: RandomNumberGenerator) -> void:
	var c := (lo + hi) * 0.5
	k.box(Vector3(c.x, fy + 0.01, c.y), Vector3(3.0, 0.02, 2.0), "rug_red", 0.0, false)
	k.box(Vector3(hi.x - 0.4, fy + 0.5, c.y), Vector3(0.5, 1.0, 1.6), "shelf")  # display case
	for i in 2:
		k.box(Vector3(lo.x + 1.0, fy + 0.25, c.y - 1.5 + i * 3.0), Vector3(0.6, 0.5, 1.6), "desk", 0.0, true)


static func _books(k: LandmarkKit, p: Vector2, side: String, ln: float, y: float, rng: RandomNumberGenerator) -> void:
	for i in int(ln / 0.6):
		if rng.randf() < 0.3:
			continue
		var o := -ln * 0.5 + (i + 0.5) * 0.6
		var q := p + (Vector2(o, 0) if side == "n" or side == "s" else Vector2(0, o))
		k.box(Vector3(q.x, y + 0.14, q.y), Vector3(0.5, 0.28, 0.22) if side == "n" or side == "s" else Vector3(0.22, 0.28, 0.5), "book", 0.0, false)


static func _board_papers(k: LandmarkKit, lo: Vector2, hi: Vector2, fy: float, side: String, rng: RandomNumberGenerator) -> void:
	var p := _wall_point(lo, hi, side, 0.1)
	var along_x := side == "n" or side == "s"
	k.box(Vector3(p.x, fy + 1.7, p.y), Vector3(3.0, 1.0, 0.04) if along_x else Vector3(0.04, 1.0, 3.0), "corkboard", 0.0, false)
	for j in 6:
		var o := rng.randf_range(-1.3, 1.3)
		var q := p + (Vector2(o, 0) if along_x else Vector2(0, o))
		k.box(Vector3(q.x, fy + 1.7 + rng.randf_range(-0.35, 0.35), q.y), Vector3(0.28, 0.32, 0.05) if along_x else Vector3(0.05, 0.32, 0.28),
			_pick(rng, ["paper", "paint_yellow", "plastic_green"]), 0.0, false)


static func _litter(k: LandmarkKit, lo: Vector2, hi: Vector2, fy: float, rng: RandomNumberGenerator, per_m2: float) -> void:
	var n := int((hi.x - lo.x) * (hi.y - lo.y) * per_m2)
	for i in n:
		var p := Vector3(rng.randf_range(lo.x + 0.5, hi.x - 0.5), fy + 0.02, rng.randf_range(lo.y + 0.5, hi.y - 0.5))
		k.box(p, Vector3(rng.randf_range(0.2, 0.7), 0.01, rng.randf_range(0.2, 0.6)), "blood" if rng.randf() < 0.15 else "paper", rng.randf() * TAU, false)


# Point on the inside of a room wall (n = low z, s = high z, w = low x, e = high x), `inset` from it.
static func _wall_point(lo: Vector2, hi: Vector2, side: String, inset: float) -> Vector2:
	var c := (lo + hi) * 0.5
	match side:
		"n": return Vector2(c.x, lo.y + inset)
		"s": return Vector2(c.x, hi.y - inset)
		"w": return Vector2(lo.x + inset, c.y)
		_: return Vector2(hi.x - inset, c.y)


static func _opposite(side: String) -> String:
	return {"n": "s", "s": "n", "w": "e", "e": "w"}[side]


static func _side_wall(side: String) -> String:
	return {"n": "w", "s": "e", "w": "s", "e": "n"}[side]


static func _pick(rng: RandomNumberGenerator, from: Array) -> String:
	return str(from[rng.randi_range(0, from.size() - 1)])
