# ChillersHq — builds the Chillers' HQ in the Nebraskan Student Union at UNK into a LandmarkKit (D-053): a two-storey
# brick block with window strips and a flat roof, north + south doors, and a walkable ground floor: the lounge
# (couches, rugs, tapestries, string lights, fire barrel, dining counters + bookstore along the north wall), the
# grow room in the old ballroom (east: soil beds of plants under glowing grow lights) and Meekachu's throne room
# (west: dais, beanbag throne, snack machine). Outside on the south lawn: the campus camp (tents, bonfire, logs, the
# van) and the CHILLERS signs. Loot containers and the Chillers (ResidentNpc) come from the data file.
# Origin = middle of the main block on the ground, x east, z south. Depends on: LandmarkKit, scenes/loot_container.tscn,
# scenes/resident_npc.tscn.
extends RefCounted

const LOOT := preload("res://scenes/loot_container.tscn")
const NPC := preload("res://scenes/resident_npc.tscn")


static func build(k: LandmarkKit, d: Dictionary, palettes: Dictionary, rng: RandomNumberGenerator) -> void:
	var b: Dictionary = d.building
	_shell(k, b)
	_lounge(k, b, rng)
	_grow_room(k, b, palettes.weed, rng)
	_throne_room(k, b)
	_camp(k, d.camp, rng)
	for s: Dictionary in d.signs:
		var p: Array = s.pos
		var l := Label3D.new()
		l.name = "Sign_%d" % k.root.get_child_count()
		l.text = str(s.text)
		l.font_size = int(s.size)
		l.pixel_size = 0.01
		l.outline_size = 12
		l.modulate = Color(0.95, 0.85, 0.4)
		l.shaded = true
		l.double_sided = false
		l.position = Vector3(p[0], p[1], p[2])
		l.visibility_range_end = 300.0
		k.root.add_child(l)
	var i := 0
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
		light.distance_fade_begin = 60.0
		light.distance_fade_length = 20.0
		k.root.add_child(light)
		i += 1
	for l: Dictionary in d.loot:
		var p: Array = l.pos
		var sz: Array = l.size
		k.place(LOOT, Transform3D(Basis(), Vector3(p[0], p[1], p[2])), {"container_id": "chillers_" + str(l.id),
			"display_name": str(l.name), "loot_table": str(l.table), "size": Vector3(sz[0], sz[1], sz[2]),
			"color": Color(0.4, 0.34, 0.28)}, "Loot_" + str(l.id))
	for n: Dictionary in d.npcs:
		var p: Array = n.pos
		k.place(NPC, Transform3D(Basis(Vector3.UP, deg_to_rad(float(n.yaw_deg))), Vector3(p[0], p[1], p[2])),
			{"npc_id": str(n.npc_id)}, str(n.name))


# --- building shell -----------------------------------------------------------------------------

static func _shell(k: LandmarkKit, b: Dictionary) -> void:
	var hx := float(b.half_x)
	var hz := float(b.half_z)
	var t := float(b.wall_m)
	var top := float(b.top_y)
	var ceil_y := float(b.ceiling_y)
	k.block(Vector3(-hx, -2.0, -hz), Vector3(hx, 0.05, hz), "floor")
	# South and north faces: window strips on both storeys, a door in the middle.
	for zs: float in [-1.0, 1.0]:
		var z0 := hz - t if zs > 0.0 else -hz
		_facade(k, b, z0, z0 + t, hx, t)
	# East and west faces: solid brick with upper windows.
	for xs: float in [-1.0, 1.0]:
		var x0 := hx - t if xs > 0.0 else -hx
		k.block(Vector3(x0, -2.0, -hz + t), Vector3(x0 + t, top, hz - t), "brick")
		k.block(Vector3(x0 + (t + 0.02 if xs > 0.0 else -0.02), 5.6, -hz + 3.0), Vector3(x0 + (t + 0.04 if xs > 0.0 else -0.04), 7.6, hz - 3.0), "glass", false)
	# Ceiling of the ground floor (upper storey isn't playable), roof slab and parapet.
	k.block(Vector3(-hx + t, ceil_y, -hz + t), Vector3(hx - t, ceil_y + 0.3, hz - t), "plaster")
	k.block(Vector3(-hx, top - 0.3, -hz), Vector3(hx, top, hz), "roof")
	for s: float in [-1.0, 1.0]:
		k.block(Vector3(-hx, top, s * hz - 0.2), Vector3(hx, top + 0.8, s * hz + 0.2), "concrete", false)
		k.block(Vector3(s * hx - 0.2, top, -hz), Vector3(s * hx + 0.2, top + 0.8, hz), "concrete", false)
	# Interior partitions: throne room (west) and grow room (east), a doorway in each.
	var dh := float(b.inner_door_half_m)
	for x: float in [float(b.throne_x), float(b.grow_x)]:
		k.block(Vector3(x - 0.15, 0.0, -hz + t), Vector3(x + 0.15, ceil_y, -dh), "plaster")
		k.block(Vector3(x - 0.15, 0.0, dh), Vector3(x + 0.15, ceil_y, hz - t), "plaster")
		k.block(Vector3(x - 0.15, float(b.door_h), -dh), Vector3(x + 0.15, ceil_y, dh), "plaster")


