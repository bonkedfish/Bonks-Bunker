# BuildCell — map import pipeline, step 2 (run this scene directly; no internet needed).
# Reads data/map/import_config.json, the raw OSM JSON saved by fetch_osm, and data/map/landmarks.json,
# then generates one cell scene and saves it to output_scene:
#   Ground      flat ground minus landmark ground holes (box collision per rect, one mesh)
#   Boundary    invisible walls at the cell edge
#   Buildings   every OSM building extruded and merged into ONE mesh + ONE trimesh collider,
#               except buildings a landmark replaces (replaces_osm_ways / exclusion_radius_m)
#   Roads       drivable roads and paths as flat strips (two meshes, visual only)
#   ZombieSpawns  markers every SPAWN_SPACING metres along drivable roads
# Re-running regenerates the cell from the saved source; landmarks are separate data and untouched.
# Depends on: DataLoader, MapProjection.
extends Node

const CONFIG_PATH := "res://data/map/import_config.json"
const LANDMARKS_PATH := "res://data/map/landmarks.json"
const ROAD_WIDTHS := {
	"motorway": 14.0, "trunk": 12.0, "primary": 12.0, "secondary": 10.0, "tertiary": 9.0,
	"residential": 7.5, "unclassified": 7.0, "living_street": 6.0, "service": 4.5, "track": 3.0,
	"footway": 1.8, "path": 1.5, "cycleway": 2.0, "pedestrian": 3.0,
}
const DRIVABLE := ["motorway", "trunk", "primary", "secondary", "tertiary", "residential",
	"unclassified", "living_street", "service"]
const BUILDING_HEIGHTS := {"house": 5.0, "garage": 3.0, "shed": 2.5, "school": 8.0, "commercial": 7.0,
	"retail": 6.0, "apartments": 10.0, "static_caravan": 3.2}
const DEFAULT_BUILDING_HEIGHT := 5.0
const SPAWN_SPACING := 30.0
const SPAWN_EDGE_MARGIN := 10.0
const BOUNDARY_HEIGHT := 10.0


func _ready() -> void:
	var cfg := DataLoader.load_json(CONFIG_PATH)
	var landmarks := DataLoader.load_json(LANDMARKS_PATH)
	var src := DataLoader.load_json(str(cfg.get("source_path", "")))
	if cfg.is_empty() or src.is_empty():
		_finish("BUILD: missing config or source data - run tools/map_import/fetch_osm.tscn first")
		return
	var proj := MapProjection.new(float(cfg.center_lat), float(cfg.center_lon))
	var r := float(cfg.radius_m)

	var skip_ways := {}
	var exclusions: Array = []  # [Vector2 centre, radius]
	var holes: Array[Rect2] = []
	for key: String in landmarks:
		var lm: Dictionary = landmarks[key]
		var pos := proj.to_local(float(lm.lat), float(lm.lon))
		for id in lm.get("replaces_osm_ways", []):
			skip_ways[int(id)] = true
		if lm.has("exclusion_radius_m"):
			exclusions.append([pos, float(lm.exclusion_radius_m)])
		var rot := deg_to_rad(float(lm.get("rotation_deg", 0.0)))
		for h in lm.get("ground_holes", []):  # [x_min, z_min, x_max, z_max] in landmark space
			var a := Vector2(h[0], h[1]).rotated(-rot) + pos
			var b := Vector2(h[2], h[3]).rotated(-rot) + pos
			holes.append(Rect2(a, b - a).abs())

	var root := Node3D.new()
	root.name = str(cfg.cell_name)
	_build_ground(root, r, holes)
	_build_boundary(root, r)
	var counts := _build_buildings(root, src, proj, r, skip_ways, exclusions)
	var road_count := _build_roads(root, src, proj, r)
	var spawn_count := _build_spawns(root, src, proj, r)
	_set_owner(root, root)

	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		var out := str(cfg.output_scene)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
		err = ResourceSaver.save(packed, out)
	_finish("BUILD: %s -> %s (error %d): %d buildings (%d skipped for landmarks), %d road ways, %d zombie spawns, %d ground holes" % [
		cfg.cell_name, cfg.output_scene, err, counts.x, counts.y, road_count, spawn_count, holes.size()])


# --- ground + boundary -----------------------------------------------------------

