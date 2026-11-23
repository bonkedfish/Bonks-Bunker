# DiscMesh — realistic golf disc meshes (D-117), presentation only: each disc in data/discgolf/discs.json is a lathe of
# its rim profile ("shape": diameter, height, rim width, rim depth, dome, nose 0 sharp .. 1 blunt) with a domed
# flight plate, the nose / parting line, the rim foot and the hollow underside, in the disc's plastic ("plastic":
# roughness, clearcoat, wear) with a hot-stamp foil design on top ("stamp", shaders/disc_plastic.gdshader). One
# mesh per disc id, shared by the disc in hand (first and third person), in flight, lying on the ground and in the
# ace replay. The disc's centre is at its origin (half its height above the rim bottom), its top facing +Y.
# Depends on: DiscFlightRules (disc data), shaders/disc_plastic.gdshader.
extends RefCounted

const SHADER := preload("res://shaders/disc_plastic.gdshader")
const SEGMENTS := 40
const DESIGNS := {"ring": 0, "star": 1, "bison": 2}
const DEFAULT_SHAPE := {"diameter_m": 0.211, "height_m": 0.016, "rim_width_m": 0.016, "rim_depth_m": 0.013, "dome_m": 0.001,
	"nose": 0.5}

static var _meshes: Dictionary = {}


static func mesh(disc_id: String) -> ArrayMesh:
	if not _meshes.has(disc_id):
		var disc: Dictionary = DiscFlightRules.discs().get(disc_id, {})
		_meshes[disc_id] = build(disc.get("shape", DEFAULT_SHAPE), _material(disc))
	return _meshes[disc_id]


# The (r, y) outline of the disc's cross-section, walked round the solid: top centre, out over the flight plate and
# shoulder, down the nose, in along the rim foot, up the inner rim wall and back under the plate to the centre.
static func profile(shape: Dictionary) -> PackedVector2Array:
	var r := float(shape.diameter_m) * 0.5
	var h := float(shape.height_m)
	var rw := float(shape.rim_width_m)
	var rd := float(shape.rim_depth_m)
	var dome := float(shape.dome_m)
	var n := clampf(float(shape.nose), 0.0, 1.0)
	var th := clampf(h - rd - dome, 0.0018, 0.004)
	var side := h - dome
	var y_nose := side * lerpf(0.42, 0.55, n)
	var rim := PackedVector2Array([
		Vector2(r - rw * lerpf(0.45, 0.3, n), side - side * lerpf(0.06, 0.12, n)),
		Vector2(r - rw * lerpf(0.04, 0.1, n), y_nose + side * lerpf(0.12, 0.2, n)),
		Vector2(r, y_nose),
		Vector2(r - rw * lerpf(0.12, 0.08, n), y_nose - side * lerpf(0.2, 0.25, n)),
		Vector2(r - rw * 0.35, 0.0012),
		Vector2(r - rw * 0.6, 0.0),
		Vector2(r - rw * 0.88, 0.0012)])
	for i in 1 + roundi(n * 2.0):  # Chaikin: a sharp driver nose stays crisp, a putter's rounds over
		rim = _chaikin(rim)
	var out := PackedVector2Array([Vector2(0.0, h), Vector2(r - rw * 1.1, side + dome * 0.1)])
	out.append_array(rim)
	out.append_array(PackedVector2Array([Vector2(r - rw, rd * 0.35), Vector2(r - rw, rd * 0.85),
		Vector2(r - rw - minf(0.004, rw * 0.3), rd), Vector2(0.0, h - th)]))
	var c := h * 0.5
	for i in out.size():
		var v := out[i]
		v.y -= c
		out[i] = v
	return out


static func build(shape: Dictionary, mat: Material) -> ArrayMesh:
	var prof := profile(shape)
	var d := float(shape.diameter_m)
	var top_end := 2  # profile points 0..top_end are the flight plate top: they carry the stamp UVs
	var normals := PackedVector2Array()
	for i in prof.size():
		var a := prof[maxi(i - 1, 0)]
		var b := prof[mini(i + 1, prof.size() - 1)]
		var t := (b - a).normalized()
		normals.append(Vector2(-t.y, t.x))  # outward for this walk direction
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in prof.size() - 1:
		for s in SEGMENTS:
			var a0 := TAU * s / SEGMENTS
			var a1 := TAU * (s + 1) / SEGMENTS
			var quad := [[i, a0], [i + 1, a0], [i + 1, a1], [i, a1]]
			for k: int in [0, 1, 2, 0, 2, 3]:
				var pi: int = quad[k][0]
				var ang: float = quad[k][1]
				var p := prof[pi]
				var nn := normals[pi]
				var pos := Vector3(cos(ang) * p.x, p.y, sin(ang) * p.x)
				st.set_normal(Vector3(cos(ang) * nn.x, nn.y, sin(ang) * nn.x).normalized())
				st.set_uv(Vector2(0.5 + pos.x / d, 0.5 + pos.z / d) if i < top_end else Vector2(-1.0, -1.0))
				st.add_vertex(pos)
	var m := st.commit()
	m.surface_set_material(0, mat)
	return m


static func _material(disc: Dictionary) -> Material:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var col: Array = disc.get("color", [1, 1, 1])
	var plastic: Dictionary = disc.get("plastic", {})
	var stamp: Dictionary = disc.get("stamp", {})
	var foil: Array = stamp.get("color", [0.85, 0.86, 0.9])
	m.set_shader_parameter("base_color", Color(col[0], col[1], col[2]))
	m.set_shader_parameter("foil_color", Color(foil[0], foil[1], foil[2]))
	m.set_shader_parameter("foil_metal", float(stamp.get("metal", 0.9)))
	m.set_shader_parameter("rough", float(plastic.get("roughness", 0.4)))
	m.set_shader_parameter("coat", float(plastic.get("clearcoat", 0.3)))
	m.set_shader_parameter("wear", float(plastic.get("wear", 0.3)))
	m.set_shader_parameter("design", int(DESIGNS.get(str(stamp.get("design", "ring")), 0)))
	return m


static func _chaikin(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array([pts[0]])
	for i in pts.size() - 1:
		out.append(pts[i].lerp(pts[i + 1], 0.25))
		out.append(pts[i].lerp(pts[i + 1], 0.75))
	out.append(pts[pts.size() - 1])
	return out
