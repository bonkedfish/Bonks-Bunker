# DiscLook — D-117 disc golf look check, standalone (no map needed): builds both basket styles (near and far LOD),
# the Centennial mulch ring, both tee pads with their signs, the three discs, and survivors on both rigs (kit and
# universal) posed at each throw style's reach-back, release and follow-through, plus the first-person arms per
# style. Screenshots each view, logs the arm IK error per pose and frame time / draw calls / primitives.
# Results: tests/_look/disc_look.txt (ends with the failure count); screenshots tests/_look/disc_look_*.png.
# The full disc catalog (D-119) is shot from above (disc_look_catalog.png).
# Depends on: BasketMesh, TeeBox, DiscMesh, CharacterAnimator, ThrowPose, DiscFlightRules, course_looks.json.
extends Node

const OUT_DIR := "res://tests/_look"
const BasketMesh := preload("res://scripts/discgolf/basket_mesh.gd")
const TeeBox := preload("res://scripts/discgolf/tee_box.gd")
const DiscMesh := preload("res://scripts/discgolf/disc_mesh.gd")
const RIGS := ["survivor_lis", "ubc_scavenger_m"]

var _log := PackedStringArray()
var _fails := 0
var _cam: Camera3D
var _looks: Dictionary


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_looks = DataLoader.load_json("res://data/discgolf/course_looks.json")
	_stage()
	_cam = Camera3D.new()
	_cam.fov = 70.0
	add_child(_cam)
	_cam.make_current()
	# Baskets: Centennial (Mach II style, mulch ring) at x 0, Cottonmill (modern) at x 3.
	_basket("mach2", Vector3(0, 0, 0), true)
	_basket("modern", Vector3(3, 0, 0), false)
	await _shot("baskets_near", Vector3(1.5, 1.4, 3.2), Vector3(1.5, 0.9, 0))
	await _shot("basket_chains", Vector3(0.0, 1.1, 0.9), Vector3(0, 1.0, 0))
	await _shot("baskets_far", Vector3(1.5, 2.0, 45.0), Vector3(1.5, 0.9, 0))
	# Tees with signs.
	_tee("asphalt", "post", Vector3(-8, 0, 0), 0.55)
	_tee("concrete", "frame", Vector3(-14, 0, 0), 0.5)
	await _shot("tees", Vector3(-11, 2.2, 6.5), Vector3(-11, 0.4, -1.5))
	await _shot("sign_post", Vector3(-6.9, 1.15, 0.6), Vector3(-6.9, 1.1, -2.4))
	# The three starters on the asphalt pad.
	var i := 0
	for id: String in ["disc_driver", "disc_mid", "disc_putter"]:
		var mi := MeshInstance3D.new()
		mi.mesh = DiscMesh.mesh(id)
		mi.position = Vector3(-8.25 + i * 0.25, 0.07, 0.5)
		add_child(mi)
		i += 1
	await _shot("discs", Vector3(-8.0, 0.45, 0.85), Vector3(-8.0, 0.07, 0.5))
	# The whole catalog (D-119), fastest first, laid out in rows of six on the grass.
	var order := DiscFlightRules.bag_order()
	for k in order.size():
		var mi := MeshInstance3D.new()
		mi.mesh = DiscMesh.mesh(order[k])
		mi.position = Vector3(-14.0 + (k % 6) * 0.26, 0.02, 3.0 + (k / 6) * 0.26)
		add_child(mi)
	await _shot("catalog", Vector3(-13.35, 1.0, 3.75 + (order.size() / 6) * 0.13), Vector3(-13.35, 0.0, 3.0 + (order.size() / 6) * 0.13))
	# Third person: one survivor per style in a row, each rig, three phases.
	var styles := DiscFlightRules.style_order()
	for r in RIGS.size():
		var bodies: Array[CharacterAnimator] = []
		for s in styles.size():
			var b := CharacterAnimator.new()
			add_child(b)
			b.position = Vector3(20 + s * 2.2, 0, r * 6.0)
			_check(b.set_model(str(RIGS[r])), "%s loads" % RIGS[r])
			bodies.append(b)
		for phase: String in ["reach", "release", "follow"]:
			for s in styles.size():
				var c := ThrowPose.clip(str(styles[s]))
				var t: float = c.reach if phase == "reach" else (c.release if phase == "release" else 0.9)
				bodies[s].pose_throw(str(styles[s]), "disc_driver", t)
			for k in 4:
				for b: CharacterAnimator in bodies:
					b.update(0.016, false, false, 100.0)
				await get_tree().process_frame
			for s in styles.size():
				_check(bodies[s].throw_ik_error < 0.06, "%s %s %s: hand %.3f m off the swing" % [RIGS[r], styles[s], phase, bodies[s].throw_ik_error])
			await _shot("tp_%s_%s" % [RIGS[r], phase], Vector3(24.4, 1.6, r * 6.0 + 6.5), Vector3(24.4, 1.0, r * 6.0))
			await _shot("tp_side_%s_%s" % [RIGS[r], phase], Vector3(31.5, 1.4, r * 6.0 + 1.0), Vector3(20.0, 1.0, r * 6.0))
		for b: CharacterAnimator in bodies:
			b.queue_free()
	# First person: arms under the camera, per style at reach and release.
	_cam.global_position = Vector3(40, 1.7, 0)
	_cam.rotation = Vector3.ZERO
	var arms := CharacterAnimator.new()
	_cam.add_child(arms)
	_check(arms.set_model("survivor_lis", true), "first-person arms load")
	for st: String in styles:
		for phase: String in ["reach", "release"]:
			var c := ThrowPose.clip(st)
			arms.pose_throw(st, "disc_driver", c.reach if phase == "reach" else c.release - 0.02)
			for k in 4:
				arms.update(0.016, false, false, 100.0)
				await get_tree().process_frame
			_check(arms.throw_ik_error < 0.06, "first person %s %s: hand %.3f m off" % [st, phase, arms.throw_ik_error])
			await _grab("fp_%s_%s" % [st, phase])
			var tip: Vector3 = arms._skeleton.global_transform * arms._ik.hand_tip(arms._skeleton)
			_log.append("  hand in camera space %s (x right, y up, -z ahead), on screen: %s" % [str(_cam.to_local(tip).snapped(Vector3.ONE * 0.01)), str(_cam.is_position_in_frustum(tip))])
	# A whole swing plays and ends with the disc gone and hands back to idle.
	var rel := arms.start_throw("backhand", "disc_driver")
	_check(rel > 0.2 and rel < 1.0, "backhand releases %.2f s after the start" % rel)
	for k in 90:
		arms.update(0.016, false, false, 100.0)
		await get_tree().process_frame
	_check(not arms.throwing(), "swing finishes")
	_log.append("%d failure(s)" % _fails)
	var f := FileAccess.open(OUT_DIR + "/disc_look.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	get_tree().quit()


func _stage() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = sky
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300, 300)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.42, 0.2)
	gm.roughness = 1.0
	ground.material_override = gm
	add_child(ground)


