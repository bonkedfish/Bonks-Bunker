# InspectLandmark — tuning aid: loads each generated landmark scene in SHOTS on its own (or only the one named in
# tests/_look/inspect_only.txt) (no terrain), logs every merged mesh's
# material and AABB, and screenshots it from the downtown test's interior camera spots into
# tests/_look/inspect_<id>_<n>.png. Log: tests/_look/inspect_landmark.txt. Depends on: world/landmarks/<id>.scn.
extends Node3D

const SHOTS := {
	"copperfields": [[Vector3(-1, 1.7, -9.5), Vector3(-2, 1.0, 6)], [Vector3(0, 8, -16), Vector3(0, 0, 0)]],
	"gillies": [[Vector3(0, 1.7, -11.5), Vector3(0, 1.0, 10)], [Vector3(6, 2.5, -9), Vector3(-4, 1.5, 0)]],
	"kenwood": [[Vector3(70, 50, 75), Vector3(0, 0, -25)], [Vector3(-30, 1.7, -20.75), Vector3(10, 1.5, -20.75)],
		[Vector3(8, 1.7, -77), Vector3(-1, 1, -70)], [Vector3(14, 4, -30), Vector3(45, 1, -12)], [Vector3(5, 2, 18), Vector3(-15, 1, -2)],
		[Vector3(-3.5, 1.7, -36), Vector3(-3.5, 1.5, -89)], [Vector3(-40, 20, 60), Vector3(-5, 0, 20)]],
	"centennial_pool": [[Vector3(30, 25, 35), Vector3(0, -1, -5)], [Vector3(-8, 1.6, 12), Vector3(2, -1.5, -12)],
		[Vector3(0, -0.1, -13.5), Vector3(-4, 0.5, 10)], [Vector3(-20, 1.7, 19.2), Vector3(-20, 1, 27)], [Vector3(7, 1.7, 19.2), Vector3(-2, 1, 23)],
		[Vector3(-10, 6, 45), Vector3(-9, 1, 25)]],
	"merryman": [[Vector3(55, 30, 60), Vector3(0, 4, 0)], [Vector3(20, 6.6, -2), Vector3(-15, 3, -2)], [Vector3(-12, 1.9, -2), Vector3(18, 3, -2)],
		[Vector3(-2, 1.7, 19), Vector3(20, 1.5, 15)], [Vector3(-26.5, 1.8, -17.2), Vector3(30, 1.5, -17.2)], [Vector3(-40, 8, -40), Vector3(0, 6, 0)]],
	"big_apple": [[Vector3(110, 60, 90), Vector3(30, 0, 10)], [Vector3(-38, 1.7, -17), Vector3(-38, 1, 10)], [Vector3(-20, 1.7, -24), Vector3(-60, 1, -40)],
		[Vector3(11, 1.7, -20), Vector3(-5, 1, -36)], [Vector3(16, 1.7, 0), Vector3(35, 1, 25)], [Vector3(125, 10, 105), Vector3(122, 0, 64)]],
	"cope_stadium": [[Vector3(90, 70, 110), Vector3(-20, 0, 0)], [Vector3(0, 1.7, 0), Vector3(-60, 8, 0)], [Vector3(-63, 9.8, -10), Vector3(0, 0, 10)],
		[Vector3(-72, 9.8, -30), Vector3(-80, 9, 10)], [Vector3(-5, 1.7, -77), Vector3(-5, 1, -92)], [Vector3(0, 2, 30), Vector3(0, 9, 72)]],
	"rv_park": [[Vector3(150, 120, 150), Vector3(0, 0, 0)], [Vector3(-112, 1.8, 140), Vector3(-93.8, 1.5, 118.8)], [Vector3(25, 2, 5), Vector3(7.9, 1, -13.1)],
		[Vector3(-118, 1.7, 125), Vector3(-95, 1.2, 125)], [Vector3(-105, 2, 75), Vector3(-125, 0.5, 100)], [Vector3(70, 4, -60), Vector3(94, 0, -36)]],
	"country_club": [[Vector3(70, 60, 100), Vector3(10, 0, 10)], [Vector3(10, 1.7, -3), Vector3(-10, 1, -12)], [Vector3(20, 2, -10), Vector3(40, -1, -28)],
		[Vector3(22, 1.7, 32), Vector3(35, 1, 40)], [Vector3(68, 3, 45), Vector3(68, 0, 70)], [Vector3(-25, 2, 85), Vector3(-38, 1, 100)]],
}


func _ready() -> void:
	var out := PackedStringArray()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.4, 0.5, 0.6)
	add_child(env)
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	var only := ""  # tests/_look/inspect_only.txt, if present, names the one landmark to shoot
	if FileAccess.file_exists("res://tests/_look/inspect_only.txt"):
		only = FileAccess.get_file_as_string("res://tests/_look/inspect_only.txt").strip_edges()
	for id: String in SHOTS:
		if only != "" and id != only:
			continue
		var inst := (load("res://world/landmarks/%s.scn" % id) as PackedScene).instantiate() as Node3D
		add_child(inst)
		for mi: MeshInstance3D in inst.find_children("Mesh_*", "MeshInstance3D", false, false):
			out.append("%s %-14s %s" % [id, str(mi.name).trim_prefix("Mesh_"), mi.get_aabb()])
		var i := 0
		for s: Array in SHOTS[id]:
			cam.position = s[0]
			cam.look_at(s[1])
			await get_tree().create_timer(0.5).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://tests/_look/inspect_%s_%d.png" % [id, i])
			i += 1
		inst.queue_free()
		await get_tree().process_frame
	var f := FileAccess.open("res://tests/_look/inspect_landmark.txt", FileAccess.WRITE)
	f.store_string("\n".join(out))
	f.close()
	get_tree().quit()
