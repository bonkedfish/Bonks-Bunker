# CoopElevator — builds the Kearney Co-op grain elevator (D-103, Act 2 chapter 1) from
# data/landmarks/coop_elevator.json: the concrete silo bank and headhouse with its bucket-leg tower, a stretch of
# the old spur with a rusted hopper car, plus the data parts (drive shed whose plate floor is the Suits' hatch,
# scale house, floors, glowing seams, signs, lights, the logbook desk, the yard crew's markers) and Gus.
# Local frame = map axes, origin map (3360, -1290).
# Depends on: LandmarkKit, landmark_parts.gd, scenes/resident_npc.tscn.
extends RefCounted

const Parts := preload("res://tools/landmarks/landmark_parts.gd")
const NPC := preload("res://scenes/resident_npc.tscn")


static func build(k: LandmarkKit, d: Dictionary) -> void:
	Parts.build_all(k, d, "coop_elevator", float(d.dims.floor_y))
	var s: Dictionary = d.silos
	for c: Array in s.centres:
		k.cylinder(Vector3(c[0], 0.0, c[1]), float(s.radius), float(s.height), "silo", 16, true)
	var hh: Dictionary = d.headhouse
	var b: Array = hh.box
	k.box(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]), "silo")
	k.block(Vector3(b[0] - b[3] * 0.5 - 0.3, b[1] + b[4] * 0.5, b[2] - b[5] * 0.5 - 0.3),
		Vector3(b[0] + b[3] * 0.5 + 0.3, b[1] + b[4] * 0.5 + 0.4, b[2] + b[5] * 0.5 + 0.3), "roof")
	var l: Array = hh.leg
	k.box(Vector3(l[0], l[1], l[2]), Vector3(l[3], l[4], l[5]), "corrugated")
	_rails(k, d.rails)
	_hopper(k, d.hopper)
	for n: Dictionary in d.get("npcs", []):
		var p: Array = n.pos
		k.place(NPC, Transform3D(Basis(Vector3.UP, deg_to_rad(float(n.yaw_deg))), Vector3(p[0], p[1], p[2])),
			{"npc_id": str(n.npc_id)}, str(n.name))


static func _rails(k: LandmarkKit, r: Dictionary) -> void:
	var x0 := float(r.x0)
	var x1 := float(r.x1)
	var zs: Array = r.z
	for z: float in zs:
		k.box(Vector3((x0 + x1) * 0.5, 0.2, z), Vector3(x1 - x0, 0.14, 0.08), "steel", 0.0, false)
	var mid := (float(zs[0]) + float(zs[1])) * 0.5
	var x := x0
	while x <= x1:
		k.box(Vector3(x, 0.08, mid), Vector3(0.25, 0.12, 2.4), "wood", 0.0, false)
		x += float(r.tie_m)


static func _hopper(k: LandmarkKit, h: Dictionary) -> void:
	var p: Array = h.pos
	var len := float(h.len)
	var c := Vector3(p[0], 0.0, p[1])
	k.box(c + Vector3(0, 2.6, 0), Vector3(len, 2.8, 3.0), "rust")
	for i in 3:  # hopper chutes under the car
		k.box(c + Vector3(-len * 0.3 + i * len * 0.3, 0.95, 0), Vector3(1.6, 0.6, 2.2), "rust", 0.0, false)
	for sx: float in [-len * 0.38, len * 0.38]:
		for sz: float in [-0.72, 0.72]:
			k.box(c + Vector3(sx, 0.55, sz), Vector3(0.9, 0.7, 0.2), "steel", 0.0, false)
