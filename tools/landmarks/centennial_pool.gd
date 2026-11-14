# CentennialPool — builds the drained Centennial Park pool (D-078) into a LandmarkKit from
# data/landmarks/centennial_pool.json. Local frame = map axes (x east, z south), y up, y 0 = the landmark's flattened
# ground. Basin: a floor grid sunk below the deck by depth(x, z) (zero-depth beach in the SW corner, 3 ft shallow
# end to the 6 ft deep end in the north), vertical walls, coping, drop line, sprays, ladders; the terrain under it is
# cut by landmarks.json "ground_holes". Then the concrete deck, the bathhouse (locker rooms, guard room, concession),
# the chain-link fence, deck furniture, drained-pool mess (leaves, puddle, floaties, junk), signs, lights, loot
# containers and lair spawn markers (Marker3D, group "lair_spawns", meta "enemy").
# Depends on: LandmarkKit, scenes/loot_container.tscn.
extends RefCounted

const LOOT := preload("res://scenes/loot_container.tscn")


static func build(k: LandmarkKit, d: Dictionary, rng: RandomNumberGenerator) -> void:
	_basin(k, d)
	_sprays(k, d)
	_deck(k, d)
	_bathhouse(k, d)
	_fence(k, d)
	_furniture(k, d)
	_mess(k, d, rng)
	_place(k, d)


# Water depth (m) below the deck top at x, z: the depth profile along z, faded to 0 across the beach.
static func depth(d: Dictionary, x: float, z: float) -> float:
	var prof: Array = d.basin.depth_profile
	var dep := float(prof[0][1])
	for i in range(1, prof.size()):
		if z <= float(prof[i][0]):
			var t := inverse_lerp(float(prof[i - 1][0]), float(prof[i][0]), z)
			dep = lerpf(float(prof[i - 1][1]), float(prof[i][1]), clampf(t, 0.0, 1.0))
			break
		dep = float(prof[i][1])
	var be: Dictionary = d.basin.beach
	var c: Array = be.centre
	if x < float(c[0]) and z > float(c[1]):
		var rho := Vector2((x - float(c[0])) / float(be.rx), (z - float(c[1])) / float(be.rz)).length()
		dep *= clampf((1.0 - rho) / float(be.ramp), 0.0, 1.0)
	return dep


static func floor_y(d: Dictionary, x: float, z: float) -> float:
	return float(d.dims.deck_y) - depth(d, x, z)


# --- basin ---------------------------------------------------------------------------------------

