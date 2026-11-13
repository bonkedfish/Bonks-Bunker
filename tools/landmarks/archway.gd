# Archway — builds the Great Platte River Road Archway into a LandmarkKit (D-049): a covered span over I-80
# (steel deck, timber-faced walls with maroon X-trusses outside, a shallow barrel roof) between two brick towers
# on stone bases with green copper pyramid roofs and bronze eagles, plus the low visitor centre. Walkable inside:
# the north tower's ground-floor lobby (east door) and switchback stairs up to the museum deck - four exhibit rooms
# (wagon trail, buffalo + Pony Express with Evan's jerky smoker, the 1950s diner with a broken overlook window onto
# the interstate, the gift shop) - and the south tower's upper room, Evan's camp. Loot containers come from the data
# file; Evan is placed as a ResidentNpc. Origin = middle of the span on the ground, x east, z south.
# Depends on: LandmarkKit, scenes/loot_container.tscn, scenes/resident_npc.tscn.
extends RefCounted

const LOOT := preload("res://scenes/loot_container.tscn")
const NPC := preload("res://scenes/resident_npc.tscn")


static func build(k: LandmarkKit, d: Dictionary, rng: RandomNumberGenerator) -> void:
	var sp: Dictionary = d.span
	var tw: Dictionary = d.towers
	_span(k, sp)
	_tower(k, tw, float(tw.north_z), 1.0, true, float(sp.deck_y))
	_tower(k, tw, float(tw.south_z), -1.0, false, float(sp.deck_y))
	_visitor_centre(k, d.visitor_centre)
	_exhibits(k, sp, rng)
	_evan_camp(k, float(tw.south_z), float(sp.deck_y), rng)
	for s: Dictionary in d.signs:
		_sign(k, str(s.text), float(tw.north_z if s.tower == "north" else tw.south_z), tw)
	_lights(k, d)
	for l: Dictionary in d.loot:
		var p: Array = l.pos
		var sz: Array = l.size
		k.place(LOOT, Transform3D(Basis(), Vector3(p[0], p[1], p[2])), {"container_id": "archway_" + str(l.id),
			"display_name": str(l.name), "loot_table": str(l.table), "size": Vector3(sz[0], sz[1], sz[2]),
			"color": Color(0.42, 0.33, 0.25)}, "Loot_" + str(l.id))
	var e: Dictionary = d.evan
	var ep: Array = e.pos
	k.place(NPC, Transform3D(Basis(), Vector3(ep[0], ep[1], ep[2])), {"npc_id": str(e.npc_id)}, "Evan")


# --- span --------------------------------------------------------------------------------------

