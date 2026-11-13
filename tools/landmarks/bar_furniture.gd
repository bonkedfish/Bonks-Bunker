# BarFurniture — furniture and raider props for the downtown bars (D-059, D-062), built from small LandmarkKit boxes
# and cylinders. One entry = {type, pos [x, z] | from/to [x, z], yaw (deg), ...} at floor height y. Types:
# counter, back_bar, stools, booth, table, pool_table, stage, jukebox, tv, couch, bunk, crates, kegs, ring, stalls,
# dartboard, shelf, sandbags, scrap_wall, tower, car_wreck, fire_barrel, tent, debris.
# Big pieces collide (box shapes); small clutter doesn't. Depends on: LandmarkKit.
extends RefCounted


static func add(k: LandmarkKit, f: Dictionary, y: float, rng: RandomNumberGenerator) -> void:
	var yaw := deg_to_rad(float(f.get("yaw", 0.0)))
	var p := Vector3(f.pos[0], y, f.pos[1]) if f.has("pos") else Vector3.ZERO
	var a := Vector3(f.from[0], y, f.from[1]) if f.has("from") else p
	var b := Vector3(f.to[0], y, f.to[1]) if f.has("to") else p
	match str(f.type):
		"counter":
			_along(k, a, b, 0.75, 1.1, 0.0, "wood_dark", true)
			_along(k, a, b, 0.9, 0.06, 1.1, "wood", false)
		"back_bar":
			_along(k, a, b, 0.45, 0.9, 0.0, "wood_dark", true)
			_along(k, a, b, 0.3, 0.04, 1.6, "wood", false)
			_along(k, a, b, 0.3, 0.04, 2.1, "wood", false)
			var n := int(a.distance_to(b) / 0.18)
			for i in n:
				var t := (i + 0.5) / n
				if rng.randf() < 0.35:
					continue
				var q := a.lerp(b, t)
				var shelf: float = [0.9, 1.64, 2.14][rng.randi_range(0, 2)]
				k.cylinder(q + Vector3(0, shelf, 0), 0.035, rng.randf_range(0.2, 0.3), ["glass_green", "glass_amber", "glass_clear"][rng.randi_range(0, 2)], 6)
		"stools":
			var n := int(f.get("n", 6))
			for i in n:
				var q := a.lerp(b, (i + 0.5) / n)
				k.cylinder(q, 0.04, 0.72, "steel", 6)
				k.box(q + Vector3(0, 0.75, 0), Vector3(0.36, 0.06, 0.36), "leather_red", 0.0, false)
		"booth":
			var bx := Basis(Vector3.UP, yaw)
			k.box(p + Vector3(0, 0.74, 0), Vector3(1.3, 0.05, 0.8), "wood", yaw)
			k.box(p + bx * Vector3(0, 0.37, 0), Vector3(0.15, 0.74, 0.15), "steel", yaw, false)
			for s: float in [-1.0, 1.0]:
				k.box(p + bx * Vector3(0, 0.25, s * 0.85), Vector3(1.4, 0.5, 0.55), str(f.get("mat", "leather_red")), yaw)
				k.box(p + bx * Vector3(0, 0.75, s * 1.08), Vector3(1.4, 1.0, 0.12), str(f.get("mat", "leather_red")), yaw)
		"table":
			k.box(p + Vector3(0, 0.74, 0), Vector3(0.85, 0.05, 0.85), "wood", yaw)
			k.box(p + Vector3(0, 0.37, 0), Vector3(0.1, 0.74, 0.1), "steel", yaw, false)
			for i in int(f.get("chairs", 3)):
				var ang := yaw + TAU * i / float(f.get("chairs", 3)) + rng.randf_range(-0.3, 0.3)
				var c := p + Vector3(sin(ang), 0, cos(ang)) * 0.75
				var tipped := rng.randf() < 0.25
				k.box(c + Vector3(0, 0.22 if tipped else 0.45, 0), Vector3(0.42, 0.06, 0.42), "wood_dark", ang, false)
				if not tipped:
					k.box(c + Vector3(sin(ang), 0, cos(ang)) * 0.2 + Vector3(0, 0.72, 0), Vector3(0.42, 0.5, 0.05), "wood_dark", ang, false)
		"pool_table":
			var bx := Basis(Vector3.UP, yaw)
			k.box(p + Vector3(0, 0.62, 0), Vector3(1.4, 0.28, 2.5), "wood_dark", yaw)
			k.box(p + Vector3(0, 0.77, 0), Vector3(1.2, 0.03, 2.3), "felt", yaw, false)
			for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				k.box(p + bx * Vector3(s.x * 0.55, 0.24, s.y * 1.1), Vector3(0.14, 0.48, 0.14), "wood_dark", yaw, false)
			k.box(p + bx * Vector3(0.75, 0.82, 0.4), Vector3(0.03, 0.03, 1.45), "wood", yaw + 0.2, false)  # a cue left on the rail
		"stage":
			var sz: Array = f.size
			var bx := Basis(Vector3.UP, yaw)
			k.box(p + Vector3(0, 0.3, 0), Vector3(sz[0], 0.6, sz[1]), "wood_dark", yaw)
			k.ramp(p + bx * Vector3(float(sz[0]) * 0.5 + 1.2, 0.0, float(sz[1]) * 0.5 - 0.6), p + bx * Vector3(float(sz[0]) * 0.5, 0.6, float(sz[1]) * 0.5 - 0.6), 1.0, 0.2, "wood_dark")
			var top := p + Vector3(0, 0.6, 0)
			for dr: Vector3 in [Vector3(0, 0, 0.6), Vector3(-0.6, 0, 0.4), Vector3(0.6, 0, 0.4), Vector3(0.3, 0, 1.0)]:
				k.cylinder(top + bx * dr, 0.28 if dr.z > 0.9 else 0.2, 0.45 if dr.z > 0.9 else 0.3, "drum", 10, false)
			for s: float in [-1.0, 1.0]:
				k.box(top + bx * Vector3(s * (float(sz[0]) * 0.5 - 0.6), 0.6, 0.2), Vector3(0.7, 1.2, 0.5), "metal_dark", yaw)
			k.cylinder(top + bx * Vector3(0, 0, -0.6), 0.02, 1.5, "steel", 6)
		"jukebox":
			k.box(p + Vector3(0, 0.8, 0), Vector3(0.8, 1.6, 0.5), "wood_dark", yaw)
			k.box(p + Basis(Vector3.UP, yaw) * Vector3(0, 1.1, -0.26), Vector3(0.6, 0.6, 0.02), "neon_pink", yaw, false)
		"tv":
			k.box(p + Vector3(0, float(f.get("y", 2.6)), 0), Vector3(1.3, 0.75, 0.1), "metal_dark", yaw, false)
		"couch":
			var bx := Basis(Vector3.UP, yaw)
			var m := str(f.get("mat", "leather_black"))
			k.box(p + Vector3(0, 0.25, 0), Vector3(2.0, 0.5, 0.85), m, yaw)
			k.box(p + bx * Vector3(0, 0.65, 0.35), Vector3(2.0, 0.6, 0.18), m, yaw, false)
			for s: float in [-1.0, 1.0]:
				k.box(p + bx * Vector3(s * 0.92, 0.45, 0), Vector3(0.18, 0.5, 0.85), m, yaw, false)
		"bunk":
			var bx := Basis(Vector3.UP, yaw)
			k.box(p + Vector3(0, 0.12, 0), Vector3(1.0, 0.24, 2.0), "wood", yaw)
			k.box(p + Vector3(0, 0.3, 0), Vector3(0.9, 0.14, 1.9), "mattress", yaw, false)
			k.box(p + bx * Vector3(0.05, 0.39, 0.2), Vector3(0.85, 0.05, 1.1), ["canvas", "canvas_b", "leather_red"][rng.randi_range(0, 2)], yaw + rng.randf_range(-0.2, 0.2), false)
		"crates":
			for i in int(f.get("n", 3)):
				var s := rng.randf_range(0.6, 1.0)
				var off := Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
				var stack := i >= 2 and rng.randf() < 0.5
				k.box(p + off * (0.4 if stack else 1.0) + Vector3(0, s * 0.5 + (0.9 if stack else 0.0), 0), Vector3(s, s, s), "wood", rng.randf() * TAU, not stack)
		"kegs":
			var n := int(f.get("n", 4))
			for i in n:
				k.cylinder(a.lerp(b, (i + 0.5) / n), 0.28, 0.6, "steel", 10, true)
		"ring":
			var sz: Array = f.size
			var hx := float(sz[0]) * 0.5
			var hz := float(sz[1]) * 0.5
			k.block(p + Vector3(-hx, 0.0, -hz), p + Vector3(hx, 0.04, hz), "mat_blue", false)
			for c: Vector2 in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]:
				k.cylinder(p + Vector3(c.x, 0, c.y), 0.08, 1.4, "rust", 6, true)
			for h: float in [0.5, 0.9, 1.3]:  # ropes on three sides; the front (-z) side is open
				k.railing(PackedVector3Array([p + Vector3(-hx, h - 1.0 + 0.0, -hz), p + Vector3(-hx, h - 1.0, hz), p + Vector3(hx, h - 1.0, hz), p + Vector3(hx, h - 1.0, -hz)]), 1.0, "rope", 99.0, h > 1.0)
		"stalls":
			var bx := Basis(Vector3.UP, yaw)
			for i in int(f.get("n", 2)):
				var c := p + bx * Vector3(i * 1.1, 0, 0)
				k.box(c + bx * Vector3(0.55, 1.0, 0), Vector3(0.05, 2.0, 1.5), "metal_dark", yaw)
				k.box(c + Vector3(0, 0.22, 0) + bx * Vector3(0, 0, 0.45), Vector3(0.4, 0.44, 0.55), "porcelain", yaw, false)
		"dartboard":
			k.disc(p + Vector3(0, 1.75, 0), 0.23, "drum", 12, Basis(Vector3.UP, yaw) * Vector3(0, 0, -1))
		"shelf":
			var bx := Basis(Vector3.UP, yaw)
			var w := float(f.get("w", 1.8))
			k.box(p + Vector3(0, 0.95, 0), Vector3(w, 1.9, 0.5), "metal_dark", yaw, true)
			for i in 6:
				k.box(p + bx * Vector3(rng.randf_range(-w * 0.4, w * 0.4), [0.35, 1.0, 1.6][i % 3], -0.1), Vector3(0.3, 0.25, 0.3), "canvas_b", yaw, false)
		"sandbags":
			var h := int(f.get("rows", 3))
			var n := maxi(1, int(a.distance_to(b) / 0.62))
			var dir := (b - a).normalized()
			var ang := atan2(dir.x, dir.z)
			for r in h:
				for i in n:
					var q := a.lerp(b, (i + 0.5 + (0.5 if r % 2 == 1 else 0.0)) / (n + 0.5))
					k.box(q + Vector3(0, 0.13 + r * 0.24, 0), Vector3(0.36, 0.24, 0.6), "sandbag", ang + rng.randf_range(-0.08, 0.08), false)
			_collider_only(k, a, b, 0.5, h * 0.24 + 0.05)
		"scrap_wall":
			var h := float(f.get("h", 2.6))
			var n := maxi(1, int(a.distance_to(b) / 1.1))
			var dir := (b - a).normalized()
			var ang := atan2(dir.x, dir.z)
			for i in n:
				var q := a.lerp(b, (i + 0.5) / n)
				var hh := h * rng.randf_range(0.8, 1.05)
				k.box(q + Vector3(0, hh * 0.5 - 0.3, 0), Vector3(0.06, hh + 0.3, 1.2), "rust" if i % 2 == 0 else "steel", ang + rng.randf_range(-0.08, 0.08), false)
			_collider_only(k, a, b, 0.3, h)
		"tower":
			var h := float(f.get("h", 4.0))
			for c: Vector2 in [Vector2(-1.3, -1.3), Vector2(1.3, -1.3), Vector2(1.3, 1.3), Vector2(-1.3, 1.3)]:
				k.box(p + Vector3(c.x, h * 0.5 - 0.5, c.y), Vector3(0.2, h + 1.0, 0.2), "wood_dark", 0.0, true)
			k.box(p + Vector3(0, h, 0), Vector3(3.0, 0.2, 3.0), "wood", 0.0, true)
			for s: Vector2 in [Vector2(0, -1.45), Vector2(0, 1.45), Vector2(-1.45, 0), Vector2(1.45, 0)]:
				k.box(p + Vector3(s.x, h + 0.55, s.y), Vector3(3.0 if s.x == 0 else 0.08, 0.9, 0.08 if s.x == 0 else 3.0), "rust", 0.0, true)
			k.box(p + Vector3(0, h * 0.5, 1.45), Vector3(0.5, h, 0.05), "wood_dark", 0.0, false)  # ladder look
		"car_wreck":
			var bx := Basis(Vector3.UP, yaw)
			var m := str(f.get("mat", "car_0"))
			k.box(p + Vector3(0, 0.55, 0), Vector3(1.8, 0.65, 4.3), m, yaw)
			k.box(p + bx * Vector3(0, 1.1, 0.2), Vector3(1.6, 0.5, 2.1), m, yaw, false)
			k.box(p + bx * Vector3(0, 1.12, 0.2), Vector3(1.62, 0.36, 2.0), "glass_dark", yaw, false)
			for s: Vector2 in [Vector2(-0.85, -1.4), Vector2(0.85, -1.4), Vector2(-0.85, 1.4), Vector2(0.85, 1.4)]:
				k.box(p + bx * Vector3(s.x, 0.3, s.y), Vector3(0.22, 0.6, 0.6), "tyre", yaw, false)
		"fire_barrel":
			k.cylinder(p, 0.3, 0.9, "rust", 10, true)
			k.disc(p + Vector3(0, 0.88, 0), 0.27, "fire", 10)
		"tent":
			var bx := Basis(Vector3.UP, yaw)
			var m := str(f.get("mat", "canvas"))
			var c := [bx * Vector3(-1.2, 0, -1.4), bx * Vector3(1.2, 0, -1.4), bx * Vector3(1.2, 0, 1.4), bx * Vector3(-1.2, 0, 1.4)]
			var ridge := [bx * Vector3(0, 1.5, -1.4), bx * Vector3(0, 1.5, 1.4)]
			k.quad(p + c[0], p + ridge[0], p + ridge[1], p + c[3], m)
			k.quad(p + c[1], p + c[2], p + ridge[1], p + ridge[0], m)
			k.tri(p + c[2], p + c[3], p + ridge[1], m)
		"debris":
			var sz: Array = f.size
			for i in int(f.get("n", 10)):
				var q := p + Vector3(rng.randf_range(-0.5, 0.5) * float(sz[0]), 0.06, rng.randf_range(-0.5, 0.5) * float(sz[1]))
				k.box(q, Vector3(rng.randf_range(0.15, 0.6), rng.randf_range(0.04, 0.15), rng.randf_range(0.15, 0.6)), "debris", rng.randf() * TAU, false)
		_:
			push_warning("BarFurniture: unknown type '%s'" % f.type)


# A run of box along a->b, `depth` thick, from y0 to y0+h above the floor (a and b already carry the floor y).
static func _along(k: LandmarkKit, a: Vector3, b: Vector3, depth: float, h: float, y0: float, mat: String, collide: bool) -> void:
	var dir := b - a
	k.box((a + b) * 0.5 + Vector3(0, y0 + h * 0.5, 0), Vector3(depth, h, dir.length()), mat, atan2(dir.x, dir.z), collide)


# One invisible box collider along a->b (keeps many small decorative pieces down to a single shape).
static func _collider_only(k: LandmarkKit, a: Vector3, b: Vector3, depth: float, h: float) -> void:
	var dir := b - a
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(depth, h, dir.length())
	shape.shape = box
	shape.transform = k.frame * Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), (a + b) * 0.5 + Vector3(0, h * 0.5, 0))
	k.body.add_child(shape)