static func _basin(k: LandmarkKit, d: Dictionary) -> void:
	var r: Array = d.basin.rect
	var top := float(d.dims.deck_y)
	var step := float(d.basin.step_m)
	var nx := roundi((float(r[2]) - float(r[0])) / step)
	var nz := roundi((float(r[3]) - float(r[1])) / step)
	var faces := PackedVector3Array()
	for iz in nz:
		for ix in nx:
			var x0 := float(r[0]) + ix * step
			var z0 := float(r[1]) + iz * step
			var p := [Vector3(x0, 0, z0), Vector3(x0 + step, 0, z0), Vector3(x0 + step, 0, z0 + step), Vector3(x0, 0, z0 + step)]
			var dry := true
			for i in 4:
				p[i].y = floor_y(d, p[i].x, p[i].z)
				dry = dry and p[i].y > top - 0.005
			k.quad(p[0], p[1], p[2], p[3], "deck" if dry else "pool_floor")
			faces.append_array(PackedVector3Array([p[0], p[1], p[2], p[0], p[2], p[3]]))
	# Walls round the rect wherever there is depth, with the coping strip on the deck above them.
	var corners := [Vector2(r[0], r[1]), Vector2(r[2], r[1]), Vector2(r[2], r[3]), Vector2(r[0], r[3])]
	var cw := float(d.dims.coping_m)
	for e in 4:
		var a: Vector2 = corners[e]
		var b: Vector2 = corners[(e + 1) % 4]
		var n := roundi(a.distance_to(b) / step)
		var out := (a + b) * 0.5 - (Vector2(r[0] + r[2], r[1] + r[3]) * 0.5)
		out = Vector2(signf(out.x) if absf(out.x) > absf(out.y) else 0.0, signf(out.y) if absf(out.y) >= absf(out.x) else 0.0)
		var run_start := -1
		for i in n + 1:
			var wet := false
			if i < n:
				var p0 := a.lerp(b, float(i) / n)
				var p1 := a.lerp(b, float(i + 1) / n)
				var y0 := floor_y(d, p0.x, p0.y)
				var y1 := floor_y(d, p1.x, p1.y)
				wet = y0 < top - 0.005 or y1 < top - 0.005
				if wet:
					var q := [Vector3(p0.x, top, p0.y), Vector3(p1.x, top, p1.y), Vector3(p1.x, y1, p1.y), Vector3(p0.x, y0, p0.y)]
					k.quad(q[0], q[1], q[2], q[3], "pool_wall")
					faces.append_array(PackedVector3Array([q[0], q[1], q[2], q[0], q[2], q[3]]))
			if wet and run_start < 0:
				run_start = i
			elif not wet and run_start >= 0:
				var c0 := a.lerp(b, float(run_start) / n)
				var c1 := a.lerp(b, float(i) / n)
				var lo := c0.min(c1) + Vector2(minf(out.x, 0.0), minf(out.y, 0.0)) * cw
				var hi := c0.max(c1) + Vector2(maxf(out.x, 0.0), maxf(out.y, 0.0)) * cw
				k.block(Vector3(lo.x, top, lo.y), Vector3(hi.x, top + 0.02, hi.y), "coping", false)
				run_start = -1
	k.trimesh(faces)
	# Drop line where the floor starts falling to the deep end, and the dark tile lane line down the middle.
	var dz := float(d.basin.drop_line_z)
	var lx0 := float(r[0]) + 0.3
	var lx1 := float(r[2]) - 0.3
	k.quad(Vector3(lx0, floor_y(d, lx0, dz - 0.15) + 0.01, dz - 0.15), Vector3(lx1, floor_y(d, lx1, dz - 0.15) + 0.01, dz - 0.15),
		Vector3(lx1, floor_y(d, lx1, dz + 0.15) + 0.01, dz + 0.15), Vector3(lx0, floor_y(d, lx0, dz + 0.15) + 0.01, dz + 0.15), "tile_line")
	for dr: Array in d.basin.drains:
		k.disc(Vector3(dr[0], floor_y(d, dr[0], dr[1]) + 0.012, dr[1]), 0.3, "drain", 8)
	for l: Array in d.basin.ladders:  # [x, z at the wall, side: +1 = ladder into +z]
		_ladder(k, d, Vector2(l[0], l[1]), float(l[2]))


static func _ladder(k: LandmarkKit, d: Dictionary, at: Vector2, side: float) -> void:
	var top := float(d.dims.deck_y)
	var fy := floor_y(d, at.x, at.y + side * 0.4)
	for sx: float in [-0.3, 0.3]:
		var x := at.x + sx
		k.cylinder(Vector3(x, fy, at.y + side * 0.18), 0.03, top + 0.85 - fy, "chrome", 6)
		k.box(Vector3(x, top + 0.85, at.y - side * 0.12), Vector3(0.06, 0.06, 0.6), "chrome", 0.0, false)
		k.cylinder(Vector3(x, top, at.y - side * 0.4), 0.03, 0.85, "chrome", 6)
	var y := top - 0.35
	while y > fy + 0.2:
		k.box(Vector3(at.x, y, at.y + side * 0.18), Vector3(0.6, 0.04, 0.12), "chrome", 0.0, false)
		y -= 0.3


# --- sprays ---------------------------------------------------------------------------------------

