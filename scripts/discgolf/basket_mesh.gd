# BasketMesh — realistic disc golf baskets (D-117), presentation only, built from a basket style in
# data/discgolf/course_looks.json: the pole with its ground sleeve, the wire tray (top rim, uprights, hoops, floor,
# support collar), the chain band with its spokes and cap, and the chain tiers - in the near version every chain is
# real links (alternating 90 degrees, hanging with a little sag and twist round the pole), in the far version flat
# strips. Steel is vertex-coloured galvanised grey with rust where water sits (tray floor, pole foot, chain ends) by
# `wear`; the band is its own glowing surface (D-076). Origin = the basket's base on the ground. One mesh per
# style / wear / detail, shared by every basket of that course. Depends on: nothing (data passed in).
extends RefCounted

static var _cache: Dictionary = {}


static func mesh(style: Dictionary, metal: Dictionary, link: Dictionary, wear: float, near: bool) -> ArrayMesh:
	var key := "%d|%.2f|%s" % [style.hash(), wear, near]
	if not _cache.has(key):
		_cache[key] = _build(style, metal, link, wear, near)
	return _cache[key]


static func _build(s: Dictionary, metal: Dictionary, link: Dictionary, wear: float, near: bool) -> ArrayMesh:
	var steel := _col(metal.color)
	var chain := _col(metal.chain)
	var rust := _col(metal.rust)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pole_r := float(s.pole_r)
	var tray_r := float(s.tray_r)
	var y0 := float(s.tray_bottom)
	var y1 := float(s.tray_top)
	var sides := 12 if near else 8
	var paint := func(p: Vector3, base: Color) -> Color:  # rust: more low down, in patches
		var low := clampf(1.0 - p.y / 1.0, 0.0, 1.0)
		var k := clampf((_noise(p * 9.0) * 0.8 + low * 0.5 - 0.55) * 2.2, 0.0, 1.0) * wear
		return base.lerp(rust, k)
	# pole + ground sleeve + cap
	_cyl(st, Vector3(0, -0.3, 0), float(s.pole_top) + 0.3, pole_r, pole_r, sides, steel, paint)
	_cyl(st, Vector3(0, -0.05, 0), 0.17, pole_r * 1.5, pole_r * 1.5, sides, steel.darkened(0.15), paint)
	_cyl(st, Vector3(0, float(s.pole_top), 0), 0.03, pole_r * 1.3, pole_r * 0.4, sides, steel, paint)
	# tray: floor, collar under it, rims, uprights, hoops
	_disc(st, Vector3(0, y0, 0), tray_r * 0.97, 24 if near else 14, steel.darkened(0.1), paint, true)
	_cyl(st, Vector3(0, y0 - 0.09, 0), 0.09, pole_r * 1.4, tray_r * 0.4, sides, steel, paint)
	if near:
		_ring(st, Vector3(0, y1, 0), tray_r, 0.007, 32, 5, steel, paint)
		_ring(st, Vector3(0, y0 + 0.01, 0), tray_r * 0.97, 0.006, 32, 5, steel, paint)
		for h: Variant in s.get("hoops", []):
			_ring(st, Vector3(0, float(h), 0), lerpf(tray_r * 0.97, tray_r, (float(h) - y0) / (y1 - y0)), 0.0045, 32, 4, steel, paint)
		var bars := int(s.tray_bars)
		for i in bars:
			var a := TAU * i / bars
			var bot := Vector3(cos(a) * tray_r * 0.97, y0, sin(a) * tray_r * 0.97)
			var top := Vector3(cos(a) * tray_r, y1, sin(a) * tray_r)
			_rod(st, bot, top, 0.0045, 5, steel, paint)
	else:
		_cyl(st, Vector3(0, y0, 0), y1 - y0, tray_r * 0.97, tray_r, 16, steel, paint, true)
	# band spokes + lips (the band itself is surface 1)
	var band_r := float(s.band_r)
	var b0 := float(s.band_bottom)
	var b1 := float(s.band_top)
	var spokes := int(s.get("spokes", 6))
	for i in spokes:
		var a := TAU * (i + 0.5) / spokes
		_rod(st, Vector3(0, float(s.pole_top) - 0.04, 0), Vector3(cos(a) * band_r, b1, sin(a) * band_r), 0.006, 4, steel, paint)
	if near:
		_ring(st, Vector3(0, b1, 0), band_r, 0.006, 32, 4, steel, paint)
		_ring(st, Vector3(0, b0, 0), band_r, 0.006, 32, 4, steel, paint)
	# chains
	for tier: Dictionary in s.tiers:
		var n := int(tier.count)
		for i in n:
			var a := TAU * (i + (0.5 if tier.top_r < band_r * 0.7 else 0.0)) / n
			var a2 := a + deg_to_rad(float(tier.get("twist_deg", 0.0)))
			var top := Vector3(cos(a) * float(tier.top_r), b0 - 0.01, sin(a) * float(tier.top_r))
			var bot := Vector3(cos(a2) * float(tier.bottom_r), float(tier.bottom_y), sin(a2) * float(tier.bottom_r))
			var out := Vector3(cos(a), 0, sin(a))
			if near:
				_chain(st, top, bot, out * float(tier.sag), link, chain, paint)
			else:
				_strip(st, top, (top + bot) * 0.5 + out * float(tier.sag), 0.011, chain)
				_strip(st, (top + bot) * 0.5 + out * float(tier.sag), bot, 0.011, chain)
	var m := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.metallic = 0.7
	mat.roughness = 0.45
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # thin wire and strips: lit from both sides
	m.surface_set_material(0, mat)
	var band := SurfaceTool.new()  # the chain band: its own glowing surface so the basket stands out (D-076)
	band.begin(Mesh.PRIMITIVE_TRIANGLES)
	var yellow := _col(metal.band)
	var faded := func(p: Vector3, c: Color) -> Color:  # weathered paint: darker patches
		return c.lerp(c.darkened(0.45), clampf((_noise(p * 14.0) - 0.6) * 3.0, 0.0, 1.0) * wear)
	_cyl(band, Vector3(0, b0, 0), b1 - b0, band_r, band_r, 32 if near else 16, yellow, faded, true)
	band.commit(m)
	var glow := StandardMaterial3D.new()
	glow.vertex_color_use_as_albedo = true
	glow.emission_enabled = true
	glow.emission = yellow
	glow.emission_energy_multiplier = 2.0
	glow.metallic = 0.2
	glow.roughness = 0.5
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.surface_set_material(1, glow)
	return m


