# PoiBuilding — builds one small walk-in POI into a LandmarkKit (D-056): a one-storey box (style wall material,
# 4.2 m walls, flat roof + parapet with an accent sign band), front on local -Z with a 2.4 m door and glass
# shopfront, one dim interior light, a little debris, and 3-6 loot containers laid out by style (store/pharmacy
# shelf rows, diner counter + booths, garage workbench + wreck, office desks + filing cabinets). Gas stations add
# a canopy with pumps out front. Origin = middle of the footprint on the ground. Returns the loot container count.
# Depends on: LandmarkKit, scenes/loot_container.tscn.
extends RefCounted

const LOOT := preload("res://scenes/loot_container.tscn")
const WALL_H := 4.2
const T := 0.3
const DOOR_HALF := 1.2
const DOOR_H := 2.6

static var _n := 0


static func build(k: LandmarkKit, key: String, kind: String, style: Dictionary, width: float, depth: float,
		sign_text: String, rng: RandomNumberGenerator) -> int:
	_n = 0
	var hw := width * 0.5
	var hd := depth * 0.5
	_shell(k, str(style.wall), hw, hd)
	_sign(k, sign_text, hw, hd)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.position = Vector3(0, WALL_H - 0.6, 0)
	light.light_color = Color(1.0, 0.82, 0.6)
	light.light_energy = 1.2
	light.omni_range = maxf(hw, hd) + 3.0
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 50.0
	light.distance_fade_length = 15.0
	k.root.add_child(light)
	var table := str(style.loot)
	match kind:
		"store", "pharmacy":
			_shelves(k, key, table, hw, hd, "Shelf" if kind == "store" else "Pharmacy Shelf")
			k.box(Vector3(-hw + 2.0, 0.5, -hd + 2.0), Vector3(2.4, 1.0, 0.7), "accent")
			_loot(k, key, "Register", table, Vector3(-hw + 2.0, 1.0, -hd + 2.0), Vector3(0.5, 0.3, 0.4))
		"gas_station":
			_shelves(k, key, table, hw, hd, "Shelf")
			_loot(k, key, "Counter", table, Vector3(-hw + 1.8, 0, -hd + 1.8), Vector3(2.0, 1.0, 0.7))
			_canopy(k, key, table, hw, hd)
		"diner":
			_loot(k, key, "Kitchen Counter", table, Vector3(0, 0, hd - 1.2), Vector3(minf(width - 3.0, 8.0), 1.0, 0.8))
			_loot(k, key, "Diner Fridge", "fridge", Vector3(hw - 1.0, 0, hd - 1.0), Vector3(1.0, 1.9, 0.8))
			var bx := -hw + 1.0
			while bx < hw - 2.5:
				k.box(Vector3(bx + 0.8, 0.4, -hd + 1.3), Vector3(1.4, 0.8, 0.6), "seat")
				k.box(Vector3(bx + 0.8, 0.75, -hd + 2.2), Vector3(1.2, 0.05, 0.8), "wood", 0.0, false)
				bx += 2.6
			_loot(k, key, "Tip Jar", table, Vector3(-hw + 1.2, 0, hd - 2.4), Vector3(0.6, 1.0, 0.6))
		"garage":
			_loot(k, key, "Workbench", table, Vector3(-hw + 0.7, 0, 0), Vector3(0.8, 1.0, minf(depth - 3.0, 4.0)))
			_loot(k, key, "Tool Chest", "toolbox", Vector3(hw - 0.8, 0, hd - 1.0), Vector3(1.0, 1.1, 0.6))
			_loot(k, key, "Parts Shelf", table, Vector3(0, 0, hd - 0.6), Vector3(minf(width - 4.0, 4.0), 1.8, 0.6))
			k.box(Vector3(hw * 0.25, 0.7, -hd * 0.1), Vector3(1.9, 1.1, 4.2), "steel")  # the car on the lift
			k.box(Vector3(hw * 0.25, 1.5, -hd * 0.1 + 0.4), Vector3(1.7, 0.7, 2.2), "steel")
		_:  # office
			var dx := -hw + 2.0
			while dx < hw - 1.5 and _n < 4:
				k.box(Vector3(dx, 0.75, 0.5), Vector3(1.4, 0.05, 0.8), "wood", 0.0, false)
				_loot(k, key, "Desk Drawer", table, Vector3(dx + 0.4, 0, 0.5), Vector3(0.45, 0.72, 0.7))
				dx += 3.0
			_loot(k, key, "Filing Cabinet", table, Vector3(hw - 0.6, 0, hd - 0.6), Vector3(0.6, 1.4, 0.6))
	for i in rng.randi_range(4, 8):
		var p := Vector3(rng.randf_range(-hw + 0.8, hw - 0.8), 0.1, rng.randf_range(-hd + 3.0, hd - 0.8))
		k.box(p, Vector3(rng.randf_range(0.2, 0.6), 0.2, rng.randf_range(0.2, 0.6)), "debris", rng.randf() * TAU, false)
	return _n