static func _sprays(k: LandmarkKit, d: Dictionary) -> void:
	for m: Dictionary in d.sprays.mushrooms:
		var p: Array = m.pos
		var base := floor_y(d, p[0], p[1])
		var h := float(m.height)
		k.cylinder(Vector3(p[0], base, p[1]), 0.22, h, "spray_stem", 10, true)
		var r := float(m.radius)
		k.sweep(Vector3(p[0], base + h, p[1]), PackedVector2Array([Vector2(0.0, 0.5), Vector2(r * 0.55, 0.35), Vector2(r, 0.0)]),
			0.0, TAU, 16, "spray_cap", "spray_cap")
	for s: Array in d.sprays.arches:  # [x, z, yaw_deg]: a little hooped spray pipe
		var base := floor_y(d, s[0], s[1])
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(s[2])), Vector3(s[0], base, s[1]))
		for sx: float in [-0.5, 0.5]:
			k.box_xf(xf.translated_local(Vector3(sx, 0.75, 0)), Vector3(0.12, 1.5, 0.12), "spray_stem", sx < 0.0)
		k.box_xf(xf.translated_local(Vector3(0, 1.5, 0)), Vector3(1.12, 0.12, 0.12), "spray_stem", false)
		k.box_xf(xf.translated_local(Vector3(0, 1.42, 0)), Vector3(0.2, 0.1, 0.2), "spray_cap", false)


# --- deck -----------------------------------------------------------------------------------------

static func _deck(k: LandmarkKit, d: Dictionary) -> void:
	var top := float(d.dims.deck_y)
	var dr: Array = d.deck.rect
	var b: Array = d.basin.rect
	k.block(Vector3(dr[0], -0.3, dr[1]), Vector3(dr[2], top, b[1]), "deck")
	k.block(Vector3(dr[0], -0.3, b[3]), Vector3(dr[2], top, dr[3]), "deck")
	k.block(Vector3(dr[0], -0.3, b[1]), Vector3(b[0], top, b[3]), "deck")
	k.block(Vector3(b[2], -0.3, b[1]), Vector3(dr[2], top, b[3]), "deck")
	for t: Array in d.deck.text:  # painted depth markers / NO DIVING on the deck: [text, x, z, yaw_deg, size]
		var l := Label3D.new()
		l.name = "Deck_" + str(t[0]).replace(" ", "_")
		l.text = str(t[0])
		l.font_size = int(t[4])
		l.pixel_size = 0.01
		l.modulate = Color(0.08, 0.12, 0.3)
		l.shaded = true
		l.position = Vector3(t[1], top + 0.012, t[2])
		l.rotation = Vector3(deg_to_rad(-90.0), deg_to_rad(float(t[3])), 0.0)
		l.visibility_range_end = 40.0
		k.root.add_child(l)


# --- bathhouse ------------------------------------------------------------------------------------

