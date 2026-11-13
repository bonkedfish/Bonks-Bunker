# YanneyErc — builds The Environment Resource Center and the marina on Yanney Park Lake's west shore into a
# LandmarkKit (D-047): a weathered timber lodge on a stone base with a hipped metal roof and a window wall facing
# the lake (some panes broken), a plank deck, and a boardwalk dock on pilings running out over the water to a
# T-head, with abandoned paddle boats and canoes half sunk alongside. Solid building (not enterable).
# Origin = building centre on the ground; `yaw` turns the building's long axis (local +x) along long_axis_map.
# Depends on: LandmarkKit.
extends RefCounted


static func build(k: LandmarkKit, d: Dictionary, yaw: float, dock_from: Vector2, dock_to: Vector2,
		rng: RandomNumberGenerator) -> void:
	var s: Array = d.size
	var hx := float(s[0]) * 0.5
	var hz := float(s[1]) * 0.5
	var h := float(s[2])
	k.frame = Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO)
	k.block(Vector3(-hx, -0.3, -hz), Vector3(hx, 1.0, hz), "stone")
	k.block(Vector3(-hx + 0.2, 1.0, -hz + 0.2), Vector3(hx - 0.2, h, hz - 0.2), "planks")
	# Window wall on the lake side (-z): dark panes, some smashed (left out).
	var n := 9
	for i in n:
		if rng.randf() < 0.3:
			continue
		var x := -hx + 1.5 + (i + 0.5) * (hx * 2.0 - 3.0) / n
		k.box(Vector3(x, 1.0 + (h - 1.4) * 0.5 + 0.2, -hz + 0.17), Vector3((hx * 2.0 - 3.0) / n - 0.25, h - 1.6, 0.04), "glass", 0.0, false)
	k.hip_roof(Vector2(-hx - 0.9, -hz - 0.9), Vector2(hx + 0.9, hz + 0.9), h, float(d.roof_rise_m), "roof_metal", hx * 2.0 - hz * 2.0)
	k.block(Vector3(-hx + 2.0, -0.2, -hz - 5.0), Vector3(hx - 2.0, 0.6, -hz), "planks")  # lake-side deck
	k.frame = Transform3D.IDENTITY
	# Boardwalk dock + T-head on pilings.
	var dir := (dock_to - dock_from).normalized()
	var side := dir.orthogonal()
	var y := 0.55
	_deck(k, dock_from, dock_to, 2.6, y)
	var head := float(d.dock_head_m)
	_deck(k, dock_to - side * head * 0.5, dock_to + side * head * 0.5, 3.0, y)
	var length := dock_from.distance_to(dock_to)
	for i in int(length / 3.0) + 1:
		var p := dock_from + dir * i * 3.0
		for sg in [-1.0, 1.0]:
			var q: Vector2 = p + side * sg * 1.2
			k.cylinder(Vector3(q.x, -3.0, q.y), 0.14, 3.0 + y, "planks", 6)
	for i in int(head / 3.0) + 1:
		var p := dock_to - side * head * 0.5 + side * i * 3.0
		k.cylinder(Vector3(p.x, -3.0, p.y), 0.14, 3.0 + y, "planks", 6)
	# Abandoned boats along the T-head: tilted, half under water.
	for i in int(d.boats):
		var p := dock_to - side * head * 0.4 + side * (i + 0.5) * head * 0.8 / int(d.boats) + dir * (2.6 if i % 2 == 0 else -2.6)
		var tilt := rng.randf_range(0.15, 0.45)
		var by := rng.randf_range(-0.9, -0.3)
		var basis := Basis(Vector3.UP, atan2(dir.x, dir.y) + rng.randf_range(-0.4, 0.4)) * Basis(Vector3.FORWARD, tilt)
		var canoe := i % 2 == 1
		var size := Vector3(0.9, 0.45, 4.8) if canoe else Vector3(1.6, 0.6, 2.4)
		var mat: String = ["paint_red", "paint_yellow", "paint_blue"][rng.randi_range(0, 2)]
		k.box_xf(Transform3D(basis, Vector3(p.x, by, p.y)), size, mat, false, ["top"])
		k.box_xf(Transform3D(basis, Vector3(p.x, by, p.y) + basis.y * 0.05), Vector3(size.x - 0.12, size.y - 0.15, size.z - 0.12),
			"paint_dark", false, ["top"])
		if not canoe:
			k.box_xf(Transform3D(basis, Vector3(p.x, by, p.y) + basis.y * 0.45), Vector3(1.4, 0.06, 0.5), "steel", false)


static func _deck(k: LandmarkKit, a: Vector2, b: Vector2, w: float, y: float) -> void:
	var c := (a + b) * 0.5
	var d := b - a
	k.box(Vector3(c.x, y - 0.1, c.y), Vector3(w, 0.2, d.length()), "planks", atan2(d.x, d.y))