# One long facade (z0..z1 thick) with ground + upper window strips and a centre door.
static func _facade(k: LandmarkKit, b: Dictionary, z0: float, z1: float, hx: float, t: float) -> void:
	var top := float(b.top_y)
	var wlo := float(b.window_lo)
	var whi := float(b.window_hi)
	var dw := float(b.door_half_m)
	var dh := float(b.door_h)
	for side: float in [-1.0, 1.0]:
		var xa := minf(side * dw, side * hx)
		var xb := maxf(side * dw, side * hx)
		k.block(Vector3(xa, -2.0, z0), Vector3(xb, wlo, z1), "brick")
		k.block(Vector3(xa, whi, z0), Vector3(xb, 5.6, z1), "brick")
		k.block(Vector3(xa, 7.6, z0), Vector3(xb, top, z1), "brick")
		k.block(Vector3(xa, 5.6, z0 + 0.15), Vector3(xb, 7.6, z1 - 0.15), "glass")
		# Ground windows: glass with every third pane smashed out (boarded instead).
		var n := int((xb - xa) / 3.0)
		for i in n:
			var p0 := xa + i * (xb - xa) / n
			var p1 := xa + (i + 1) * (xb - xa) / n
			k.block(Vector3(p0, wlo, z0), Vector3(p0 + 0.25, whi, z1), "brick")
			if i % 3 == 1:
				for j in 3:
					k.box(Vector3((p0 + p1) * 0.5, wlo + 0.4 + j * 0.7, (z0 + z1) * 0.5), Vector3(p1 - p0, 0.25, t + 0.06), "wood", 0.06 * (j - 1))
			else:
				k.block(Vector3(p0 + 0.25, wlo, z0 + 0.15), Vector3(p1, whi, z1 - 0.15), "glass")
	k.block(Vector3(-dw, dh, z0), Vector3(dw, 5.6, z1), "brick")


# --- rooms -------------------------------------------------------------------------------------

static func _couch(k: LandmarkKit, c: Vector3, yaw: float, mat: String, length := 2.2) -> void:
	var bs := Basis(Vector3.UP, yaw)
	k.box_xf(Transform3D(bs, c + bs * Vector3(0, 0.22, 0)), Vector3(length, 0.44, 0.9), mat)
	k.box_xf(Transform3D(bs, c + bs * Vector3(0, 0.6, 0.38)), Vector3(length, 0.8, 0.22), mat, false)
	for s: float in [-1.0, 1.0]:
		k.box_xf(Transform3D(bs, c + bs * Vector3(s * (length * 0.5 - 0.1), 0.45, 0)), Vector3(0.2, 0.5, 0.9), mat, false)