static func _bathhouse(k: LandmarkKit, d: Dictionary) -> void:
	var bh: Dictionary = d.bathhouse
	var r: Array = bh.rect
	var fy := float(d.dims.deck_y)
	var t := float(bh.wall_m)
	var h := float(bh.height)
	k.block(Vector3(r[0], -0.3, r[1]), Vector3(r[2], fy, r[3]), "tile")
	k.block(Vector3(r[0] - 0.3, h, r[1] - 0.3), Vector3(r[2] + 0.3, h + 0.2, r[3] + 0.3), "roof")
	k.block(Vector3(r[0] + t, h - 0.05, r[1] + t), Vector3(r[2] - t, h, r[3] - t), "ceiling", false)
	var c := [Vector2(r[0], r[1]), Vector2(r[2], r[1]), Vector2(r[2], r[3]), Vector2(r[0], r[3])]
	var edge := {"n": [c[0], c[1]], "e": [c[1], c[2]], "s": [c[3], c[2]], "w": [c[0], c[3]]}  # door "at" is from the first point
	for e: String in edge:
		var a: Vector2 = edge[e][0]
		var b: Vector2 = edge[e][1]
		var inward := (Vector2(r[0] + r[2], r[1] + r[3]) * 0.5 - (a + b) * 0.5).normalized()
		inward = Vector2(signf(inward.x), 0.0) if e == "e" or e == "w" else Vector2(0.0, signf(inward.y))
		var o := inward * t * 0.5
		_wall(k, a + o, b + o, t, h, float(bh.door_h), "block_wall", bh.doors.get(e, []), t * 0.5)
		k.box_xf(Transform3D(Basis(Vector3.UP, atan2((b - a).x, (b - a).y)), Vector3((a.x + b.x) * 0.5, h - 0.25, (a.y + b.y) * 0.5) - Vector3(inward.x, 0, inward.y) * 0.02),
			Vector3(0.05, 0.5, a.distance_to(b) + t), "trim", false)
	for w: Dictionary in bh.walls:
		_wall(k, Vector2(w.a[0], w.a[1]), Vector2(w.b[0], w.b[1]), 0.15, h, float(bh.door_h), "block_wall", w.get("doors", []), 0.0)
	for s: Array in bh.stalls:  # [x0, z0, x1, z1, count, toilet side "x0"/"x1"]: a row of stalls along z
		var n := int(s[4])
		var dz := (float(s[3]) - float(s[1])) / n
		for i in n + 1:
			k.block(Vector3(s[0], fy + 0.15, float(s[1]) + i * dz - 0.02), Vector3(s[2], fy + 1.9, float(s[1]) + i * dz + 0.02), "stall", false)
		for i in n:
			var zc := float(s[1]) + (i + 0.5) * dz
			var tx := float(s[0]) + 0.35 if str(s[5]) == "x0" else float(s[2]) - 0.35
			k.box(Vector3(tx, fy + 0.22, zc), Vector3(0.6, 0.44, 0.42), "porcelain", 0.0, false)
	for l: Array in bh.lockers:  # [x0, z0, x1, z1]
		k.block(Vector3(l[0], fy, l[1]), Vector3(l[2], fy + 1.9, l[3]), "locker")
	for b: Array in bh.benches:  # [x, z, length along z]
		k.box(Vector3(b[0], fy + 0.22, b[1]), Vector3(0.35, 0.44, b[2]), "bench")
	for s: Array in bh.showers:  # [x, z]: head + pipe on a wall
		k.cylinder(Vector3(s[0], fy + 1.2, s[1]), 0.02, 1.0, "chrome", 6)
		k.box(Vector3(s[0], fy + 2.15, s[1]), Vector3(0.14, 0.06, 0.14), "chrome", 0.0, false)
	for s: Array in bh.sinks:  # [x, z, yaw_deg]
		k.box(Vector3(s[0], fy + 0.8, s[1]), Vector3(0.55, 0.15, 0.45), "porcelain", deg_to_rad(s[2]), false)
	for b: Array in bh.counters:  # [x0, z0, x1, z1]
		k.block(Vector3(b[0], fy, b[1]), Vector3(b[2], fy + 0.95, b[3]), "counter")


static func _wall(k: LandmarkKit, a: Vector2, b: Vector2, t: float, top: float, door_h: float, mat: String,
		gaps: Array, extend: float) -> void:
	var dir := (b - a).normalized()
	var length := (b - a).length()
	var cuts: Array = []
	for g in gaps:
		cuts.append([float(g[0]) - float(g[1]), float(g[0]) + float(g[1]), float(g[2]) if g.size() > 2 else 0.0,
			float(g[3]) if g.size() > 3 else door_h])
	cuts.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	var at := -extend
	for c: Array in cuts:
		if c[0] > at:
			_seg(k, a, dir, at, c[0], -0.3, top, t, mat)
		if c[2] > 0.0:  # window-style opening: wall below the sill
			_seg(k, a, dir, c[0], c[1], -0.3, c[2], t, mat)
		_seg(k, a, dir, c[0], c[1], c[3], top, t, mat)
		at = c[1]
	if length + extend > at:
		_seg(k, a, dir, at, length + extend, -0.3, top, t, mat)


static func _seg(k: LandmarkKit, a: Vector2, dir: Vector2, s0: float, s1: float, y0: float, y1: float, t: float,
		mat: String) -> void:
	if s1 - s0 < 0.01 or y1 - y0 < 0.01:
		return
	var mid := a + dir * (s0 + s1) * 0.5
	var xf := Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.y)), Vector3(mid.x, (y0 + y1) * 0.5, mid.y))
	k.box_xf(xf, Vector3(t, y1 - y0, s1 - s0), mat)


