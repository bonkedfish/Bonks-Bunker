# YanneySplashground — builds the Yanney Park Splashground into a LandmarkKit (D-047): a round concrete pad with
# faded coloured rubber circles, dry spray arches, posts with tipping buckets, a spray mushroom, benches round the
# edge and a low fence ring with gaps. Long dry and rusting; weeds pushing through the pad.
# Origin = pad centre on the ground. Depends on: LandmarkKit.
extends RefCounted


static func build(k: LandmarkKit, d: Dictionary, palettes: Dictionary, rng: RandomNumberGenerator) -> void:
	var r := float(d.radius_m)
	k.disc(Vector3(0, 0.05, 0), r, "path", 32)
	var paints := ["paint_blue", "paint_yellow", "paint_red"]
	for i in 5:
		var a := rng.randf() * TAU
		var p := Vector3(cos(a), 0, sin(a)) * rng.randf_range(2.0, r - 4.0)
		k.disc(p + Vector3.UP * 0.06, rng.randf_range(1.5, 3.0), paints[i % 3], 16)
	# Spray arches: half-rings of pipe.
	for i in 3:
		var a := TAU * i / 3.0 + 0.4
		var c := Vector3(cos(a), 0, sin(a)) * r * 0.55
		var yaw := a + PI * 0.5
		var prev := Vector3.INF
		for j in 9:
			var t := PI * j / 8.0
			var p := c + Basis(Vector3.UP, yaw) * Vector3(cos(t) * 2.2, sin(t) * 2.6, 0)
			if prev != Vector3.INF:
				var mid := (prev + p) * 0.5
				var dd := p - prev
				var bx := dd.normalized()
				var bz := Basis(Vector3.UP, yaw) * Vector3(0, 0, 1)
				k.box_xf(Transform3D(Basis(bx, bz.cross(bx), bz), mid), Vector3(dd.length() + 0.05, 0.16, 0.16),
					paints[(i + 1) % 3], false)
			prev = p
		k.box(c + Basis(Vector3.UP, yaw) * Vector3(-2.2, 0.3, 0), Vector3(0.3, 0.6, 0.3), "steel")
		k.box(c + Basis(Vector3.UP, yaw) * Vector3(2.2, 0.3, 0), Vector3(0.3, 0.6, 0.3), "steel")
	# Bucket posts.
	for i in 4:
		var a := TAU * i / 4.0 + 1.1
		var p := Vector3(cos(a), 0, sin(a)) * r * 0.3
		k.cylinder(p, 0.12, 3.5, "rust", 6, true)
		k.box(p + Vector3(0.6, 3.6, 0), Vector3(1.4, 0.12, 0.12), "rust", a, false)
		k.box(p + Basis(Vector3.UP, a) * Vector3(1.2, 3.1, 0), Vector3(0.7, 0.7, 0.7), paints[i % 3], rng.randf(), false)
	# Spray mushroom in the middle.
	k.cylinder(Vector3.ZERO, 0.35, 3.0, "paint_blue", 8, true)
	k.disc(Vector3(0, 3.0, 0), 2.4, "paint_yellow", 16)
	# Benches and a gapped fence round the edge.
	for i in 8:
		var a := TAU * i / 8.0
		var p := Vector3(cos(a), 0, sin(a)) * (r + 1.6)
		k.box(p + Vector3.UP * 0.45, Vector3(2.0, 0.08, 0.5), "planks", -a + PI * 0.5)
		k.box(p + Vector3.UP * 0.22, Vector3(0.1, 0.45, 0.4), "steel", -a + PI * 0.5, false)
	var pts := PackedVector3Array()
	for i in 41:
		var a := TAU * i / 40.0
		var p := Vector3(cos(a), 0, sin(a)) * (r + 3.5)
		if i % 10 == 0 or (i % 10 == 1) or rng.randf() < 0.1:
			if pts.size() > 1:
				k.railing(pts, 1.0, "rust", 2.0)
			pts = PackedVector3Array()
			continue
		pts.append(p)
	if pts.size() > 1:
		k.railing(pts, 1.0, "rust", 2.0)
	# Weeds through the cracks.
	for i in 30:
		var a := rng.randf() * TAU
		var p := Vector3(cos(a), 0, sin(a)) * sqrt(rng.randf()) * r
		k.flowers(p + Vector3.UP * 0.05, 0.6, 5, palettes.wild, rng, "flowers", Vector2(0.2, 0.6))
