# TreeMesh — builds one low-poly tree mesh for the map importer (D-043): a tapered trunk, a few branches and
# (unless bare) clumps of lumpy low-poly canopy. Vertex coloured (bark / leaves); origin at the trunk base,
# height 1 (scaled per instance). Deterministic from the RandomNumberGenerator passed in. No rendering imports
# beyond building the ArrayMesh. Depends on: nothing.
class_name TreeMesh
extends RefCounted

const SIDES := 6


static func build(rng: RandomNumberGenerator, bare: bool, trunk_radius: float, bark: Color, leaf: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(rng.randf_range(-0.04, 0.04), 0.55 if not bare else 0.7, rng.randf_range(-0.04, 0.04))
	_limb(st, Vector3.ZERO, top, trunk_radius, trunk_radius * 0.6, bark)
	var branches := rng.randi_range(3, 5) if not bare else rng.randi_range(5, 7)
	for i in branches:
		var a := TAU * (float(i) + rng.randf() * 0.5) / branches
		var start := top * rng.randf_range(0.6, 1.0)
		var reach := rng.randf_range(0.18, 0.3)
		var end := start + Vector3(cos(a) * reach, rng.randf_range(0.15, 0.3), sin(a) * reach)
		_limb(st, start, end, trunk_radius * 0.45, trunk_radius * 0.15, bark)
		if bare:
			var end2 := end + Vector3(cos(a + 0.6) * reach * 0.5, rng.randf_range(0.08, 0.18), sin(a + 0.6) * reach * 0.5)
			_limb(st, end, end2, trunk_radius * 0.15, trunk_radius * 0.05, bark)
		else:
			_blob(st, rng, end + Vector3(0, 0.05, 0), rng.randf_range(0.16, 0.24), leaf)
	if not bare:
		_blob(st, rng, top + Vector3(0, 0.22, 0), rng.randf_range(0.24, 0.3), leaf)
	st.generate_normals()
	return st.commit()


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
	var p := [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
	var faces := [[0, 4, 3], [0, 3, 5], [0, 5, 2], [0, 2, 4], [1, 3, 4], [1, 5, 3], [1, 2, 5], [1, 4, 2]]
	var shade := col * rng.randf_range(0.85, 1.1)
	var squash := Vector3(1.0, rng.randf_range(0.7, 0.9), 1.0)
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