# --- fence ----------------------------------------------------------------------------------------

static func _fence(k: LandmarkKit, d: Dictionary) -> void:
	var h := float(d.fence.height)
	for line: Array in d.fence.lines:
		var pts := PackedVector3Array()
		for p: Array in line:
			pts.append(Vector3(p[0], 0.0, p[1]))
		k.railing(pts, h, "fence_post", 3.0, true)
		for i in range(pts.size() - 1):
			k.quad(pts[i] + Vector3.UP * 0.05, pts[i + 1] + Vector3.UP * 0.05, pts[i + 1] + Vector3.UP * h, pts[i] + Vector3.UP * h, "chainlink")
	var g: Dictionary = d.fence.gate  # hanging open: frame + mesh panel swung out from the hinge post
	var hinge := Vector3(g.hinge[0], 0.0, g.hinge[1])
	var dir := Vector3(sin(deg_to_rad(g.yaw_deg)), 0.0, cos(deg_to_rad(g.yaw_deg)))
	var tip := hinge + dir * float(g.width)
	k.railing(PackedVector3Array([hinge, tip]), h - 0.1, "fence_post", 3.0, false)
	k.quad(hinge + Vector3.UP * 0.1, tip + Vector3.UP * 0.1, tip + Vector3.UP * (h - 0.1), hinge + Vector3.UP * (h - 0.1), "chainlink")


# --- deck furniture -------------------------------------------------------------------------------

static func _furniture(k: LandmarkKit, d: Dictionary) -> void:
	var top := float(d.dims.deck_y)
	var f: Dictionary = d.furniture
	for c: Array in f.loungers:  # [x, z, yaw_deg]
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(c[2])), Vector3(c[0], top, c[1]))
		k.box_xf(xf.translated_local(Vector3(0, 0.3, 0.25)), Vector3(0.65, 0.08, 1.4), "lounger", false)
		k.box_xf(Transform3D(xf.basis * Basis(Vector3.RIGHT, deg_to_rad(-50.0)), xf * Vector3(0, 0.55, -0.6)), Vector3(0.65, 0.08, 0.7), "lounger", false)
		k.box_xf(xf.translated_local(Vector3(0, 0.15, 0)), Vector3(0.6, 0.3, 1.8), "", true)
	for u: Array in f.umbrellas:  # [x, z]: table + umbrella
		k.cylinder(Vector3(u[0], 0.0, u[1]), 0.45, 0.72, "lounger", 10, true)
		k.cylinder(Vector3(u[0], 0.72, u[1]), 0.03, 1.6, "fence_post", 6)
		k.sweep(Vector3(u[0], 2.0, u[1]), PackedVector2Array([Vector2(0.0, 0.4), Vector2(1.4, 0.0)]), 0.0, TAU, 8, "canvas", "canvas")
	var g: Array = f.guard_chair  # [x, z, yaw_deg]: tall lifeguard stand facing the pool
	var gx := Transform3D(Basis(Vector3.UP, deg_to_rad(g[2])), Vector3(g[0], top, g[1]))
	for lx: float in [-0.45, 0.45]:
		for lz: float in [-0.3, 0.6]:
			k.box_xf(gx.translated_local(Vector3(lx, 0.95, lz)), Vector3(0.08, 1.9, 0.08), "lifeguard", lx < 0.0 and lz < 0.0)
	k.box_xf(gx.translated_local(Vector3(0, 1.9, 0)), Vector3(1.0, 0.08, 0.7), "lifeguard", true)
	k.box_xf(gx.translated_local(Vector3(0, 2.35, 0.33)), Vector3(1.0, 0.8, 0.06), "lifeguard", false)
	for i in 5:
		k.box_xf(gx.translated_local(Vector3(0, 0.35 * (i + 1), 0.62)), Vector3(0.82, 0.04, 0.08), "lifeguard", false)
	k.cylinder(gx * Vector3(0.4, 1.9, 0.3), 0.025, 1.6, "fence_post", 6)
	k.sweep(gx * Vector3(0.4, 3.3, 0.3), PackedVector2Array([Vector2(0.0, 0.35), Vector2(1.0, 0.0)]), 0.0, TAU, 8, "rescue_red", "rescue_red")
	var hp: Array = f.hoop  # [x, z, yaw_deg]: poolside basketball hoop leaning out over the shallow end
	var hx := Transform3D(Basis(Vector3.UP, deg_to_rad(hp[2])), Vector3(hp[0], top, hp[1]))
	k.box_xf(hx.translated_local(Vector3(0, 0.6, 0)), Vector3(0.12, 1.2, 0.12), "lounger", true)
	k.box_xf(hx.translated_local(Vector3(0, 1.45, -0.05)), Vector3(0.9, 0.6, 0.04), "lounger", false)
	for i in 8:
		var a := TAU * i / 8.0
		k.box_xf(Transform3D(hx.basis * Basis(Vector3.UP, a), hx * Vector3(0.23 * cos(a), 1.25, -0.3 + 0.23 * sin(a))),
			Vector3(0.03, 0.03, 0.19), "rescue_red", false)
	for c: Array in f.trash_cans:  # [x, z]
		k.cylinder(Vector3(c[0], 0.0, c[1]), 0.3, 0.95, "fence_post", 8, true)


