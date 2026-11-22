# VegetationBuilder — scatters instanced props for the map importer (D-043, D-044): vegetation from
# data/art/vegetation.json and street clutter from data/art/clutter.json (one builder per data file).
# Makes the shared assets once into out_dir: generated TreeMesh / CarMesh variants and reduced-LOD copies of the
# approved Poly Haven models (whole glTF meshes as variants, or "nodes" regexes merging parts of a modular set into
# one prop), alpha-scissor materials. Then for each cell turns a list of placements into MultiMeshInstance3D nodes
# per kind/variant and block_m block (so visibility ranges cull per block) plus one StaticBody3D of simple colliders.
# Placement points are chosen by build_cells (it knows roads and buildings).
# Colliders match the models (D-091): a tree's trunk collider runs along the trunk TreeMesh drew (its "tree_shape"
# metadata: lean, length, bark thickness at chest height); collide_radius_m props get a cylinder as tall as the model
# (it used to be 3 m for everything - stumps had an invisible column that stopped players and discs).
# Species and plants (D-098): "species" become kinds tree_<id> (TreeMesh.build_species, trunk colliders unless a
# bush), "plants" become kinds by id (PlantMesh: tall grass, wildflowers, reeds; no collision, no shadows).
# Vehicles (D-116): a prop with "fit" {length_m, flip} is turned so its long side runs along +Z (flip = turn it
# round so the front faces +Z), scaled to that length, centred and stood on y = 0 - downloaded models come in
# every unit and orientation. Its LODs are regenerated after (the other props keep the one reduced lod_ratio mesh).
# Depends on: DataLoader, TreeMesh, PlantMesh, CarMesh, imported glTFs under models_dir.
class_name VegetationBuilder
extends RefCounted

const DATA_PATH := "res://data/art/vegetation.json"

var data: Dictionary
var error := ""
var holder_name := "Vegetation"
var kinds: Dictionary = {}  # kind id -> { meshes: [Mesh], visible_m, shadows, collide_radius, collide_box, collide }


func _init(data_path := DATA_PATH, node_name := "Vegetation") -> void:
	holder_name = node_name
	data = DataLoader.load_json(data_path)
	for key in ["models_dir", "out_dir", "block_m", "props", "placement"]:
		if not data.has(key):
			error = "%s: missing '%s'" % [data_path, key]
			return
	for id: String in data.props:
		var path := "%s/%s" % [data.models_dir, data.props[id].gltf]
		if not ResourceLoader.exists(path):
			error = "model %s not imported - run tools/assets/fetch_models.tscn, then open the editor once" % path
			return


