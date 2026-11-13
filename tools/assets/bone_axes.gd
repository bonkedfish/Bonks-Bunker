# BoneAxes — tuning aid for gear props (D-061): loads the Quaternius male and female base bodies, and for the bones
# gear attaches to prints each bone's rest origin (model space, metres after the 1.78/1.7 m height scale) and which
# model direction its local +X/+Y/+Z point (model faces +Z before yaw_offset). Log: tests/_look/bone_axes.txt.
# Depends on: the UBC glTFs in assets/characters/ubc/.
extends Node

const MODELS := ["res://assets/characters/ubc/Superhero_Male_FullBody.gltf", "res://assets/characters/ubc/Superhero_Female_FullBody.gltf"]
const BONES := ["Head", "neck_01", "spine_03", "spine_01", "pelvis", "upperarm_l", "upperarm_r", "clavicle_l", "lowerarm_l", "hand_r", "thigh_l", "calf_l"]


func _ready() -> void:
	var out := PackedStringArray()
	for path: String in MODELS:
		var inst := (load(path) as PackedScene).instantiate() as Node3D
		add_child(inst)
		var skel := inst.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var mesh_aabb := AABB()
		for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
			mesh_aabb = mesh_aabb.merge(mi.global_transform * mi.get_aabb())
		out.append("%s  mesh aabb %s  skeleton global scale %s" % [path.get_file(), mesh_aabb, skel.global_transform.basis.get_scale()])
		for b: String in BONES:
			var i := skel.find_bone(b)
			if i < 0:
				continue
			var g := skel.global_transform * skel.get_bone_global_rest(i)
			var bs := g.basis
			out.append("  %-11s origin %s  +X->%s  +Y->%s  +Z->%s  scale %s" % [b, g.origin.snapped(Vector3.ONE * 0.001),
				_dir(bs.x), _dir(bs.y), _dir(bs.z), bs.get_scale().snapped(Vector3.ONE * 0.001)])
		inst.queue_free()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/_look"))
	var f := FileAccess.open("res://tests/_look/bone_axes.txt", FileAccess.WRITE)
	f.store_string("\n".join(out))
	f.close()
	get_tree().quit()


func _dir(v: Vector3) -> String:
	return str(v.normalized().snapped(Vector3.ONE * 0.01))
