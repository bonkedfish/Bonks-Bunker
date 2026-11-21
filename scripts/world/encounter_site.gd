# EncounterSite — one open random encounter in the world (D-105), built the same way on every peer from its
# definition in data/encounters/encounters.json plus the site's seed, so no per-node replication is needed: the host
# only broadcasts (slot, encounter id, position, yaw, seed) and everyone builds the identical scene.
# Builds, in the site's own frame (x east, y up, z south before the site's yaw):
#   props   {box [cx,cy,cz,sx,sy,sz]} | {cyl [x,y,z,r,h]} | {car [x,y,z], body, paint, burned?} | {sign ...}
#           | {fire [x,y,z]} | {kit "<PropKits kind>", at [x,y,z], yaw} , each with mat (a colour name from
#           COLORS or [r,g,b]), yaw?, collide?, emit?
#   npc     {id, at [x,y,z], yaw}                         a scenes/resident_npc.tscn named "Npc" (talkable)
#   loot    [{id, name, table, at [x,y,z], size, yaw?}]   real LootContainers, named "Loot_<id>"
#   uses    [{label, at [x,y,z], size?}]                  E-spots (group "sport_spots") routed to the director
#   pool    {at [x,y,z], yaw}                             a real playable pool table (D-084)
# Enemies are not built here: the host springs them through EncounterDirector, which adds lair_spawns markers.
# Depends on: CarMesh, scenes/resident_npc.tscn, scenes/loot_container.tscn, EncounterDirector (the use target).
class_name EncounterSite
extends Node3D

const NPC_SCENE := preload("res://scenes/resident_npc.tscn")
const LOOT_SCENE := preload("res://scenes/loot_container.tscn")
const POOL_SCENE := preload("res://scenes/pool_table.tscn")

const COLORS := {
	"steel": Color(0.42, 0.44, 0.46), "rust": Color(0.42, 0.24, 0.13), "wood": Color(0.42, 0.3, 0.18),
	"dark": Color(0.12, 0.12, 0.13), "white": Color(0.88, 0.88, 0.85), "red": Color(0.6, 0.12, 0.1),
	"blue": Color(0.17, 0.28, 0.5), "green": Color(0.2, 0.38, 0.22), "tan": Color(0.68, 0.6, 0.44),
	"orange": Color(0.85, 0.42, 0.08), "yellow": Color(0.85, 0.74, 0.15), "canvas": Color(0.55, 0.5, 0.38),
	"glass": Color(0.07, 0.09, 0.1), "tyre": Color(0.06, 0.06, 0.06), "ash": Color(0.16, 0.15, 0.14),
	"chrome": Color(0.7, 0.72, 0.75), "pink": Color(0.8, 0.45, 0.55), "bone": Color(0.86, 0.84, 0.76),
}

var slot := 0
var encounter_id := ""
var def: Dictionary = {}

var _mats: Dictionary = {}


# Builds the whole site. `director` is the node E-spots send their request_use to (same path on every peer).
func build(a_slot: int, id: String, definition: Dictionary, site_seed: int, director: Node) -> void:
	slot = a_slot
	encounter_id = id
	def = definition
	var rng := RandomNumberGenerator.new()
	rng.seed = site_seed
	for p: Dictionary in def.get("props", []):
		_prop(p, rng)
	var npc: Dictionary = def.get("npc", {})
	if not npc.is_empty():
		var n := NPC_SCENE.instantiate()
		n.name = "Npc"
		n.npc_id = str(npc.id)
		n.position = _v3(npc.get("at", [0, 0, 0]))
		n.rotation.y = deg_to_rad(float(npc.get("yaw", 0.0)))
		add_child(n)
	var i := 0
	for l: Dictionary in def.get("loot", []):
		var c := LOOT_SCENE.instantiate()
		c.name = "Loot_%s" % str(l.get("id", i))
		c.container_id = "enc_%d_%s_%s" % [slot, id, str(l.get("id", i))]
		c.display_name = str(l.get("name", "Container"))
		c.loot_table = str(l.get("table", "junk_pile"))
		c.size = _v3(l.get("size", [0.8, 0.6, 0.6]))
		c.color = _color(l.get("mat", "steel"))
		c.position = _v3(l.get("at", [0, 0, 0]))
		c.rotation.y = deg_to_rad(float(l.get("yaw", 0.0)))
		add_child(c)
		i += 1
	var pool: Dictionary = def.get("pool", {})
	if not pool.is_empty():
		var table := POOL_SCENE.instantiate()
		table.name = "PoolTable"
		table.position = _v3(pool.get("at", [0, 0, 0]))
		table.rotation.y = deg_to_rad(float(pool.get("yaw", 0.0)))
		add_child(table)
	var u := 0
	for s: Dictionary in def.get("uses", []):
		add_child(_use_spot(s, u, director))
		u += 1


# Host: the enemy markers for this site's ambush, added on every peer when it springs.
func add_ambush_markers(rng: RandomNumberGenerator) -> void:
	var a: Dictionary = def.get("ambush", {})
	if a.is_empty() or has_node("Ambush"):
		return
	var holder := Node3D.new()
	holder.name = "Ambush"
	add_child(holder)
	var n := int(a.get("count", 3))
	var r := float(a.get("radius_m", 12.0))
	for i in n:
		var angle := TAU * (float(i) + rng.randf_range(0.0, 0.5)) / float(maxi(n, 1))
		var m := Marker3D.new()
		m.name = "encamb_%d_%d" % [slot, i]
		m.position = Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(r * 0.6, r) + Vector3(0, 0.05, 0)
		m.set_meta("enemy", str(a.get("enemy", "raider_gunner")))
		m.add_to_group("lair_spawns", true)
		holder.add_child(m)


