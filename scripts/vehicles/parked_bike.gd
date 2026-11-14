# ParkedBike — a motorcycle standing in the world that nobody is riding (D-083), made by BikeDirector on every peer
# as child "B_<bike id>". An E use spot (group "sport_spots": metas target / index / display_name; the HUD shows
# "E <display_name>"): E asks the host to ride it (BikeDirector.host_mount). A crashed bike lies on its side until
# someone picks it up. Solid to walk into (world + interactables layer). Mesh from BikeMesh (shared per bike + scheme).
# Depends on: BikeMesh, BikeRules, BikeDirector (parent).
class_name ParkedBike
extends StaticBody3D

const LAYER := 9  # world + interactables

var bike_id := ""


func setup(id: String, model: String, scheme: int, fuel: float, tipped: bool, view_m: float) -> void:
	bike_id = id
	name = "B_" + id
	add_to_group("sport_spots")
	collision_layer = LAYER
	collision_mask = 0
	var b := BikeRules.bike(model)
	var pivot := Node3D.new()
	add_child(pivot)
	if tipped:  # lying on its left side
		pivot.rotation.z = deg_to_rad(78.0)
		pivot.position.y = 0.12
	var mi := MeshInstance3D.new()
	mi.mesh = BikeMesh.body(model, scheme)
	mi.visibility_range_end = view_m
	pivot.add_child(mi)
	for a: Vector3 in BikeMesh.axles(model):
		var w := MeshInstance3D.new()
		w.mesh = BikeMesh.wheel(model)
		w.position = a
		w.visibility_range_end = view_m
		pivot.add_child(w)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var sh: Dictionary = b.shape
	box.size = Vector3(0.45, 0.4, float(sh.wheelbase) + float(sh.wheel_r) * 2.0) if tipped \
		else Vector3(0.45, float(sh.seat_h), float(sh.wheelbase) + float(sh.wheel_r) * 2.0)
	shape.shape = box
	shape.position.y = box.size.y * 0.5
	add_child(shape)
	set_meta("target", self)
	set_meta("index", 0)
	var pct := roundi(100.0 * fuel / maxf(float(b.tank_l), 0.1))
	set_meta("display_name", "%s %s (gas %d%%)" % ["Pick up the" if tipped else "Ride the", str(b.name), pct])


@rpc("any_peer", "call_local", "reliable")
func request_use(_index: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
	get_parent().host_mount(peer, bike_id)
