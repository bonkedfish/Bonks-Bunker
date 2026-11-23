# HouseDetails — real 3D detail on generated buildings (D-118), for build_cells: window frames + sills set around
# the shader's windows (same layout maths as shaders/building_wall.gdshader, so they line up), boards nailed over
# some windows, a front door on the wall facing the nearest street (a double glass door on big buildings), steps,
# porches with posts and a roof, garage doors, fascia + gutters along gable eaves, chimneys, parapets on flat roofs.
# Abandonment per building (deterministic from its footprint): boarded-up houses, burned houses (COLOR.b = 1 on
# their walls for the shader's soot, black roofs) and caved-in roofs (decided here, built by build_cells' gable roof).
# Writes into three SurfaceTools per cell: trim (vertex-coloured paint/wood/metal), boards (plank texture, UV in
# metres) and the brick wall look (chimneys, using the wall shader's UV contract). Step / deck / porch tops go into
# the building collision faces so they can be walked on.
# Numbers: data/art/building_looks.json "details". Depends on: BuildingLooks (rand01, data).
class_name HouseDetails
extends RefCounted

var d: Dictionary  # building_looks.json "details"
var w: Dictionary  # building_looks.json "window"
var counts := {"windows": 0, "boarded": 0, "doors": 0, "porches": 0, "garages": 0, "chimneys": 0, "burned": 0, "caved": 0}
var examples := {}  # kind -> [x, y, z, out x, out z]: the first front wall of each kind, for tests/house_look


func _init(looks_data: Dictionary) -> void:
	d = looks_data.details
	w = looks_data.window


# Per-building condition from its footprint centre: {boarded, burned, caved}.
func condition(centre: Vector2, cls: String) -> Dictionary:
	var c := {"boarded": false, "burned": false, "caved": false}
	if cls == "shed":
		return c
	c.burned = BuildingLooks.rand01(centre, 21) < float(d.burned_chance)
	c.boarded = not c.burned and BuildingLooks.rand01(centre, 22) < float(d.boarded_house_chance)
	c.caved = cls == "house" and BuildingLooks.rand01(centre, 23) < float(d.caved_roof_chance)
	if c.burned:
		counts.burned += 1
	if c.caved:
		counts.caved += 1
	return c