static func _shell(k: LandmarkKit, wall: String, hw: float, hd: float) -> void:
	k.block(Vector3(-hw, -1.5, -hd), Vector3(hw, 0.05, hd), "floor")
	k.block(Vector3(-hw, 0, hd - T), Vector3(hw, WALL_H, hd), wall)                # back
	k.block(Vector3(-hw, 0, -hd), Vector3(-hw + T, WALL_H, hd - T), wall)         # sides
	k.block(Vector3(hw - T, 0, -hd), Vector3(hw, WALL_H, hd - T), wall)
	# Front: low wall + glass shopfront either side of the door, header above.
	for s: float in [-1.0, 1.0]:
		var x0 := minf(s * DOOR_HALF, s * (hw - T))
		var x1 := maxf(s * DOOR_HALF, s * (hw - T))
		k.block(Vector3(x0, 0, -hd), Vector3(x1, 0.9, -hd + T), wall)
		k.block(Vector3(x0, 0.9, -hd + 0.1), Vector3(x1, 2.9, -hd + 0.18), "glass")
		k.block(Vector3(x0, 2.9, -hd), Vector3(x1, WALL_H, -hd + T), wall)
	k.block(Vector3(-DOOR_HALF, DOOR_H, -hd), Vector3(DOOR_HALF, WALL_H, -hd + T), wall)
	k.block(Vector3(-hw, WALL_H, -hd), Vector3(hw, WALL_H + 0.25, hd), "roof")
	k.block(Vector3(-hw, WALL_H + 0.25, hd - T), Vector3(hw, WALL_H + 0.8, hd), wall, false)
	k.block(Vector3(-hw, WALL_H + 0.25, -hd + T), Vector3(-hw + T, WALL_H + 0.8, hd - T), wall, false)
	k.block(Vector3(hw - T, WALL_H + 0.25, -hd + T), Vector3(hw, WALL_H + 0.8, hd - T), wall, false)
	k.block(Vector3(-hw, WALL_H - 0.9, -hd - 0.25), Vector3(hw, WALL_H + 1.3, -hd), "accent", false)  # sign band


static func _sign(k: LandmarkKit, text: String, hw: float, hd: float) -> void:
	var l := Label3D.new()
	l.name = "Sign"
	l.text = text
	l.font_size = 140 if text.length() <= 12 else 90
	l.pixel_size = 0.01
	l.outline_size = 10
	l.modulate = Color(0.95, 0.92, 0.85)
	l.shaded = true
	l.double_sided = false
	l.position = Vector3(0, WALL_H + 0.2, -hd - 0.27)
	l.rotation.y = PI  # Label3D reads from +Z; the front is -Z
	l.visibility_range_end = 250.0
	k.root.add_child(l)


# Two or three shelf rows running front-to-back, each a loot container.
static func _shelves(k: LandmarkKit, key: String, table: String, hw: float, hd: float, label: String) -> void:
	var rows := 3 if hw >= 8.0 else 2
	var run := maxf(hd * 2.0 - 6.0, 2.0)
	for r in rows:
		var x := lerpf(-hw + 2.5, hw - 2.0, (r + 0.5) / rows)
		_loot(k, key, label, table, Vector3(x, 0, 1.0), Vector3(0.8, 1.6, run))
	_loot(k, key, "Back Stock", table, Vector3(hw - 1.5, 0, hd - 0.7), Vector3(2.0, 1.9, 0.6))


static func _canopy(k: LandmarkKit, key: String, table: String, hw: float, hd: float) -> void:
	var z0 := -hd - 2.0
	var z1 := -hd - 12.0
	var cw := maxf(hw, 7.0)
	for px: float in [-cw + 1.0, cw - 1.0]:
		for pz: float in [z0 - 1.0, z1 + 1.0]:
			k.box(Vector3(px, 2.6, pz), Vector3(0.4, 5.2, 0.4), "steel")
	k.block(Vector3(-cw, 5.2, z1), Vector3(cw, 5.7, z0), "accent", false)
	for px: float in [-cw * 0.45, cw * 0.45]:
		k.box(Vector3(px, 0.1, (z0 + z1) * 0.5), Vector3(1.2, 0.2, 5.0), "concrete")
		_loot(k, key, "Fuel Pump", table, Vector3(px, 0.2, (z0 + z1) * 0.5), Vector3(0.7, 1.6, 0.5))


static func _loot(k: LandmarkKit, key: String, label: String, table: String, pos: Vector3, size: Vector3) -> void:
	k.place(LOOT, Transform3D(Basis(), pos), {"container_id": "%s_%d" % [key, _n], "display_name": label,
		"loot_table": table, "size": size, "color": Color(0.42, 0.4, 0.38)}, "Loot_%d" % _n)
	_n += 1