# --- drained-pool mess ----------------------------------------------------------------------------

static func _mess(k: LandmarkKit, d: Dictionary, rng: RandomNumberGenerator) -> void:
	var m: Dictionary = d.mess
	var r: Array = d.basin.rect
	for p: Array in m.puddles:  # [x, z, radius]
		k.disc(Vector3(p[0], floor_y(d, p[0], p[1]) + 0.008, p[1]), float(p[2]), "puddle", 14)
	# Leaves: blown into the deep end and the corners; a few drifted piles.
	for i in int(m.leaves):
		var x := lerpf(float(r[0]) + 0.2, float(r[2]) - 0.2, rng.randf())
		var z := lerpf(float(r[1]) + 0.2, float(r[3]) - 0.2, pow(rng.randf(), float(m.leaf_bias)))
		var y := floor_y(d, x, z) + 0.006 + rng.randf() * 0.01
		var a := rng.randf() * TAU
		var s := rng.randf_range(0.1, 0.22)
		k.tri(Vector3(x, y, z), Vector3(x + cos(a) * s, y, z + sin(a) * s), Vector3(x + cos(a + 0.9) * s, y + 0.01, z + sin(a + 0.9) * s),
			"leaves" if i % 3 else "leaves_dark")
	for p: Array in m.leaf_piles:  # [x, z, radius]
		k.sweep(Vector3(p[0], floor_y(d, p[0], p[1]), p[1]), PackedVector2Array([Vector2(0.0, 0.3), Vector2(float(p[2]) * 0.6, 0.18), Vector2(p[2], 0.0)]),
			0.0, TAU, 10, "leaves_dark", "leaves_dark")
	for f: Dictionary in m.floaties:  # deflated star / manta lying crumpled on the floor
		_floatie(k, d, f, rng)
	for j: Dictionary in m.junk:  # {type, pos [x, z], yaw_deg}
		var p: Array = j.pos
		var fy := floor_y(d, p[0], p[1])
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(j.get("yaw_deg", 0.0)))), Vector3(p[0], fy, p[1]))
		match str(j.type):
			"lounger_flipped":  # upside down: legs up
				k.box_xf(xf.translated_local(Vector3(0, 0.04, 0)), Vector3(0.65, 0.08, 1.9), "lounger", true)
				for lz: float in [-0.8, 0.8]:
					k.box_xf(xf.translated_local(Vector3(0, 0.22, lz)), Vector3(0.6, 0.3, 0.05), "lounger", false)
			"cone":
				k.sweep(xf.origin, PackedVector2Array([Vector2(0.0, 0.7), Vector2(0.17, 0.0)]), 0.0, TAU, 8, "rescue_red", "rescue_red")
			"rescue_tube":
				k.box_xf(xf.translated_local(Vector3(0, 0.06, 0)), Vector3(0.15, 0.12, 1.0), "rescue_red", false)
			"kickboard":
				k.box_xf(xf.translated_local(Vector3(0, 0.02, 0)), Vector3(0.3, 0.04, 0.45), "floatie_purple", false)
			"trash_can":  # on its side
				k.box_xf(xf.translated_local(Vector3(0, 0.3, 0)), Vector3(0.6, 0.6, 0.95), "fence_post", true)
			"umbrella_down":
				k.box_xf(xf.translated_local(Vector3(0, 0.05, 0)), Vector3(0.06, 0.06, 2.3), "fence_post", false)
				k.sweep(xf * Vector3(0, 0.05, 1.2), PackedVector2Array([Vector2(0.0, 0.25), Vector2(1.0, 0.0)]), 0.0, TAU, 8, "canvas", "canvas")


