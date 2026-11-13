# StreetSigns — street name signs for the map importer (D-070). find() turns the OSM source into intersections:
# OSM nodes shared by two differently named streets of the signed kinds (one per street pair within dedupe_m).
# place() picks a street corner clear of buildings/roads (via the callables build_cells passes). build_cell() adds a
# "StreetSigns" node to a cell: posts and blades as two MultiMeshes (shared meshes saved once into the cells'
# materials dir) and the names as Label3D pairs (front + back of each blade) culled at visible_m. Names are
# shortened like real signs ("West 11th Street" -> "W 11th St"). Tuning: data/art/street_signs.json.
# Static props only, no collision. Depends on: DataLoader, MapProjection.
class_name StreetSigns
extends RefCounted

const DATA_PATH := "res://data/art/street_signs.json"

var data: Dictionary
var _post: Mesh
var _blade: Mesh


func _init(out_dir: String) -> void:
	data = DataLoader.load_json(DATA_PATH)
	var green := _color(data.blade_color)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = _color(data.post_color)
	post_mat.metallic = 0.5
	post_mat.roughness = 0.5
	var post := CylinderMesh.new()
	post.top_radius = 0.035
	post.bottom_radius = 0.035
	post.height = float(data.post_height_m)
	post.radial_segments = 6
	post.rings = 1
	post.material = post_mat
	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = green
	blade_mat.roughness = 0.6
	var blade := BoxMesh.new()
	blade.size = Vector3(float(data.blade_length_m), float(data.blade_height_m), 0.02)
	blade.material = blade_mat
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	ResourceSaver.save(post, out_dir + "/street_sign_post.res", ResourceSaver.FLAG_CHANGE_PATH)
	ResourceSaver.save(blade, out_dir + "/street_sign_blade.res", ResourceSaver.FLAG_CHANGE_PATH)
	_post = post
	_blade = blade


# Every signed intersection: [point: Vector2, name_a, dir_a: Vector2, kind_a, name_b, dir_b, kind_b].
func find(src: Dictionary, proj: MapProjection) -> Array:
	var kinds: Array = data.kinds
	var at_node: Dictionary = {}  # node id -> Array of [name, dir, kind, point]
	for el: Dictionary in src.get("elements", []):
		if str(el.get("type", "")) != "way":
			continue
		var tags: Dictionary = el.get("tags", {})
		var street := str(tags.get("name", ""))
		var kind := str(tags.get("highway", ""))
		if street == "" or not kind in kinds:
			continue
		var ids: Array = el.get("nodes", [])
		var geom: Array = el.get("geometry", [])
		if ids.size() != geom.size() or geom.size() < 2:
			continue
		var pts: Array[Vector2] = []
		for g: Dictionary in geom:
			pts.append(proj.to_local(float(g.lat), float(g.lon)))
		for i in ids.size():
			var a: Vector2 = pts[maxi(i - 1, 0)]
			var b: Vector2 = pts[mini(i + 1, pts.size() - 1)]
			var id := int(ids[i])
			if not at_node.has(id):
				at_node[id] = []
			at_node[id].append([street, (b - a).normalized(), kind, pts[i]])
	var out: Array = []
	var seen: Dictionary = {}  # "a|b" -> Array of points already signed
	var dedupe := float(data.dedupe_m)
	for id: int in at_node:
		var list: Array = at_node[id]
		if list.size() < 2:
			continue
		for i in list.size():
			for j in range(i + 1, list.size()):
				var a: Array = list[i]
				var b: Array = list[j]
				if a[0] == b[0] or absf((a[1] as Vector2).dot(b[1])) > 0.9:
					continue  # same street, or the two run the same way (a name change, not a corner)
				var key := "%s|%s" % ([a[0], b[0]] if str(a[0]) < str(b[0]) else [b[0], a[0]])
				var p: Vector2 = a[3]
				var dup := false
				for q: Vector2 in seen.get(key, []):
					if q.distance_to(p) < dedupe:
						dup = true
						break
				if dup:
					continue
				if not seen.has(key):
					seen[key] = []
				seen[key].append(p)
				out.append([p, a[0], a[1], a[2], b[0], b[1], b[2]])
	return out


# Corner position for an intersection: [Vector2 point, yaw_a, yaw_b], or [] if no corner is clear.
# half_of(kind) = road half width; clear(p) = no building / road there.
func place(crossing: Array, half_of: Callable, clear: Callable) -> Array:
	var u: Vector2 = crossing[2]
	var v := u.orthogonal()
	var off := float(data.curb_offset_m)
	var ha := float(half_of.call(crossing[3]))
	var hb := float(half_of.call(crossing[6]))
	for s: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var p: Vector2 = crossing[0] + v * s.y * (ha + off) + u * s.x * (hb + off)
		if clear.call(p):
			return [p, _yaw(u), _yaw(crossing[5])]
	return []


# Adds the cell's signs. signs: Array of [Vector3 base, yaw_a, name_a, yaw_b, name_b].
func build_cell(root: Node3D, signs: Array) -> int:
	if signs.is_empty():
		return 0
	var holder := Node3D.new()
	holder.name = "StreetSigns"
	root.add_child(holder)
	var centre := Vector3.ZERO
	for s: Array in signs:
		centre += s[0]
	centre /= signs.size()
	var posts := _multimesh(holder, "Posts", _post, signs.size())
	var blades := _multimesh(holder, "Blades", _blade, signs.size() * 2)
	var h := float(data.post_height_m)
	var vis := float(data.visible_m)
	for i in signs.size():
		var s: Array = signs[i]
		var base: Vector3 = s[0] - centre
		posts.multimesh.set_instance_transform(i, Transform3D(Basis(), base + Vector3.UP * h * 0.5))
		for k in 2:
			var yaw: float = s[1] if k == 0 else s[3]
			var y := h - 0.1 - k * (float(data.blade_height_m) + 0.03)
			var xf := Transform3D(Basis(Vector3.UP, yaw), base + Vector3(0, y, 0))
			blades.multimesh.set_instance_transform(i * 2 + k, xf)
			for side in 2:  # front and back of the blade
				var l := Label3D.new()
				l.text = shorten(str(s[2] if k == 0 else s[4]), data.abbreviations)
				l.font_size = int(data.font_size)
				l.pixel_size = float(data.pixel_size)
				l.modulate = _color(data.text_color)
				l.outline_size = 0
				l.visibility_range_end = vis
				l.double_sided = false
				l.transform = Transform3D(Basis(Vector3.UP, yaw + PI * side), base + Vector3(0, y, 0)) \
					.translated_local(Vector3(0, 0, 0.012))
				holder.add_child(l)
	holder.position = centre
	return signs.size()


func _multimesh(holder: Node3D, node_name: String, mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.visibility_range_end = float(data.visible_m) * 3.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mmi)
	return mmi


# "West 11th Street" -> "W 11th St" (abbr = data/art/street_signs.json "abbreviations"; the world map uses it too).
static func shorten(full: String, abbr: Dictionary) -> String:
	var words := full.split(" ", false)
	var out := PackedStringArray()
	for w: String in words:
		out.append(str(abbr.get(w, w)))
	return " ".join(out)


# Yaw that turns a blade's local +X to run along v (x, z).
static func _yaw(v: Vector2) -> float:
	return atan2(-v.y, v.x)


static func _color(c: Array) -> Color:
	return Color(float(c[0]), float(c[1]), float(c[2]))
