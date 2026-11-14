# RvPark — builds the Kearney RV Park & Campground (D-079; 1140 E 1st St, beside I-80) into a LandmarkKit from
# data/landmarks/rv_park.json. Local frame = map axes (x east, z south), origin in the middle of the campground strip
# along the swim lake. Buildings (office + camp store, shower / laundry house, picnic shelter), the raider camp's
# props, signs, lights, loot and raider lair markers are data (LandmarkParts); this file adds the repeated pieces:
# gravel camp roads, concrete RV pads with hookup posts, parked RVs / trailers / pickups (some armoured with scrap by
# the raiders), dome tents with fire rings, picnic tables, and the beach sand.
# Depends on: LandmarkKit, landmark_parts.gd.
extends RefCounted

const Parts := preload("res://tools/landmarks/landmark_parts.gd")


static func build(k: LandmarkKit, d: Dictionary, rng: RandomNumberGenerator) -> void:
	var fy := float(d.dims.floor_y)
	Parts.build_all(k, d, "rv_park", fy)
	for r: Dictionary in d.roads:
		_road(k, r)
	for p: Array in d.pads:  # [x, z, yaw_deg]
		_pad(k, p)
	for v: Array in d.vehicles:  # [x, z, yaw_deg, kind, paint, armoured]
		_vehicle(k, v, rng)
	for t: Array in d.tents:  # [x, z, yaw_deg]
		_tent(k, t)
	for t: Array in d.picnic_tables:  # [x, z, yaw_deg]
		_table(k, t)
	for b: Array in d.sand:  # [[x, z], ...] polygon
		Parts.slab(k, {"poly": b, "y": 0.04, "mat": "sand"})


static func _road(k: LandmarkKit, r: Dictionary) -> void:
	var pts: Array = r.points
	var w := float(r.width) * 0.5
	for i in range(pts.size() - 1):
		var a := Vector2(pts[i][0], pts[i][1])
		var b := Vector2(pts[i + 1][0], pts[i + 1][1])
		var mid := (a + b) * 0.5
		var dir := b - a
		k.box(Vector3(mid.x, 0.02, mid.y), Vector3(w * 2.0, 0.08, dir.length() + w), str(r.mat), atan2(dir.x, dir.y), false)


static func _pad(k: LandmarkKit, p: Array) -> void:
	var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(p[2]))), Vector3(p[0], 0.0, p[1]))
	k.box_xf(xf.translated_local(Vector3(0, 0.06, 0)), Vector3(4.5, 0.14, 17.0), "concrete", false)
	k.box_xf(xf.translated_local(Vector3(-2.9, 0.6, 5.5)), Vector3(0.35, 1.2, 0.3), "hookup")  # power / water post


