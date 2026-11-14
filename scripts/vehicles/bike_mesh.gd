# BikeMesh — builds the motorcycle meshes in code (D-083, no downloads) from a bike's "shape" in
# data/vehicles/bikes.json: frame, swingarm, engine, fork, bars (wide / clip-ons / ape hangers), tank with a trim
# stripe, seat, fenders (dirt / moto / street / cruiser), side plates or a sport fairing with a screen, exhaust (high /
# low / under / dual), headlight, tail light. One vertex-coloured surface per (bike, colour scheme), built once and
# shared by every bike that looks the same; the two wheels are a separate shared mesh (one per bike model) so a ridden
# bike can spin them. Local frame: ground under the bike's middle at y 0, front = -Z, rear axle at +wheelbase/2.
# Presentation only. Depends on: BikeRules (bike data).
class_name BikeMesh
extends RefCounted

const SEGMENTS := 14

static var _bodies: Dictionary = {}  # "id:scheme" -> ArrayMesh
static var _wheels: Dictionary = {}  # id -> ArrayMesh (one wheel, axle along X)
static var _paint: StandardMaterial3D
static var _rubber: StandardMaterial3D


static func body(id: String, scheme: int) -> ArrayMesh:
	var key := "%s:%d" % [id, scheme]
	if not _bodies.has(key):
		_bodies[key] = _build_body(BikeRules.bike(id), scheme)
	return _bodies[key]


static func wheel(id: String) -> ArrayMesh:
	if not _wheels.has(id):
		_wheels[id] = _build_wheel(BikeRules.bike(id).shape)
	return _wheels[id]


# Rear and front axle positions in the bike's frame.
static func axles(id: String) -> Array[Vector3]:
	var sh: Dictionary = BikeRules.bike(id).shape
	var wb := float(sh.wheelbase)
	var r := float(sh.wheel_r)
	return [Vector3(0, r, wb * 0.5), Vector3(0, r, -wb * 0.5)]


static func _materials() -> void:
	if _paint != null:
		return
	_paint = StandardMaterial3D.new()
	_paint.vertex_color_use_as_albedo = true
	_paint.roughness = 0.4
	_paint.metallic = 0.35
	_rubber = StandardMaterial3D.new()
	_rubber.vertex_color_use_as_albedo = true
	_rubber.roughness = 0.85
	_paint.cull_mode = BaseMaterial3D.CULL_DISABLED  # code-built faces: either winding shows
	_rubber.cull_mode = BaseMaterial3D.CULL_DISABLED


