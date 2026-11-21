# PropKits — small sets of boxes and cylinders that stand in for props the asset kits don't have (D-105..D-108):
# skeletons, lawn chairs, coolers, radios, cones, desks, toilets, treadmills, mannequins, vending machines and the
# collectible trinkets. Each kit returns prop dictionaries in the shape EncounterSite understands
# ({box [cx,cy,cz,sx,sy,sz] | cyl [x,y,z,r,h], mat, yaw?, collide?, emit?}), already offset and turned, so sites,
# world oddities and collectibles all build them the same way. Functional placeholders: swap a kit for a model
# later and everything that lists it follows. Pure: no nodes. Depends on: nothing.
class_name PropKits
extends RefCounted

# kind -> [[shape, mat, x, y, z, a, b, c], ...]  shape "b" = box (a,b,c = size), "c" = cylinder (a = radius, b = height)
const KITS := {
	"skeleton_sitting": [
		["b", "bone", 0, 0.42, 0, 0.3, 0.46, 0.22], ["b", "bone", 0, 0.72, 0.02, 0.26, 0.2, 0.2],
		["c", "bone", 0, 0.86, 0.02, 0.1, 0.1], ["c", "bone", -0.18, 0.3, 0.2, 0.05, 0.42],
		["c", "bone", 0.18, 0.3, 0.2, 0.05, 0.42], ["c", "bone", -0.18, 0.08, 0.42, 0.05, 0.4],
		["c", "bone", 0.18, 0.08, 0.42, 0.05, 0.4], ["c", "bone", -0.26, 0.46, 0.14, 0.045, 0.4],
		["c", "bone", 0.26, 0.46, 0.14, 0.045, 0.4]],
	"skeleton_slumped": [
		["b", "bone", 0, 0.18, 0, 0.3, 0.36, 0.24], ["c", "bone", 0, 0.42, 0.06, 0.1, 0.1],
		["c", "bone", -0.2, 0.08, 0.4, 0.05, 0.6], ["c", "bone", 0.2, 0.08, 0.4, 0.05, 0.6],
		["c", "bone", -0.3, 0.14, 0.1, 0.045, 0.34], ["c", "bone", 0.3, 0.14, 0.1, 0.045, 0.34]],
	"skeleton_standing": [
		["b", "bone", 0, 1.05, 0, 0.32, 0.5, 0.22], ["c", "bone", 0, 1.42, 0, 0.1, 0.12],
		["c", "bone", -0.1, 0.4, 0, 0.055, 0.8], ["c", "bone", 0.1, 0.4, 0, 0.055, 0.8],
		["c", "bone", -0.24, 0.95, 0, 0.05, 0.6], ["c", "bone", 0.24, 0.95, 0, 0.05, 0.6]],
	"lawn_chair": [
		["b", "canvas", 0, 0.38, 0, 0.6, 0.05, 0.56], ["b", "canvas", 0, 0.62, -0.28, 0.6, 0.52, 0.05],
		["c", "chrome", -0.28, 0.19, 0.24, 0.025, 0.38], ["c", "chrome", 0.28, 0.19, 0.24, 0.025, 0.38],
		["c", "chrome", -0.28, 0.19, -0.26, 0.025, 0.38], ["c", "chrome", 0.28, 0.19, -0.26, 0.025, 0.38]],
	"cooler": [["b", "white", 0, 0.2, 0, 0.62, 0.4, 0.4], ["b", "blue", 0, 0.43, 0, 0.64, 0.06, 0.42]],
	"radio": [["b", "dark", 0, 0.12, 0, 0.34, 0.24, 0.16], ["c", "chrome", 0.14, 0.34, 0, 0.012, 0.44],
		["c", "steel", -0.08, 0.12, 0.085, 0.07, 0.02]],
	"traffic_cone": [["b", "dark", 0, 0.02, 0, 0.34, 0.04, 0.34], ["c", "orange", 0, 0.3, 0, 0.1, 0.56],
		["c", "white", 0, 0.38, 0, 0.105, 0.08]],
	"office_desk": [["b", "wood", 0, 0.72, 0, 1.5, 0.06, 0.75], ["b", "steel", -0.68, 0.36, 0, 0.08, 0.72, 0.7],
		["b", "steel", 0.68, 0.36, 0, 0.08, 0.72, 0.7], ["b", "dark", 0, 0.92, -0.2, 0.42, 0.34, 0.06],
		["b", "white", 0, 0.76, 0.12, 0.42, 0.02, 0.18]],
	"office_chair": [["b", "dark", 0, 0.45, 0, 0.46, 0.08, 0.46], ["b", "dark", 0, 0.72, -0.2, 0.46, 0.5, 0.07],
		["c", "steel", 0, 0.22, 0, 0.04, 0.44], ["c", "dark", 0, 0.04, 0, 0.3, 0.07]],
	"toilet": [["b", "white", 0, 0.2, 0, 0.38, 0.4, 0.52], ["b", "white", 0, 0.42, 0, 0.42, 0.06, 0.56],
		["b", "white", 0, 0.58, -0.3, 0.44, 0.7, 0.2], ["c", "chrome", 0.3, 0.3, 0.3, 0.015, 0.5],
		["c", "white", 0.3, 0.56, 0.3, 0.055, 0.1]],
	"treadmill": [["b", "dark", 0, 0.18, 0, 0.7, 0.14, 1.6], ["b", "steel", 0, 0.27, 0, 0.5, 0.06, 1.4],
		["c", "steel", -0.32, 0.65, -0.6, 0.03, 0.95], ["c", "steel", 0.32, 0.65, -0.6, 0.03, 0.95],
		["b", "dark", 0, 1.1, -0.62, 0.68, 0.3, 0.1]],
	"mannequin": [["b", "pink", 0, 1.1, 0, 0.3, 0.56, 0.18], ["c", "pink", 0, 1.48, 0, 0.09, 0.22],
		["c", "pink", -0.09, 0.4, 0, 0.06, 0.8], ["c", "pink", 0.09, 0.4, 0, 0.06, 0.8],
		["c", "pink", -0.22, 1.0, 0, 0.05, 0.58], ["c", "pink", 0.22, 1.0, 0, 0.05, 0.58],
		["c", "dark", 0, 0.02, 0, 0.26, 0.04]],
	"vending_machine": [["b", "red", 0, 0.95, 0, 0.95, 1.9, 0.75], ["b", "glass", 0, 1.05, 0.38, 0.72, 1.4, 0.03],
		["b", "dark", 0.36, 1.1, 0.39, 0.14, 0.5, 0.04]],
	"bathtub": [["b", "white", 0, 0.28, 0, 0.78, 0.56, 1.7], ["b", "dark", 0, 0.5, 0, 0.66, 0.3, 1.58],
		["c", "chrome", 0, 0.68, -0.78, 0.03, 0.3]],
	"shopping_cart": [["b", "chrome", 0, 0.6, 0, 0.56, 0.5, 0.9], ["b", "chrome", 0, 0.34, 0, 0.5, 0.03, 0.84],
		["c", "dark", -0.24, 0.05, 0.38, 0.05, 0.04], ["c", "dark", 0.24, 0.05, 0.38, 0.05, 0.04],
		["c", "dark", -0.24, 0.05, -0.38, 0.05, 0.04], ["c", "dark", 0.24, 0.05, -0.38, 0.05, 0.04],
		["c", "red", 0, 0.88, -0.46, 0.02, 0.5]],
	"gnome": [["c", "red", 0, 0.42, 0, 0.09, 0.2], ["b", "blue", 0, 0.18, 0, 0.18, 0.36, 0.16],
		["c", "bone", 0, 0.34, 0.02, 0.07, 0.08]],
	"bowling_pin": [["c", "white", 0, 0.19, 0, 0.055, 0.38], ["c", "red", 0, 0.32, 0, 0.035, 0.05]],
	"rubber_duck": [["b", "yellow", 0, 0.07, 0, 0.14, 0.14, 0.2], ["b", "yellow", 0, 0.17, 0.05, 0.1, 0.1, 0.1],
		["b", "orange", 0, 0.16, 0.12, 0.05, 0.03, 0.07]],
	"plunger": [["c", "wood", 0, 0.3, 0, 0.018, 0.6], ["c", "red", 0, 0.06, 0, 0.09, 0.12]],
	"trophy": [["b", "dark", 0, 0.04, 0, 0.16, 0.08, 0.16], ["c", "yellow", 0, 0.16, 0, 0.03, 0.16],
		["c", "yellow", 0, 0.3, 0, 0.09, 0.14]],
	"lunchbox": [["b", "blue", 0, 0.11, 0, 0.26, 0.22, 0.14], ["c", "chrome", 0, 0.24, 0, 0.012, 0.12]],
	"vhs": [["b", "dark", 0, 0.015, 0, 0.19, 0.03, 0.11], ["b", "white", 0, 0.031, 0, 0.17, 0.004, 0.05]],
	"flip_phone": [["b", "dark", 0, 0.012, 0, 0.05, 0.024, 0.1], ["b", "steel", 0, 0.03, -0.03, 0.045, 0.012, 0.04]],
	"license_plate": [["b", "white", 0, 0.004, 0, 0.3, 0.008, 0.15], ["b", "blue", 0, 0.009, 0, 0.26, 0.003, 0.05]],
	"model_car": [["b", "red", 0, 0.03, 0, 0.07, 0.04, 0.16], ["b", "glass", 0, 0.06, -0.01, 0.06, 0.03, 0.07],
		["c", "dark", -0.035, 0.015, 0.05, 0.015, 0.01], ["c", "dark", 0.035, 0.015, 0.05, 0.015, 0.01]],
	"playing_card": [["b", "white", 0, 0.002, 0, 0.063, 0.004, 0.088]],
	"golf_ball": [["c", "white", 0, 0.021, 0, 0.021, 0.042]],
	"golf_tee": [["c", "yellow", 0, 0.02, 0, 0.004, 0.04], ["c", "yellow", 0, 0.045, 0, 0.011, 0.012]],
	"mannequin_head": [["c", "pink", 0, 0.11, 0, 0.09, 0.22], ["c", "dark", 0, 0.01, 0, 0.07, 0.02]],
	"crate": [["b", "wood", 0, 0.3, 0, 0.7, 0.6, 0.7]],
	"barrel": [["c", "rust", 0, 0.45, 0, 0.3, 0.9]],
	"tarp_canopy": [["c", "steel", -1.6, 1.1, -1.2, 0.04, 2.2], ["c", "steel", 1.6, 1.1, -1.2, 0.04, 2.2],
		["c", "steel", -1.6, 1.1, 1.2, 0.04, 2.2], ["c", "steel", 1.6, 1.1, 1.2, 0.04, 2.2],
		["b", "canvas", 0, 2.24, 0, 3.4, 0.06, 2.6]],
	"grave_mound": [["b", "ash", 0, 0.12, 0, 0.9, 0.24, 2.0], ["b", "wood", 0, 0.5, -1.1, 0.1, 1.0, 0.08],
		["b", "wood", 0, 0.8, -1.1, 0.5, 0.1, 0.08]],
	"door_frame": [["b", "wood", -0.55, 1.05, 0, 0.12, 2.1, 0.2], ["b", "wood", 0.55, 1.05, 0, 0.12, 2.1, 0.2],
		["b", "wood", 0, 2.16, 0, 1.22, 0.12, 0.2], ["b", "green", 0, 1.03, 0, 0.98, 2.04, 0.06],
		["c", "chrome", 0.38, 1.0, 0.06, 0.03, 0.08]],
	"chopper_wreck": [["b", "dark", 0, 0.9, 0, 1.8, 1.5, 4.2], ["b", "glass", 0, 1.1, 2.0, 1.4, 1.0, 0.1],
		["b", "dark", 0, 1.6, -2.6, 0.5, 0.9, 1.6], ["c", "steel", 0, 1.9, 0, 0.12, 0.6],
		["b", "steel", 2.6, 2.1, 0.6, 5.6, 0.08, 0.4], ["b", "steel", -1.9, 2.05, -2.2, 4.4, 0.08, 0.35]],
	"fridge": [["b", "white", 0, 0.85, 0, 0.7, 1.7, 0.68], ["b", "chrome", 0.3, 1.0, 0.35, 0.04, 0.9, 0.04]],
	"tent": [["b", "green", 0, 0.5, 0, 1.8, 1.0, 2.2], ["b", "green", 0, 1.2, 0, 0.9, 0.5, 2.2]],
	"log_seat": [["c", "wood", 0, 0.22, 0, 0.22, 1.6]],
	"sandbag_wall": [["b", "canvas", 0, 0.2, 0, 2.4, 0.4, 0.5], ["b", "canvas", 0, 0.58, 0, 2.0, 0.4, 0.5],
		["b", "canvas", 0, 0.94, 0, 1.4, 0.36, 0.5]],
}