# A chain from `a` to `b` hanging out by `sag` at its middle, link by link.
static func _chain(st: SurfaceTool, a: Vector3, b: Vector3, sag: Vector3, link: Dictionary, col: Color, paint: Callable) -> void:
	var pitch := float(link.pitch_m)
	var steps := 24
	var pts := PackedVector3Array()
	var length := 0.0
	for i in steps + 1:
		var u := float(i) / steps
		pts.append(a.lerp(b, u) + sag * sin(PI * u))
		if i > 0:
			length += pts[i].distance_to(pts[i - 1])
	var count := maxi(2, floori(length / pitch))
	var seg := 0
	var walked := 0.0
	for k in count:
		var want := (k + 0.5) * length / count
		while seg < steps - 1 and walked + pts[seg].distance_to(pts[seg + 1]) < want:
			walked += pts[seg].distance_to(pts[seg + 1])
			seg += 1
		var seg_len := pts[seg].distance_to(pts[seg + 1])
		var c := pts[seg].lerp(pts[seg + 1], clampf((want - walked) / maxf(seg_len, 0.0001), 0.0, 1.0))
		var t := (pts[seg + 1] - pts[seg]).normalized()
		var side := t.cross(Vector3.UP).normalized() if absf(t.y) < 0.99 else Vector3.RIGHT
		if k % 2 == 1:
			side = side.rotated(t, PI * 0.5)
		_link(st, c, t, side, float(link.length_m), float(link.width_m), float(link.wire_m), paint.call(c, col))


# One oval link centred at c, long along t, wide along side.
static func _link(st: SurfaceTool, c: Vector3, t: Vector3, side: Vector3, length: float, width: float, wire: float, col: Color) -> void:
	const RING := 6
	const TUBE := 3
	var plane_n := side.cross(t).normalized()
	st.set_color(col)
	for i in RING:
		for j in TUBE:
			var quad := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]
			for q: int in [0, 1, 2, 0, 2, 3]:
				var th := TAU * float(quad[q][0]) / RING
				var ph := TAU * float(quad[q][1]) / TUBE
				var centre := side * (width * 0.5 - wire) * cos(th) + t * (length * 0.5 - wire) * sin(th)
				var radial := centre.normalized() if centre.length() > 0.0001 else side
				var n := radial * cos(ph) + plane_n * sin(ph)
				st.set_normal(n)
				st.add_vertex(c + centre + n * wire)