static func _build_body(b: Dictionary, scheme: int) -> ArrayMesh:
	_materials()
	var sh: Dictionary = b.shape
	var schemes: Array = b.schemes
	var sc: Array = schemes[clampi(scheme, 0, schemes.size() - 1)]
	var paint := Color(sc[0][0], sc[0][1], sc[0][2])
	var trim := Color(sc[1][0], sc[1][1], sc[1][2])
	var frame := Color(sc[2][0], sc[2][1], sc[2][2])
	var dark := Color(0.07, 0.07, 0.08)
	var metal := Color(0.55, 0.56, 0.58)
	var chrome := Color(0.82, 0.83, 0.86)
	var wb := float(sh.wheelbase)
	var r := float(sh.wheel_r)
	var seat_h := float(sh.seat_h)
	var tank: Array = sh.tank
	var rear := Vector3(0, r, wb * 0.5)
	var front := Vector3(0, r, -wb * 0.5)
	var head := Vector3(0, seat_h + 0.1, -wb * 0.5 + 0.3)  # steering head
	var pivot := Vector3(0, r + 0.08, 0.12)  # swingarm pivot
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Frame: backbone from the head to the pivot, down tube under the engine, subframe under the seat.
	_beam(st, head, pivot + Vector3(0, 0.25, 0), 0.07, frame)
	_beam(st, head + Vector3(0, -0.12, 0.02), Vector3(0, r * 0.75, -0.12), 0.06, frame)
	_beam(st, pivot + Vector3(0, 0.25, 0), Vector3(0, seat_h - 0.05, wb * 0.5 - 0.05), 0.05, frame)
	# Swingarm (both sides) and shock.
	for x: float in [-0.1, 0.1]:
		_beam(st, pivot + Vector3(x, 0, 0), rear + Vector3(x, 0, 0), 0.05, frame)
	_beam(st, pivot + Vector3(0, 0.05, 0.12), Vector3(0, seat_h - 0.08, 0.25), 0.05, Color(0.75, 0.2, 0.1))
	# Engine block + cylinder(s).
	var eng_c := Vector3(0, r * 0.95, -0.08)
	_box(st, eng_c, Vector3(0.28, 0.3, 0.38), dark)
	_box(st, eng_c + Vector3(0, 0.22, -0.06), Vector3(0.24, 0.2, 0.2), metal)
	if str(b.engine) == "vtwin":
		_beam(st, eng_c + Vector3(0, 0.1, 0.0), eng_c + Vector3(0, 0.38, -0.2), 0.16, metal)
		_beam(st, eng_c + Vector3(0, 0.1, 0.05), eng_c + Vector3(0, 0.38, 0.22), 0.16, metal)
	# Fork tubes, triple clamp, bars.
	for x: float in [-0.09, 0.09]:
		_beam(st, front + Vector3(x, 0, 0), head + Vector3(x, 0.05, 0), 0.045, chrome if str(sh.fenders) == "cruiser" else Color(0.75, 0.6, 0.2) if str(sh.fenders) == "dirt" else metal)
	_box(st, head + Vector3(0, 0.07, 0), Vector3(0.24, 0.05, 0.1), metal)
	match str(sh.bars):
		"wide":
			_box(st, head + Vector3(0, 0.2, 0.06), Vector3(0.8, 0.03, 0.03), dark)
			for x: float in [-0.36, 0.36]:
				_box(st, head + Vector3(x, 0.2, 0.06), Vector3(0.1, 0.04, 0.04), Color(0.1, 0.1, 0.1))
		"clipons":
			for x: float in [-0.17, 0.17]:
				_beam(st, head + Vector3(x * 0.6, 0.04, 0), head + Vector3(x * 1.7, 0.0, 0.14), 0.035, dark)
		"ape":
			for x: float in [-0.3, 0.3]:
				_beam(st, head + Vector3(x * 0.4, 0.08, 0), head + Vector3(x, 0.45, 0.12), 0.03, chrome)
			_beam(st, head + Vector3(-0.3, 0.45, 0.12), head + Vector3(0.3, 0.45, 0.12), 0.03, chrome)
	# Tank with a trim stripe, seat.
	var tank_c := Vector3(0, seat_h + float(tank[1]) * 0.25, head.z + float(tank[0]) * 0.5 + 0.08)
	_box(st, tank_c, Vector3(float(tank[2]), float(tank[1]), float(tank[0])), paint)
	_box(st, tank_c + Vector3(0, float(tank[1]) * 0.5 + 0.005, 0), Vector3(float(tank[2]) * 0.3, 0.012, float(tank[0]) * 0.95), trim)
	var seat_z0 := tank_c.z + float(tank[0]) * 0.5 - 0.02
	var seat_len := (0.75 if str(sh.fenders) in ["dirt", "moto"] else 0.5)
	_box(st, Vector3(0, seat_h - 0.02, seat_z0 + seat_len * 0.5), Vector3(0.27, 0.09, seat_len), dark)
	# Fenders / tail.
	match str(sh.fenders):
		"dirt", "moto":
			_box(st, head + Vector3(0, -0.02, -0.22), Vector3(0.18, 0.03, 0.42), trim)  # high front fender
			_beam(st, Vector3(0, seat_h - 0.06, seat_z0 + seat_len - 0.05), Vector3(0, seat_h + 0.05, wb * 0.5 + 0.35), 0.16, trim)
			for x: float in [-0.16, 0.16]:  # number plates
				_box(st, Vector3(x, seat_h - 0.16, seat_z0 + 0.18), Vector3(0.02, 0.2, 0.3), paint)
		"street":
			_arc(st, front, r + 0.04, -0.4, 0.9, 0.13, paint)
			_box(st, Vector3(0, seat_h + 0.02, seat_z0 + seat_len + 0.12), Vector3(0.22, 0.1, 0.3), paint)  # tail hump
		"cruiser":
			_arc(st, front, r + 0.05, -0.6, 1.0, 0.17, paint)
			_arc(st, rear, r + 0.06, -1.6, 0.4, 0.2, paint)
			_box(st, Vector3(0, seat_h + 0.05, seat_z0 + 0.3), Vector3(0.3, 0.12, 0.2), dark)  # back of the seat
	# Fairing (sport).
	if bool(sh.fairing):
		_box(st, head + Vector3(0, 0.0, -0.12), Vector3(0.42, 0.34, 0.3), paint)
		_beam(st, head + Vector3(0, 0.15, -0.2), head + Vector3(0, 0.32, -0.02), 0.32, Color(0.15, 0.17, 0.2))  # screen
		for x: float in [-0.17, 0.17]:
			_box(st, Vector3(x, r + 0.1, -0.15), Vector3(0.04, 0.42, 0.75), paint)
			_box(st, Vector3(x * 1.02, r + 0.02, -0.15), Vector3(0.03, 0.06, 0.7), trim)
	# Exhaust.
	match str(sh.exhaust):
		"high":
			_beam(st, eng_c + Vector3(0.12, 0.15, -0.1), Vector3(0.17, seat_h - 0.1, 0.2), 0.06, metal)
			_beam(st, Vector3(0.17, seat_h - 0.1, 0.2), Vector3(0.17, seat_h - 0.02, wb * 0.5 + 0.05), 0.1, Color(0.65, 0.66, 0.68))
		"low":
			_beam(st, eng_c + Vector3(0.12, -0.05, -0.1), Vector3(0.16, r * 0.6, wb * 0.5 + 0.15), 0.07, chrome)
		"under":
			_box(st, Vector3(0, r * 0.45, 0.15), Vector3(0.2, 0.12, 0.35), metal)
		"dual":
			for y: float in [0.0, 0.1]:
				_beam(st, eng_c + Vector3(0.14, -0.05 + y, -0.05), Vector3(0.2, r * 0.7 + y, wb * 0.5 + 0.25), 0.08, chrome)
	# Lights.
	_box(st, head + Vector3(0, 0.02 if bool(sh.fairing) else 0.12, -0.18 if bool(sh.fairing) else -0.1), Vector3(0.14, 0.11, 0.05), Color(0.95, 0.92, 0.75))
	_box(st, Vector3(0, seat_h + 0.02, wb * 0.5 + 0.12), Vector3(0.1, 0.05, 0.03), Color(0.85, 0.05, 0.05))
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, _paint)
	return mesh


