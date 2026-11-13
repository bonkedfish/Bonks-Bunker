# YanneyGardens — builds The Gardens at Yanney Park (12.6 acres, NW corner of the park off W 11th St) into a
# LandmarkKit (D-047), laid out after the garden site plan: the seven themed gardens (Rose, Pollinator, Nebraska
# Native, Annual, Lilac & Hydrangea, Xeriscape, Edibles) as circular "rosette"/spiral beds with ring and petal
# paths, a grid of raised beds, the Burlington Capital Green Courtyard lawn with its path ring, a reflecting pond,
# the giant poppy sculptures, concrete paths between them and the Gail & Michael Yanney Pavilion (stone + glass,
# enterable, some glass broken). Overgrown: beds gone wild and faded. Origin = garden centre on the ground.
# Returns plants ([kind, local x, local z]) for the map's instanced vegetation (trees, shrubs, grass).
# Depends on: LandmarkKit.
extends RefCounted

const PATH_Y := 0.05
const BED_Y := 0.025


static func build(k: LandmarkKit, d: Dictionary, palettes: Dictionary, rng: RandomNumberGenerator) -> Array:
	var plants: Array = []
	var w := float(d.path_width_m)
	# Courtyard lawn ring path.
	var c: Array = d.courtyard
	var lo := Vector2(c[0], c[1])
	var hi := Vector2(c[2], c[3])
	for e in [[lo, Vector2(hi.x, lo.y)], [Vector2(hi.x, lo.y), hi], [hi, Vector2(lo.x, hi.y)], [Vector2(lo.x, hi.y), lo]]:
		_strip(k, e[0], e[1], w, "path")
	# Paths between gardens.
	for seg: Array in d.paths:
		_strip(k, Vector2(seg[0][0], seg[0][1]), Vector2(seg[1][0], seg[1][1]), w, "path")
	# Reflecting pond: concrete rim + murky water.
	var pond: Array = d.pond
	_oval_ring(k, Vector2(pond[0], pond[1]), float(pond[2]), float(pond[3]), 0.6, 0.45, "concrete")
	_oval_fill(k, Vector2(pond[0], pond[1]), float(pond[2]), float(pond[3]), 0.25, "water")
	# The seven gardens.
	for g: Dictionary in d.gardens:
		var centre := Vector2(g.centre[0], g.centre[1])
		var pal: Array = palettes[g.palette]
		match str(g.style):
			"rosette":
				_rosette(k, centre, float(g.radius), int(g.petals), pal, rng, w)
			"spiral":
				_spiral(k, centre, float(g.radius), pal, rng, w)
			"shrubs":
				_ring_path(k, centre, float(g.radius) - 1.0, w)
				_ring_path(k, centre, float(g.radius) * 0.4, w * 0.8)
				for i in 26:
					var a := rng.randf() * TAU
					var p := centre + Vector2(cos(a), sin(a)) * rng.randf_range(float(g.radius) * 0.55, float(g.radius) - 2.8)
					plants.append(["shrub_b" if rng.randf() < 0.5 else "shrub_a", p.x, p.y])
				_beds(k, centre, float(g.radius) - 2.0, 20, pal, rng)
			"gravel":
				_disc(k, centre, float(g.radius), BED_Y + 0.005, "gravel")
				_ring_path(k, centre, float(g.radius) - 0.8, w * 0.8)
				for i in 14:
					var a := rng.randf() * TAU
					var p := centre + Vector2(cos(a), sin(a)) * sqrt(rng.randf()) * (float(g.radius) - 3.0)
					plants.append(["grass_clump", p.x, p.y])
				for i in 6:
					var a := rng.randf() * TAU
					var p := centre + Vector2(cos(a), sin(a)) * sqrt(rng.randf()) * (float(g.radius) - 3.0)
					k.box(Vector3(p.x, 0.3, p.y), Vector3(rng.randf_range(0.8, 1.6), 0.7, rng.randf_range(0.7, 1.3)), "stone",
						rng.randf() * TAU)
			"grid":
				_grid(k, centre, Vector2(g.size[0], g.size[1]), pal, rng, w)
	# Giant poppy sculptures (rusting steel stems, faded red heads).
	for p: Array in d.poppies:
		var h := rng.randf_range(5.0, 7.0)
		var base := Vector3(p[0], 0.0, p[1])
		var lean := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
		k.cylinder(base, 0.12, h, "rust", 6, true)
		var head := base + Vector3.UP * h + lean
		var n := (Vector3.UP * 1.5 + lean).normalized()
		k.disc(head, 1.6, "paint_red", 10, n)
		k.disc(head + n * 0.05, 0.45, "paint_dark", 8, n)
		k.box(base + Vector3.UP * 0.2, Vector3(1.2, 0.4, 1.2), "concrete")
	_pavilion(k, d.pavilion, rng)
	# Trees around the garden edge (gaps where paths leave), plus a few dead trunks.
	var he := Vector2(d.half_extent[0], d.half_extent[1]) - Vector2(4, 4)
	var step := float(d.perimeter_tree_spacing_m)
	for e in [[Vector2(-he.x, -he.y), Vector2(he.x, -he.y)], [Vector2(he.x, -he.y), he], [he, Vector2(-he.x, he.y)],
			[Vector2(-he.x, he.y), Vector2(-he.x, -he.y)]]:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var n := int(a.distance_to(b) / step)
		for i in n:
			if rng.randf() < 0.8:
				var p := a.lerp(b, (i + 0.5) / n) + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
				plants.append(["tree_bare" if rng.randf() < 0.3 else "tree_leafy", p.x, p.y])
	for i in 3:
		plants.append(["dead_trunk", rng.randf_range(-he.x, he.x), rng.randf_range(-he.y, he.y)])
	return plants


