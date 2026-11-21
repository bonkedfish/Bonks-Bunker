# MixamoLineup — the Mixamo zombies (D-112) on their own, no world loaded: one of each in a row, lit like
# afternoon, cycling idle / walk / run / attack / scream / grab / crawl / twitch / death with a screenshot of each;
# per model it reports the skeleton (bone count, the prefix Mixamo gave it), which clips made it through
# retargeting, triangles, materials and texture sizes, and the height it was scaled to. Then 48 of them walking
# at once for frame time, draw calls and video memory - the open-world worst case.
# Results: tests/_look/mixamo_lineup.txt; mx_*.png. Depends on: CharacterAnimator, MixamoRetarget.
extends Node3D

const OUT := "res://tests/_look"
const IDS := ["mx_warzombie", "mx_zombiegirl", "mx_parasite", "mx_copzombie", "mx_warrok", "mx_ch10"]
const CLIPS := ["idle", "walk", "run", "attack", "scream", "grab", "crawl", "twitch", "death"]

var _log := PackedStringArray()
var _bodies: Array[CharacterAnimator] = []
var _cam: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_stage()
	for i in IDS.size():
		var b := CharacterAnimator.new()
		add_child(b)
		b.position = Vector3((i - (IDS.size() - 1) * 0.5) * 1.7, 0.0, 0.0)
		var ok := b.set_model(IDS[i])
		_bodies.append(b)
		_report(IDS[i], b, ok)
	await _frames(10)
	for clip: String in CLIPS:
		for b in _bodies:
			b.one_shot(clip, 999.0)
		await _frames(int(Engine.get_frames_per_second() * 0.9) + 20)
		await _shot("mx_%s.png" % clip)
	# a close look at the faces
	_cam.position = Vector3(0, 1.6, -2.6)
	_cam.look_at(Vector3(0, 1.45, 0))
	for b in _bodies:
		b.one_shot("idle", 999.0)
	await _frames(40)
	await _shot("mx_faces.png")
	await _crowd()
	var f := FileAccess.open(OUT + "/mixamo_lineup.txt", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	get_tree().quit()


func _stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -30, 0)  # light on their faces
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.38, 0.36, 0.32)
	pm.material = gm
	ground.mesh = pm
	add_child(ground)
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 1.4, -7.5)  # models face -Z (the game's forward), so look at them from there
	add_child(_cam)
	_cam.look_at(Vector3(0, 1.0, 0))
	_cam.current = true


func _report(id: String, b: CharacterAnimator, ok: bool) -> void:
	var def := CharacterAnimator.model_def(id)
	_log.append("== %s  (%s)  set_model %s" % [id, str(def.get("path", "?")).get_file(), "ok" if ok else "FAILED"])
	if not ok:
		return
	var skels := b.find_children("*", "Skeleton3D", true, false)
	if skels.size() > 0:
		var sk := skels[0] as Skeleton3D
		_log.append("   skeleton: %d bones, first '%s', hips '%s'" % [sk.get_bone_count(), sk.get_bone_name(0),
			_find_hips(sk)])
	var aps := b.find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0:
		var list := Array((aps[0] as AnimationPlayer).get_animation_list())
		list.sort()
		_log.append("   clips (%d): %s" % [list.size(), ", ".join(PackedStringArray(list))])
		for c: String in CLIPS:
			if not list.has(c):
				_log.append("   MISSING clip: %s" % c)
		for c: String in list:
			var anim := (aps[0] as AnimationPlayer).get_animation(c)
			_log.append("     %-9s %5.2f s  %3d tracks" % [c, anim.length, anim.get_track_count()])
	var tris := 0
	var mats := 0
	var tex := {}
	for mi: Node in b.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		for sidx in m.get_surface_count():
			var arrays := m.surface_get_arrays(sidx)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			tris += idx.size() / 3 if idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			mats += 1
			var mat := m.surface_get_material(sidx) as BaseMaterial3D
			if mat:
				for t: Texture2D in [mat.albedo_texture, mat.normal_texture, mat.roughness_texture, mat.metallic_texture]:
					if t:
						tex["%dx%d" % [t.get_width(), t.get_height()]] = int(tex.get("%dx%d" % [t.get_width(), t.get_height()], 0)) + 1
	var aabb := _bounds(b)
	_log.append("   %d triangles, %d surfaces, textures %s, standing %.2f m tall" % [tris, mats, str(tex), aabb.size.y])


func _find_hips(sk: Skeleton3D) -> String:
	for i in sk.get_bone_count():
		if MixamoRetarget.strip(sk.get_bone_name(i)) == "Hips":
			return sk.get_bone_name(i)
	return "(none)"


func _bounds(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi: Node in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var box := m.global_transform * m.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


# 48 walking at once: the open-world worst case (pool_size).
func _crowd() -> void:
	for b in _bodies:
		b.queue_free()
	_bodies.clear()
	await _frames(3)
	var crowd: Array[CharacterAnimator] = []
	for i in 48:
		var b := CharacterAnimator.new()
		add_child(b)
		b.position = Vector3((i % 8 - 3.5) * 1.6, 0.0, float(i / 8) * 2.2 + 2.0)
		b.set_model(IDS[i % IDS.size()])  # every model in use, Ch10 (the heaviest) included
		b.one_shot("walk", 999.0)
		crowd.append(b)
	_cam.position = Vector3(0, 2.2, -9.0)
	_cam.look_at(Vector3(0, 1.0, 5.0))
	await _frames(60)
	var sum := 0.0
	var worst := 0.0
	var n := 180
	for i in n:
		var t0 := Time.get_ticks_usec()
		for b in crowd:
			b.update(get_process_delta_time(), false, false, 100.0)
		await get_tree().process_frame
		var dt := get_process_delta_time() * 1000.0
		sum += dt
		worst = maxf(worst, dt)
	await _shot("mx_crowd.png")
	_log.append("\n48 walking: frame %.1f ms average, %.1f ms worst, %d draw calls, %d k primitives, %d MB video memory, %d MB RAM"
		% [sum / n, worst, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576])


func _process(delta: float) -> void:
	for b in _bodies:
		if is_instance_valid(b):
			b.update(delta, false, false, 100.0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "/" + file))
