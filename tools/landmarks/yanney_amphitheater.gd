# YanneyAmphitheater — builds the Yanney Park lakeside amphitheater into a LandmarkKit (D-047): a raised concrete
# stage under a quarter-dome band shell (blue/metal panels, rust rim arch), a side ramp, two rusting lighting trusses, and a terraced lawn
# bowl (grass treads, concrete risers built as walkable ramps) fanning out in front of the stage. Built facing -Z,
# turned by `yaw` toward faces_map_xz. Origin = stage centre on the ground. Overgrown: weeds on the tiers.
# Depends on: LandmarkKit.
extends RefCounted


static func build(k: LandmarkKit, d: Dictionary, yaw: float, palettes: Dictionary, rng: RandomNumberGenerator) -> void:
	k.frame = Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO)
	var s: Array = d.stage
	var hw := float(s[0]) * 0.5
	var depth := float(s[1])
	var sh := float(s[2])
	var front := -depth * 0.5
	var back := depth * 0.5
	# Stage platform + side ramp.
	k.block(Vector3(-hw, -0.3, front), Vector3(hw, sh, back), "concrete")
	k.ramp(Vector3(hw + 5.0, 0.0, back - 2.0), Vector3(hw, sh, back - 2.0), 2.4, 0.2, "concrete")
	# Band shell: a quarter-ellipsoid dome over the stage, open toward the bowl, in alternating panels with a
	# rusty rim arch at the front.
	var centre_s := Vector3(0, sh, front + 1.0)
	var rx := hw + 1.0
	var rz := depth - 1.5
	var ry := 8.5
	var lon_n := 14
	var lat_n := 7
	var shell_faces := PackedVector3Array()
	for i in lon_n:
		for j in lat_n:
			var q := [_dome(centre_s, rx, ry, rz, i, j, lon_n, lat_n), _dome(centre_s, rx, ry, rz, i + 1, j, lon_n, lat_n),
				_dome(centre_s, rx, ry, rz, i + 1, j + 1, lon_n, lat_n), _dome(centre_s, rx, ry, rz, i, j + 1, lon_n, lat_n)]
			k.quad(q[0], q[3], q[2], q[1], "shell_blue" if i % 2 == 0 else "roof_metal")
			shell_faces.append_array(PackedVector3Array([q[0], q[1], q[2], q[0], q[2], q[3]]))
	k.trimesh(shell_faces)
	var prev := Vector3.INF
	for i in lon_n + 1:
		var p := _rim(centre_s, rx, ry, i, lon_n)
		if prev != Vector3.INF:
			var seg := p - prev
			var bx := seg.normalized()
			k.box_xf(Transform3D(Basis(bx, Vector3.BACK.cross(bx), Vector3.BACK), (p + prev) * 0.5), Vector3(seg.length() + 0.1, 0.35, 0.5),
				"rust", false)
		prev = p
	# Lighting trusses either side.
	for x in [-hw - 7.0, hw + 9.0]:
		k.cylinder(Vector3(x, 0, front - 2.0), 0.25, 11.0, "rust", 6, true)
		k.box(Vector3(x, 11.0, front - 2.0), Vector3(3.0, 0.6, 0.8), "steel", 0.0, false)
	# Terraced lawn bowl in front of the stage.
	var r := float(d.bowl_inner_m)
	var prof := PackedVector2Array([Vector2(r - 2.0, 0.0), Vector2(r, 0.0)])
	var h := 0.0
	for i in int(d.tiers):
		r += float(d.tier_tread_m)
		prof.append(Vector2(r, h))
		r += float(d.tier_ramp_m)
		h += float(d.tier_rise_m)
		prof.append(Vector2(r, h))
	r += 2.0
	prof.append(Vector2(r, h))
	r += h * 3.0
	prof.append(Vector2(r, 0.0))
	var half := deg_to_rad(float(d.bowl_half_angle_deg))
	var centre := Vector3(0, 0, front)
	k.sweep(centre, prof, -PI * 0.5 - half, -PI * 0.5 + half, 24, "grass", "concrete")
	# Side walls closing the bowl ends.
	for a: float in [-PI * 0.5 - half, -PI * 0.5 + half]:
		var dir := Vector3(cos(a), 0, sin(a))
		var faces := PackedVector3Array()
		for i in range(prof.size() - 1):
			var p := prof[i]
			var q := prof[i + 1]
			var v := [centre + dir * p.x + Vector3.UP * p.y, centre + dir * q.x + Vector3.UP * q.y,
				centre + dir * q.x + Vector3.DOWN * 0.4, centre + dir * p.x + Vector3.DOWN * 0.4]
			k.quad(v[0], v[1], v[2], v[3], "concrete")
			faces.append_array(PackedVector3Array([v[0], v[1], v[2], v[0], v[2], v[3]]))
		k.trimesh(faces)
	# Weeds on the tiers.
	for i in 60:
		var a := rng.randf_range(-PI * 0.5 - half + 0.05, -PI * 0.5 + half - 0.05)
		var rr := rng.randf_range(prof[1].x, prof[prof.size() - 3].x)
		var hh := _height(prof, rr)
		k.flowers(centre + Vector3(cos(a), 0, sin(a)) * rr + Vector3.UP * hh, 1.0, 8, palettes.wild, rng, "flowers")
	k.frame = Transform3D.IDENTITY


# Point on the dome: lon 0..lon_n sweeps left -> right across the opening, lat 0 = ground ring, lat_n = the back.
static func _dome(c: Vector3, rx: float, ry: float, rz: float, i: int, j: int, lon_n: int, lat_n: int) -> Vector3:
	var lon := PI * i / lon_n
	var lat := PI * 0.5 * j / lat_n
	return c + Vector3(-cos(lon) * rx * cos(lat), sin(lon) * ry * cos(lat), rz * sin(lat))


# Front rim arch (the dome's open edge).
static func _rim(c: Vector3, rx: float, ry: float, i: int, lon_n: int) -> Vector3:
	var lon := PI * i / lon_n
	return c + Vector3(-cos(lon) * rx, sin(lon) * ry, -0.2)


static func _height(prof: PackedVector2Array, r: float) -> float:
	for i in range(prof.size() - 1):
		if r >= prof[i].x and r <= prof[i + 1].x:
			return lerpf(prof[i].y, prof[i + 1].y, (r - prof[i].x) / maxf(prof[i + 1].x - prof[i].x, 0.001))
	return 0.0