# --- garden styles -------------------------------------------------------------------------------

# Circle of radius r: soil bed, outer ring path, centre circle and `petals` petal rings, wild flowers in between.
static func _rosette(k: LandmarkKit, c: Vector2, r: float, petals: int, pal: Array, rng: RandomNumberGenerator, w: float) -> void:
	_disc(k, c, r, BED_Y, "soil")
	_ring_path(k, c, r - 1.0, w)
	_ring_path(k, c, r * 0.3, w * 0.8)
	for i in petals:
		var a := TAU * i / petals
		_ring_path(k, c + Vector2(cos(a), sin(a)) * r * 0.62, r * 0.24, w * 0.7)
		_strip(k, c + Vector2(cos(a + PI / petals), sin(a + PI / petals)) * r * 0.3,
			c + Vector2(cos(a + PI / petals), sin(a + PI / petals)) * (r - 1.0), w * 0.7, "path")
	_beds(k, c, r - 2.2, int(r * 3.0), pal, rng)


static func _spiral(k: LandmarkKit, c: Vector2, r: float, pal: Array, rng: RandomNumberGenerator, w: float) -> void:
	_disc(k, c, r, BED_Y, "soil")
	_ring_path(k, c, r - 1.0, w)
	var prev := c
	for i in range(1, 60):
		var t := i / 60.0
		var a := t * TAU * 2.5
		var p := c + Vector2(cos(a), sin(a)) * t * (r - 2.5)
		_strip(k, prev, p, w * 0.7, "path")
		prev = p
	_beds(k, c, r - 2.0, int(r * 3.0), pal, rng)


static func _grid(k: LandmarkKit, c: Vector2, size: Vector2, pal: Array, rng: RandomNumberGenerator, _w: float) -> void:
	var lo := c - size * 0.5
	_rect(k, lo - Vector2(1.5, 1.5), lo + size + Vector2(1.5, 1.5), PATH_Y, "gravel")
	for ix in 5:
		for iz in 4:
			var p := lo + Vector2((ix + 0.5) * size.x / 5.0, (iz + 0.5) * size.y / 4.0)
			var collapsed := rng.randf() < 0.15
			k.box(Vector3(p.x, 0.25 if not collapsed else 0.12, p.y), Vector3(3.6, 0.5 if not collapsed else 0.25, 2.2), "planks",
				rng.randf_range(-0.05, 0.05))
			k.flowers(Vector3(p.x, 0.5, p.y), 1.0, 12, pal, rng, "flowers", Vector2(0.3, 0.8))


# --- pieces -------------------------------------------------------------------------------------

static func _pavilion(k: LandmarkKit, d: Dictionary, rng: RandomNumberGenerator) -> void:
	var c := Vector2(d.centre[0], d.centre[1])
	var size := Vector2(d.size[0], d.size[1])
	var h := float(d.height)
	var lo := c - size * 0.5
	var hi := c + size * 0.5
	var t := 0.4
	k.block(Vector3(lo.x - 3, -0.3, lo.y - 3), Vector3(hi.x + 1, 0.15, hi.y + 1), "concrete")  # floor + front terrace
	# East (back) and short walls in stone, door gaps in the short walls.
	k.block(Vector3(hi.x - t, 0, lo.y), Vector3(hi.x, h, hi.y), "stone")
	for zz in [[lo.y, lo.y + t], [hi.y - t, hi.y]]:
		k.block(Vector3(lo.x, 0, zz[0]), Vector3(c.x - 1.2, h, zz[1]), "stone")
		k.block(Vector3(c.x + 1.2, 0, zz[0]), Vector3(hi.x, h, zz[1]), "stone")
		k.block(Vector3(c.x - 1.2, 2.4, zz[0]), Vector3(c.x + 1.2, h, zz[1]), "stone")
	# West front: glass panels between steel mullions, some gone.
	var n := int(size.y / 2.0)
	for i in n:
		var z0 := lo.y + i * size.y / n
		var z1 := z0 + size.y / n
		k.box(Vector3(lo.x, h * 0.5, z0), Vector3(0.18, h, 0.18), "steel", 0.0, false)
		if rng.randf() > float(d.glass_broken):
			k.block(Vector3(lo.x - 0.03, 0.15, z0 + 0.09), Vector3(lo.x + 0.03, h - 0.3, z1 - 0.09), "glass")
		elif rng.randf() < 0.5:
			k.block(Vector3(lo.x - 0.03, 0.15, z0 + 0.09), Vector3(lo.x + 0.03, rng.randf_range(0.6, 1.6), z1 - 0.09), "glass", false)
	k.block(Vector3(lo.x - 0.1, h - 0.3, lo.y), Vector3(lo.x + 0.1, h, hi.y), "steel", false)
	# Roof: thin slab overhanging the terrace, with a raised clerestory strip.
	k.block(Vector3(lo.x - 3.0, h, lo.y - 1.0), Vector3(hi.x + 0.5, h + 0.35, hi.y + 1.0), "roof_metal")
	k.block(Vector3(c.x - 4.0, h + 0.35, lo.y + 2.0), Vector3(c.x + 4.0, h + 1.8, hi.y - 2.0), "glass", false)
	k.block(Vector3(c.x - 4.3, h + 1.8, lo.y + 1.7), Vector3(c.x + 4.3, h + 2.0, hi.y - 1.7), "roof_metal", false)
	# Overturned tables inside.
	for i in 6:
		var p := Vector2(rng.randf_range(lo.x + 2, hi.x - 2), rng.randf_range(lo.y + 2, hi.y - 2))
		if rng.randf() < 0.5:
			k.box(Vector3(p.x, 0.75, p.y), Vector3(1.8, 0.06, 0.8), "planks", rng.randf() * TAU, false)
			k.box(Vector3(p.x, 0.37, p.y), Vector3(0.1, 0.75, 0.1), "steel", 0.0, true)
		else:
			k.box(Vector3(p.x, 0.4, p.y), Vector3(1.8, 0.8, 0.06), "planks", rng.randf() * TAU)