func _build_ground(root: Node3D, r: float, holes: Array[Rect2]) -> void:
	var rects: Array[Rect2] = [Rect2(-r, -r, 2.0 * r, 2.0 * r)]
	for hole in holes:
		rects = _subtract(rects, hole)
	var body := StaticBody3D.new()
	body.name = "Ground"
	root.add_child(body)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for rc in rects:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(rc.size.x, 1.0, rc.size.y)
		shape.shape = box
		shape.position = Vector3(rc.get_center().x, -0.5, rc.get_center().y)
		body.add_child(shape)
		_quad(st, Vector3(rc.position.x, 0, rc.position.y), Vector3(rc.end.x, 0, rc.position.y),
			Vector3(rc.end.x, 0, rc.end.y), Vector3(rc.position.x, 0, rc.end.y))
	_add_mesh(body, "Mesh", st, _material(Color(0.42, 0.4, 0.3)))


func _subtract(rects: Array[Rect2], hole: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for rc in rects:
		if not rc.intersects(hole):
			out.append(rc)
			continue
		var i := rc.intersection(hole)
		if i.position.y > rc.position.y:
			out.append(Rect2(rc.position.x, rc.position.y, rc.size.x, i.position.y - rc.position.y))
		if i.end.y < rc.end.y:
			out.append(Rect2(rc.position.x, i.end.y, rc.size.x, rc.end.y - i.end.y))
		if i.position.x > rc.position.x:
			out.append(Rect2(rc.position.x, i.position.y, i.position.x - rc.position.x, i.size.y))
		if i.end.x < rc.end.x:
			out.append(Rect2(i.end.x, i.position.y, rc.end.x - i.end.x, i.size.y))
	return out


func _build_boundary(root: Node3D, r: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Boundary"
	root.add_child(body)
	for side in [Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, 0, r), Vector3(0, 0, -r)]:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.0, BOUNDARY_HEIGHT, 2.0 * r) if side.x != 0.0 else Vector3(2.0 * r, BOUNDARY_HEIGHT, 1.0)
		shape.shape = box
		shape.position = side + Vector3(signf(side.x) * 0.5, BOUNDARY_HEIGHT * 0.5, signf(side.z) * 0.5)
		body.add_child(shape)


# --- buildings -------------------------------------------------------------------

# Returns Vector2i(built, skipped).
func _build_buildings(root: Node3D, src: Dictionary, proj: MapProjection, r: float,
		skip_ways: Dictionary, exclusions: Array) -> Vector2i:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var built := 0
	var skipped := 0
	for el: Dictionary in src.get("elements", []):
		var tags: Dictionary = el.get("tags", {})
		var geom: Array = el.get("geometry", [])
		if not tags.has("building") or geom.size() < 4:
			continue
		var poly := PackedVector2Array()
		for g: Dictionary in geom:
			poly.append(proj.to_local(float(g.lat), float(g.lon)))
		if poly[0].distance_to(poly[poly.size() - 1]) < 0.01:
			poly.remove_at(poly.size() - 1)
		var centre := Vector2.ZERO
		for p in poly:
			centre += p
		centre /= poly.size()
		if absf(centre.x) > r or absf(centre.y) > r:
			continue
		if skip_ways.has(int(el.id)) or _excluded(centre, exclusions):
			skipped += 1
			continue
		_extrude(st, faces, poly, _building_height(tags))
		built += 1
	var body := StaticBody3D.new()
	body.name = "Buildings"
	root.add_child(body)
	if built > 0:
		_add_mesh(body, "Mesh", st, _material(Color(0.62, 0.58, 0.52)))
		var shape := CollisionShape3D.new()
		var concave := ConcavePolygonShape3D.new()
		concave.backface_collision = true
		concave.set_faces(faces)
		shape.shape = concave
		body.add_child(shape)
	return Vector2i(built, skipped)


func _excluded(centre: Vector2, exclusions: Array) -> bool:
	for ex in exclusions:
		if centre.distance_to(ex[0]) <= ex[1]:
			return true
	return false


func _building_height(tags: Dictionary) -> float:
	if tags.has("height"):
		var h := str(tags.height).replace("m", "").strip_edges()
		if h.is_valid_float():
			return h.to_float()
	if tags.has("building:levels") and str(tags["building:levels"]).is_valid_float():
		return str(tags["building:levels"]).to_float() * 3.0 + 1.0
	return BUILDING_HEIGHTS.get(str(tags.building), DEFAULT_BUILDING_HEIGHT)


