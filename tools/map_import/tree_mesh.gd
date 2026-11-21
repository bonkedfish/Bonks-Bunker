# TreeMesh — builds one low-poly tree mesh for the map importer (D-043): a tapered trunk, a few branches and
# (unless bare) clumps of lumpy low-poly canopy. Vertex coloured (bark / leaves); origin at the trunk base,
# height 1 (scaled per instance). Deterministic from the RandomNumberGenerator passed in. No rendering imports
# beyond building the ArrayMesh. The mesh carries what it drew as metadata "tree_shape" (D-091), in the same units:
# {trunk: [base, top, r0, r1], limbs: [[a, b, r0, r1], ...], blobs: [[centre, radius], ...]} - the trunk collider
# (VegetationBuilder) and disc golf's branch / leaf hits (DiscFlightRules.canopy_contact) are built from it, so they
# match the model.
# build_species() (D-098) draws the Kearney species from data/art/vegetation.json "species" by shape: round (ash,
# maple), vase (American elm), tall_open (cottonwood), airy (honey locust), weeping (willow), cone (spruce), pine
# (ponderosa), column (eastern red cedar), bush (no trunk). Conifer tiers are drawn as cones; their tree_shape blobs
# are spheres along the trunk sized to each tier, so colliders and disc hits still work.
# Depends on: nothing.
class_name TreeMesh
extends RefCounted

const SIDES := 6