func _basket(style_id: String, at: Vector3, ring: bool) -> void:
	var style: Dictionary = _looks.baskets[style_id]
	var near := float(style.near_m)
	for is_near: bool in [true, false]:
		var mi := MeshInstance3D.new()
		mi.mesh = BasketMesh.mesh(style, _looks.metal, _looks.link, 0.55, is_near)
		if is_near:
			mi.visibility_range_end = near
		else:
			mi.visibility_range_begin = near
			mi.visibility_range_end = float(style.far_m)
		mi.position = at
		add_child(mi)
		_log.append("basket %s %s: %d surfaces, %d vertices" % [style_id, "near" if is_near else "far", mi.mesh.get_surface_count(), _verts(mi.mesh)])
	if ring:
		for m: Mesh in TeeBox.ring_meshes(_looks.rings.mulch):
			var r := MeshInstance3D.new()
			r.mesh = m
			r.position = at
			add_child(r)


func _tee(tee_id: String, sign_id: String, at: Vector3, wear: float) -> void:
	var style: Dictionary = _looks.tees[tee_id]
	var pad := MeshInstance3D.new()
	pad.mesh = TeeBox.pad_mesh(style)
	pad.position = at + Vector3(0, float(style.top_m) - 0.15, 0)
	add_child(pad)
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(20, -40), Vector2(10, -90)])
	var built: Array = TeeBox.sign_mesh(_looks.signs[sign_id], pts, wear, 7)
	var board := MeshInstance3D.new()
	board.mesh = built[0]
	board.position = at + Vector3(float(style.size[0]) * 0.5 + 0.7, 0, -float(style.size[1]) * 0.5)
	add_child(board)
	var label := Label3D.new()
	label.text = "HOLE 4\nPAR 3\n312 FT"
	label.font_size = 34
	label.pixel_size = 0.0022
	label.outline_size = 4
	label.position = built[1] + Vector3(0, 0, 0.003)
	board.add_child(label)


func _verts(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		n += (m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return n


func _shot(tag: String, from: Vector3, at: Vector3) -> void:
	_cam.global_position = from
	_cam.look_at(at)
	await _grab(tag)


func _grab(tag: String) -> void:
	for k in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_DIR + "/disc_look_%s.png" % tag))
	var sum := 0.0
	for i in 20:
		await get_tree().process_frame
		sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_log.append("%s: frame %.1f ms, %d draw calls, %d k primitives" % [tag, sum / 20.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)])


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	_log.append(("PASS " if ok else "FAIL ") + what)