# Frames / boards for every shader window, plus the door (and porch / steps / garage) on the street side.
# outline as passed to build_cells._walls (any winding), y0 = wall base (ground - 0.3), y1 = wall top.
func add(cell: Dictionary, outline: PackedVector2Array, y0: float, y1: float, ground: float, centre: Vector2,
		cls: String, windows: bool, cond: Dictionary, front: Array) -> void:
	if cls == "shed":
		return
	var poly := outline.duplicate()
	if _signed_area(poly) < 0.0:
		poly.reverse()
	var trim: SurfaceTool = cell.trim_st
	var boards: SurfaceTool = cell.boards_st
	var trim_col := _pick(d.trim_colors, centre, 24)
	if cond.burned:
		trim_col = trim_col.darkened(0.75)
	# the front edge: outward normal pointing most toward the nearest street
	var front_i := -1
	if not front.is_empty():
		var to_street: Vector2 = (front[0] as Vector2) - centre
		var best := 0.2
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			if a.distance_to(b) < 3.0:
				continue
			var e := (b - a).normalized()
			var dot := Vector2(e.y, -e.x).dot(to_street.normalized())
			if dot > best:
				best = dot
				front_i = i
	var wall_h := y1 - y0
	var spacing := float(w.spacing_m)
	var floor_h := float(w.floor_height_m)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var edge_len := a.distance_to(b)
		if edge_len < 0.01:
			continue
		var e := (b - a) / edge_len
		var right := Vector3(e.x, 0.0, e.y)
		var out := Vector3(e.y, 0.0, -e.x)
		var n := floori(edge_len / spacing)
		var margin := (edge_len - n * spacing) * 0.5
		var door_col := -1
		var garage_col := -1
		if i == front_i:
			door_col = clampi(n / 2, 0, maxi(n - 1, 0)) if n >= 1 else -1
			_door(cell, a, e, right, out, edge_len, margin, door_col, spacing, ground, cls, cond, centre, trim_col)
			var fp := Vector3(a.x, ground, a.y) + right * edge_len * 0.5
			for kind: String in [cls, "boarded" if cond.boarded else "", "burned" if cond.burned else "", "caved" if cond.caved else ""]:
				_example(kind, fp, out)
			if cls == "house" and edge_len >= float(d.garage_min_edge_m) and n >= 3 \
					and BuildingLooks.rand01(centre, 25) < float(d.garage_chance):
				garage_col = 0 if door_col > n / 2 else n - 1
				var gt := margin + garage_col * spacing + spacing * 0.5
				var g: Dictionary = d.garage
				var gc := Vector3(a.x, 0.0, a.y) + right * gt + Vector3.UP * (ground + float(g.h_m) * 0.5) + out * 0.03
				var gcol := _pick(d.garage_colors, centre, 26) * (0.5 if cond.burned else 1.0)
				_box(trim, gc, right, out, Vector3(float(g.w_m) * 0.5, float(g.h_m) * 0.5, 0.03), gcol)
				for k in range(1, 4):  # panel seams
					var sy := -float(g.h_m) * 0.5 + float(g.h_m) * k / 4.0
					_box(trim, gc + Vector3.UP * sy + out * 0.03, right, out, Vector3(float(g.w_m) * 0.5 - 0.04, 0.025, 0.012), gcol.darkened(0.35))
				counts.garages += 1
				_example("garage", gc, out)
		if not windows or n < 1:
			continue
		var fl := 0
		while (fl + 1) * floor_h <= wall_h + 0.4:
			for col in n:
				if fl == 0 and (col == door_col or col == garage_col):
					continue
				var t := margin + col * spacing + spacing * 0.5
				var sill_y := y0 + fl * floor_h + float(w.sill_m)
				var base := Vector3(a.x, 0.0, a.y) + right * t
				_window(trim, boards, base, right, out, sill_y, trim_col,
					_boarded(cond, centre, i, col, fl))
			fl += 1


# Brick chimney through one roof slope, up past the ridge.
func chimney(cell: Dictionary, rect: Dictionary, eave: float, rise: float, centre: Vector2, rnd: float) -> void:
	if BuildingLooks.rand01(centre, 27) >= float(d.chimney_chance):
		return
	if not cell.walls.has("brick"):
		var bst := SurfaceTool.new()
		bst.begin(Mesh.PRIMITIVE_TRIANGLES)
		cell.walls.brick = bst
	var c: Vector2 = rect.centre
	var u: Vector2 = rect.axis
	var v := Vector2(-u.y, u.x)
	var along := float(rect.length) * 0.5 * (0.55 if BuildingLooks.rand01(centre, 28) < 0.5 else -0.55)
	var p := c + u * along + v * float(rect.width) * 0.2
	var s := float(d.chimney_m) * 0.5
	var top := eave + rise + 0.8
	var st: SurfaceTool = cell.walls.brick
	var bottom := eave
	var col := Color((top - bottom) / 64.0, rnd, 0.0)
	var corners := [p + (u + v) * s, p + (u - v) * s, p + (-u - v) * s, p + (-u + v) * s]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var n := Vector3(b.y - a.y, 0.0, a.x - b.x).normalized()
		var el := a.distance_to(b)
		for vt: Array in [[a, bottom, 0.0], [b, bottom, el], [b, top, el], [a, bottom, 0.0], [b, top, el], [a, top, 0.0]]:
			var q: Vector2 = vt[0]
			st.set_color(col)
			st.set_normal(n)
			st.set_uv(Vector2(float(vt[2]), float(vt[1]) - bottom))
			st.set_uv2(Vector2.ZERO)
			st.add_vertex(Vector3(q.x, float(vt[1]), q.y))
	for k in [0, 1, 2, 0, 2, 3]:  # cap
		var q: Vector2 = corners[k]
		st.set_color(col)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(q.x, q.y))
		st.set_uv2(Vector2.ZERO)
		st.add_vertex(Vector3(q.x, top, q.y))
	counts.chimneys += 1


