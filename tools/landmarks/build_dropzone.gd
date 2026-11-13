# BuildDropZone — landmark builder for Drop Zone (D-074; run this scene directly, no internet needed). Reads
# data/dropzone/dropzone.json and writes world/landmarks/dropzone.scn: the two-storey building on its OSM footprint
# (lobby with bar + arcade, stairs to the upper deck, 32 open hitting bays on the east face with mats, dividers and
# screens, pergola entrance), the range (turf, the coloured target greens, tall net poles and nets), the 18-hole
# putting course (greens, fringe, bunkers, ponds, cups and flags) and the 4 pickleball courts (surface, lines, nets,
# fence). The scene root gets scripts/dropzone/drop_zone.gd, which runs the games at load. Re-run after editing the
# data, then re-run build_cells (navmesh + flat pad). Log: tests/_look/dropzone_build.txt.
# Depends on: DataLoader, LandmarkKit, data/dropzone/dropzone.json.
extends Node

const DATA_PATH := "res://data/dropzone/dropzone.json"
const ROOT_SCRIPT := "res://scripts/dropzone/drop_zone.gd"


func _ready() -> void:
	var d := DataLoader.load_json(DATA_PATH)
	var k := LandmarkKit.new("DropZone", d.materials)
	_building(k, d)
	_bays(k, d)
	_range(k, d)
	_putting(k, d)
	_courts(k, d)
	k.root.set_script(load(ROOT_SCRIPT))
	var msg := k.save(str(d.scene))
	print(msg)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/_look"))
	var f := FileAccess.open("res://tests/_look/dropzone_build.txt", FileAccess.WRITE)
	f.store_string(msg)
	f.close()
	get_tree().quit()


func _building(k: LandmarkKit, d: Dictionary) -> void:
	var b: Dictionary = d.building
	var lo := Vector2(b.lo[0], b.lo[1])
	var hi := Vector2(b.hi[0], b.hi[1])
	var h := float(b.height)
	var up := float(b.upper_y)
	var face := float(d.bay_face_x)
	var t := 0.3
	k.block(Vector3(lo.x, -0.3, lo.y), Vector3(hi.x, 0.02, hi.y), "concrete")
	# North and south walls: white below, grey band above (as in the photo).
	for z: float in [lo.y, hi.y - t]:
		k.block(Vector3(lo.x, 0.0, z), Vector3(face - 6.0, up, z + t), "wall_white")
		k.block(Vector3(lo.x, up, z), Vector3(face, h, z + t), "wall_grey")
		k.block(Vector3(face - 6.0, 0.0, z), Vector3(face, up, z + t), "wall_grey")
	# West wall with the glass entrance in the middle.
	k.block(Vector3(lo.x, 0.0, lo.y), Vector3(lo.x + t, h, -3.0), "wall_white")
	k.block(Vector3(lo.x, 0.0, 3.0), Vector3(lo.x + t, h, hi.y), "wall_white")
	k.block(Vector3(lo.x, 3.0, -3.0), Vector3(lo.x + t, h, 3.0), "wall_grey")
	k.box(Vector3(lo.x + 0.15, 1.5, -2.2), Vector3(0.08, 3.0, 1.6), "glass", 0.0, false)
	k.box(Vector3(lo.x + 0.15, 1.5, 2.2), Vector3(0.08, 3.0, 1.6), "glass", 0.0, false)
	for z: float in [-15.0, -9.0, 9.0, 15.0]:  # windows
		k.box(Vector3(lo.x - 0.02, 2.0, z), Vector3(0.06, 1.6, 3.5), "glass", 0.0, false)
	# Roof, upper deck (mezzanine over the bays), its rail.
	k.block(Vector3(lo.x, h, lo.y), Vector3(hi.x, h + 0.3, hi.y), "roof")
	var mx := float(b.mezzanine_x)
	k.block(Vector3(mx, up - 0.3, lo.y + t), Vector3(face, up, hi.y - t), "concrete")
	k.block(Vector3(mx - 0.1, up, lo.y + t), Vector3(mx, up + 1.0, -19.0), "dark")
	k.block(Vector3(mx - 0.1, up, -16.0), Vector3(mx, up + 1.0, hi.y - t), "dark")
	# Stairs up to the deck (ramp), from the lobby.
	var st: Dictionary = b.stairs
	var zc := (float(st.z0) + float(st.z1)) * 0.5
	k.ramp(Vector3(st.x0, 0.0, zc), Vector3(st.x1, up, zc), float(st.z1) - float(st.z0), 0.3, "concrete")
	# Columns along the bay face.
	for i in 17:
		var z := -24.0 + i * 3.0
		k.block(Vector3(face - 0.3, 0.0, z - 0.15), Vector3(face, h, z + 0.15), "wall_grey")
	# Lobby: bar, tables, arcade row.
	k.block(Vector3(-20.0, 0.0, -20.0), Vector3(-8.0, 1.1, -18.8), "wood")
	k.block(Vector3(-20.0, 1.1, -20.1), Vector3(-8.0, 1.16, -18.6), "dark")
	k.block(Vector3(-20.0, 0.0, -24.8), Vector3(-8.0, 2.4, -24.2), "dark", false)  # back bar shelf
	for p: Vector2 in [Vector2(-18, -6), Vector2(-12, -6), Vector2(-18, 2), Vector2(-12, 2), Vector2(-6, -2)]:
		k.box(Vector3(p.x, 0.75, p.y), Vector3(1.2, 0.06, 1.2), "wood", 0.0, false)
		k.cylinder(Vector3(p.x, 0.0, p.y), 0.08, 0.72, "dark")
	for i in 7:
		var z := 10.0 + i * 2.0
		k.box(Vector3(-27.5, 1.0, z), Vector3(0.9, 2.0, 1.4), "arcade", 0.0, true)
	# Pergola over the entrance.
	for z: float in [-4.0, 4.0]:
		for x: float in [lo.x - 4.0, lo.x - 0.6]:
			k.box(Vector3(x, 1.5, z), Vector3(0.25, 3.0, 0.25), "wood")
	for i in 9:
		k.box(Vector3(lo.x - 2.3, 3.05, -4.0 + i), Vector3(4.2, 0.12, 0.12), "wood", 0.0, false)


