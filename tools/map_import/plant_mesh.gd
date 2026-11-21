# PlantMesh — builds small ground plants for the map importer (D-098): tall prairie grass tufts, wildflower clumps
# and cattail reeds for pond edges. Vertex coloured, double-sided (the shared tree material), origin at the base,
# height 1 (scaled per instance). Blades are thin bent triangles; flower heads and cattail heads are tiny octahedra.
# Deterministic from the RandomNumberGenerator passed in. Depends on: nothing.
class_name PlantMesh
extends RefCounted


# kind: "grass" | "flowers" | "reeds". p: the plant's vegetation.json entry (colors, head_colors, blades).
static func build(rng: RandomNumberGenerator, kind: String, p: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols: Array = p.colors
	var col := _c(cols[rng.randi_range(0, cols.size() - 1)])
	var blades: Array = p.get("blades", [10, 16])
	var n := rng.randi_range(int(blades[0]), int(blades[1]))
	match kind:
		"grass":
			for i in n:
				_blade(st, rng, rng.randf_range(0.6, 1.0), 0.035, rng.randf_range(0.15, 0.35), col * rng.randf_range(0.85, 1.15))
		"reeds":
			var head := _c(p.head_color)
			for i in n:
				var h := rng.randf_range(0.6, 1.0)
				var tip := _blade(st, rng, h, 0.025, rng.randf_range(0.03, 0.12), col * rng.randf_range(0.85, 1.1))
				if i % 3 == 0:  # a cattail on every third stalk
					_head(st, tip + Vector3(0, -0.08, 0), Vector3(0.025, 0.08, 0.025), head)
		"flowers":
			var heads: Array = p.head_colors
			var hc := _c(heads[rng.randi_range(0, heads.size() - 1)])
			for i in n:
				var tip := _blade(st, rng, rng.randf_range(0.55, 1.0), 0.02, rng.randf_range(0.05, 0.15), col)
				var s := rng.randf_range(0.05, 0.08)
				_head(st, tip, Vector3(s, s * 0.6, s), hc * rng.randf_range(0.9, 1.1))
	st.generate_normals()
	return st.commit()


# One blade / stalk from a random spot near the base, leaning out by `bend` at the tip. Returns the tip.
static func _blade(st: SurfaceTool, rng: RandomNumberGenerator, h: float, w: float, bend: float, col: Color) -> Vector3:
	var a := rng.randf() * TAU
	var base := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.18)
	var out := Vector3(cos(a + rng.randf_range(-0.5, 0.5)), 0, sin(a + rng.randf_range(-0.5, 0.5)))
	var mid := base + Vector3(0, h * 0.55, 0) + out * bend * 0.35
	var tip := base + Vector3(0, h, 0) + out * bend
	var side := out.cross(Vector3.UP).normalized() * w
	var dark := col * 0.75
	for q: Array in [[base - side, dark], [base + side, dark], [mid + side * 0.6, col], [base - side, dark], [mid + side * 0.6, col],
			[mid - side * 0.6, col], [mid - side * 0.6, col], [mid + side * 0.6, col], [tip, col * 1.1]]:
		st.set_color(q[1])
		st.add_vertex(q[0])
	return tip


# Small octahedron (flower head / cattail), half-sizes s.
static func _head(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var p := [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
	for f: Array in [[0, 4, 3], [0, 3, 5], [0, 5, 2], [0, 2, 4], [1, 3, 4], [1, 5, 3], [1, 2, 5], [1, 4, 2]]:
		for k: int in f:
			st.set_color(col)
			st.add_vertex(c + (p[k] as Vector3) * s)


static func _c(a: Array) -> Color:
	return Color(float(a[0]), float(a[1]), float(a[2]))