# Caved-in roof (build_cells leaves the middle third of the +v slope open): broken rafters across the hole,
# one snapped and hanging into the house.
func rafters(cell: Dictionary, rect: Dictionary, eave: float, rise: float, overhang: float) -> void:
	var c: Vector2 = rect.centre
	var u: Vector2 = rect.axis
	var v := Vector2(-u.y, u.x)
	var hl := float(rect.length) * 0.5 + overhang
	var hw := float(rect.width) * 0.5
	var col := Color(0.2, 0.15, 0.1)
	var along := Vector3(u.x, 0.0, u.y)
	for i in 4:
		var f := lerpf(0.4, 0.64, float(i) / 3.0)
		var r := c - u * hl + u * (hl * 2.0 * f)
		var top := Vector3(r.x, eave + rise, r.y)
		var low := Vector3(r.x + v.x * hw, eave, r.y + v.y * hw)
		if i == 2:  # snapped: hangs down inside
			low = top.lerp(low, 0.55) + Vector3.DOWN * 1.6
		var mid := (top + low) * 0.5
		var dir := (low - top).normalized()
		_box(cell.trim_st, mid, dir, along, Vector3(top.distance_to(low) * 0.5, 0.07, 0.05), col)


# Fascia board + gutter along both eaves of a gable roof (eave line already includes the overhang).
func gutters(cell: Dictionary, rect: Dictionary, eave: float, rise: float, overhang: float, centre: Vector2, burned: bool) -> void:
	var c: Vector2 = rect.centre
	var u: Vector2 = rect.axis
	var v := Vector2(-u.y, u.x)
	var hl := float(rect.length) * 0.5 + overhang
	var hw := float(rect.width) * 0.5 + overhang
	var drop := overhang * rise / maxf(float(rect.width) * 0.5, 0.01)
	var col := _pick(d.trim_colors, centre, 24).darkened(0.75 if burned else 0.0)
	for side: float in [-1.0, 1.0]:
		var mid := c + v * hw * side
		var out := Vector3(v.x * side, 0.0, v.y * side)
		var right := Vector3(u.x, 0.0, u.y)
		var y := eave - drop
		_box(cell.trim_st, Vector3(mid.x, y - 0.09, mid.y) + out * 0.02, right, out, Vector3(hl, 0.09, 0.02), col)
		_box(cell.trim_st, Vector3(mid.x, y - 0.05, mid.y) + out * 0.09, right, out, Vector3(hl, 0.05, 0.05), col.darkened(0.15))


# --- pieces ----------------------------------------------------------------------------------