func _bays(k: LandmarkKit, d: Dictionary) -> void:
	var face := float(d.bay_face_x)
	for bay: Dictionary in d.bays:
		var y := float(bay.y)
		var z := float(bay.z)
		k.box(Vector3(float(bay.x), y + 0.04, z), Vector3(1.6, 0.04, 1.6), "turf_mat", 0.0, false)
		k.box(Vector3(face - 7.5, y + 1.0, z), Vector3(0.3, 2.0, 0.9), "dark")         # kiosk
		k.box(Vector3(face - 7.32, y + 1.5, z), Vector3(0.04, 0.6, 0.8), "screen", 0.0, false)
		k.box(Vector3(face - 8.6, y + 0.45, z), Vector3(1.6, 0.5, 0.7), "wood")        # bench
	for lvl_y: float in [0.0, float(d.building.upper_y)]:
		for i in 17:  # dividers between bays
			var z := -24.0 + i * 3.0
			k.block(Vector3(face - 7.0, lvl_y, z - 0.05), Vector3(face - 0.3, lvl_y + 2.4, z + 0.05), "wall_white", false)
	# Upper deck rail at the bay face.
	k.block(Vector3(face - 0.1, float(d.building.upper_y), -24.0), Vector3(face, float(d.building.upper_y) + 1.0, 24.0), "dark")


func _range(k: LandmarkKit, d: Dictionary) -> void:
	var r: Dictionary = d.range
	var y := 0.03
	k.quad(Vector3(r.x0, y, r.z0), Vector3(r.x1, y, r.z0), Vector3(r.x1, y, r.z1), Vector3(r.x0, y, r.z1), "turf")
	for tg: Dictionary in d.targets:
		var c := Vector3(tg.x, 0.05, tg.z)
		var col := str(tg.color)
		k.disc(c, float(tg.r), col, 32)
		k.disc(c + Vector3.UP * 0.01, float(tg.r) * 0.34, "dark" if col == "white" else "white", 24)
		k.cylinder(c, 0.03, 1.8, "pole", 6)
		k.box(c + Vector3(0.3, 1.6, 0.0), Vector3(0.6, 0.35, 0.02), col, 0.0, false)
	var n: Dictionary = d.nets
	var hgt := float(n.height)
	var every := float(n.pole_every)
	for zline: float in [float(n.north_z), float(n.south_z)]:
		var x := float(r.x0)
		var prev := x
		while x <= float(n.far_x) + 0.1:
			k.cylinder(Vector3(x, 0.0, zline), 0.25, hgt, "pole", 8, true)
			if x > prev:
				k.quad(Vector3(prev, 0.0, zline), Vector3(x, 0.0, zline), Vector3(x, hgt, zline), Vector3(prev, hgt, zline), "net")
			prev = x
			x += every
	var z := float(n.north_z)
	var zprev := z
	while z <= float(n.south_z) + 0.1:
		k.cylinder(Vector3(n.far_x, 0.0, z), 0.25, hgt, "pole", 8, true)
		if z > zprev:
			k.quad(Vector3(n.far_x, 0.0, zprev), Vector3(n.far_x, 0.0, z), Vector3(n.far_x, hgt, z), Vector3(n.far_x, hgt, zprev), "net")
		zprev = z
		z += (float(n.south_z) - float(n.north_z)) / 3.0