static func _cyl(st: SurfaceTool, base: Vector3, h: float, r0: float, r1: float, sides: int, col: Color, paint: Callable,
		_open := true) -> void:
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var ps := [base + Vector3(cos(a0) * r0, 0, sin(a0) * r0), base + Vector3(cos(a0) * r1, h, sin(a0) * r1),
			base + Vector3(cos(a1) * r1, h, sin(a1) * r1), base + Vector3(cos(a1) * r0, 0, sin(a1) * r0)]
		var ns := [Vector3(cos(a0), 0, sin(a0)), Vector3(cos(a0), 0, sin(a0)), Vector3(cos(a1), 0, sin(a1)), Vector3(cos(a1), 0, sin(a1))]
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(paint.call(ps[k], col))
			st.set_normal(ns[k])
			st.add_vertex(ps[k])


static func _disc(st: SurfaceTool, c: Vector3, r: float, sides: int, col: Color, paint: Callable, _both := true) -> void:
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var ps := [c, c + Vector3(cos(a1) * r, 0, sin(a1) * r), c + Vector3(cos(a0) * r, 0, sin(a0) * r)]
		for p: Vector3 in ps:
			st.set_color(paint.call(p, col))
			st.set_normal(Vector3.UP)
			st.add_vertex(p)


# A thin torus round the vertical axis at centre c.
static func _ring(st: SurfaceTool, c: Vector3, r: float, wire: float, seg: int, tube: int, col: Color, paint: Callable) -> void:
	for i in seg:
		for j in tube:
			var quad := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]
			for q: int in [0, 1, 2, 0, 2, 3]:
				var a := TAU * float(quad[q][0]) / seg
				var ph := TAU * float(quad[q][1]) / tube
				var radial := Vector3(cos(a), 0, sin(a))
				var n := radial * cos(ph) + Vector3.UP * sin(ph)
				var p := c + radial * r + n * wire
				st.set_color(paint.call(p, col))
				st.set_normal(n)
				st.add_vertex(p)


# A thin round bar from a to b.
static func _rod(st: SurfaceTool, a: Vector3, b: Vector3, r: float, sides: int, col: Color, paint: Callable) -> void:
	var t := (b - a).normalized()
	var u := t.cross(Vector3.UP if absf(t.y) < 0.95 else Vector3.RIGHT).normalized()
	var v := t.cross(u)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var n0 := u * cos(a0) + v * sin(a0)
		var n1 := u * cos(a1) + v * sin(a1)
		var ps := [a + n0 * r, b + n0 * r, b + n1 * r, a + n1 * r]
		var ns := [n0, n0, n1, n1]
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(paint.call(ps[k], col))
			st.set_normal(ns[k])
			st.add_vertex(ps[k])


static func _strip(st: SurfaceTool, a: Vector3, b: Vector3, w: float, col: Color) -> void:
	st.set_color(col)
	var flat := Vector3(a.x, 0, a.z)
	var side := (b - a).cross(flat.normalized() if flat.length() > 0.01 else Vector3.RIGHT).normalized() * w
	var n := side.cross(b - a).normalized()
	for p: Vector3 in [a - side, b - side, b + side, a - side, b + side, a + side]:
		st.set_normal(n)
		st.add_vertex(p)


# Smooth value noise 0..1 (deterministic, so every peer builds the same basket).
static func _noise(p: Vector3) -> float:
	var i := p.floor()
	var f := p - i
	f = f * f * (Vector3(3, 3, 3) - 2.0 * f)
	var n := 0.0
	for dz in 2:
		for dy in 2:
			for dx in 2:
				var w := (f.x if dx else 1.0 - f.x) * (f.y if dy else 1.0 - f.y) * (f.z if dz else 1.0 - f.z)
				n += w * _hash(i + Vector3(dx, dy, dz))
	return n


static func _hash(p: Vector3) -> float:
	var h := sin(p.x * 127.1 + p.y * 311.7 + p.z * 74.7) * 43758.5453
	return h - floorf(h)


static func _col(a: Array) -> Color:
	return Color(float(a[0]), float(a[1]), float(a[2]))
