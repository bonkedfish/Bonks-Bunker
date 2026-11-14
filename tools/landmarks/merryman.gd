# Merryman — builds the Merryman Performing Arts Center (D-079; 225 W 22nd St, the 1926 Central school auditorium,
# renovated 2006) into a LandmarkKit from data/landmarks/merryman.json. Local frame = map axes (x east, z south),
# origin at the building's centre. Walls, floors, the raked house, balcony, stairs, rooms and furniture, signs,
# lights, loot and lair markers are data (LandmarkParts); this file adds the stage house: deck finish, main
# curtain, legs and borders, line-set battens, the fly gallery, the grid and the cyclorama.
# Depends on: LandmarkKit, landmark_parts.gd.
extends RefCounted

const Parts := preload("res://tools/landmarks/landmark_parts.gd")


static func build(k: LandmarkKit, d: Dictionary, _rng: RandomNumberGenerator) -> void:
	var fy := float(d.dims.floor_y)
	Parts.build_all(k, d, "merryman", fy)
	_stage(k, d.stage, fy)


static func _stage(k: LandmarkKit, s: Dictionary, fy: float) -> void:
	var r: Array = s.rect  # stage house inside walls: x0 (back wall), z0, x1 (proscenium), z1
	var px := float(r[2])
	var op: Array = s.opening  # proscenium opening [z0, z1]
	var arch := float(s.arch_top)
	var grid := float(s.grid_y)
	k.block(Vector3(r[0], fy, r[1]), Vector3(px, fy + 0.03, r[3]), "stage_wood", false)
	# Main curtain, drawn two-thirds open; a valance across the top of the arch.
	var mid := (float(op[0]) + float(op[1])) * 0.5
	var half := (float(op[1]) - float(op[0])) * 0.5
	for side: float in [-1.0, 1.0]:
		var zc := mid + side * (half - half * 0.33 * 0.5)
		k.box(Vector3(px - 0.4, fy + arch * 0.5, zc), Vector3(0.12, arch, half * 0.33), "curtain_red", 0.0, false)
	k.box(Vector3(px - 0.4, fy + arch - 0.6, mid), Vector3(0.14, 1.2, half * 2.0), "curtain_red", 0.0, false)
	# Legs (black side masking) and borders, every `masking_m` upstage of the curtain.
	var x := px - float(s.masking_m)
	while x > float(r[0]) + 1.5:
		for side: float in [-1.0, 1.0]:
			k.box(Vector3(x, fy + arch * 0.5, mid + side * (half + 0.6)), Vector3(0.08, arch, 2.4), "curtain_black", 0.0, false)
		k.box(Vector3(x, fy + arch - 0.4, mid), Vector3(0.08, 0.8, half * 2.0 + 4.0), "curtain_black", 0.0, false)
		x -= float(s.masking_m)
	# Line-set battens hanging below the grid, the grid itself and the fly gallery along the north wall.
	var b := px - 0.8
	while b > float(r[0]) + 0.8:
		k.box(Vector3(b, fy + float(s.batten_y), mid), Vector3(0.06, 0.06, half * 2.0 + 3.0), "steel", 0.0, false)
		k.box(Vector3(b, fy + (float(s.batten_y) + grid) * 0.5, mid - half - 1.4), Vector3(0.02, grid - float(s.batten_y), 0.02), "steel", 0.0, false)
		b -= float(s.batten_m)
	var gz := float(r[1]) + 0.2
	while gz < float(r[3]):
		k.box(Vector3((float(r[0]) + px) * 0.5, fy + grid, gz), Vector3(px - float(r[0]) - 0.4, 0.15, 0.12), "steel", 0.0, false)
		gz += 0.6
	var gy := fy + float(s.gallery_y)
	k.block(Vector3(float(r[0]) + 0.3, gy - 0.15, float(r[1]) + 0.3), Vector3(px - 0.3, gy, float(r[1]) + 1.8), "steel")
	k.railing(PackedVector3Array([Vector3(float(r[0]) + 0.3, gy, float(r[1]) + 1.8), Vector3(px - 0.3, gy, float(r[1]) + 1.8)]), 1.0, "steel", 1.5, true)
	# Cyclorama: pale cloth across the back wall.
	k.box(Vector3(float(r[0]) + 1.0, fy + arch * 0.5 + 0.5, mid), Vector3(0.05, arch + 1.0, half * 2.0 + 2.0), "cyc", 0.0, false)
