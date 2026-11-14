# BigApple — builds the Big Apple Fun Center (D-079; 500 W 4th St) into a LandmarkKit from
# data/landmarks/big_apple.json. Local frame = map axes (x east, z south), origin at the building's centre.
# Shell, rooms, furniture, burn damage, signs, lights, loot and lair markers are data (LandmarkParts); this file adds
# the repeated set pieces: the bowling centre (lanes, gutters, approaches, ball returns, pinsetter housings, masking
# panels, score monitors, a few racks of pins), rows of arcade cabinets, and the outdoor go-kart track (asphalt
# ribbon along a traced centre line, tyre stacks on both edges, parked karts).
# Depends on: LandmarkKit, landmark_parts.gd.
extends RefCounted

const Parts := preload("res://tools/landmarks/landmark_parts.gd")


static func build(k: LandmarkKit, d: Dictionary, rng: RandomNumberGenerator) -> void:
	var fy := float(d.dims.floor_y)
	Parts.build_all(k, d, "big_apple", fy)
	_bowling(k, d.bowling, fy, rng)
	for row: Dictionary in d.arcade_rows:
		_cabinets(k, row, fy, rng)
	_kart_track(k, d.kart_track, rng)


# Lanes run along z from the approach (z_approach) past the foul line (z_foul) to the pins (z_pins) and the pit.
static func _bowling(k: LandmarkKit, b: Dictionary, fy: float, rng: RandomNumberGenerator) -> void:
	var n := int(b.lanes)
	var x0 := float(b.x0)
	var pair := (float(b.x1) - x0) / (n / 2)
	var za := float(b.z_approach)
	var zf := float(b.z_foul)
	var zp := float(b.z_pins)
	var zb := float(b.z_back)
	var racked: Array = b.racked_lanes
	for p in n / 2:
		var px := x0 + p * pair
		k.box(Vector3(px + 1.56, fy + 0.35, (za + zf) * 0.5 - 0.6), Vector3(0.42, 0.7, 1.6), "ball_return")  # ball return
		k.box(Vector3(px + 1.56, fy + 2.9, zf - 2.5), Vector3(1.6, 0.9, 0.12), "monitor", 0.0, false)        # score monitor
		for side in 2:
			var lane := p * 2 + side
			var lx := px + 0.79 + side * 1.536  # lane 1.066 + two 0.235 gutters each; capping between pairs
			k.block(Vector3(lx - 0.53, fy, zf), Vector3(lx + 0.53, fy + 0.03, zp + 1.0), "lane", false)
			k.block(Vector3(lx - 0.53, fy, za), Vector3(lx + 0.53, fy + 0.02, zf), "approach", false)
			for g: float in [-0.65, 0.65]:
				k.block(Vector3(lx + g - 0.12, fy - 0.05, zf), Vector3(lx + g + 0.12, fy + 0.0, zp + 1.0), "gutter", false)
			k.block(Vector3(lx - 0.53, fy + 0.03, zf - 0.02), Vector3(lx + 0.53, fy + 0.035, zf + 0.02), "foul_line", false)
			if lane in racked:
				_pins(k, Vector3(lx, fy + 0.03, zp), rng, int(lane) % 3 == 0)
		k.block(Vector3(px - 0.08, fy, zf), Vector3(px + 0.08, fy + 0.25, zp + 1.0), "capping", false)
	# Pinsetter housings across the back with the masking panel above, solid so nobody walks into the machines.
	k.block(Vector3(x0, fy, zp + 1.0), Vector3(float(b.x1), fy + 2.0, zb), "machine")
	k.block(Vector3(x0, fy + 2.0, zp + 0.8), Vector3(float(b.x1), fy + 3.2, zp + 1.0), "masking", false)
	k.block(Vector3(x0, fy, za - 0.4), Vector3(float(b.x1), fy + 0.05, za), "approach", false)