static func build(rng: RandomNumberGenerator, bare: bool, trunk_radius: float, bark: Color, leaf: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(rng.randf_range(-0.04, 0.04), 0.55 if not bare else 0.7, rng.randf_range(-0.04, 0.04))
	_limb(st, Vector3.ZERO, top, trunk_radius, trunk_radius * 0.6, bark)
	var limbs := []
	var blobs := []
	var branches := rng.randi_range(3, 5) if not bare else rng.randi_range(5, 7)
	for i in branches:
		var a := TAU * (float(i) + rng.randf() * 0.5) / branches
		var start := top * rng.randf_range(0.6, 1.0)
		var reach := rng.randf_range(0.18, 0.3)
		var end := start + Vector3(cos(a) * reach, rng.randf_range(0.15, 0.3), sin(a) * reach)
		_limb(st, start, end, trunk_radius * 0.45, trunk_radius * 0.15, bark)
		limbs.append([start, end, trunk_radius * 0.45, trunk_radius * 0.15])
		if bare:
			var end2 := end + Vector3(cos(a + 0.6) * reach * 0.5, rng.randf_range(0.08, 0.18), sin(a + 0.6) * reach * 0.5)
			_limb(st, end, end2, trunk_radius * 0.15, trunk_radius * 0.05, bark)
			limbs.append([end, end2, trunk_radius * 0.15, trunk_radius * 0.05])
		else:
			var r := rng.randf_range(0.16, 0.24)
			_blob(st, rng, end + Vector3(0, 0.05, 0), r, leaf)
			blobs.append([end + Vector3(0, 0.05, 0), r])
	if not bare:
		var r := rng.randf_range(0.24, 0.3)
		_blob(st, rng, top + Vector3(0, 0.22, 0), r, leaf)
		blobs.append([top + Vector3(0, 0.22, 0), r])
	st.generate_normals()
	var mesh := st.commit()
	mesh.set_meta("tree_shape", {"trunk": [Vector3.ZERO, top, trunk_radius, trunk_radius * 0.6], "limbs": limbs,
		"blobs": blobs})
	return mesh


# One tree of a species shape (height 1, origin at the trunk base). sp: {shape, dense (0..1), ...};
# trunk_radius in height units.
static func build_species(rng: RandomNumberGenerator, sp: Dictionary, trunk_radius: float, bark: Color, leaf: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var limbs := []
	var blobs := []
	var shape := str(sp.get("shape", "round"))
	var dense := float(sp.get("dense", 0.5))
	var lean := Vector3(rng.randf_range(-0.03, 0.03), 0.0, rng.randf_range(-0.03, 0.03))
	var top := Vector3.ZERO
	match shape:
		"round", "airy", "tall_open", "weeping":
			var trunk_h: float = {"round": 0.5, "airy": 0.5, "tall_open": 0.6, "weeping": 0.42}[shape]
			top = Vector3(0, trunk_h, 0) + lean
			_limb(st, Vector3.ZERO, top, trunk_radius, trunk_radius * 0.6, bark)
			var n := rng.randi_range(4, 6) + roundi(dense * 2.0)
			var blob_r: Vector2 = {"round": Vector2(0.17, 0.25), "airy": Vector2(0.1, 0.14), "tall_open": Vector2(0.14, 0.24),
				"weeping": Vector2(0.15, 0.2)}[shape]
			if shape == "airy":
				n += 4
			for i in n:
				var a := TAU * (float(i) + rng.randf() * 0.6) / n
				var start := top * rng.randf_range(0.65, 1.0)
				var reach := rng.randf_range(0.2, 0.34) * (1.2 if shape == "airy" else 1.0)
				var rise := rng.randf_range(0.1, 0.32) * (1.4 if shape == "tall_open" else 1.0)
				var end := start + Vector3(cos(a) * reach, rise, sin(a) * reach)
				_limb(st, start, end, trunk_radius * 0.42, trunk_radius * 0.14, bark)
				limbs.append([start, end, trunk_radius * 0.42, trunk_radius * 0.14])
				var r := rng.randf_range(blob_r.x, blob_r.y)
				var c := end + Vector3(0, 0.04, 0)
				var squash := 0.8
				if shape == "weeping":  # long hanging curtains of leaves
					c = end + Vector3(0, -0.12, 0)
					squash = 1.8
				_blob_s(st, rng, c, r, leaf, squash)
				blobs.append([c, r * maxf(squash, 1.0)])
			var crown := Vector3(0, top.y + 0.24, 0) + lean
			var cr := rng.randf_range(0.22, 0.3) * (0.7 if shape == "airy" else 1.0)
			_blob_s(st, rng, crown, cr, leaf, 0.8)
			blobs.append([crown, cr])
		"vase":  # elm: the trunk forks low into long limbs that arch up and out under a wide, full umbrella crown
			top = Vector3(0, 0.36, 0) + lean
			_limb(st, Vector3.ZERO, top, trunk_radius, trunk_radius * 0.7, bark)
			var n := rng.randi_range(5, 6)
			for i in n:
				var a := TAU * (float(i) + rng.randf() * 0.4) / n
				var mid := top + Vector3(cos(a) * 0.14, 0.24, sin(a) * 0.14)
				var end := mid + Vector3(cos(a) * 0.2, 0.2, sin(a) * 0.2)
				_limb(st, top, mid, trunk_radius * 0.55, trunk_radius * 0.35, bark)
				_limb(st, mid, end, trunk_radius * 0.35, trunk_radius * 0.15, bark)
				limbs.append([top, mid, trunk_radius * 0.55, trunk_radius * 0.35])
				limbs.append([mid, end, trunk_radius * 0.35, trunk_radius * 0.15])
				for k in 3:  # the umbrella's rim: clumps fanning out past the limb tip, drooping at the edge
					var b := a + (k - 1) * 0.45
					var out := 0.08 + 0.06 * float(k == 1)
					var c := end + Vector3(cos(b) * out, rng.randf_range(-0.05, 0.03), sin(b) * out)
					var r := rng.randf_range(0.15, 0.2)
					_blob_s(st, rng, c, r, leaf, 0.6)
					blobs.append([c, r])
			for i in rng.randi_range(4, 5):  # fill the dome over the limbs so the crown reads as one canopy
				var a := TAU * (float(i) + rng.randf() * 0.5) / 5.0
				var c := Vector3(cos(a) * 0.17, top.y + 0.56 + rng.randf_range(0.0, 0.06), sin(a) * 0.17) + lean
				var r := rng.randf_range(0.18, 0.23)
				_blob_s(st, rng, c, r, leaf, 0.6)
				blobs.append([c, r])
		"cone", "column":  # spruce / red cedar: a straight trunk under stacked tiers
			top = Vector3(0, 1.0, 0)
			_limb(st, Vector3.ZERO, top * 0.9, trunk_radius, trunk_radius * 0.3, bark)
			var tiers := rng.randi_range(5, 7) if shape == "cone" else rng.randi_range(6, 8)
			var base_y := 0.08 if shape == "cone" else 0.05
			var width := 0.3 if shape == "cone" else 0.17
			for i in tiers:
				var f := float(i) / tiers
				var y0 := lerpf(base_y, 0.9, f)
				var h := (1.0 - base_y) / tiers * (1.9 if shape == "cone" else 1.5)
				var r := width * (1.0 - f * 0.85) * rng.randf_range(0.9, 1.1)
				_cone(st, rng, Vector3(0, y0, 0), r, h, leaf)
				blobs.append([Vector3(0, y0 + h * 0.35, 0), r * 0.85])
		"pine":  # ponderosa: long bare trunk, open clumps of needles near the top
			top = Vector3(0, 0.72, 0) + lean
			_limb(st, Vector3.ZERO, top, trunk_radius, trunk_radius * 0.55, bark)
			var n := rng.randi_range(4, 6)
			for i in n:
				var a := TAU * (float(i) + rng.randf() * 0.5) / n
				var start := top * rng.randf_range(0.75, 1.0)
				var end := start + Vector3(cos(a) * rng.randf_range(0.14, 0.24), rng.randf_range(0.02, 0.12), sin(a) * rng.randf_range(0.14, 0.24))
				_limb(st, start, end, trunk_radius * 0.3, trunk_radius * 0.1, bark)
				limbs.append([start, end, trunk_radius * 0.3, trunk_radius * 0.1])
				var r := rng.randf_range(0.11, 0.16)
				_blob_s(st, rng, end, r, leaf, 0.7)
				blobs.append([end, r])
			var crown := top + Vector3(0, 0.16, 0)
			_blob_s(st, rng, crown, 0.15, leaf, 1.2)
			blobs.append([crown, 0.18])
		"bush":  # no trunk: a few overlapping clumps from the ground up (height 1 = the bush's height)
			top = Vector3(0, 0.2, 0)
			var n := rng.randi_range(3, 5)
			for i in n:
				var a := TAU * float(i) / n + rng.randf()
				var c := Vector3(cos(a) * 0.22, rng.randf_range(0.3, 0.5), sin(a) * 0.22)
				var r := rng.randf_range(0.3, 0.4)
				_blob_s(st, rng, c, r, leaf, 0.85)
				blobs.append([c, r])
	st.generate_normals()
	var mesh := st.commit()
	mesh.set_meta("tree_shape", {"trunk": [Vector3.ZERO, top, trunk_radius, trunk_radius * 0.6], "limbs": limbs, "blobs": blobs})
	return mesh


# 7-sided jagged cone (a conifer tier) standing on `base`, open underneath (the material is double sided).
static func _cone(st: SurfaceTool, rng: RandomNumberGenerator, base: Vector3, r: float, h: float, col: Color) -> void:
	var n := 7
	var tip := base + Vector3(rng.randf_range(-0.01, 0.01), h, rng.randf_range(-0.01, 0.01))
	var shade := col * rng.randf_range(0.85, 1.08)
	var ring: Array[Vector3] = []
	for i in n:
		var a := TAU * i / n + rng.randf() * 0.2
		ring.append(base + Vector3(cos(a) * r * rng.randf_range(0.85, 1.15), rng.randf_range(-0.02, 0.02), sin(a) * r * rng.randf_range(0.85, 1.15)))
	for i in n:
		for q: Vector3 in [tip, ring[(i + 1) % n], ring[i]]:
			st.set_color(shade)
			st.add_vertex(q)
		for q: Vector3 in [base + Vector3(0, h * 0.15, 0), ring[i], ring[(i + 1) % n]]:  # underside, slightly hollow
			st.set_color(shade * 0.7)
			st.add_vertex(q)


# Tapered 6-sided tube from a to b (radii r0 -> r1), no caps.
static func _limb(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, col: Color) -> void:
	var axis := (b - a).normalized()
	var u := axis.cross(Vector3.FORWARD if absf(axis.y) > 0.9 else Vector3.UP).normalized()
	var v := axis.cross(u)
	for i in SIDES:
		var a0 := TAU * i / SIDES
		var a1 := TAU * (i + 1) / SIDES
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		var q := [a + d0 * r0, a + d1 * r0, b + d1 * r1, b + d0 * r1]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			st.add_vertex(q[k])


# Lumpy octahedron subdivided once (32 faces), coloured with a little per-clump variation.
static func _blob(st: SurfaceTool, rng: RandomNumberGenerator, c: Vector3, r: float, col: Color) -> void:
	_blob_s(st, rng, c, r, col, rng.randf_range(0.7, 0.9))


# _blob with a chosen vertical squash (< 1 flat, > 1 tall / hanging).
static func _blob_s(st: SurfaceTool, rng: RandomNumberGenerator, c: Vector3, r: float, col: Color, squash_y: float) -> void:
	var p := [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
	var faces := [[0, 4, 3], [0, 3, 5], [0, 5, 2], [0, 2, 4], [1, 3, 4], [1, 5, 3], [1, 2, 5], [1, 4, 2]]
	var shade := col * rng.randf_range(0.85, 1.1)
	var squash := Vector3(1.0, squash_y, 1.0)
	var jitter := {}
	for f: Array in faces:
		var a: Vector3 = p[f[0]]
		var b: Vector3 = p[f[1]]
		var d: Vector3 = p[f[2]]
		var ab := (a + b).normalized()
		var bd := (b + d).normalized()
		var da := (d + a).normalized()
		for tri in [[a, ab, da], [ab, b, bd], [da, bd, d], [ab, bd, da]]:
			for q: Vector3 in tri:
				var key := q.snapped(Vector3.ONE * 0.01)
				if not jitter.has(key):
					jitter[key] = rng.randf_range(0.8, 1.15)
				st.set_color(shade)
				st.add_vertex(c + q * squash * r * float(jitter[key]))
