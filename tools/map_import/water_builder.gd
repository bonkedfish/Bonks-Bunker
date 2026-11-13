# WaterBuilder — lakes, ponds and rivers for the map importer (D-047), from OSM natural=water (ways + multipolygon
# outer rings) and waterway lines, tuned by data/map/water.json. "overrides" (D-073): inside a rect, OSM's carve is
# replaced by traced rings (where the OSM outline is off the imagery).
# Builds a carve map on the terrain lattice (lattice_m, same as terrain_step_m): for every lattice vertex under water
# it stores the water surface height and the bed height. Lakes: flat surface just below the lowest shore point,
# bed sloping down from the shore to lake_max_depth_m. Rivers/canals: surface follows the ground along the centre
# line (minus a bank drop), bed is a rounded channel of the waterway's width/depth. Vertices within road_keep_m of
# a drivable road are never carved, so roads keep their embankment over culverts.
# build_cells asks ground(x, z) for terrain heights, is_water(p) to keep props out, and add_cell() for each cell's
# water surface mesh (StreetSurface-style shader material), its swim-detection collider (layer 6 = 32) and far-shell
# quads. Depends on: DataLoader, MapProjection, HeightField, shaders/water.gdshader.
class_name WaterBuilder
extends RefCounted

const DATA_PATH := "res://data/map/water.json"
const SHADER_PATH := "res://shaders/water.gdshader"
const SURFACE_LAYER := 32

var data: Dictionary
var material: ShaderMaterial
var bodies := 0
var _field: HeightField
var _step := 4.0
var _surface: Dictionary = {}  # Vector2i lattice -> water surface y
var _bed: Dictionary = {}      # Vector2i lattice -> bed y
var _roads: Dictionary = {}    # Vector2i (32 m) -> Array of [a, b, half]


func _init(src: Dictionary, proj: MapProjection, field: HeightField, drivable_half_widths: Dictionary) -> void:
	data = DataLoader.load_json(DATA_PATH)
	_field = field
	_step = float(data.get("lattice_m", 4.0))
	for el: Dictionary in src.get("elements", []):
		var kind := str(el.get("tags", {}).get("highway", ""))
		if drivable_half_widths.has(kind):
			var pts := _points(el.get("geometry", []), proj)
			for i in range(pts.size() - 1):
				_hash_road(pts[i], pts[i + 1], float(drivable_half_widths[kind]))
	for el: Dictionary in src.get("elements", []):
		var tags: Dictionary = el.get("tags", {})
		if str(tags.get("natural", "")) == "water":
			if el.get("type", "") == "relation":
				for m: Dictionary in el.get("members", []):
					if str(m.get("role", "")) == "outer":
						_carve_lake(_points(m.get("geometry", []), proj))
			else:
				_carve_lake(_points(el.get("geometry", []), proj))
		elif tags.has("waterway"):
			_carve_river(_points(el.get("geometry", []), proj), str(tags.waterway), str(tags.get("name", "")))
	for o: Dictionary in data.get("overrides", []):  # traced shorelines where OSM is off (D-073)
		_override(o)
	var s: Dictionary = data.shader
	material = ShaderMaterial.new()
	material.shader = load(SHADER_PATH)
	material.set_shader_parameter("shallow", _color(s.shallow))
	material.set_shader_parameter("deep", _color(s.deep))
	material.set_shader_parameter("depth_fade_m", float(s.depth_fade_m))
	material.set_shader_parameter("wave_scale", float(s.wave_scale))


# Terrain height at a lattice vertex (or anywhere): the carved bed under water, else the plain field.
func ground(x: float, z: float) -> float:
	var k := Vector2i(roundi(x / _step), roundi(z / _step))
	if _bed.has(k) and absf(x - k.x * _step) < 0.01 and absf(z - k.y * _step) < 0.01:
		return _bed[k]
	return _field.sample(x, z)


func is_water(p: Vector2) -> bool:
	return _surface.has(Vector2i(roundi(p.x / _step), roundi(p.y / _step)))


# Water quads for one cell: the surface mesh + swim collider under `root`, flat quads into the far shell.
func add_cell(rect: Rect2, root: Node3D, far_st: SurfaceTool) -> int:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var n := roundi(rect.size.x / _step)
	var quads := 0
	var fc := _color(data.far_color)
	for iz in n:
		for ix in n:
			var x0 := rect.position.x + ix * _step
			var z0 := rect.position.y + iz * _step
			var keys := [Vector2i(roundi(x0 / _step), roundi(z0 / _step)), Vector2i(roundi(x0 / _step) + 1, roundi(z0 / _step)),
				Vector2i(roundi(x0 / _step) + 1, roundi(z0 / _step) + 1), Vector2i(roundi(x0 / _step), roundi(z0 / _step) + 1)]
			var y := -INF
			var depth := 0.0
			for k: Vector2i in keys:
				if _surface.has(k):
					y = maxf(y, _surface[k])
					depth = maxf(depth, float(_surface[k]) - float(_bed[k]))
			if y == -INF:
				continue
			# Each corner at its own surface height (rivers slope smoothly); dry corners take the quad's highest.
			var ys: Array[float] = []
			for k: Vector2i in keys:
				ys.append(float(_surface[k]) if _surface.has(k) else y)
			var corners := [Vector3(x0, ys[0], z0), Vector3(x0 + _step, ys[1], z0), Vector3(x0 + _step, ys[2], z0 + _step), Vector3(x0, ys[3], z0 + _step)]
			for i in [0, 1, 2, 0, 2, 3]:
				var v: Vector3 = corners[i]
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(v.x, v.z))
				st.set_color(Color(depth / 8.0, 0, 0))
				st.add_vertex(v)
				faces.append(v)
				far_st.set_color(fc)
				far_st.set_normal(Vector3.UP)
				far_st.add_vertex(v)
			quads += 1
	if quads == 0:
		return 0
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = st.commit()
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "WaterSurface"
	body.collision_layer = SURFACE_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.backface_collision = true
	concave.set_faces(faces)
	shape.shape = concave
	body.add_child(shape)
	root.add_child(body)
	return quads