# Builds and saves every mesh/material once. Call before build_cell().
func make_assets() -> void:
	var dir := str(data.out_dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var vc_mat := StandardMaterial3D.new()
	vc_mat.vertex_color_use_as_albedo = true
	vc_mat.roughness = 0.9
	vc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if data.has("trees"):
		_make_trees(dir, vc_mat)
	if data.has("species"):
		_make_species(dir, vc_mat)
	if data.has("plants"):
		_make_plants(dir, vc_mat)
	if data.has("cars"):
		_make_cars(dir, vc_mat)
	for id: String in data.props:
		var p: Dictionary = data.props[id]
		var root := (load("%s/%s" % [data.models_dir, p.gltf]) as PackedScene).instantiate()
		var found: Array = []
		_find_meshes(root, found)
		var meshes: Array = []
		if p.has("nodes"):
			for pattern: String in p.nodes:
				var re := RegEx.create_from_string(pattern)
				var parts: Array = []
				for mi: MeshInstance3D in found:
					if re.search(str(mi.name)):
						parts.append(mi)
				meshes.append(_merged(parts, root, float(p.lod_ratio)))
		else:
			for i in mini(int(p.get("variants", 1)), found.size()):
				meshes.append(_merged([found[i]], root, float(p.lod_ratio)))
		for i in meshes.size():
			if p.has("fit"):
				meshes[i] = _fit(meshes[i], p.fit)
			ResourceSaver.save(meshes[i], "%s/%s_%d.res" % [dir, id, i], ResourceSaver.FLAG_CHANGE_PATH)
		root.free()
		kinds[id] = {"meshes": meshes, "visible_m": float(p.visible_m), "shadows": bool(p.shadows),
			"collide_radius": float(p.get("collide_radius_m", 0.0)), "collide_box": p.get("collide_box_m", []),
			"collide": str(p.get("collide", ""))}


func _make_trees(dir: String, mat: Material) -> void:
	var t: Dictionary = data.trees
	var bark := _color(t.bark_color)
	ResourceSaver.save(mat, dir + "/tree.tres", ResourceSaver.FLAG_CHANGE_PATH)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4321
	for bare_i in 2:
		var bare := bare_i == 1
		var meshes: Array = []
		var n := int(t.bare_variants if bare else t.leafy_variants)
		for i in n:
			var leaf := _color(t.canopy_colors[i % t.canopy_colors.size()])
			var r := rng.randf_range(float(t.trunk_radius_m[0]), float(t.trunk_radius_m[1])) / float(t.height_m[1])
			var m := TreeMesh.build(rng, bare, r * 1.6, bark, leaf)
			m.surface_set_material(0, mat)
			ResourceSaver.save(m, "%s/tree_%s_%d.res" % [dir, "bare" if bare else "leafy", i], ResourceSaver.FLAG_CHANGE_PATH)
			meshes.append(m)
		kinds["tree_bare" if bare else "tree_leafy"] = {"meshes": meshes, "visible_m": float(t.visible_m),
			"shadows": true, "collide_radius": 0.25 if bool(t.collide) else 0.0, "collide_box": [], "collide": ""}


# Kearney species (D-098): kind "tree_<id>" per data.species entry, variants by canopy colour.
func _make_species(dir: String, mat: Material) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9898
	for id: String in data.species:
		var sp: Dictionary = data.species[id]
		var meshes: Array = []
		var cols: Array = sp.canopy_colors
		for i in int(sp.variants):
			var r := rng.randf_range(float(sp.trunk_radius_m[0]), float(sp.trunk_radius_m[1])) / float(sp.height_m[1])
			var m := TreeMesh.build_species(rng, sp, r * 1.6, _color(sp.bark_color), _color(cols[i % cols.size()]))
			m.surface_set_material(0, mat)
			ResourceSaver.save(m, "%s/tree_%s_%d.res" % [dir, id, i], ResourceSaver.FLAG_CHANGE_PATH)
			meshes.append(m)
		var bush := bool(sp.get("bush", false))
		kinds["tree_" + id] = {"meshes": meshes, "visible_m": 90.0 if bush else float(data.trees.visible_m), "shadows": not bush,
			"collide_radius": 0.0 if bush else 0.25, "collide_box": [], "collide": ""}


# Ground plants (D-098): one kind per data.plants id.
func _make_plants(dir: String, mat: Material) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2468
	for id: String in data.plants:
		var p: Dictionary = data.plants[id]
		var meshes: Array = []
		for i in int(p.variants):
			var m := PlantMesh.build(rng, str(p.kind), p)
			m.surface_set_material(0, mat)
			ResourceSaver.save(m, "%s/plant_%s_%d.res" % [dir, id, i], ResourceSaver.FLAG_CHANGE_PATH)
			meshes.append(m)
		kinds[id] = {"meshes": meshes, "visible_m": float(p.visible_m), "shadows": false, "collide_radius": 0.0,
			"collide_box": [], "collide": ""}


# One kind "car" whose variants are every body type x paint (burned ones included), generated by CarMesh.
func _make_cars(dir: String, mat: Material) -> void:
	var c: Dictionary = data.cars
	var rng := RandomNumberGenerator.new()
	rng.seed = 1977
	var meshes: Array = []
	var paints: Array = c.paints
	for body: String in c.bodies:
		for i in int(c.variants_per_body):
			var burned := i == int(c.variants_per_body) - 1 and bool(c.burned_last)
			var paint := _color(paints[rng.randi_range(0, paints.size() - 1)])
			var m := CarMesh.build(rng, body, paint, burned, float(c.rust))
			m.surface_set_material(0, mat)
			ResourceSaver.save(m, "%s/car_%s_%d.res" % [dir, body, i], ResourceSaver.FLAG_CHANGE_PATH)
			meshes.append(m)
	kinds["car"] = {"meshes": meshes, "visible_m": float(c.visible_m), "shadows": true,
		"collide_radius": 0.0, "collide_box": [], "collide": "box"}


# How a tree kind shows in the far shell (build_cells._far_tree): "round", "cone", "bare", or "" (bushes, plants:
# nothing far away).
func far_style(kind: String) -> String:
	if kind == "tree_bare":
		return "bare"
	if kind == "tree_leafy":
		return "round"
	if not kind.begins_with("tree_") or not data.has("species") or not data.species.has(kind.substr(5)):
		return ""
	var sp: Dictionary = data.species[kind.substr(5)]
	return "" if bool(sp.get("bush", false)) else str(sp.get("far", "round"))


# Scale range for a kind (trees: height in metres).
func scale_range(kind: String) -> Vector2:
	if kind.begins_with("tree_") and data.has("species") and data.species.has(kind.substr(5)):
		var h: Array = data.species[kind.substr(5)].height_m
		return Vector2(float(h[0]), float(h[1]))
	if data.has("plants") and data.plants.has(kind):
		return Vector2(float(data.plants[kind].height_m[0]), float(data.plants[kind].height_m[1]))
	if kind.begins_with("tree_"):
		return Vector2(float(data.trees.height_m[0]), float(data.trees.height_m[1]))
	if kind == "car":
		return Vector2.ONE
	var s: Array = data.props[kind].scale
	return Vector2(float(s[0]), float(s[1]))


# One cylinder along a TreeMesh trunk ({trunk: [base, top, r0, r1]} in mesh units, scaled by s): as thick as the bark
# a quarter of the way up (chest to head height on a grown tree), leaning with it, up to where the branches start.
func _add_trunk(body: StaticBody3D, shape_info: Dictionary, basis: Basis, pos: Vector3, s: float) -> void:
	var t: Array = shape_info.trunk
	var a: Vector3 = pos + basis * ((t[0] as Vector3) * s)
	var b: Vector3 = pos + basis * ((t[1] as Vector3) * s)
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var cyl := CylinderShape3D.new()
	cyl.height = a.distance_to(b)
	cyl.radius = lerpf(float(t[2]), float(t[3]), 0.25) * s
	var shape := CollisionShape3D.new()
	shape.shape = cyl
	shape.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)
	body.add_child(shape)


