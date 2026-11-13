# InspectLandmark — tuning aid: loads each generated bar scene on its own (no terrain), logs every merged mesh's
# material and AABB, and screenshots it from the downtown test's interior camera spots into
# tests/_look/inspect_<id>_<n>.png. Log: tests/_look/inspect_landmark.txt. Depends on: world/landmarks/<id>.scn.
extends Node3D

const SHOTS := {
	"copperfields": [[Vector3(-1, 1.7, -9.5), Vector3(-2, 1.0, 6)], [Vector3(0, 8, -16), Vector3(0, 0, 0)]],
	"gillies": [[Vector3(0, 1.7, -11.5), Vector3(0, 1.0, 10)], [Vector3(6, 2.5, -9), Vector3(-4, 1.5, 0)]],
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
	for id: String in SHOTS:
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