static func _build_wheel(sh: Dictionary) -> ArrayMesh:
	_materials()
	var r := float(sh.wheel_r)
	var w := float(sh.wheel_w)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_disc(st, r, w, Color(0.06, 0.06, 0.06))                # tyre
	_disc(st, r * 0.72, w + 0.01, Color(0.5, 0.51, 0.53))   # rim face
	_disc(st, r * 0.14, w + 0.06, Color(0.75, 0.76, 0.78))  # hub
	for i in 6:  # spokes so the spin reads
		var a := TAU * i / 6.0
		var p := Vector3(0, sin(a), cos(a)) * r * 0.42
		st.set_color(Color(0.3, 0.31, 0.33))
		_box(st, p, Vector3(w + 0.012, 0.035, r * 0.6), Color(0.3, 0.31, 0.33), Basis(Vector3.RIGHT, -a))
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, _rubber)
	return mesh


# --- primitives ------------------------------------------------------------------------------------

static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color, basis := Basis.IDENTITY) -> void:
	st.set_color(col)
	var h := s * 0.5
	var p := [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1),
		Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]
	var faces := [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]
	for f: Array in faces:
		var q: Array[Vector3] = []
		for k: int in f:
			q.append(c + basis * (p[k] * h))
		for v: Vector3 in [q[0], q[1], q[2], q[0], q[2], q[3]]:
			st.add_vertex(v)


# A square tube of width w from a to b.
static func _beam(st: SurfaceTool, a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var d := b - a
	if d.length() < 0.001:
		return
	var z := d.normalized()
	var x := Vector3.UP.cross(z)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var y := z.cross(x).normalized()
	_box(st, (a + b) * 0.5, Vector3(w, w, d.length()), col, Basis(x, y, z))


# A cylinder of radius r, width w, axis along X, centred at the origin.
static func _disc(st: SurfaceTool, r: float, w: float, col: Color) -> void:
	st.set_color(col)
	var hw := w * 0.5
	for i in SEGMENTS:
		var a0 := TAU * i / SEGMENTS
		var a1 := TAU * (i + 1) / SEGMENTS
		var p0 := Vector3(0, sin(a0) * r, cos(a0) * r)
		var p1 := Vector3(0, sin(a1) * r, cos(a1) * r)
		var l0 := p0 + Vector3(-hw, 0, 0)
		var l1 := p1 + Vector3(-hw, 0, 0)
		var r0 := p0 + Vector3(hw, 0, 0)
		var r1 := p1 + Vector3(hw, 0, 0)
		for v: Vector3 in [l0, r0, r1, l0, r1, l1]:  # tread
			st.add_vertex(v)
		for v: Vector3 in [Vector3(-hw, 0, 0), l1, l0, Vector3(hw, 0, 0), r0, r1]:  # sides
			st.add_vertex(v)


# A curved fender: an arc of boxes around centre c (axle) of radius rad from angle a0 to a1 (0 = up, + = rearward).
static func _arc(st: SurfaceTool, c: Vector3, rad: float, a0: float, a1: float, w: float, col: Color) -> void:
	var n := 6
	for i in n:
		var a := lerpf(a0, a1, (i + 0.5) / n)
		var p := c + Vector3(0, cos(a), sin(a)) * rad
		_box(st, p, Vector3(w, 0.02, rad * (a1 - a0) / n * 1.1), col, Basis(Vector3.RIGHT, a))