# The prop dictionaries for `kind`, moved to `at` and turned by `yaw` degrees (so a kit can face any way).
static func parts(kind: String, at: Vector3, yaw_deg: float, collide := true) -> Array:
	var out: Array = []
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	for part: Array in KITS.get(kind, []):
		var local := Vector3(part[2], part[3], part[4])
		var world := at + basis * local
		if str(part[0]) == "c":
			out.append({"cyl": [world.x, world.y - float(part[6]) * 0.5, world.z, part[5], part[6]],
				"mat": part[1], "collide": false})
		else:
			out.append({"box": [world.x, world.y, world.z, part[5], part[6], part[7]], "mat": part[1],
				"yaw": yaw_deg, "collide": false})
	if collide and not out.is_empty():
		out.append({"box": _bounds(kind, at, basis), "mat": "dark", "yaw": yaw_deg, "invisible": true})
	return out


static func has(kind: String) -> bool:
	return KITS.has(kind)


# One box that covers the whole kit, used as its collision (invisible).
static func _bounds(kind: String, at: Vector3, basis: Basis) -> Array:
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for part: Array in KITS[kind]:
		var c := Vector3(part[2], part[3], part[4])
		var half := Vector3(part[5], part[6], part[7]) * 0.5 if str(part[0]) == "b" else Vector3(part[5], float(part[6]) * 0.5, part[5])
		lo = Vector3(minf(lo.x, c.x - half.x), minf(lo.y, c.y - half.y), minf(lo.z, c.z - half.z))
		hi = Vector3(maxf(hi.x, c.x + half.x), maxf(hi.y, c.y + half.y), maxf(hi.z, c.z + half.z))
	var centre := at + basis * ((lo + hi) * 0.5)
	var size := hi - lo
	return [centre.x, centre.y, centre.z, maxf(size.x, 0.1), maxf(size.y, 0.1), maxf(size.z, 0.1)]