# --- flat helpers (paths, beds, rings) -----------------------------------------------------------

static func _strip(k: LandmarkKit, a: Vector2, b: Vector2, w: float, mat: String) -> void:
	var d := b - a
	if d.length() < 0.01:
		return
	var s := d.normalized().orthogonal() * w * 0.5
	var y := PATH_Y
	k.quad(Vector3(a.x + s.x, y, a.y + s.y), Vector3(b.x + s.x, y, b.y + s.y), Vector3(b.x - s.x, y, b.y - s.y),
		Vector3(a.x - s.x, y, a.y - s.y), mat)
	_disc(k, b, w * 0.5, y, mat, 8)  # round joints


static func _ring_path(k: LandmarkKit, c: Vector2, r: float, w: float) -> void:
	var n := maxi(16, int(r * 2.0))
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		var ri := r - w * 0.5
		var ro := r + w * 0.5
		k.quad(Vector3(c.x + d0.x * ri, PATH_Y, c.y + d0.y * ri), Vector3(c.x + d1.x * ri, PATH_Y, c.y + d1.y * ri),
			Vector3(c.x + d1.x * ro, PATH_Y, c.y + d1.y * ro), Vector3(c.x + d0.x * ro, PATH_Y, c.y + d0.y * ro), "path")


static func _disc(k: LandmarkKit, c: Vector2, r: float, y: float, mat: String, sides := 0) -> void:
	k.disc(Vector3(c.x, y, c.y), r, mat, sides if sides > 0 else maxi(16, int(r * 2.0)), Vector3.UP)


static func _rect(k: LandmarkKit, lo: Vector2, hi: Vector2, y: float, mat: String) -> void:
	k.quad(Vector3(lo.x, y, lo.y), Vector3(hi.x, y, lo.y), Vector3(hi.x, y, hi.y), Vector3(lo.x, y, hi.y), mat)


static func _oval_fill(k: LandmarkKit, c: Vector2, rx: float, rz: float, y: float, mat: String) -> void:
	for i in 24:
		var a0 := TAU * i / 24.0
		var a1 := TAU * (i + 1) / 24.0
		k.tri(Vector3(c.x, y, c.y), Vector3(c.x + cos(a1) * rx, y, c.y + sin(a1) * rz), Vector3(c.x + cos(a0) * rx, y, c.y + sin(a0) * rz), mat)


static func _oval_ring(k: LandmarkKit, c: Vector2, rx: float, rz: float, w: float, h: float, mat: String) -> void:
	for i in 24:
		var a := TAU * (i + 0.5) / 24.0
		var p := Vector2(c.x + cos(a) * rx, c.y + sin(a) * rz)
		var tangent := Vector2(-sin(a) * rx, cos(a) * rz)
		var seg := tangent.length() * TAU / 24.0
		k.box(Vector3(p.x, h * 0.5, p.y), Vector3(w, h, seg + 0.1), mat, atan2(tangent.x, tangent.y))


# Wild flower clumps scattered inside radius r.
static func _beds(k: LandmarkKit, c: Vector2, r: float, clumps: int, pal: Array, rng: RandomNumberGenerator) -> void:
	for i in clumps:
		var a := rng.randf() * TAU
		var p := c + Vector2(cos(a), sin(a)) * sqrt(rng.randf()) * r
		k.flowers(Vector3(p.x, 0.0, p.y), rng.randf_range(0.8, 1.8), rng.randi_range(6, 14), pal, rng, "flowers")