static func _span(k: LandmarkKit, sp: Dictionary) -> void:
	var hw := float(sp.half_width_m)
	var hl := float(sp.half_length_m)
	var y := float(sp.deck_y)
	var top := y + float(sp.room_h_m)
	# Deck: steel girder box + plank floor.
	k.block(Vector3(-hw, y - float(sp.deck_depth_m), -hl), Vector3(hw, y - 0.1, hl), "steel")
	k.block(Vector3(-hw + 0.4, y - 0.1, -hl), Vector3(hw - 0.4, y, hl), "floor")
	# Side walls (timber facade), the east one broken open over the diner as the interstate overlook.
	var ov: Array = sp.overlook_z
	k.block(Vector3(-hw, y, -hl), Vector3(-hw + 0.4, top, hl), "facade")
	k.block(Vector3(hw - 0.4, y, -hl), Vector3(hw, top, float(ov[0])), "facade")
	k.block(Vector3(hw - 0.4, y, float(ov[1])), Vector3(hw, top, hl), "facade")
	k.block(Vector3(hw - 0.4, y, float(ov[0])), Vector3(hw, y + 1.2, float(ov[1])), "facade")
	k.block(Vector3(hw - 0.4, top - 1.2, float(ov[0])), Vector3(hw, top, float(ov[1])), "facade")
	k.block(Vector3(hw - 0.3, y + 1.2, float(ov[0])), Vector3(hw - 0.25, top - 1.2, float(ov[0]) + 3.5), "glass")
	# Outside: maroon X-trusses, verticals and chords on both faces.
	var panel := float(sp.truss_panel_m)
	var n := roundi(2.0 * hl / panel)
	for side: float in [-1.0, 1.0]:
		var x := side * (hw + 0.15)
		for i in n + 1:
			var z := -hl + i * panel
			k.box(Vector3(x, (y - 1.4 + top) * 0.5, z), Vector3(0.35, top - y + 1.4, 0.35), "truss", 0.0, false)
			if i < n:
				_beam(k, Vector3(x, y - 1.3, z), Vector3(x, top, z + panel), 0.3, "truss")
				_beam(k, Vector3(x, top, z), Vector3(x, y - 1.3, z + panel), 0.3, "truss")
		k.box(Vector3(x, top, 0), Vector3(0.4, 0.4, 2.0 * hl), "truss", 0.0, false)
		k.box(Vector3(x, y - 1.3, 0), Vector3(0.4, 0.4, 2.0 * hl), "truss", 0.0, false)
	# Ceiling (collision) + shallow barrel roof.
	k.block(Vector3(-hw, top, -hl), Vector3(hw, top + 0.15, hl), "plaster")
	var rise := float(sp.roof_rise_m)
	var r := hw + 0.5
	var segs := 10
	for i in segs:
		var a0 := PI * i / segs
		var a1 := PI * (i + 1) / segs
		var p0 := Vector3(-cos(a0) * r, top + 0.15 + sin(a0) * rise, 0)
		var p1 := Vector3(-cos(a1) * r, top + 0.15 + sin(a1) * rise, 0)
		k.quad(p0 + Vector3(0, 0, -hl - 0.5), p0 + Vector3(0, 0, hl + 0.5), p1 + Vector3(0, 0, hl + 0.5),
			p1 + Vector3(0, 0, -hl - 0.5), "roof_metal")
	# Partition walls between the exhibit rooms, a 3 m doorway in each.
	var parts: Array = sp.partitions_z
	var doors: Array = sp.doors_x
	for i in parts.size():
		var z := float(parts[i])
		var dx := float(doors[i])
		k.block(Vector3(-hw + 0.4, y, z - 0.15), Vector3(dx - 1.5, top, z + 0.15), "plaster")
		k.block(Vector3(dx + 1.5, y, z - 0.15), Vector3(hw - 0.4, top, z + 0.15), "plaster")
		k.block(Vector3(dx - 1.5, y + 3.0, z - 0.15), Vector3(dx + 1.5, top, z + 0.15), "plaster")