# Walls + flat roof. Materials render both faces, so winding only matters for the normals we set.
func _extrude(st: SurfaceTool, faces: PackedVector3Array, poly: PackedVector2Array, h: float) -> void:
	var area := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	if area < 0.0:
		poly.reverse()
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var e := (b - a).normalized()
		st.set_normal(Vector3(e.y, 0.0, -e.x))
		var tri := [Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(b.x, h, b.y),
			Vector3(a.x, 0, a.y), Vector3(b.x, h, b.y), Vector3(a.x, h, a.y)]
		for v: Vector3 in tri:
			st.add_vertex(v)
			faces.append(v)
	var idx := Geometry2D.triangulate_polygon(poly)
	st.set_normal(Vector3.UP)
	for i in idx:
		var v := Vector3(poly[i].x, h, poly[i].y)
		st.add_vertex(v)
		faces.append(v)


# --- roads -------------------------------------------------------------------------

func _build_roads(root: Node3D, src: Dictionary, proj: MapProjection, r: float) -> int:
	var asphalt := SurfaceTool.new()
	asphalt.begin(Mesh.PRIMITIVE_TRIANGLES)
	asphalt.set_normal(Vector3.UP)
	var paths := SurfaceTool.new()
	paths.begin(Mesh.PRIMITIVE_TRIANGLES)
	paths.set_normal(Vector3.UP)
	var count := 0
	for el: Dictionary in src.get("elements", []):
		var tags: Dictionary = el.get("tags", {})
		var kind := str(tags.get("highway", ""))
		if not ROAD_WIDTHS.has(kind):
			continue
		var drivable := kind in DRIVABLE
		var st := asphalt if drivable else paths
		var y := 0.02 if drivable else 0.03
		var half := float(ROAD_WIDTHS[kind]) * 0.5
		var pts: Array[Vector2] = []
		for g: Dictionary in el.get("geometry", []):
			pts.append(proj.to_local(float(g.lat), float(g.lon)))
		var used := false
		for i in range(pts.size() - 1):
			var a := pts[i]
			var b := pts[i + 1]
			if not _inside(a, r) and not _inside(b, r):
				continue
			var side := (b - a).normalized().orthogonal() * half
			_quad(asphalt if drivable else paths, Vector3(a.x - side.x, y, a.y - side.y), Vector3(b.x - side.x, y, b.y - side.y),
				Vector3(b.x + side.x, y, b.y + side.y), Vector3(a.x + side.x, y, a.y + side.y))
			_cap(st, b, half, y)  # round off joints
			used = true
		if used:
			count += 1
	_add_mesh(root, "Roads", asphalt, _material(Color(0.18, 0.18, 0.19)))
	_add_mesh(root, "Paths", paths, _material(Color(0.55, 0.53, 0.5)))
	return count


func _inside(p: Vector2, r: float) -> bool:
	return absf(p.x) <= r and absf(p.y) <= r


func _cap(st: SurfaceTool, c: Vector2, radius: float, y: float) -> void:
	for i in 8:
		var a0 := TAU * i / 8.0
		var a1 := TAU * (i + 1) / 8.0
		st.add_vertex(Vector3(c.x, y, c.y))
		st.add_vertex(Vector3(c.x + cos(a0) * radius, y, c.y + sin(a0) * radius))
		st.add_vertex(Vector3(c.x + cos(a1) * radius, y, c.y + sin(a1) * radius))


# --- zombie spawns ---------------------------------------------------------------------

func _build_spawns(root: Node3D, src: Dictionary, proj: MapProjection, r: float) -> int:
	var holder := Node3D.new()
	holder.name = "ZombieSpawns"
	root.add_child(holder)
	var n := 0
	for el: Dictionary in src.get("elements", []):
		var kind := str(el.get("tags", {}).get("highway", ""))
		if not kind in DRIVABLE:
			continue
		var carried := SPAWN_SPACING * 0.5
		var geom: Array = el.get("geometry", [])
		for i in range(geom.size() - 1):
			var a := proj.to_local(float(geom[i].lat), float(geom[i].lon))
			var b := proj.to_local(float(geom[i + 1].lat), float(geom[i + 1].lon))
			var length := a.distance_to(b)
			var t := carried
			while t < length:
				var p := a.lerp(b, t / length)
				if _inside(p, r - SPAWN_EDGE_MARGIN):
					var m := Marker3D.new()
					m.name = "Spawn%d" % n
					m.position = Vector3(p.x, 0.1, p.y)
					holder.add_child(m)
					n += 1
				t += SPAWN_SPACING
			carried = t - length
	return n


# --- helpers ------------------------------------------------------------------------

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)


func _add_mesh(parent: Node, node_name: String, st: SurfaceTool, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)


func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _set_owner(node: Node, owner_node: Node) -> void:
	for c in node.get_children():
		c.owner = owner_node
		_set_owner(c, owner_node)


func _finish(message: String) -> void:
	print(message)
	await get_tree().create_timer(20.0).timeout
	get_tree().quit()
