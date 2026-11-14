# CountryClub — builds Kearney Country Club's grounds (D-079; 2800 19th Ave) into a LandmarkKit from
# data/landmarks/country_club.json. Local frame = map axes (x east, z south), origin at the clubhouse. Clubhouse,
# pro shop + cart barn, maintenance shed, pool house, parking, rooms, furniture, signs, lights, loot and lair markers
# are data (LandmarkParts); this file adds the drained pool basin (sunk into a landmarks.json ground hole) and the
# round wading pool, the two tennis courts (surface, lines, nets), chain-link fences, parked golf carts, and the GroundProps node
# that stands the hole flags and tee signs on the real ground across the course. The course surfaces themselves are
# painted onto the terrain by build_cells from data/landmarks/country_club_paint.json (D-080). Scenery only: no golf
# gameplay (D-079).
# Depends on: LandmarkKit, landmark_parts.gd, scripts/world/ground_props.gd.
extends RefCounted

const Parts := preload("res://tools/landmarks/landmark_parts.gd")
const GroundProps := preload("res://scripts/world/ground_props.gd")


static func build(k: LandmarkKit, d: Dictionary, _rng: RandomNumberGenerator) -> void:
	var fy := float(d.dims.floor_y)
	Parts.build_all(k, d, "country_club", fy)
	_pool(k, d.pool)
	for c: Dictionary in d.tennis:
		_court(k, c)
	for c: Array in d.carts:  # [x, z, yaw_deg]
		_cart(k, c)
	for line: Array in d.fences:  # chain-link polylines (gates are the gaps between lines)
		_fence(k, line)
	var props := Node3D.new()
	props.name = "CourseProps"
	props.set_script(GroundProps)
	var flags := PackedVector2Array()
	for f: Array in d.course.flags:
		flags.append(Vector2(f[0], f[1]))
	props.set("flags", flags)
	props.set("signs", d.course.tee_signs)  # [x, z, yaw_deg, text] per hole, from the OSM hole lines
	k.root.add_child(props)
	Parts.signs(k, d.course.signs)  # clubhouse / pro shop / pool wall signs


# Kidney pool: floor at -depth, walls round the outline, coping on the deck; plus the round wading pool's curb.
static func _pool(k: LandmarkKit, p: Dictionary) -> void:
	var top := float(p.deck_y)
	var floor_y := top - float(p.depth)
	var poly := PackedVector2Array()
	for q: Array in p.kidney:
		poly.append(Vector2(q[0], q[1]))
	var faces := PackedVector3Array()
	var idx := Geometry2D.triangulate_polygon(poly)
	for i in range(0, idx.size(), 3):
		var v := [Vector3(poly[idx[i]].x, floor_y, poly[idx[i]].y), Vector3(poly[idx[i + 1]].x, floor_y, poly[idx[i + 1]].y),
			Vector3(poly[idx[i + 2]].x, floor_y, poly[idx[i + 2]].y)]
		k.tri(v[0], v[1], v[2], "pool_floor")
		faces.append_array(PackedVector3Array(v))
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var q := [Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), Vector3(b.x, floor_y, b.y), Vector3(a.x, floor_y, a.y)]
		k.quad(q[0], q[1], q[2], q[3], "pool_wall")
		faces.append_array(PackedVector3Array([q[0], q[1], q[2], q[0], q[2], q[3]]))
		var mid := (a + b) * 0.5
		var dir := b - a
		k.box(Vector3(mid.x, top + 0.02, mid.y), Vector3(0.35, 0.04, dir.length() + 0.2), "coping", atan2(dir.x, dir.y), false)
	k.trimesh(faces)
	var c := Vector3(p.puddle[0], floor_y + 0.01, p.puddle[1])
	k.disc(c, float(p.puddle[2]), "puddle", 12)
	var w: Array = p.wading  # [x, z, radius]
	var wc := Vector3(w[0], top, w[1])
	var r := float(w[2])
	k.disc(wc + Vector3(0, 0.005, 0), r, "pool_floor", 18)
	k.sweep(wc, PackedVector2Array([Vector2(r, 0.0), Vector2(r, 0.3), Vector2(r + 0.3, 0.3), Vector2(r + 0.3, 0.0)]), 0.0, TAU, 18, "coping", "pool_wall")


static func _court(k: LandmarkKit, c: Dictionary) -> void:
	var o := Vector3(c.centre[0], float(c.y), c.centre[1])
	var hw := 10.97 * 0.5
	var hl := 23.77 * 0.5
	k.block(o + Vector3(-hw - 3.5, -0.1, -hl - 6.0), o + Vector3(hw + 3.5, 0.02, hl + 6.0), "court_out", false)
	k.block(o + Vector3(-hw, 0.02, -hl), o + Vector3(hw, 0.03, hl), "court_in", false)
	var lines := [[-hw, -hl, hw, -hl], [-hw, hl, hw, hl], [-hw, -hl, -hw, hl], [hw, -hl, hw, hl],
		[-4.115, -hl, -4.115, hl], [4.115, -hl, 4.115, hl], [-4.115, -6.4, 4.115, -6.4], [-4.115, 6.4, 4.115, 6.4], [0, -6.4, 0, 6.4]]
	for l: Array in lines:
		k.block(o + Vector3(minf(l[0], l[2]) - 0.025, 0.03, minf(l[1], l[3]) - 0.025), o + Vector3(maxf(l[0], l[2]) + 0.025, 0.035, maxf(l[1], l[3]) + 0.025), "paint_white", false)
	for s: float in [-1.0, 1.0]:
		k.cylinder(o + Vector3(s * (hw + 0.9), 0.0, 0), 0.04, 1.07, "steel", 6)
	k.box(o + Vector3(0, 0.5, 0), Vector3(hw * 2.0 + 1.8, 0.9, 0.03), "net", 0.0, false)


static func _fence(k: LandmarkKit, line: Array) -> void:
	var pts := PackedVector3Array()
	for p: Array in line:
		pts.append(Vector3(p[0], 0.1, p[1]))
	k.railing(pts, 2.4, "fence_post", 3.0, true)
	for i in range(pts.size() - 1):
		k.quad(pts[i], pts[i + 1], pts[i + 1] + Vector3.UP * 2.4, pts[i] + Vector3.UP * 2.4, "chainlink")


static func _cart(k: LandmarkKit, c: Array) -> void:
	var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(c[2]))), Vector3(c[0], 0.12, c[1]))
	k.box_xf(xf.translated_local(Vector3(0, 0.45, 0)), Vector3(1.2, 0.5, 2.4), "cart_white")
	k.box_xf(xf.translated_local(Vector3(0, 1.85, 0.1)), Vector3(1.25, 0.06, 2.0), "cart_roof", false)
	for z: float in [-0.8, 0.9]:
		for s: float in [-0.55, 0.55]:
			k.box_xf(xf.translated_local(Vector3(s, 1.15, z)), Vector3(0.05, 1.4, 0.05), "steel", false)