func _window(trim: SurfaceTool, boards: SurfaceTool, base: Vector3, right: Vector3, out: Vector3, sill_y: float,
		col: Color, boarded: bool) -> void:
	var hw := float(w.width_m) * 0.5
	var h := float(w.height_m)
	var fw := float(d.frame_w_m)
	var fd := float(d.frame_depth_m)
	var c := base + Vector3.UP * (sill_y + h * 0.5)
	_box(trim, c + right * (hw + fw * 0.5) + out * fd * 0.5, right, out, Vector3(fw * 0.5, h * 0.5 + fw, fd * 0.5), col)
	_box(trim, c - right * (hw + fw * 0.5) + out * fd * 0.5, right, out, Vector3(fw * 0.5, h * 0.5 + fw, fd * 0.5), col)
	_box(trim, c + Vector3.UP * (h * 0.5 + fw * 0.5) + out * fd * 0.5, right, out, Vector3(hw + fw, fw * 0.5, fd * 0.5), col)
	var sd := float(d.sill_depth_m)
	_box(trim, c - Vector3.UP * (h * 0.5 + 0.03) + out * sd * 0.5, right, out, Vector3(hw + fw * 1.4, 0.03, sd * 0.5), col)
	counts.windows += 1
	if not boarded:
		return
	counts.boarded += 1
	var planks := 3 + int(absf(sin(c.x * 3.1 + c.z)) * 2.0)
	for k in planks:
		var y := -h * 0.4 + h * 0.8 * float(k) / float(maxi(planks - 1, 1))
		var tilt := sin(c.x * 7.0 + float(k) * 2.3) * 0.12
		var r := (right + Vector3.UP * tilt).normalized()
		_plank(boards, c + Vector3.UP * y + out * (fd + 0.015), r, out, hw + fw * 1.2, 0.09)


func _door(cell: Dictionary, a: Vector2, e: Vector2, right: Vector3, out: Vector3, edge_len: float, margin: float,
		door_col: int, spacing: float, ground: float, cls: String, cond: Dictionary, centre: Vector2, trim_col: Color) -> void:
	var dd: Dictionary = d.door
	var t := margin + door_col * spacing + spacing * 0.5 if door_col >= 0 else edge_len * 0.5
	var big := cls != "house"
	var dw := float(dd.w_m) * (1.9 if big else 1.0)
	var dh := float(dd.h_m)
	var base := Vector3(a.x, 0.0, a.y) + right * t
	var trim: SurfaceTool = cell.trim_st
	var door_c := _pick(dd.colors, centre, 29) if not big else Color(0.03, 0.035, 0.04)
	if cond.burned:
		door_c = door_c.darkened(0.8)
	var step_n := int(dd.steps)
	var step_h := float(dd.step_h_m)
	var floor_y := ground + (step_n * step_h if not big else 0.0)
	_box(trim, base + Vector3.UP * (floor_y + dh * 0.5) + out * 0.025, right, out, Vector3(dw * 0.5, dh * 0.5, 0.025), door_c)
	var fw := float(d.frame_w_m)
	_box(trim, base + right * (dw * 0.5 + fw * 0.5) + Vector3.UP * (floor_y + dh * 0.5) + out * 0.04, right, out, Vector3(fw * 0.5, dh * 0.5 + fw, 0.04), trim_col)
	_box(trim, base - right * (dw * 0.5 + fw * 0.5) + Vector3.UP * (floor_y + dh * 0.5) + out * 0.04, right, out, Vector3(fw * 0.5, dh * 0.5 + fw, 0.04), trim_col)
	_box(trim, base + Vector3.UP * (floor_y + dh + fw * 0.5) + out * 0.04, right, out, Vector3(dw * 0.5 + fw, fw * 0.5, 0.04), trim_col)
	counts.doors += 1
	if big:
		return
	var faces: PackedVector3Array = cell.b_faces
	var step_col := Color(0.55, 0.54, 0.5)
	var p: Dictionary = d.porch
	var porch := BuildingLooks.rand01(centre, 30) < float(d.porch_chance)
	var depth := 0.0
	if porch:
		var pw := float(p.w_m) * 0.5
		var pd := float(p.d_m)
		var deck_c := base + out * (pd * 0.5) + Vector3.UP * (ground + floor_y) * 0.5
		var deck_h := (floor_y - ground) * 0.5
		_box(trim, deck_c - Vector3.UP * 0.15, right, out, Vector3(pw, deck_h + 0.15, pd * 0.5), Color(0.42, 0.36, 0.28).darkened(0.6 if cond.burned else 0.0), faces, true)
		for sx: float in [-1.0, 1.0]:
			var post := base + right * (pw - 0.08) * sx + out * (pd - 0.08) + Vector3.UP * (floor_y + float(p.roof_h_m) * 0.5)
			_box(trim, post, right, out, Vector3(0.06, float(p.roof_h_m) * 0.5, 0.06), trim_col)
		_box(trim, base + out * (pd * 0.5 + 0.1) + Vector3.UP * (floor_y + float(p.roof_h_m) + 0.05), right, out,
			Vector3(pw + 0.15, 0.06, pd * 0.5 + 0.1), Color(0.24, 0.22, 0.2).darkened(0.6 if cond.burned else 0.0))
		depth = pd
		counts.porches += 1
		_example("porch", base + Vector3.UP * ground, out)
	for s in step_n:
		var sy := ground + (step_n - s - 1) * step_h
		var sc := base + out * (depth + float(dd.step_d_m) * (s + 0.5)) + Vector3.UP * (sy + step_h * 0.5 - 0.15)
		_box(trim, sc, right, out, Vector3(0.75, step_h * 0.5 + 0.15, float(dd.step_d_m) * 0.5), step_col, faces, true)


