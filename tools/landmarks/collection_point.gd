# CollectionPoint — builds the Act 1 finale spot (D-102): the Suits' collection truck backed up to Cash-Wa dock 3 on
# West 4th Street, two black SUVs, cover, a floodlight, and the escort's lair markers, from
# data/landmarks/collection_point.json. Local frame = map axes, origin map (1150, 350).
# The data parts (floors, props, signs, lights, loot, spawns) go through LandmarkParts; this file adds the vehicles.
# Depends on: LandmarkKit, landmark_parts.gd.
extends RefCounted

const Parts := preload("res://tools/landmarks/landmark_parts.gd")


static func build(k: LandmarkKit, d: Dictionary) -> void:
	Parts.build_all(k, d, "collection_point", float(d.dims.floor_y))
	var t: Dictionary = d.truck
	_truck(k, Transform3D(Basis(Vector3.UP, deg_to_rad(float(t.yaw_deg))), Vector3(t.pos[0], 0.0, t.pos[1])))
	for s: Array in d.suvs:  # [x, z, yaw_deg]
		_suv(k, Transform3D(Basis(Vector3.UP, deg_to_rad(float(s[2]))), Vector3(s[0], 0.0, s[1])))


# Unmarked white box truck; local -z = the cab end. The box's back is open: a steel cage inside, empty.
static func _truck(k: LandmarkKit, xf: Transform3D) -> void:
	k.box_xf(xf.translated_local(Vector3(0, 0.75, 0)), Vector3(2.2, 0.3, 9.0), "steel")  # frame
	k.box_xf(xf.translated_local(Vector3(0, 1.45, -3.6)), Vector3(2.4, 1.6, 1.9), "truck_cab")
	k.box_xf(xf.translated_local(Vector3(0, 1.75, -4.56)), Vector3(2.2, 0.8, 0.04), "window_dark", false)
	var box := xf.translated_local(Vector3(0, 2.15, 1.4))
	for side: float in [-1.0, 1.0]:  # walls of the cargo box, open at the back
		k.box_xf(box.translated_local(Vector3(side * 1.22, 0, 0)), Vector3(0.06, 2.6, 6.2), "truck_white")
	k.box_xf(box.translated_local(Vector3(0, 1.3, 0)), Vector3(2.5, 0.06, 6.2), "truck_white")
	k.box_xf(box.translated_local(Vector3(0, 0, -3.08)), Vector3(2.5, 2.6, 0.06), "truck_white")
	k.box_xf(box.translated_local(Vector3(0, -1.22, 0)), Vector3(2.4, 0.12, 6.2), "steel")  # floor
	for i in 7:  # cage bars across the back half
		k.box_xf(box.translated_local(Vector3(-0.9 + i * 0.3, -0.05, 0.6)), Vector3(0.05, 2.3, 0.05), "cage", false)
	k.box_xf(box.translated_local(Vector3(0, 1.05, 0.6)), Vector3(2.0, 0.06, 0.06), "cage", false)
	for z: float in [-3.6, 2.2, 3.4]:
		for s: float in [-1.0, 1.0]:
			k.box_xf(xf.translated_local(Vector3(s * 1.05, 0.5, z)), Vector3(0.35, 1.0, 1.0), "tyre", false)


static func _suv(k: LandmarkKit, xf: Transform3D) -> void:
	k.box_xf(xf.translated_local(Vector3(0, 0.95, 0)), Vector3(2.0, 1.0, 5.0), "suv_black")
	k.box_xf(xf.translated_local(Vector3(0, 1.75, 0.3)), Vector3(1.9, 0.7, 3.2), "suv_black")
	k.box_xf(xf.translated_local(Vector3(0, 1.75, -1.32)), Vector3(1.8, 0.6, 0.04), "window_dark", false)
	for s: float in [-1.0, 1.0]:
		k.box_xf(xf.translated_local(Vector3(s * 0.96, 1.75, 0.3)), Vector3(0.04, 0.55, 3.0), "window_dark", false)
		for z: float in [-1.6, 1.6]:
			k.box_xf(xf.translated_local(Vector3(s * 0.9, 0.42, z)), Vector3(0.3, 0.84, 0.84), "tyre", false)