func _putting(k: LandmarkKit, d: Dictionary) -> void:
	var p: Dictionary = d.putting
	var a: Array = p.area
	k.quad(Vector3(a[0], 0.02, a[1]), Vector3(a[2], 0.02, a[1]), Vector3(a[2], 0.02, a[3]), Vector3(a[0], 0.02, a[3]), "fringe")
	for h: Dictionary in p.holes:
		var g: Dictionary = h.green
		var c := Vector3(g.c[0], 0.03, g.c[1])
		var pts: Array[Vector3] = []
		for i in 28:
			var ang := TAU * i / 28.0
			var q := Vector2(cos(ang) * float(g.a), sin(ang) * float(g.b)).rotated(float(g.rot))
			pts.append(c + Vector3(q.x, 0.0, q.y))
		for i in 28:
			k.tri(c, pts[(i + 1) % 28], pts[i], "green")
		if h.has("bunker"):
			k.disc(Vector3(h.bunker.c[0], 0.035, h.bunker.c[1]), float(h.bunker.r), "sand", 16)
		if h.has("water"):
			k.disc(Vector3(h.water.c[0], 0.036, h.water.c[1]), float(h.water.r), "pond", 16)
		var cup := Vector3(h.cup[0], 0.04, h.cup[1])
		k.disc(cup, 0.08, "cup", 12)
		k.cylinder(cup, 0.01, 1.2, "white", 4)
		k.box(cup + Vector3(0.14, 1.08, 0.0), Vector3(0.28, 0.18, 0.01), "red", 0.0, false)
		k.box(Vector3(h.tee[0], 0.035, h.tee[1]), Vector3(0.5, 0.01, 0.5), "white", 0.0, false)
	var s: Array = p.start
	k.box(Vector3(s[0], 0.9, s[1]), Vector3(1.4, 1.8, 0.2), "dark")


func _courts(k: LandmarkKit, d: Dictionary) -> void:
	var a: Array = d.pickle_area
	k.quad(Vector3(a[0], 0.02, a[1]), Vector3(a[2], 0.02, a[1]), Vector3(a[2], 0.02, a[3]), Vector3(a[0], 0.02, a[3]), "court_out")
	var hw := float(d.court_size[0]) * 0.5
	var hl := float(d.court_size[1]) * 0.5
	for ct: Dictionary in d.courts:
		var c := Vector3(ct.c[0], 0.03, ct.c[1])
		k.quad(c + Vector3(-hw, 0, -hl), c + Vector3(hw, 0, -hl), c + Vector3(hw, 0, hl), c + Vector3(-hw, 0, hl), "court")
		var y := Vector3(0, 0.005, 0)
		for z: float in [-hl, hl, -2.13, 2.13]:  # baselines + kitchen lines
			k.box(c + y + Vector3(0, 0, z), Vector3(hw * 2.0, 0.005, 0.05), "line", 0.0, false)
		for x: float in [-hw, hw]:
			k.box(c + y + Vector3(x, 0, 0), Vector3(0.05, 0.005, hl * 2.0), "line", 0.0, false)
		for z: float in [-hl, hl]:  # centre service lines (baseline to kitchen)
			k.box(c + y + Vector3(0, 0, (z + signf(z) * 2.13) * 0.5), Vector3(0.05, 0.005, hl - 2.13), "line", 0.0, false)
		k.box(c + Vector3(0, 0.45, 0), Vector3(hw * 2.0 + 0.6, 0.86, 0.03), "net", 0.0, false)
		k.box(c + Vector3(0, 0.88, 0), Vector3(hw * 2.0 + 0.6, 0.05, 0.05), "white", 0.0, false)
		for x: float in [-hw - 0.3, hw + 0.3]:
			k.cylinder(c + Vector3(x, 0, 0), 0.04, 0.92, "pole", 6)
		k.box(c + Vector3(hw + 1.0, 0.7, hl - 1.0), Vector3(0.2, 1.4, 0.2), "dark")  # scoreboard post (E to play)
	var corners := PackedVector3Array([Vector3(a[0], 0, a[1]), Vector3(a[2], 0, a[1]), Vector3(a[2], 0, a[3]), Vector3(a[0], 0, a[3]), Vector3(a[0], 0, a[1])])
	k.railing(corners, 1.2, "pole", 2.5, false)
