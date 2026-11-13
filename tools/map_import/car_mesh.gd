# CarMesh — builds one low-poly abandoned car for the map importer (D-044): body, cabin with dark windows, wheels
# (some missing: the car sits on its hub), faded paint with rust blotches, or burned out. Vertex coloured; length
# along +Z, origin on the ground under the middle. Body types: "sedan", "pickup", "suv". Deterministic from the
# RandomNumberGenerator passed in. Depends on: nothing.
class_name CarMesh
extends RefCounted

const BODIES := {
	# length, width, body bottom, body top, cabin start (from rear), cabin end, cabin top, roof inset
	"sedan": [4.6, 1.8, 0.3, 0.95, 1.2, 3.2, 1.42, 0.12],
	"pickup": [5.3, 1.95, 0.45, 1.1, 2.3, 3.8, 1.85, 0.1],
	"suv": [4.8, 1.9, 0.4, 1.1, 0.5, 3.6, 1.8, 0.08],
}
const GLASS := Color(0.05, 0.06, 0.07)
const TYRE := Color(0.06, 0.06, 0.06)
const RUST := Color(0.36, 0.2, 0.1)
const BURNED := Color(0.11, 0.09, 0.08)


static func build(rng: RandomNumberGenerator, body: String, paint: Color, burned: bool, rust: float) -> ArrayMesh:
	var b: Array = BODIES.get(body, BODIES.sedan)
	var length: float = b[0]
	var hw: float = b[1] * 0.5
	var z0 := -length * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := BURNED if burned else paint * rng.randf_range(0.75, 0.95)
	var sag := rng.randf_range(-0.12, 0.0)  # flat tyres / broken suspension on one side
	# Lower body.
	_box(st, rng, Vector3(-hw, b[2], z0), Vector3(hw, b[3], z0 + length), base, rust, burned, sag)
	# Cabin: tapered box, windows dark.
	var c0: float = z0 + b[4]
	var c1: float = z0 + b[5]
	var inset: float = b[7] * 2.0
	_cabin(st, Vector3(-hw + 0.05, b[3], c0), Vector3(hw - 0.05, b[6], c1), inset, base, burned, sag)
	# Wheels (each may be missing).
	for wz: float in [z0 + 0.85, z0 + length - 0.85]:
		for sx: float in [-1.0, 1.0]:
			if burned or rng.randf() < 0.25:
				continue
			_wheel(st, Vector3(sx * (hw - 0.05), 0.33, wz), 0.33, 0.22)
	st.generate_normals()
	return st.commit()


static func _shade(rng: RandomNumberGenerator, base: Color, rust: float, burned: bool) -> Color:
	if burned:
		return base * rng.randf_range(0.8, 1.3)
	return base.lerp(RUST, rust * rng.randf()) if rng.randf() < 0.5 else base


# Axis-aligned box from lo to hi, each face shaded on its own; `sag` lowers the +x side.
static func _box(st: SurfaceTool, rng: RandomNumberGenerator, lo: Vector3, hi: Vector3, base: Color, rust: float,
		burned: bool, sag: float) -> void:
	var c := [_sag(Vector3(lo.x, lo.y, lo.z), sag), _sag(Vector3(hi.x, lo.y, lo.z), sag), _sag(Vector3(hi.x, lo.y, hi.z), sag),
		_sag(Vector3(lo.x, lo.y, hi.z), sag), _sag(Vector3(lo.x, hi.y, lo.z), sag), _sag(Vector3(hi.x, hi.y, lo.z), sag),
		_sag(Vector3(hi.x, hi.y, hi.z), sag), _sag(Vector3(lo.x, hi.y, hi.z), sag)]
	for f in [[4, 5, 6, 7], [3, 2, 1, 0], [0, 1, 5, 4], [2, 3, 7, 6], [1, 2, 6, 5], [3, 0, 4, 7]]:
		_quad(st, c[f[0]], c[f[1]], c[f[2]], c[f[3]], _shade(rng, base, rust, burned))


static func _cabin(st: SurfaceTool, lo: Vector3, hi: Vector3, inset: float, base: Color, burned: bool, sag: float) -> void:
	var b0 := _sag(Vector3(lo.x, lo.y, lo.z), sag)
	var b1 := _sag(Vector3(hi.x, lo.y, lo.z), sag)
	var b2 := _sag(Vector3(hi.x, lo.y, hi.z), sag)
	var b3 := _sag(Vector3(lo.x, lo.y, hi.z), sag)
	var t0 := _sag(Vector3(lo.x + inset, hi.y, lo.z + inset * 2.0), sag)
	var t1 := _sag(Vector3(hi.x - inset, hi.y, lo.z + inset * 2.0), sag)
	var t2 := _sag(Vector3(hi.x - inset, hi.y, hi.z - inset * 3.0), sag)
	var t3 := _sag(Vector3(lo.x + inset, hi.y, hi.z - inset * 3.0), sag)
	var glass := BURNED * 0.6 if burned else GLASS
	_quad(st, t0, t1, t2, t3, base)  # roof
	_quad(st, b0, b1, t1, t0, glass)  # rear window
	_quad(st, b2, b3, t3, t2, glass)  # windscreen
	_quad(st, b1, b2, t2, t1, glass)  # side windows
	_quad(st, b3, b0, t0, t3, glass)


# Wheel as an 8-sided disc with a tread band, axis along x.
static func _wheel(st: SurfaceTool, c: Vector3, r: float, w: float) -> void:
	for i in 8:
		var a0 := TAU * i / 8.0
		var a1 := TAU * (i + 1) / 8.0
		var o0 := Vector3(0, sin(a0), cos(a0)) * r
		var o1 := Vector3(0, sin(a1), cos(a1)) * r
		var l := Vector3(-w * 0.5, 0, 0)
		var rr := Vector3(w * 0.5, 0, 0)
		_quad(st, c + l + o0, c + l + o1, c + rr + o1, c + rr + o0, TYRE)
		_tri(st, c + rr, c + rr + o0, c + rr + o1, TYRE)
		_tri(st, c + l, c + l + o1, c + l + o0, TYRE)


static func _sag(v: Vector3, sag: float) -> Vector3:
	return v + Vector3(0, sag if v.x > 0.0 else 0.0, 0)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(st, a, b, c, col)
	_tri(st, a, c, d, col)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	for v in [a, b, c]:
		st.set_color(col)
		st.add_vertex(v)