# Square beam from a to b (no collision).
static func _beam(k: LandmarkKit, a: Vector3, b: Vector3, t: float, mat: String) -> void:
	var x := (b - a).normalized()
	var ref := Vector3.UP if absf(x.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var z := x.cross(ref).normalized()
	var y := z.cross(x)
	k.box_xf(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(a.distance_to(b), t, t), mat, false)


# --- towers ------------------------------------------------------------------------------------

# One brick tower at z = tz. `toward` = +1 if the span is on the tower's +z side. The north tower has the lobby
# door (east face) and the stairs; the south one is closed below the deck.
static func _tower(k: LandmarkKit, tw: Dictionary, tz: float, toward: float, stairs: bool, deck_y: float) -> void:
	var hw := float(tw.half_width_m)
	var hd := float(tw.depth_m) * 0.5
	var y0 := float(tw.base_y)
	var y1 := float(tw.top_y)
	var t := 0.5
	var z_lo := tz - hd
	var z_hi := tz + hd
	var span_z := z_hi if toward > 0.0 else z_lo   # face toward the span
	var far_z := z_lo if toward > 0.0 else z_hi
	var room_top := deck_y + 6.2
	# West wall, east wall (with the lobby door), far wall.
	k.block(Vector3(-hw, y0, z_lo), Vector3(-hw + t, y1, z_hi), "brick")
	if stairs:
		k.block(Vector3(hw - t, y0, z_lo), Vector3(hw, y1, tz - 1.5), "brick")
		k.block(Vector3(hw - t, y0, tz + 1.5), Vector3(hw, y1, z_hi), "brick")
		k.block(Vector3(hw - t, 3.0, tz - 1.5), Vector3(hw, y1, tz + 1.5), "brick")
	else:
		k.block(Vector3(hw - t, y0, z_lo), Vector3(hw, y1, z_hi), "brick")
	var fz0 := minf(far_z, far_z + toward * t)
	k.block(Vector3(-hw + t, y0, fz0), Vector3(hw - t, y1, fz0 + t), "brick")
	# Span-side wall with the opening into the deck.
	var sz0 := minf(span_z, span_z - toward * t)
	k.block(Vector3(-hw + t, y0, sz0), Vector3(hw - t, deck_y, sz0 + t), "brick")
	k.block(Vector3(-hw + t, room_top, sz0), Vector3(hw - t, y1, sz0 + t), "brick")
	k.block(Vector3(-hw + t, deck_y, sz0), Vector3(-6.0, room_top, sz0 + t), "brick")
	k.block(Vector3(6.0, deck_y, sz0), Vector3(hw - t, room_top, sz0 + t), "brick")
	# Stone base skin, cornice, cap and copper pyramid roof with a bronze eagle.
	var s0 := float(tw.stone_to_y)
	k.block(Vector3(-hw - 0.12, y0, z_lo - 0.12), Vector3(-hw, s0, z_hi + 0.12), "stone", false)
	k.block(Vector3(-hw, y0, z_lo - 0.12), Vector3(hw, s0, z_lo), "stone", false)
	k.block(Vector3(-hw, y0, z_hi), Vector3(hw, s0, z_hi + 0.12), "stone", false)
	if stairs:
		k.block(Vector3(hw, y0, z_lo - 0.12), Vector3(hw + 0.12, s0, tz - 1.5), "stone", false)
		k.block(Vector3(hw, y0, tz + 1.5), Vector3(hw + 0.12, s0, z_hi + 0.12), "stone", false)
		k.block(Vector3(hw - t - 0.05, 0.0, tz - 1.6), Vector3(hw + 0.15, 3.0, tz - 1.45), "wood", false)
		k.block(Vector3(hw - t - 0.05, 0.0, tz + 1.45), Vector3(hw + 0.15, 3.0, tz + 1.6), "wood", false)
	else:
		k.block(Vector3(hw, y0, z_lo - 0.12), Vector3(hw + 0.12, s0, z_hi + 0.12), "stone", false)
	k.block(Vector3(-hw - 0.35, y1 - 0.6, z_lo - 0.35), Vector3(hw + 0.35, y1, z_hi + 0.35), "stone")
	k.block(Vector3(-hw + t, room_top, z_lo + t), Vector3(hw - t, room_top + 0.2, z_hi - t), "plaster")
	k.hip_roof(Vector2(-hw - 0.4, z_lo - 0.4), Vector2(hw + 0.4, z_hi + 0.4), y1, float(tw.roof_rise_m), "copper",
		2.0 * hw - 2.0 * hd)
	_eagle(k, Vector3(0, y1 + float(tw.roof_rise_m), tz))
	# Floors.
	var ix0 := -hw + t
	var ix1 := hw - t
	var iz0 := z_lo + t
	var iz1 := z_hi - t
	if not stairs:
		k.block(Vector3(ix0, deck_y - 0.4, iz0), Vector3(ix1, deck_y, iz1), "floor")
		return
	k.block(Vector3(ix0, -0.3, iz0), Vector3(ix1, 0.05, iz1), "concrete")
	k.block(Vector3(hw - t, -0.3, tz - 1.5), Vector3(hw, 0.05, tz + 1.5), "concrete")  # threshold
	k.ramp(Vector3(hw + 3.0, -1.0, tz), Vector3(hw, 0.05, tz), 3.0, 0.4, "concrete")  # step-free door ramp
	# Switchback stairs on the west side: flight 1 runs toward the span, a landing, flight 2 runs back up.
	var dz := toward
	var start := tz - dz * 4.0       # flight 1 foot
	var turn := tz + dz * 3.5        # landing edge
	var mid_y := deck_y * 0.5
	k.ramp(Vector3(-9.0, 0.0, start), Vector3(-9.0, mid_y, turn), 2.0, 0.3, "concrete")
	var lz0 := minf(turn, iz1 if dz > 0.0 else iz0)
	var lz1 := maxf(turn, iz1 if dz > 0.0 else iz0)
	k.block(Vector3(ix0, mid_y - 0.3, lz0), Vector3(-6.0, mid_y, lz1), "concrete")
	k.ramp(Vector3(-7.0, mid_y, turn), Vector3(-7.0, deck_y, start), 2.0, 0.3, "concrete")
	# Upper floor around the stairwell (open over x -10..-6 between the flights' ends).
	k.block(Vector3(-6.0, deck_y - 0.4, iz0), Vector3(ix1, deck_y, iz1), "floor")
	var fz := minf(start, iz0 if dz > 0.0 else iz1)
	var fz1 := maxf(start, iz0 if dz > 0.0 else iz1)
	k.block(Vector3(ix0, deck_y - 0.4, fz), Vector3(-6.0, deck_y, fz1), "floor")
	var stair_pts := PackedVector3Array([Vector3(-6.0, deck_y, start), Vector3(-6.0, deck_y, iz1 if dz > 0.0 else iz0)])
	k.railing(stair_pts, 1.0, "steel")
	k.railing(PackedVector3Array([Vector3(ix0, deck_y, start), Vector3(-8.0, deck_y, start)]), 1.0, "steel")


static func _eagle(k: LandmarkKit, p: Vector3) -> void:
	k.box(p + Vector3(0, 0.15, 0), Vector3(0.5, 0.3, 0.5), "bronze", 0.0, false)
	k.box(p + Vector3(0, 0.75, 0), Vector3(0.45, 0.9, 0.55), "bronze", 0.0, false)
	k.box(p + Vector3(0, 1.35, -0.25), Vector3(0.28, 0.3, 0.35), "bronze", 0.0, false)
	for s: float in [-1.0, 1.0]:
		_beam(k, p + Vector3(s * 0.2, 1.0, 0.05), p + Vector3(s * 1.5, 1.9, 0.25), 0.18, "bronze")
		_beam(k, p + Vector3(s * 1.5, 1.9, 0.25), p + Vector3(s * 2.0, 1.5, 0.35), 0.14, "bronze")


static func _sign(k: LandmarkKit, text: String, tz: float, tw: Dictionary) -> void:
	var hw := float(tw.half_width_m)
	for side: float in [-1.0, 1.0]:
		var x := side * (hw + 0.13)
		k.box(Vector3(x, 17.5, tz), Vector3(0.12, 1.4, 7.5), "sign", 0.0, false)
		var l := Label3D.new()
		l.name = "Sign_%d_%d" % [int(tz), int(side)]
		l.text = text
		l.font_size = 140
		l.pixel_size = 0.01
		l.outline_size = 0
		l.modulate = Color(0.92, 0.82, 0.55)
		l.shaded = true
		l.double_sided = false
		l.position = Vector3(x + side * 0.08, 17.5, tz)
		l.rotation.y = side * PI * 0.5
		l.visibility_range_end = 400.0
		k.root.add_child(l)


static func _visitor_centre(k: LandmarkKit, v: Dictionary) -> void:
	var lo: Array = v.lo
	var hi: Array = v.hi
	var h := float(v.height_m)
	k.block(Vector3(lo[0], -3.0, lo[1]), Vector3(hi[0], h, hi[1]), "brick")
	k.block(Vector3(lo[0] - 0.1, -3.0, lo[1] - 0.1), Vector3(hi[0] + 0.1, 1.0, hi[1] + 0.1), "stone", false)
	k.hip_roof(Vector2(lo[0] - 0.8, lo[1] - 0.8), Vector2(hi[0] + 0.8, hi[1] + 0.8), h, float(v.roof_rise_m), "copper",
		float(hi[0]) - float(lo[0]) - (float(hi[1]) - float(lo[1])))
	# Boarded-up entrance on the parking-lot (north) side.
	var cx := (float(lo[0]) + float(hi[0])) * 0.5
	k.block(Vector3(cx - 4.0, 0.0, float(lo[1]) - 0.15), Vector3(cx + 4.0, 3.2, float(lo[1])), "glass", false)
	for i in 5:
		k.box(Vector3(cx, 0.6 + i * 0.6, float(lo[1]) - 0.22), Vector3(8.4, 0.25, 0.05), "wood", 0.08 * (i % 2 * 2 - 1), false)


static func _lights(k: LandmarkKit, d: Dictionary) -> void:
	var c: Array = d.light_color
	var i := 0
	for p: Array in d.lights:
		var l := OmniLight3D.new()
		l.name = "Light_%d" % i
		l.position = Vector3(p[0], p[1], p[2])
		l.light_color = Color(c[0], c[1], c[2])
		l.light_energy = float(d.light_energy)
		l.omni_range = float(d.light_range_m)
		l.shadow_enabled = false
		l.distance_fade_enabled = true
		l.distance_fade_begin = 60.0
		l.distance_fade_length = 20.0
		k.root.add_child(l)
		i += 1


# --- exhibits ----------------------------------------------------------------------------------

static func _exhibits(k: LandmarkKit, sp: Dictionary, rng: RandomNumberGenerator) -> void:
	var y := float(sp.deck_y)
	# Room 1 (z -40..-20): westward wagon trail - covered wagon, two oxen, crates.
	k.block(Vector3(-4.0, y, -36.0), Vector3(6.0, y + 0.25, -26.0), "wood")
	_wagon(k, Vector3(1.0, y + 0.25, -31.0))
	for i in 2:
		_animal(k, Vector3(-0.7 + i * 1.4, y + 0.25, -35.0), "hide", 1.0)
	# Room 2 (z -20..0): two buffalo, the Pony Express station counter, Evan's jerky smoker + drying rack.
	k.block(Vector3(-3.5, y, -17.0), Vector3(3.5, y + 0.25, -11.0), "wood")
	_animal(k, Vector3(-1.5, y + 0.25, -14.0), "hide", 1.6)
	_animal(k, Vector3(1.6, y + 0.25, -13.0), "hide", 1.4)
	k.block(Vector3(-9.5, y, -11.0), Vector3(-6.5, y + 1.1, -9.8), "wood")
	k.cylinder(Vector3(5.0, y, -7.5), 0.45, 1.2, "steel", 10, true)
	k.box(Vector3(5.0, y + 1.6, -7.5), Vector3(0.1, 1.0, 0.1), "steel", 0.0, false)
	for i in 2:
		k.box(Vector3(7.8, y + 1.3 + i * 0.5, -7.5), Vector3(0.04, 0.04, 2.6), "steel", 0.0, false)
		for j in 7:
			k.box(Vector3(7.8, y + 1.15 + i * 0.5, -8.6 + j * 0.36), Vector3(0.03, 0.28, 0.08), "jerky", 0.0, false)
	for p: Vector3 in [Vector3(7.8, y, -8.9), Vector3(7.8, y, -6.1)]:
		k.box(p + Vector3(0, 1.0, 0), Vector3(0.08, 2.0, 0.08), "wood", 0.0, false)
	# Room 3 (z 0..20): 1950s diner - tile floor, counter, stools, booths by the broken overlook window.
	k.block(Vector3(-9.5, y, 0.2), Vector3(9.5, y + 0.02, 19.8), "tile", false)
	k.block(Vector3(-9.5, y, 4.0), Vector3(-8.0, y + 1.1, 16.0), "diner_red")
	k.block(Vector3(-9.55, y + 1.1, 3.9), Vector3(-7.9, y + 1.15, 16.1), "chrome")
	for i in 6:
		k.cylinder(Vector3(-7.2, y, 5.0 + i * 2.0), 0.05, 0.75, "chrome", 6)
		k.disc(Vector3(-7.2, y + 0.75, 5.0 + i * 2.0), 0.22, "diner_red", 10)
	for i in 3:
		var bz := 5.0 + i * 4.0
		k.block(Vector3(6.5, y, bz - 1.4), Vector3(9.4, y + 0.5, bz - 0.9), "diner_red")
		k.block(Vector3(6.5, y, bz + 0.9), Vector3(9.4, y + 0.5, bz + 1.4), "diner_red")
		k.block(Vector3(6.7, y + 0.72, bz - 0.6), Vector3(9.3, y + 0.78, bz + 0.6), "chrome")
		k.cylinder(Vector3(8.0, y, bz), 0.06, 0.72, "chrome", 6)
	k.block(Vector3(-3.0, y, 18.6), Vector3(-1.8, y + 1.7, 19.6), "diner_red")  # jukebox
	# Room 4 (z 20..40): gift shop - centre display table and the raccoon who runs it.
	k.block(Vector3(-1.5, y, 26.0), Vector3(1.5, y + 0.9, 30.0), "wood")
	_raccoon(k, Vector3(0.4, y + 0.9, 27.5))
	# Scattered debris.
	for i in 30:
		var p := Vector3(rng.randf_range(-9.0, 9.0), y + 0.05, rng.randf_range(-39.0, 39.0))
		k.box(p, Vector3(rng.randf_range(0.2, 0.6), 0.1, rng.randf_range(0.2, 0.6)),
			"paper" if rng.randf() < 0.6 else "wood", rng.randf() * TAU, false)


static func _wagon(k: LandmarkKit, p: Vector3) -> void:
	k.block(p + Vector3(-0.8, 0.7, -1.8), p + Vector3(0.8, 1.3, 1.8), "wood")
	for s: float in [-1.0, 1.0]:
		for e: float in [-1.2, 1.2]:
			var c := p + Vector3(s * 0.9, 0.7, e)
			k.disc(c, 0.7, "wood", 12, Vector3(s, 0, 0))
			k.disc(c, 0.7, "wood", 12, Vector3(-s, 0, 0))
	# Canvas bonnet: half hoops along the bed.
	var segs := 8
	for i in segs:
		var a0 := PI * i / segs
		var a1 := PI * (i + 1) / segs
		var p0 := Vector3(-cos(a0) * 0.85, 1.3 + sin(a0) * 1.1, 0)
		var p1 := Vector3(-cos(a1) * 0.85, 1.3 + sin(a1) * 1.1, 0)
		k.quad(p + p0 + Vector3(0, 0, -1.6), p + p0 + Vector3(0, 0, 1.6), p + p1 + Vector3(0, 0, 1.6),
			p + p1 + Vector3(0, 0, -1.6), "canvas")


# A blocky four-legged exhibit animal (ox / buffalo) facing -z; `hump` > 1 makes a buffalo.
static func _animal(k: LandmarkKit, p: Vector3, mat: String, hump: float) -> void:
	k.box(p + Vector3(0, 1.0, 0), Vector3(0.9, 0.8, 2.0), mat)
	if hump > 1.0:
		k.box(p + Vector3(0, 1.45 + (hump - 1.0) * 0.3, -0.45), Vector3(1.0, 0.7 * hump, 0.9), "hide", 0.0, false)
	k.box(p + Vector3(0, 1.1, -1.25), Vector3(0.5, 0.55, 0.6), mat, 0.0, false)
	for sx: float in [-0.3, 0.3]:
		for sz: float in [-0.75, 0.75]:
			k.box(p + Vector3(sx, 0.3, sz), Vector3(0.18, 0.6, 0.18), mat, 0.0, false)
		k.box(p + Vector3(sx * 1.2, 1.45, -1.35), Vector3(0.08, 0.25, 0.08), "canvas", 0.0, false)


static func _raccoon(k: LandmarkKit, p: Vector3) -> void:
	k.box(p + Vector3(0, 0.15, 0), Vector3(0.28, 0.25, 0.45), "fur", 0.0, false)
	k.box(p + Vector3(0, 0.25, -0.28), Vector3(0.2, 0.18, 0.18), "fur", 0.0, false)
	k.box(p + Vector3(0, 0.27, -0.33), Vector3(0.21, 0.05, 0.1), "steel", 0.0, false)
	_beam(k, p + Vector3(0, 0.12, 0.2), p + Vector3(0.05, 0.25, 0.6), 0.09, "fur")


# --- Evan's camp (south tower, upper room) -----------------------------------------------------

static func _evan_camp(k: LandmarkKit, tz: float, y: float, rng: RandomNumberGenerator) -> void:
	# Foil on every wall (it keeps the thoughts in).
	k.block(Vector3(-9.95, y, tz - 5.3), Vector3(-9.9, y + 5.5, tz + 5.4), "foil", false)
	k.block(Vector3(9.9, y, tz - 5.3), Vector3(9.95, y + 5.5, tz + 5.4), "foil", false)
	k.block(Vector3(-9.9, y, tz + 5.45), Vector3(9.9, y + 5.5, tz + 5.5), "foil", false)
	# Mattress, blanket, radio, spoon pile, candle crates.
	k.block(Vector3(-9.6, y, tz + 2.5), Vector3(-7.4, y + 0.3, tz + 4.8), "mattress")
	k.block(Vector3(-9.4, y + 0.3, tz + 3.3), Vector3(-7.6, y + 0.36, tz + 4.7), "canvas", false)
	k.block(Vector3(-6.8, y, tz + 4.6), Vector3(-6.2, y + 0.4, tz + 5.2), "steel")
	for i in 40:
		var a := rng.randf() * TAU
		var r := rng.randf() * 0.35
		k.box(Vector3(-4.5 + cos(a) * r, y + 0.03 + rng.randf() * 0.12, tz + 4.5 + sin(a) * r), Vector3(0.03, 0.02, 0.18),
			"chrome", rng.randf() * TAU, false)
	# Gary, the wagon wheel, propped against the far wall.
	k.disc(Vector3(-1.5, y + 0.72, tz + 5.25), 0.7, "wood", 12, Vector3(0, 0, -1))
	k.disc(Vector3(-1.5, y + 0.72, tz + 5.2), 0.7, "wood", 12, Vector3(0, 0, 1))
	# The conspiracy board on the east wall: cork, notes, red string.
	var bx := 9.85
	k.block(Vector3(bx - 0.08, y + 1.0, tz - 3.5), Vector3(bx, y + 3.8, tz + 3.5), "cork", false)
	var pins: Array[Vector3] = []
	for i in 14:
		var p := Vector3(bx - 0.1, y + rng.randf_range(1.2, 3.6), tz + rng.randf_range(-3.2, 3.2))
		k.box(p, Vector3(0.01, 0.28, 0.22), "paper", 0.0, false)
		pins.append(p)
	for i in 12:
		var a := pins[rng.randi() % pins.size()] + Vector3(-0.01, 0, 0)
		var b := pins[rng.randi() % pins.size()] + Vector3(-0.01, 0, 0)
		if a.distance_to(b) > 0.3:
			_beam(k, a, b, 0.015, "string")
	# Cans everywhere.
	for i in 18:
		var p := Vector3(rng.randf_range(-6.0, 6.0), y, tz + rng.randf_range(-4.5, 4.5))
		k.cylinder(p, 0.05, 0.12, "chrome", 6)