static func _pins(k: LandmarkKit, head: Vector3, rng: RandomNumberGenerator, knocked: bool) -> void:
	var spots := [Vector2(0, 0), Vector2(-0.15, 0.26), Vector2(0.15, 0.26), Vector2(-0.3, 0.52), Vector2(0, 0.52),
		Vector2(0.3, 0.52), Vector2(-0.45, 0.78), Vector2(-0.15, 0.78), Vector2(0.15, 0.78), Vector2(0.45, 0.78)]
	for s: Vector2 in spots:
		var base := head + Vector3(s.x, 0.0, s.y)
		if knocked and rng.randf() < 0.6:
			k.box(base + Vector3(rng.randf_range(-0.2, 0.2), 0.06, 0.1), Vector3(0.38, 0.11, 0.11), "pin", rng.randf() * TAU, false)
			continue
		k.cylinder(base, 0.06, 0.38, "pin", 6)


# A straight row of cabinets (screen + marquee boxes), some knocked over or burned.
static func _cabinets(k: LandmarkKit, r: Dictionary, fy: float, rng: RandomNumberGenerator) -> void:
	var a := Vector2(r.a[0], r.a[1])
	var b := Vector2(r.b[0], r.b[1])
	var n := maxi(1, floori(a.distance_to(b) / float(r.spacing)))
	var yaw := deg_to_rad(float(r.yaw_deg))
	var burned := float(r.get("burned", 0.0))
	for i in n:
		var p := a.lerp(b, (i + 0.5) / n)
		var mat := "charred" if rng.randf() < burned else "cabinet"
		if rng.randf() < float(r.get("toppled", 0.0)):
			k.box_xf(Transform3D(Basis(Vector3.UP, yaw + rng.randf_range(-0.5, 0.5)) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(p.x, fy + 0.4, p.y)),
				Vector3(0.75, 1.8, 0.8), mat)
			continue
		var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, fy, p.y))
		k.box_xf(xf.translated_local(Vector3(0, 0.9, 0)), Vector3(0.75, 1.8, 0.8), mat)
		if mat == "cabinet":
			k.box_xf(xf.translated_local(Vector3(0, 1.25, -0.41)), Vector3(0.6, 0.5, 0.02), "screen", false)
			k.box_xf(xf.translated_local(Vector3(0, 1.7, -0.3)), Vector3(0.7, 0.2, 0.25), "marquee_glow", false)


static func _kart_track(k: LandmarkKit, t: Dictionary, rng: RandomNumberGenerator) -> void:
	var pts := PackedVector2Array()
	for p: Array in t.centre:
		pts.append(Vector2(p[0], p[1]))
	var w := float(t.width) * 0.5
	var y := float(t.y)
	var faces := PackedVector3Array()
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var na := _side(pts, i) * w
		var nb := _side(pts, (i + 1) % n) * w
		var q := [Vector3(a.x + na.x, y, a.y + na.y), Vector3(b.x + nb.x, y, b.y + nb.y), Vector3(b.x - nb.x, y, b.y - nb.y), Vector3(a.x - na.x, y, a.y - na.y)]
		k.quad(q[0], q[1], q[2], q[3], "asphalt")
		faces.append_array(PackedVector3Array([q[0], q[1], q[2], q[0], q[2], q[3]]))
		var seg_len := a.distance_to(b)
		var m := maxi(1, floori(seg_len / float(t.tyre_m)))
		for j in m:
			var c := a.lerp(b, float(j) / m)
			var s := _side(pts, i)
			for side: float in [-1.0, 1.0]:
				var tp := c + s * side * (w + 0.4)
				k.cylinder(Vector3(tp.x, y, tp.y), 0.32, 0.55, "tyre", 7, true)
	k.trimesh(faces)
	for kp: Array in t.karts:  # [x, z, yaw_deg]
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(kp[2]))), Vector3(kp[0], y, kp[1]))
		k.box_xf(xf.translated_local(Vector3(0, 0.25, 0)), Vector3(1.1, 0.3, 1.9), "kart" if rng.randf() < 0.7 else "kart_b")
		k.box_xf(xf.translated_local(Vector3(0, 0.55, 0.25)), Vector3(0.5, 0.5, 0.15), "tyre", false)


static func _side(pts: PackedVector2Array, i: int) -> Vector2:
	var n := pts.size()
	var d := (pts[(i + 1) % n] - pts[(i - 1 + n) % n]).normalized()
	return Vector2(-d.y, d.x)