# placements: Array of [kind, variant, Vector3 position, yaw, scale]; kind "_box" adds only a box collider
# (scale = Vector3 size, position = box centre). Adds a holder_name node under root.
func build_cell(root: Node3D, placements: Array) -> int:
	if placements.is_empty():
		return 0
	var holder := Node3D.new()
	holder.name = holder_name
	root.add_child(holder)
	var body := StaticBody3D.new()
	body.name = "Colliders"
	var groups := {}  # "kind|variant|bx|bz" -> Array of Transform3D
	var block := float(data.block_m)
	for pl: Array in placements:
		var kind: String = pl[0]
		var pos: Vector3 = pl[2]
		if kind == "_box":
			_add_box(body, pl[4], Transform3D(Basis(Vector3.UP, pl[3]), pos))
			continue
		var s: float = pl[4]
		var basis := Basis(Vector3.UP, pl[3])
		var xf := Transform3D(basis.scaled(Vector3.ONE * s), pos)
		var key := "%s|%d|%d|%d" % [kind, pl[1], floori(pos.x / block), floori(pos.z / block)]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(xf)
		var k: Dictionary = kinds[kind]
		var aabb: AABB = k.meshes[int(pl[1])].get_aabb()
		var mesh: Mesh = k.meshes[int(pl[1])]
		if kind.begins_with("tree_") and float(k.collide_radius) > 0.0 and mesh.has_meta("tree_shape"):
			_add_trunk(body, mesh.get_meta("tree_shape"), basis, pos, s)
		elif float(k.collide_radius) > 0.0:
			var shape := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = float(k.collide_radius) * (s / 10.0 if kind.begins_with("tree_") else s)
			cyl.height = maxf(aabb.size.y * s, 0.2)
			shape.shape = cyl
			shape.position = pos + Vector3(0, aabb.position.y * s + cyl.height * 0.5, 0)
			body.add_child(shape)
		elif k.collide_box.size() == 3:
			var size := Vector3(k.collide_box[0], k.collide_box[1], k.collide_box[2]) * s
			_add_box(body, size, Transform3D(basis, pos + Vector3(0, size.y * 0.4, 0)))
		elif k.collide == "box":
			_add_box(body, aabb.size * s, Transform3D(basis, pos + basis * (aabb.get_center() * s)))
		elif k.collide == "cylinder":
			var shape := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = maxf(aabb.size.x, aabb.size.z) * 0.5 * s
			cyl.height = aabb.size.y * s
			shape.shape = cyl
			shape.position = pos + Vector3(0, cyl.height * 0.5, 0)
			body.add_child(shape)
	var keys := groups.keys()
	keys.sort()
	for key: String in keys:
		var parts := key.split("|")
		var k: Dictionary = kinds[parts[0]]
		var xfs: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = k.meshes[int(parts[1])]
		mm.instance_count = xfs.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.name = key.replace("|", "_")
		mmi.multimesh = mm
		mmi.visibility_range_end = float(k.visible_m)
		mmi.visibility_range_end_margin = 10.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if not bool(k.shadows):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Put the node at the block centre so the visibility range is measured from there.
		var centre := Vector3((int(parts[2]) + 0.5) * block, 0.0, (int(parts[3]) + 0.5) * block)
		var c_y := 0.0
		for xf: Transform3D in xfs:
			c_y += xf.origin.y
		centre.y = c_y / xfs.size()
		mmi.position = centre
		for i in xfs.size():
			var xf: Transform3D = xfs[i]
			xf.origin -= centre
			mm.set_instance_transform(i, xf)
		holder.add_child(mmi)
	if body.get_child_count() > 0:
		holder.add_child(body)
	else:
		body.free()
	return placements.size()