# --- carving -------------------------------------------------------------------------------

# Inside the override's rect (map coords), drops what OSM carved and carves the traced rings instead, at the level the
# OSM water had there (so the lake surface stays one level across the rect edge).
func _override(o: Dictionary) -> void:
	var r: Array = o.rect
	var rect := Rect2(Vector2(r[0], r[1]), Vector2(float(r[2]) - float(r[0]), float(r[3]) - float(r[1])))
	var level := INF
	for k: Vector2i in _surface.keys():
		if rect.has_point(Vector2(k) * _step):
			level = minf(level, float(_surface[k]))
			_surface.erase(k)
			_bed.erase(k)
	for ring: Array in o.get("lakes", []):
		var poly := PackedVector2Array()
		for q: Array in ring:
			poly.append(Vector2(q[0], q[1]))
		_carve_lake(poly, level)


# fixed_surface: use this water level instead of the lowest shore point (NAN / INF = from the shore).
func _carve_lake(poly: PackedVector2Array, fixed_surface := NAN) -> void:
	if poly.size() < 4:
		return
	bodies += 1
	var shore := INF
	for p in poly:
		shore = minf(shore, _field.sample(p.x, p.y))
	var surface := shore - float(data.lake_freeboard_m)
	if not is_nan(fixed_surface) and fixed_surface != INF:
		surface = fixed_surface
	var lo := Vector2(INF, INF)
	var hi := -lo
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	for gz in range(floori(lo.y / _step), ceili(hi.y / _step) + 1):
		for gx in range(floori(lo.x / _step), ceili(hi.x / _step) + 1):
			var p := Vector2(gx * _step, gz * _step)
			if not Geometry2D.is_point_in_polygon(p, poly) or _near_road(p):
				continue
			var d := INF
			for i in poly.size():
				d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])))
			var depth := clampf(d * float(data.lake_shore_slope), float(data.min_depth_m), float(data.lake_max_depth_m))
			_store(Vector2i(gx, gz), surface, minf(surface - depth, _field.sample(p.x, p.y) - 0.1))


func _carve_river(line: PackedVector2Array, kind: String, river_name: String) -> void:
	var widths: Dictionary = data.waterway_widths_m
	if line.size() < 2 or not widths.has(kind):
		return
	bodies += 1
	var half := float(widths[kind]) * 0.5
	var max_depth := float(data.waterway_depths_m.get(kind, 1.0))
	for key: String in data.name_overrides:
		if river_name.begins_with(key):
			half = float(data.name_overrides[key].width_m) * 0.5
			max_depth = float(data.name_overrides[key].depth_m)
	for i in range(line.size() - 1):
		var a := line[i]
		var b := line[i + 1]
		var lo := a.min(b) - Vector2.ONE * half
		var hi := a.max(b) + Vector2.ONE * half
		for gz in range(floori(lo.y / _step), ceili(hi.y / _step) + 1):
			for gx in range(floori(lo.x / _step), ceili(hi.x / _step) + 1):
				var p := Vector2(gx * _step, gz * _step)
				var c := Geometry2D.get_closest_point_to_segment(p, a, b)
				var d := p.distance_to(c)
				if d > half or _near_road(p):
					continue
				var surface := _field.sample(c.x, c.y) - float(data.river_bank_drop_m)
				var depth := maxf(max_depth * (1.0 - pow(d / half, 2.0)), float(data.min_depth_m))
				_store(Vector2i(gx, gz), surface, minf(surface - depth, _field.sample(p.x, p.y) - 0.1))


# Where two bodies overlap keep the lower surface (water runs downhill) and the deeper bed.
func _store(k: Vector2i, surface: float, bed: float) -> void:
	if _surface.has(k):
		surface = minf(surface, _surface[k])
		bed = minf(bed, _bed[k])
	_surface[k] = surface
	_bed[k] = minf(bed, surface - float(data.min_depth_m))


func _hash_road(a: Vector2, b: Vector2, half: float) -> void:
	var r := half + float(data.road_keep_m)
	for gz in range(floori((minf(a.y, b.y) - r) / 32.0), floori((maxf(a.y, b.y) + r) / 32.0) + 1):
		for gx in range(floori((minf(a.x, b.x) - r) / 32.0), floori((maxf(a.x, b.x) + r) / 32.0) + 1):
			var k := Vector2i(gx, gz)
			if not _roads.has(k):
				_roads[k] = []
			_roads[k].append([a, b, r])


func _near_road(p: Vector2) -> bool:
	for e: Array in _roads.get(Vector2i(floori(p.x / 32.0), floori(p.y / 32.0)), []):
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, e[0], e[1])) < float(e[2]):
			return true
	return false


func _points(geom: Array, proj: MapProjection) -> PackedVector2Array:
	var out := PackedVector2Array()
	for g: Dictionary in geom:
		out.append(proj.to_local(float(g.lat), float(g.lon)))
	return out


func _color(c: Array) -> Color:
	return Color(float(c[0]), float(c[1]), float(c[2]))
