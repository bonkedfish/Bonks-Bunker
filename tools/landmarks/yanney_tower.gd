# YanneyTower — builds the John & Carmen Gottschalk Tower (80 ft observation tower, Yanney Park) into a
# LandmarkKit (D-047): red-brick shaft with slit windows, an open rusty steel stair cage on its south side with
# climbable switchback flights (ramps, ~33 deg) and landings, a railed top deck and a pyramid metal roof on posts,
# on a concrete plinth with low brick walls. Origin = shaft centre on the ground; entry from the west at the foot
# of the stair cage. Overgrown: weeds at the base, some railing segments missing (collision stays).
# Depends on: LandmarkKit.
extends RefCounted


static func build(k: LandmarkKit, d: Dictionary, palettes: Dictionary, rng: RandomNumberGenerator) -> void:
	var half := float(d.core_m) * 0.5
	var top := float(d.deck_y)
	var flights := int(d.flights)
	var rise := top / flights
	var land := float(d.landing_m)
	var run := float(d.flight_run_m)
	var cw := float(d.cage_width_m) * 0.5
	var z0 := half + 0.1                 # north landings: z0..z1 (against the shaft)
	var z1 := z0 + land
	var z2 := z1 + run                   # south landings: z2..z3
	var z3 := z2 + land
	var pad := float(d.pad_half_m)

	# Plinth: concrete pad + low brick walls with gaps for the entry (west) and paths (north, east).
	k.block(Vector3(-pad, -0.4, -pad), Vector3(pad, 0.06, z3 + 3.0), "concrete")
	k.block(Vector3(-pad, 0.0, -pad), Vector3(-1.5, 0.8, -pad + 0.4), "brick")
	k.block(Vector3(1.5, 0.0, -pad), Vector3(pad, 0.8, -pad + 0.4), "brick")
	k.block(Vector3(pad - 0.4, 0.0, -pad), Vector3(pad, 0.8, z3 + 3.0), "brick")
	k.block(Vector3(-pad, 0.0, z0 + 2.5), Vector3(-pad + 0.4, 0.8, z3 + 3.0), "brick")

	# Shaft with slit windows on three faces (dark glass set just proud of the brick).
	k.block(Vector3(-half, 0.0, -half), Vector3(half, top - 0.4, half), "brick")
	for y in [3.0, 8.0, 13.0, 17.5]:
		for f in [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
			var c: Vector3 = f * (half + 0.02) + Vector3.UP * (y + 1.4)
			var size := Vector3(0.04, 2.8, 0.4) if absf(f.x) > 0.5 else Vector3(0.4, 2.8, 0.04)
			k.box(c, size, "glass" if rng.randf() > 0.3 else "paint_dark", 0.0, false)
	k.block(Vector3(-half - 0.15, top - 1.2, -half - 0.15), Vector3(half + 0.15, top - 0.4, half + 0.15), "concrete", false)

	# Stair cage: corner columns, flights (ramps with step nosings), landings, divider, outer walls.
	for x in [-cw - 0.1, cw + 0.1]:
		for z in [z0, z3]:
			k.box(Vector3(x, (top + 1.2) * 0.5, z), Vector3(0.2, top + 1.2, 0.2), "rust", 0.0, false)
	for i in flights:
		var y0 := i * rise
		var y1 := (i + 1) * rise
		var left := i % 2 == 0
		var x := -cw * 0.5 if left else cw * 0.5
		var a := Vector3(x, y0, z1 if left else z2)
		var b := Vector3(x, y1, z2 if left else z1)
		k.ramp(a, b, cw - 0.1, 0.12, "steel")
		for s in range(1, 8):
			var p := a.lerp(b, s / 8.0)
			k.box(p + Vector3.UP * 0.03, Vector3(cw - 0.1, 0.05, 0.06), "rust", 0.0, false)
		var outer := Vector3(x + (-cw * 0.5 if left else cw * 0.5), 0, 0)
		if rng.randf() > 0.15:
			k.railing(PackedVector3Array([Vector3(outer.x, y0, a.z), Vector3(outer.x, y1, b.z)]), 1.0, "rust", 1.0, false)
	for j in range(1, flights + 1):
		var y := j * rise
		var south := j % 2 == 1
		k.block(Vector3(-cw, y - 0.14, z2 if south else z0), Vector3(cw, y, z3 if south else z1), "steel")
		var zr := z3 if south else z0
		if south:
			k.railing(PackedVector3Array([Vector3(-cw, y, zr), Vector3(cw, y, zr)]), 1.05, "rust", 1.2, false)
	k.block(Vector3(-0.04, 0.0, z1), Vector3(0.04, top, z2), "rust")  # divider between up/down flights
	# Outer cage walls (collision only, the railings show): east, south full; west open at the ground landing.
	k.block(Vector3(cw + 0.05, 0.0, z0), Vector3(cw + 0.15, top + 1.2, z3), "")
	k.block(Vector3(-cw, 0.0, z3 + 0.05), Vector3(cw, top + 1.2, z3 + 0.15), "")
	k.block(Vector3(-cw - 0.15, 2.3, z0), Vector3(-cw - 0.05, top + 1.2, z1), "")
	k.block(Vector3(-cw - 0.15, 0.0, z1), Vector3(-cw - 0.05, top + 1.2, z3), "")
	for y in range(2, int(top), 3):
		for x in [-cw - 0.1, cw + 0.1]:
			k.box(Vector3(x, y, (z0 + z3) * 0.5), Vector3(0.08, 0.08, z3 - z0), "rust", 0.0, false)
		k.box(Vector3(0, y, z3), Vector3(cw * 2.0, 0.08, 0.08), "rust", 0.0, false)

	# Top deck: slab around the shaft up to the stair hole; railings; roof on four posts.
	var dh := float(d.deck_half_m)
	k.block(Vector3(-dh, top - 0.4, -dh), Vector3(dh, top, z1), "concrete")
	var rail_y := top
	k.railing(PackedVector3Array([Vector3(-dh, rail_y, z1), Vector3(-dh, rail_y, -dh), Vector3(dh, rail_y, -dh),
		Vector3(dh, rail_y, z1)]), 1.1, "rust", 1.2)
	k.railing(PackedVector3Array([Vector3(-dh, rail_y, z1), Vector3(-cw, rail_y, z1)]), 1.1, "rust", 1.2)
	k.railing(PackedVector3Array([Vector3(cw, rail_y, z1), Vector3(dh, rail_y, z1)]), 1.1, "rust", 1.2)
	k.railing(PackedVector3Array([Vector3(-cw, rail_y, z1), Vector3(0.0, rail_y, z1)]), 1.1, "rust", 1.0)
	var ry := top + float(d.roof_posts_m)
	for x in [-dh + 0.15, dh - 0.15]:
		for z in [-dh + 0.15, z1 - 0.15]:
			k.box(Vector3(x, (top + ry) * 0.5, z), Vector3(0.22, ry - top, 0.22), "steel", 0.0, false)
	k.hip_roof(Vector2(-dh - 0.6, -dh - 0.6), Vector2(dh + 0.6, z1 + 0.6), ry, float(d.roof_rise_m), "roof_metal")

	# Weeds around the foot of the walls.
	for i in 14:
		var a := rng.randf() * TAU
		k.flowers(Vector3(cos(a) * (pad - 0.8), 0.0, sin(a) * (pad - 0.8)), 1.2, 10, palettes.wild, rng, "flowers")