static func _lounge(k: LandmarkKit, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var hz := float(b.half_z)
	# Couch circles around rugs + coffee tables.
	var mats := ["couch_a", "couch_b", "couch_c"]
	for c: Vector3 in [Vector3(-14, 0, 4), Vector3(0, 0, 8), Vector3(-6, 0, -6)]:
		k.block(c + Vector3(-3.5, 0.05, -2.5), c + Vector3(3.5, 0.07, 2.5), "rug" if int(c.x) % 2 == 0 else "rug_b", false)
		k.block(c + Vector3(-0.8, 0.0, -0.5), c + Vector3(0.8, 0.45, 0.5), "wood")
		_couch(k, c + Vector3(0, 0, 2.2), 0.0, mats[rng.randi() % 3])
		_couch(k, c + Vector3(0, 0, -2.2), PI, mats[rng.randi() % 3])
		_couch(k, c + Vector3(2.8, 0, 0), PI * 0.5, mats[rng.randi() % 3], 1.8)
	# Beanbags and a fire barrel in the middle.
	for i in 6:
		var p := Vector3(rng.randf_range(-22.0, 10.0), 0.0, rng.randf_range(12.0, 18.0))
		k.box(p + Vector3(0, 0.25, 0), Vector3(0.9, 0.5, 0.9), "beanbag", rng.randf() * TAU)
	k.cylinder(Vector3(-2, 0, 0), 0.35, 0.9, "rust", 10, true)
	k.disc(Vector3(-2, 0.88, 0), 0.32, "fire", 10)
	# North wall: dining counter + bookstore remains.
	k.block(Vector3(-24, 0, -18.4), Vector3(-6, 1.0, -17.4), "steel")
	for i in 5:
		k.cylinder(Vector3(-22 + i * 3.5, 0, -15.6), 0.04, 0.7, "steel", 6)
		k.disc(Vector3(-22 + i * 3.5, 0.7, -15.6), 0.22, "couch_a", 10)
	# Tapestries + string lights along the walls.
	for i in 5:
		k.block(Vector3(-24 + i * 8, 1.2, hz - 0.45), Vector3(-20 + i * 8, 3.8, hz - 0.43), "tapestry" if i % 2 == 0 else "tapestry_b", false)
	for z: float in [-hz + 0.5, hz - 0.5]:
		var x := -25.5
		while x < 13.5:
			k.box(Vector3(x, 4.1 - 0.25 * absf(sin(x * 0.6)), z), Vector3(0.08, 0.08, 0.08), "bulbs", 0.0, false)
			x += 0.8
	# Litter.
	for i in 40:
		var p := Vector3(rng.randf_range(-25.0, 13.0), 0.1, rng.randf_range(-19.0, 19.0))
		k.box(p, Vector3(rng.randf_range(0.1, 0.3), 0.04, rng.randf_range(0.1, 0.3)), "tapestry_b" if rng.randf() < 0.3 else "wood",
			rng.randf() * TAU, false)


static func _grow_room(k: LandmarkKit, b: Dictionary, pal: Array, rng: RandomNumberGenerator) -> void:
	var cols: Array = []
	for c: Array in pal:
		cols.append(Color(c[0], c[1], c[2]))
	var x0 := float(b.grow_x) + 2.0
	var x1 := float(b.half_x) - 3.0
	var z := -17.0
	while z <= 15.0:
		k.block(Vector3(x0, 0.0, z), Vector3(x1, 0.45, z + 1.4), "soil")
		var x := x0 + 0.6
		while x < x1:
			k.flowers(Vector3(x, 0.45, z + 0.7), 0.5, 3, cols, rng, "plants", Vector2(0.8, 1.5))
			x += 1.2
		# Grow light bar above the bed.
		k.block(Vector3(x0, 3.2, z + 0.55), Vector3(x1, 3.28, z + 0.85), "grow_light", false)
		k.block(Vector3(x0, 3.28, z + 0.65), Vector3(x1, 4.5, z + 0.75), "steel", false)
		z += 4.0


static func _throne_room(k: LandmarkKit, b: Dictionary) -> void:
	var hx := float(b.half_x)
	var hz := float(b.half_z)
	# Dais with steps, beanbag throne with a gold backrest made of hubcaps, banners either side.
	k.block(Vector3(-hx + 0.4, 0.0, -5.0), Vector3(-37.0, 0.6, 5.0), "wood")
	k.ramp(Vector3(-35.0, 0.0, 0.0), Vector3(-37.0, 0.6, 0.0), 6.0, 0.3, "wood")  # step-free
	k.box(Vector3(-42.0, 0.95, 0.0), Vector3(1.6, 0.7, 1.6), "beanbag")
	k.box(Vector3(-43.0, 1.9, 0.0), Vector3(0.3, 2.2, 2.4), "gold", 0.0, false)
	for i in 5:
		k.disc(Vector3(-42.82, 1.2 + (i % 2) * 0.9, -0.9 + i * 0.45), 0.3, "gold", 10, Vector3.RIGHT)
	for s: float in [-1.0, 1.0]:
		k.block(Vector3(-hx + 0.45, 0.8, s * 6.0 - 1.2), Vector3(-hx + 0.5, 4.2, s * 6.0 + 1.2), "tapestry", false)
	# String lights over the dais.
	var z := -hz + 1.0
	while z < hz - 1.0:
		k.box(Vector3(-38.0, 4.0 - 0.3 * absf(sin(z * 0.5)), z), Vector3(0.08, 0.08, 0.08), "bulbs", 0.0, false)
		z += 0.7
	# Couches facing the throne.
	_couch(k, Vector3(-30.0, 0, -6.0), -PI * 0.5, "couch_b")
	_couch(k, Vector3(-30.0, 0, 6.0), -PI * 0.5, "couch_c")


# --- campus camp -------------------------------------------------------------------------------

static func _camp(k: LandmarkKit, c: Dictionary, rng: RandomNumberGenerator) -> void:
	for t: Array in c.tents:
		_tent(k, Vector3(t[0], 0, t[1]), float(t[2]), "canvas" if rng.randf() < 0.5 else "canvas_b")
	var f: Array = c.fire
	var fp := Vector3(f[0], 0, f[1])
	for i in 8:
		var a := TAU * i / 8.0
		k.box(fp + Vector3(cos(a), 0.12, sin(a)) * 0.9, Vector3(0.35, 0.24, 0.3), "concrete", a, false)
	k.disc(fp + Vector3(0, 0.15, 0), 0.6, "fire", 10)
	for i in 3:
		var a := TAU * i / 3.0 + 0.4
		k.box(fp + Vector3(cos(a), 0, sin(a)) * 3.0 + Vector3(0, 0.22, 0), Vector3(2.2, 0.44, 0.45), "wood", a + PI * 0.5)
	var v: Array = c.van
	_van(k, Vector3(v[0], 0, v[1]), float(v[2]))


static func _tent(k: LandmarkKit, p: Vector3, yaw: float, mat: String) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var hw := 1.3
	var hl := 1.6
	var h := 1.5
	var a := p + bs * Vector3(-hw, 0, -hl)
	var b2 := p + bs * Vector3(hw, 0, -hl)
	var c := p + bs * Vector3(hw, 0, hl)
	var dd := p + bs * Vector3(-hw, 0, hl)
	var r0 := p + bs * Vector3(0, h, -hl)
	var r1 := p + bs * Vector3(0, h, hl)
	k.quad(a, dd, r1, r0, mat)
	k.quad(b2, r0, r1, c, mat)
	k.tri(a, r0, b2, mat)
	var faces := PackedVector3Array([a, dd, r1, a, r1, r0, b2, r0, r1, b2, r1, c, a, r0, b2, dd, c, r1])
	k.trimesh(faces)


static func _van(k: LandmarkKit, p: Vector3, yaw: float) -> void:
	var bs := Basis(Vector3.UP, yaw)
	k.box_xf(Transform3D(bs, p + bs * Vector3(0, 1.1, 0)), Vector3(2.0, 1.5, 5.0), "van")
	k.box_xf(Transform3D(bs, p + bs * Vector3(0, 2.05, -0.3)), Vector3(1.9, 0.5, 4.2), "van_white", false)
	k.box_xf(Transform3D(bs, p + bs * Vector3(0, 1.75, 2.45)), Vector3(1.7, 0.6, 0.12), "glass", false)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.7, 1.7]:
			k.box_xf(Transform3D(bs, p + bs * Vector3(sx * 1.0, 0.36, sz)), Vector3(0.3, 0.72, 0.72), "tyre", false)
	# Peace sign on each side.
	for sx: float in [-1.0, 1.0]:
		k.disc(p + bs * Vector3(sx * 1.02, 1.2, 0.2), 0.45, "van_white", 14, bs * Vector3(sx, 0, 0))