# kinds: class_a (motorhome), trailer, fifth_wheel, pickup, van
static func _vehicle(k: LandmarkKit, v: Array, rng: RandomNumberGenerator) -> void:
	var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(v[2]))), Vector3(v[0], 0.0, v[1]))
	var paint := str(v[4])
	var armour := bool(v[5])
	match str(v[3]):
		"class_a":
			k.box_xf(xf.translated_local(Vector3(0, 1.95, 0)), Vector3(2.55, 2.9, 11.0), paint)
			k.box_xf(xf.translated_local(Vector3(0, 1.45, -5.6)), Vector3(2.5, 1.9, 0.3), "window_dark", false)
			k.box_xf(xf.translated_local(Vector3(1.29, 2.3, 0.5)), Vector3(0.03, 0.7, 7.0), "window_dark", false)
			k.box_xf(xf.translated_local(Vector3(1.29, 1.6, 0)), Vector3(0.04, 0.18, 11.0), "stripe", false)
			_wheels(k, xf, [-3.8, 3.2], 1.2)
		"trailer":
			k.box_xf(xf.translated_local(Vector3(0, 1.75, 0)), Vector3(2.4, 2.6, 8.0), paint)
			k.box_xf(xf.translated_local(Vector3(0, 0.55, -4.8)), Vector3(0.2, 0.2, 1.6), "steel", false)  # tongue
			k.box_xf(xf.translated_local(Vector3(1.21, 2.2, 0.8)), Vector3(0.03, 0.6, 3.0), "window_dark", false)
			k.box_xf(xf.translated_local(Vector3(1.22, 1.3, 0)), Vector3(0.04, 0.15, 8.0), "stripe", false)
			_wheels(k, xf, [0.6], 1.15)
		"fifth_wheel":
			k.box_xf(xf.translated_local(Vector3(0, 1.85, 0.8)), Vector3(2.5, 2.8, 8.4), paint)
			k.box_xf(xf.translated_local(Vector3(0, 2.6, -4.4)), Vector3(2.5, 1.5, 2.0), paint)  # raised nose
			k.box_xf(xf.translated_local(Vector3(1.26, 2.3, 1.5)), Vector3(0.03, 0.6, 4.0), "window_dark", false)
			_wheels(k, xf, [2.4, 3.4], 1.2)
		"pickup":
			k.box_xf(xf.translated_local(Vector3(0, 0.85, 0.8)), Vector3(2.0, 0.9, 5.6), paint)
			k.box_xf(xf.translated_local(Vector3(0, 1.6, -0.2)), Vector3(1.9, 0.75, 1.8), paint)
			k.box_xf(xf.translated_local(Vector3(0, 1.62, -1.1)), Vector3(1.8, 0.55, 0.05), "window_dark", false)
			_wheels(k, xf, [-1.0, 2.6], 1.0)
		_:
			k.box_xf(xf.translated_local(Vector3(0, 1.2, 0)), Vector3(2.0, 1.9, 5.2), paint)
			k.box_xf(xf.translated_local(Vector3(0, 1.6, -2.61)), Vector3(1.8, 0.6, 0.03), "window_dark", false)
			_wheels(k, xf, [-1.6, 1.6], 1.0)
	if armour:  # raider scrap plating bolted along both sides + a sheet over the windscreen
		for side: float in [-1.0, 1.0]:
			for i in 3:
				var off := Vector3(side * 1.35, 1.2 + rng.randf_range(-0.2, 0.3), -3.0 + i * 3.0)
				k.box_xf(Transform3D(xf.basis * Basis(Vector3.FORWARD, rng.randf_range(-0.15, 0.15)), xf * off), Vector3(0.05, 1.4, 2.6), "scrap")
		k.box_xf(xf.translated_local(Vector3(0, 1.6, -5.75)), Vector3(2.3, 1.2, 0.06), "scrap", false)


static func _wheels(k: LandmarkKit, xf: Transform3D, zs: Array, half_track: float) -> void:
	for z: float in zs:
		for s: float in [-1.0, 1.0]:
			k.box_xf(xf.translated_local(Vector3(s * half_track, 0.4, z)), Vector3(0.3, 0.8, 0.8), "tyre", false)


static func _tent(k: LandmarkKit, t: Array) -> void:
	var c := Vector3(t[0], 0.0, t[1])
	k.sweep(c, PackedVector2Array([Vector2(0.0, 1.3), Vector2(1.1, 0.95), Vector2(1.6, 0.0)]), 0.0, TAU, 8, "tent", "tent")
	var yaw := deg_to_rad(float(t[2]))
	var ring := c + Vector3(sin(yaw), 0, cos(yaw)) * 3.5
	k.cylinder(ring, 0.6, 0.25, "stone", 8, false)
	k.disc(ring + Vector3(0, 0.05, 0), 0.5, "ash", 8)


static func _table(k: LandmarkKit, t: Array) -> void:
	var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(t[2]))), Vector3(t[0], 0.0, t[1]))
	k.box_xf(xf.translated_local(Vector3(0, 0.75, 0)), Vector3(0.8, 0.06, 1.9), "wood")
	for s: float in [-1.0, 1.0]:
		k.box_xf(xf.translated_local(Vector3(s * 0.7, 0.45, 0)), Vector3(0.3, 0.05, 1.9), "wood", false)
		k.box_xf(xf.translated_local(Vector3(0, 0.37, s * 0.7)), Vector3(1.6, 0.74, 0.08), "wood", false)