func _boarded(cond: Dictionary, centre: Vector2, edge: int, col: int, fl: int) -> bool:
	if cond.boarded and (fl == 0 or BuildingLooks.rand01(centre + Vector2(edge, col), 31) < 0.5):
		return true
	return BuildingLooks.rand01(centre + Vector2(edge * 7 + col, fl * 13), 32) < float(d.boarded_window_chance)


# An axis box (5 sides, the back against the wall left out). half = (along right, up, along out).
# collide = also append its triangles to faces (the building's collision).
func _box(st: SurfaceTool, c: Vector3, right: Vector3, out: Vector3, half: Vector3, col: Color,
		faces := PackedVector3Array(), collide := false) -> void:
	var r := right * half.x
	var u := Vector3.UP * half.y
	var o := out * half.z
	var quads := [
		[c + o - r - u, c + o + r - u, c + o + r + u, c + o - r + u, out],  # front
		[c - o - r + u, c - o + r + u, c + o + r + u, c + o - r + u, Vector3.UP],  # top
		[c - o - r - u, c + o - r - u, c + o + r - u, c - o + r - u, Vector3.DOWN],  # bottom
		[c - o + r - u, c - o + r + u, c + o + r + u, c + o + r - u, right],  # right side
		[c - o - r - u, c + o - r - u, c + o - r + u, c - o - r + u, -right],  # left side
	]
	for q: Array in quads:
		var nrm: Vector3 = q[4]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.set_normal(nrm)
			st.add_vertex(q[k])
			if collide:
				faces.append(q[k])


func _plank(st: SurfaceTool, c: Vector3, right: Vector3, out: Vector3, half_len: float, half_h: float) -> void:
	var up := out.cross(right).normalized() * -1.0
	if up.y < 0.0:
		up = -up
	var r := right * half_len
	var u := up * half_h
	var pts := [c - r - u, c + r - u, c + r + u, c - r + u]
	var uvs := [Vector2(0, 0), Vector2(half_len * 2.0, 0), Vector2(half_len * 2.0, half_h * 2.0), Vector2(0, half_h * 2.0)]
	var shift := Vector2(fmod(absf(c.x * 1.7 + c.z), 3.0), fmod(absf(c.y * 2.3), 2.0))
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_normal(out)
		st.set_uv((uvs[k] as Vector2) + shift)
		st.add_vertex(pts[k])


func _example(kind: String, p: Vector3, out: Vector3) -> void:
	if kind != "" and not examples.has(kind):
		examples[kind] = [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(out.x, 0.001), snappedf(out.z, 0.001)]


func _pick(list: Array, centre: Vector2, salt: int) -> Color:
	var c: Array = list[mini(int(BuildingLooks.rand01(centre, salt) * list.size()), list.size() - 1)]
	return Color(c[0], c[1], c[2])


func _signed_area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		s += p.x * q.y - q.x * p.y
	return s