static func _floatie(k: LandmarkKit, d: Dictionary, f: Dictionary, rng: RandomNumberGenerator) -> void:
	var p: Array = f.pos
	var s := float(f.size)
	var yaw := deg_to_rad(float(f.get("yaw_deg", 0.0)))
	var outline := PackedVector2Array()
	if str(f.shape) == "star":
		for i in 10:
			var a := TAU * i / 10.0
			outline.append(Vector2(cos(a), sin(a)) * (s if i % 2 == 0 else s * 0.42))
	else:  # manta: nose, wing tips, tail notch
		outline = PackedVector2Array([Vector2(0, -0.55), Vector2(0.35, -0.35), Vector2(1.0, 0.1), Vector2(0.3, 0.3),
			Vector2(0.06, 0.45), Vector2(0.02, 1.4), Vector2(-0.02, 1.4), Vector2(-0.06, 0.45), Vector2(-0.3, 0.3),
			Vector2(-1.0, 0.1), Vector2(-0.35, -0.35)])
		for i in outline.size():
			outline[i] *= s
	var mat := str(f.mat)
	var c := Vector2(p[0], p[1])
	var top := Vector3(c.x, floor_y(d, c.x, c.y) + 0.1, c.y)
	var rim: Array[Vector3] = []
	for o in outline:
		var w := c + o.rotated(-yaw)
		rim.append(Vector3(w.x, floor_y(d, w.x, w.y) + rng.randf_range(0.01, 0.06), w.y))
	for i in rim.size():
		k.tri(top, rim[i], rim[(i + 1) % rim.size()], mat)


# --- signs, lights, loot, spawns ---------------------------------------------------------------------

static func _place(k: LandmarkKit, d: Dictionary) -> void:
	var fy := float(d.dims.deck_y)
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
		l.visibility_range_end = float(s.get("visible_m", 60.0))
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
		light.distance_fade_begin = 45.0
		light.distance_fade_length = 15.0
		k.root.add_child(light)
		i += 1
	for l: Dictionary in d.loot:
		var p: Array = l.pos
		var sz: Array = l.size
		var col: Array = l.get("color", [0.35, 0.36, 0.4])
		k.place(LOOT, Transform3D(Basis(Vector3.UP, deg_to_rad(float(l.get("yaw_deg", 0.0)))), Vector3(p[0], fy + float(sz[1]) * 0.5, p[1])),
			{"container_id": "centennial_pool_" + str(l.id), "display_name": str(l.name), "loot_table": str(l.table),
			"size": Vector3(sz[0], sz[1], sz[2]), "color": Color(col[0], col[1], col[2])}, "Loot_" + str(l.id))
	for s: Array in d.spawns:
		var mk := Marker3D.new()
		mk.name = "centennial_pool_" + str(s[0])
		var xz: Array = s[2]
		mk.position = Vector3(xz[0], floor_y(d, xz[0], xz[1]) + 0.05, xz[1])
		mk.set_meta("enemy", str(s[1]))
		mk.add_to_group("lair_spawns", true)
		k.root.add_child(mk)
