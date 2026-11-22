# GrassField — 3D grass around the camera (D-115). Main child "Grass", group "grass", every peer (presentation
# only; nothing networked, nothing collides).
# The ground around the camera is split into chunk_m squares; every chunk within the graphics tier's radius_m
# gets one MultiMesh of grass clumps (pooled nodes, at most builds_per_frame built a frame, nearest first).
# Where clumps go: density per m2 x the cell's grass mask (tools/map_import/build_grass_masks: low on roads,
# none on buildings / water / greens), then a ray down onto the cell's "Terrain" body - if it hits anything else
# (a building, a landmark floor, a car) there is no clump. A chunk is seeded from its coordinates, so it looks the
# same every time it is rebuilt. Low tier: off. Masks load and unload with their cells (WorldStreamer signals).
# Perf: one draw call per chunk, no shadows; ~250 rays per chunk build, only when the camera reaches new ground.
# Depends on: DataLoader, data/tuning/grass.json, shaders/grass.gdshader, Graphics autoload, WorldStreamer.
class_name GrassField
extends Node3D

const TUNING := "res://data/tuning/grass.json"
const SHADER := preload("res://shaders/grass.gdshader")
const TERRAIN_MASK := 1

var built_count := 0  # chunks built so far (tests)
var build_ms := 0.0  # time the last chunk build took (tests / perf)
var active: Dictionary = {}  # Vector2i chunk -> MultiMeshInstance3D

var _t: Dictionary
var _density := 0.0
var _radius := 0.0
var _chunk := 16.0
var _streamer: Node
var _masks: Dictionary = {}  # Vector2i cell -> PackedByteArray
var _mask_n := 256
var _queue: Array[Vector2i] = []
var _pool: Array[MultiMeshInstance3D] = []
var _mesh: ArrayMesh
var _mat: ShaderMaterial
var _update_in := 0.0
var _buf := PackedFloat32Array()


func _ready() -> void:
	add_to_group("grass")
	_t = DataLoader.load_json(TUNING)
	_chunk = float(_t.chunk_m)
	_mesh = _clump_mesh()
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("wind_m", float(_t.wind_m))
	var g := get_node_or_null("/root/Graphics")
	if g:
		g.tier_changed.connect(_apply_tier)
		_apply_tier(str(g.tier))
	else:
		_apply_tier("medium")


func _apply_tier(tier: String) -> void:
	var tt: Dictionary = _t.tiers.get(tier, _t.tiers.medium)
	_density = float(tt.density)
	_radius = float(tt.radius_m)
	_mat.set_shader_parameter("fade_end_m", _radius)
	_mat.set_shader_parameter("fade_start_m", _radius * (1.0 - float(_t.fade_share)))
	for ch: Vector2i in active.keys():
		_release(ch)
	_queue.clear()


func _process(delta: float) -> void:
	if _streamer == null:
		_streamer = get_tree().get_first_node_in_group("world_streamer")
		if _streamer and _streamer.get("grid") != null:
			_streamer.cell_loaded.connect(_on_cell_loaded)
			_streamer.cell_unloaded.connect(_on_cell_unloaded)
			for c: Vector2i in _streamer.near_loaded:
				_on_cell_loaded(c)
		else:
			_streamer = null
			return
	var cam := get_viewport().get_camera_3d()
	if cam == null or _density <= 0.0:
		return
	_update_in -= delta
	if _update_in <= 0.0:
		_update_in = float(_t.update_s)
		_plan(cam.global_position)
	for i in int(_t.builds_per_frame):
		if _queue.is_empty():
			break
		_build(_queue.pop_front(), cam.global_position)


# Which chunks should exist: release the far ones, queue the missing ones nearest first.
func _plan(at: Vector3) -> void:
	var here := Vector2(at.x, at.z)
	var keep := (_radius + _chunk) * (_radius + _chunk)
	for ch: Vector2i in active.keys():
		if _centre(ch).distance_squared_to(here) > keep:
			_release(ch)
	var r := ceili(_radius / _chunk)
	var c0 := Vector2i(floori(at.x / _chunk), floori(at.z / _chunk))
	var want: Array[Vector2i] = []
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var ch := c0 + Vector2i(dx, dz)
			if not active.has(ch) and _centre(ch).distance_to(here) < _radius + _chunk * 0.71:
				want.append(ch)
	want.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _centre(a).distance_squared_to(here) < _centre(b).distance_squared_to(here))
	_queue = want


func busy() -> bool:
	return not _queue.is_empty()


