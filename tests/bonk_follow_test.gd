# BonkFollowTest — loads the real level, hosts, checks the navmesh connects the bunker to the yard
# (closest-point gaps along the stair ramp + a path query), then moves the player to the yard and the
# house and prints where Bonk is every 2 s. Run this scene directly.
# Depends on: scenes/main.tscn, Net autoload, Bonk (group "bonk").
extends Node

const BUNKER := Vector3(-41.8, 0.0, 0.4)

var _bonk: Node3D
var _stuck_time := 0.0
var _last_report := -10.0


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz test")  # throwaway world, deleted below
	main._on_host_pressed()
	await get_tree().create_timer(3.0).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var me: Node3D = get_tree().get_first_node_in_group("local_player")
	var bonk: Node3D = get_tree().get_first_node_in_group("bonk")
	var map: RID = bonk.nav.get_navigation_map()
	_bonk = bonk

	# Navmesh along the ramp centreline (local x 1..7 rises y -4..0).
	for i in 7:
		var lx := 1.0 + i
		var p := BUNKER + Vector3(lx, -4.0 + (lx - 1.0) * 4.0 / 6.0, 0.0)
		var c := NavigationServer3D.map_get_closest_point(map, p)
		print("NAV ramp x=%.0f: want %s closest %s gap %.2f" % [lx, p.snapped(Vector3.ONE * 0.1), c.snapped(Vector3.ONE * 0.1), c.distance_to(p)])
	var yard := BUNKER + Vector3(10.0, 0.0, 0.0)
	var path := NavigationServer3D.map_get_path(map, me.global_position, yard, true)
	var end := path[path.size() - 1] if path.size() > 0 else Vector3.INF
	print("NAV path spawn->yard: %d points, ends %s, %.1f m short" % [path.size(), end.snapped(Vector3.ONE * 0.1), end.distance_to(NavigationServer3D.map_get_closest_point(map, yard))])

	me.global_position = yard + Vector3.UP * 0.2
	print("FOLLOW: player moved to the yard %s" % yard)
	for i in 10:
		await get_tree().create_timer(2.0).timeout
		print("FOLLOW t=%2ds player %s bonk %s  dist %.1f  vel %.1f  next %s" % [(i + 1) * 2, me.global_position.snapped(Vector3.ONE * 0.1), bonk.global_position.snapped(Vector3.ONE * 0.1),
			bonk.global_position.distance_to(me.global_position), bonk.velocity.length(), bonk.nav.get_next_path_position().snapped(Vector3.ONE * 0.1)])

	var house := get_tree().get_first_node_in_group("loot_containers")
	for c in get_tree().get_nodes_in_group("loot_containers"):
		if c.get_parent().get_parent().name == "bonk_house":
			house = c
			break
	me.global_position = house.global_position + Vector3(0, 0.2, 0) + (house.global_basis.z * 1.2)
	print("FOLLOW: player moved into the house near %s %s" % [house.name, me.global_position.snapped(Vector3.ONE * 0.1)])
	for i in 8:
		await get_tree().create_timer(2.0).timeout
		print("FOLLOW t=%2ds player %s bonk %s  dist %.1f  vel %.1f" % [(i + 1) * 2, me.global_position.snapped(Vector3.ONE * 0.1), bonk.global_position.snapped(Vector3.ONE * 0.1),
			bonk.global_position.distance_to(me.global_position), bonk.velocity.length()])

	# Walk straight into Bonk for 2 s (real input path) and see whether he steps aside (D-035).
	me.global_position = BUNKER + Vector3(10.0, 0.2, 0.0)  # open yard; Bonk catches up and stops ~3.5 m away
	await get_tree().create_timer(8.0).timeout
	var me_start := me.global_position
	var to_bonk := bonk.global_position - me.global_position
	me.yaw = atan2(-to_bonk.x, -to_bonk.z)
	await get_tree().create_timer(0.3).timeout
	var bonk_start := bonk.global_position
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.action_press("move_forward")
	var closest := INF
	for i in 20:
		await get_tree().create_timer(0.1).timeout
		closest = minf(closest, Vector2(bonk.global_position.x - me.global_position.x, bonk.global_position.z - me.global_position.z).length())
	Input.action_release("move_forward")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("DODGE: start gap %.1f m; bonk moved" % to_bonk.length() + " %.1f m, closest %.2f m (0.70 = bumping), player walked %.1f m" % [
		bonk.global_position.distance_to(bonk_start), closest, me.global_position.distance_to(me_start)])
	SaveStore.delete(main.saves.world_slug)
	await get_tree().create_timer(20.0).timeout
	get_tree().quit()


# Every physics frame: when Bonk wants to move but barely does for 0.5 s, report what he is touching.
func _physics_process(delta: float) -> void:
	if _bonk == null:
		return
	var horiz := Vector2(_bonk.velocity.x, _bonk.velocity.z).length()
	if not (_bonk.brain.wants_move and horiz < 0.5):
		_stuck_time = 0.0
		return
	_stuck_time += delta
	var now := Time.get_ticks_msec() / 1000.0
	if _stuck_time < 0.5 or now - _last_report < 1.0:
		return
	_last_report = now
	var touching := []
	for i in _bonk.get_slide_collision_count():
		var c: KinematicCollision3D = _bonk.get_slide_collision(i)
		var o: Object = c.get_collider()
		touching.append("%s n=%s at %s" % [o.get_path() if o is Node else o, c.get_normal().snapped(Vector3.ONE * 0.01), c.get_position().snapped(Vector3.ONE * 0.01)])
	print("STUCK %.1fs bonk %s state=%s on_floor=%s on_wall=%s next=%s touching=%s" % [_stuck_time, _bonk.global_position.snapped(Vector3.ONE * 0.01),
		CompanionBrain.State.keys()[_bonk.brain.state], _bonk.is_on_floor(), _bonk.is_on_wall(), _bonk.nav.get_next_path_position().snapped(Vector3.ONE * 0.01), touching])