func _add_box(body: StaticBody3D, size: Vector3, xf: Transform3D) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.transform = xf
	body.add_child(shape)


func _find_meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		out.append(node)
	for c in node.get_children():
		_find_meshes(c, out)


# One mesh from several glTF parts: each part's imported LOD closest to ratio x full, its transform within the
# scene baked in, surfaces merged per material, then moved so the footprint is centred on x = z = 0.
func _merged(parts: Array, root: Node, ratio: float) -> ArrayMesh:
	var by_mat := {}  # Material -> SurfaceTool
	var order: Array = []
	for mi: MeshInstance3D in parts:
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != root and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var src := mi.mesh
		for s in src.get_surface_count():
			var tmp := ArrayMesh.new()
			tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _lod_arrays(src, s, ratio))
			var mat := mi.get_active_material(s)
			if not by_mat.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				by_mat[mat] = st
				order.append(mat)
			(by_mat[mat] as SurfaceTool).append_from(tmp, 0, xf)
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var out := ArrayMesh.new()
	var arrays_list: Array = []
	for mat in order:
		var st: SurfaceTool = by_mat[mat]
		st.generate_tangents()
		var arrays := st.commit_to_arrays()
		for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			lo = lo.min(v)
			hi = hi.max(v)
		arrays_list.append(arrays)
	var shift := Vector3(-(lo.x + hi.x) * 0.5, 0.0, -(lo.z + hi.z) * 0.5)
	for i in arrays_list.size():
		var arrays: Array = arrays_list[i]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for j in verts.size():
			verts[j] += shift
		arrays[Mesh.ARRAY_VERTEX] = verts
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(i, _scissor(order[i]))
	return out


# A copy of `mesh` turned long side along +Z (+ 180 degrees if fit.flip), scaled to fit.length_m long, centred
# on x/z and with its lowest point at y = 0. Normals and tangents turn with it.
func _fit(mesh: ArrayMesh, fit: Dictionary) -> ArrayMesh:
	var box := mesh.get_aabb()
	var basis := Basis.IDENTITY
	if box.size.x > box.size.z:
		basis = Basis(Vector3.UP, PI * 0.5)
	if bool(fit.get("flip", false)):
		basis = Basis(Vector3.UP, PI) * basis
	var length := maxf(box.size.x, box.size.z)
	var s := float(fit.length_m) / maxf(length, 0.001)
	var c := box.get_center()
	var xf := Transform3D(basis.scaled(Vector3.ONE * s), Vector3.ZERO) * Transform3D(Basis.IDENTITY, Vector3(-c.x, -box.position.y, -c.z))
	var im := ImporterMesh.new()  # fresh LODs, so far cars cost a fraction of near ones
	for i in mesh.get_surface_count():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(mesh, i, xf)
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays(), [], {}, mesh.surface_get_material(i))
	im.generate_lods(60.0, 25.0, [])
	return im.get_mesh()


# The surface's arrays with the imported LOD index buffer closest to ratio x the full index count.
func _lod_arrays(src: Mesh, s: int, ratio: float) -> Array:
	var arrays := src.surface_get_arrays(s)
	for extra in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		arrays[extra] = null  # D-116: some downloaded models carry these; a static prop never needs them
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var target := idx.size() * ratio
	var best := idx
	var info := RenderingServer.mesh_get_surface(src.get_rid(), s)
	var wide := int(arrays[Mesh.ARRAY_VERTEX].size()) > 65535
	for lod: Dictionary in info.get("lods", []):
		var bytes: PackedByteArray = lod.index_data
		var cand := bytes.to_int32_array() if wide else _u16(bytes)
		if absf(cand.size() - target) < absf(best.size() - target) and cand.size() >= 3:
			best = cand
	arrays[Mesh.ARRAY_INDEX] = best
	return arrays


func _scissor(mat: Material) -> Material:
	var m := mat as BaseMaterial3D
	if m == null:
		return mat
	m = m.duplicate() as BaseMaterial3D
	if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _u16(bytes: PackedByteArray) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(bytes.size() / 2)
	for i in out.size():
		out[i] = bytes.decode_u16(i * 2)
	return out


func _color(c: Array) -> Color:
	return Color(float(c[0]), float(c[1]), float(c[2]))