func _build(ch: Vector2i, cam_pos: Vector3) -> void:
	var t0 := Time.get_ticks_usec()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(ch)
	var space := get_world_3d().direct_space_state
	var tries := int(_density * _chunk * _chunk)
	var origin := Vector2(ch) * _chunk
	var sc: Array = _t.clump_scale
	var green := Color(_t.green_tip_color[0], _t.green_tip_color[1], _t.green_tip_color[2])
	_buf.resize(tries * 16)
	var n := 0
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = TERRAIN_MASK
	for i in tries:
		var x := origin.x + rng.randf() * _chunk
		var z := origin.y + rng.randf() * _chunk
		var m := _mask_at(x, z)
		if m <= 0.0 or rng.randf() > m:
			continue
		q.from = Vector3(x, cam_pos.y + 80.0, z)
		q.to = Vector3(x, cam_pos.y - 80.0, z)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or str((hit.collider as Node).name) != "Terrain":
			continue
		var p: Vector3 = hit.position
		var s := rng.randf_range(float(sc[0]), float(sc[1]))
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.2), s))
		var k := n * 16
		_buf[k] = b.x.x; _buf[k + 1] = b.y.x; _buf[k + 2] = b.z.x; _buf[k + 3] = p.x
		_buf[k + 4] = b.x.y; _buf[k + 5] = b.y.y; _buf[k + 6] = b.z.y; _buf[k + 7] = p.y
		_buf[k + 8] = b.x.z; _buf[k + 9] = b.y.z; _buf[k + 10] = b.z.z; _buf[k + 11] = p.z
		var tint := Color(1, 1, 1).lerp(green * 1.6, float(_t.green_share) * rng.randf() * 1.5)
		var v := rng.randf_range(0.82, 1.12)
		_buf[k + 12] = tint.r * v; _buf[k + 13] = tint.g * v; _buf[k + 14] = tint.b * v; _buf[k + 15] = 1.0
		n += 1
	var mmi: MultiMeshInstance3D = _pool.pop_back() if not _pool.is_empty() else _new_node()
	var mm := mmi.multimesh
	mm.instance_count = n
	if n > 0:
		mm.buffer = _buf.slice(0, n * 16)
	mmi.visible = n > 0
	active[ch] = mmi
	built_count += 1
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _new_node() -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _mesh
	mmi.multimesh = mm
	mmi.material_override = _mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


func _release(ch: Vector2i) -> void:
	var mmi: MultiMeshInstance3D = active[ch]
	active.erase(ch)
	mmi.visible = false
	mmi.multimesh.instance_count = 0
	_pool.append(mmi)


func _centre(ch: Vector2i) -> Vector2:
	return (Vector2(ch) + Vector2(0.5, 0.5)) * _chunk


# 0..1 grass density at world x/z (0 where no mask is loaded).
func _mask_at(x: float, z: float) -> float:
	var grid = _streamer.grid
	var c: Vector2i = grid.cell_of(Vector3(x, 0.0, z))
	var data: PackedByteArray = _masks.get(c, PackedByteArray())
	if data.is_empty():
		return 0.0
	var r: Rect2 = grid.rect_of(c)
	var m := float(_t.mask_m)
	var px := clampi(int((x - r.position.x) / m), 0, _mask_n - 1)
	var pz := clampi(int((z - r.position.y) / m), 0, _mask_n - 1)
	return data[pz * _mask_n + px] / 255.0


func _on_cell_loaded(c: Vector2i) -> void:
	var path := "%s/cell_%d_%d.res" % [_t.mask_dir, c.x, c.y]
	if not ResourceLoader.exists(path):
		return
	var img := load(path) as Image
	if img:
		_mask_n = img.get_width()
		_masks[c] = img.get_data()
	for ch: Vector2i in active.keys():  # chunks built before their mask arrived
		if _streamer.grid.cell_of(Vector3(_centre(ch).x, 0.0, _centre(ch).y)) == c:
			_release(ch)


func _on_cell_unloaded(c: Vector2i) -> void:
	_masks.erase(c)


# One clump: `blades` tapered, slightly bent blades (3 triangles each), UV.y = height fraction, root-to-tip colour.
func _clump_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 115
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hr: Array = _t.height_m
	var base := Color(_t.base_color[0], _t.base_color[1], _t.base_color[2])
	var tip := Color(_t.tip_color[0], _t.tip_color[1], _t.tip_color[2])
	var w := float(_t.blade_width_m)
	var spread := float(_t.spread_m)
	for b in int(_t.blades):
		var at := Vector3(rng.randf_range(-spread, spread), 0.0, rng.randf_range(-spread, spread))
		var yaw := rng.randf() * TAU
		var side := Vector3(cos(yaw), 0.0, sin(yaw)) * w * 0.5
		var lean := Vector3(-sin(yaw), 0.0, cos(yaw)) * rng.randf_range(0.05, 0.25)
		var h := rng.randf_range(float(hr[0]), float(hr[1]))
		var mid := at + Vector3.UP * h * 0.55 + lean * h * 0.3
		var top := at + Vector3.UP * h + lean * h
		var tip_c := tip * rng.randf_range(0.85, 1.1)
		var pts := [[at - side, 0.0], [at + side, 0.0], [mid - side * 0.6, 0.55], [mid + side * 0.6, 0.55], [top, 1.0]]
		for tri: Array in [[0, 1, 2], [1, 3, 2], [2, 3, 4]]:
			for k: int in tri:
				var f: float = pts[k][1]
				st.set_color(base.lerp(tip_c, f))
				st.set_uv(Vector2(0.0, f))
				st.set_normal(Vector3.UP)
				st.add_vertex(pts[k][0])
	return st.commit()