# The marker-name prefix this site's ambush bodies are keyed by in LairDirector.
func ambush_prefix() -> String:
	return "encamb_%d_" % slot


func _use_spot(s: Dictionary, index: int, director: Node) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Use_%d" % index
	body.collision_layer = 9  # world + interactables, like a loot container
	body.collision_mask = 0
	body.position = _v3(s.get("at", [0, 0, 0]))
	var size := _v3(s.get("size", [0.8, 0.8, 0.8]))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.add_to_group("sport_spots")  # the player's E prompt reads display_name and calls target.request_use(index)
	body.set_meta("display_name", str(s.get("label", "Use")))
	body.set_meta("target", director)
	body.set_meta("index", slot * 100 + index)
	return body


func _prop(p: Dictionary, rng: RandomNumberGenerator) -> void:
	if p.has("kit"):
		for part: Dictionary in PropKits.parts(str(p.kit), _v3(p.get("at", [0, 0, 0])), float(p.get("yaw", 0.0)),
				bool(p.get("collide", true))):
			_prop(part, rng)
		return
	if bool(p.get("invisible", false)):  # a kit's collision box
		var b2: Array = p.box
		_collider(Vector3(b2[0], b2[1], b2[2]), Vector3(b2[3], b2[4], b2[5]), deg_to_rad(float(p.get("yaw", 0.0))), 1.0)
		return
	if p.has("car"):
		var mi := MeshInstance3D.new()
		var paint := _color(p.get("mat", "blue"))
		mi.mesh = CarMesh.build(rng, str(p.get("body", "sedan")), paint, bool(p.get("burned", false)), 0.5)
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.8
		mi.material_override = mat
		mi.position = _v3(p.car)
		mi.rotation.y = deg_to_rad(float(p.get("yaw", 0.0)))
		add_child(mi)
		_collider(mi.position, Vector3(2.0, 1.5, 4.6), mi.rotation.y, 0.75)
		return
	if p.has("sign"):
		var l := Label3D.new()
		l.text = str(p.sign)
		l.font_size = int(p.get("size", 42))
		l.pixel_size = 0.01
		l.outline_size = 8
		l.modulate = _color(p.get("mat", "white"))
		l.position = _v3(p.get("at", [0, 1.5, 0]))
		l.rotation.y = deg_to_rad(float(p.get("yaw", 0.0)))
		l.visibility_range_end = float(p.get("visible_m", 40.0))
		add_child(l)
		return
	if p.has("fire"):
		var at := _v3(p.fire)
		_mesh(_cylinder(0.55, 0.22), at + Vector3(0, 0.11, 0), 0.0, _color("ash"), false)
		_mesh(_cylinder(0.38, 0.3), at + Vector3(0, 0.3, 0), 0.0, Color(1.0, 0.45, 0.1), true)
		var light := OmniLight3D.new()
		light.position = at + Vector3(0, 1.0, 0)
		light.light_color = Color(1.0, 0.6, 0.25)
		light.light_energy = 2.2
		light.omni_range = 14.0
		light.shadow_enabled = false
		add_child(light)
		return
	var yaw := deg_to_rad(float(p.get("yaw", 0.0)))
	var color := _color(p.get("mat", "steel"))
	var emit := bool(p.get("emit", false))
	if p.has("cyl"):
		var c: Array = p.cyl
		var pos := Vector3(c[0], float(c[1]) + float(c[4]) * 0.5, c[2])
		_mesh(_cylinder(float(c[3]), float(c[4])), pos, yaw, color, emit)
		if bool(p.get("collide", false)):
			_collider(pos, Vector3(float(c[3]) * 2.0, float(c[4]), float(c[3]) * 2.0), yaw, 1.0)
		return
	var b: Array = p.get("box", [0, 0, 0, 1, 1, 1])
	var size := Vector3(b[3], b[4], b[5])
	var centre := Vector3(b[0], b[1], b[2])
	_mesh(_box(size), centre, yaw, color, emit)
	if bool(p.get("collide", true)):
		_collider(centre, size, yaw, 1.0)


func _mesh(mesh: Mesh, at: Vector3, yaw: float, color: Color, emit: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material(color, emit)
	mi.position = at
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if not emit else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _collider(at: Vector3, size: Vector3, yaw: float, grow: float) -> void:
	var body := get_node_or_null("Solid") as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = "Solid"
		body.collision_layer = 1
		body.collision_mask = 0
		add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size * grow
	shape.shape = box
	shape.position = at
	shape.rotation.y = yaw
	body.add_child(shape)


func _material(color: Color, emit: bool) -> StandardMaterial3D:
	var key := "%s%s" % [color, emit]
	if _mats.has(key):
		return _mats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	if emit:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.8
	_mats[key] = mat
	return mat


func _color(v: Variant) -> Color:
	if v is Array and (v as Array).size() >= 3:
		return Color(v[0], v[1], v[2])
	return COLORS.get(str(v), Color(0.5, 0.5, 0.5))


static func _v3(a: Variant) -> Vector3:
	var arr: Array = a if a is Array else [0, 0, 0]
	return Vector3(arr[0], arr[1], arr[2]) if arr.size() >= 3 else Vector3.ZERO


static func _box(size: Vector3) -> ArrayMesh:
	var m := BoxMesh.new()
	m.size = size
	return _to_array(m)


static func _cylinder(r: float, h: float) -> ArrayMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 10
	c.rings = 1
	return _to_array(c)


static func _to_array(p: PrimitiveMesh) -> ArrayMesh:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, p.get_mesh_arrays())
	return m
