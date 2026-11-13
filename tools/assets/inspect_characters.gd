# InspectCharacters — dumps the node tree, skeleton bones, mesh materials and animation names of the Quaternius
# character/animation files (D-058) to tests/_look/inspect_characters.txt. Depends on: imported assets/characters/.
extends Node

const FILES := ["res://assets/characters/ual/UAL1_Standard.glb", "res://assets/characters/ubc/Superhero_Male_FullBody.gltf",
	"res://assets/characters/ubc/Superhero_Female_FullBody.gltf", "res://assets/characters/ubc/hair/Hair_Buzzed.gltf",
	"res://assets/characters/zombie_apocalypse_kit/glTF/Characters_Matt.gltf"]

var _lines := PackedStringArray()


func _ready() -> void:
	for path: String in FILES:
		_lines.append("==== " + path)
		var ps := load(path) as PackedScene
		if ps == null:
			_lines.append("  (cannot load)")
			continue
		var root := ps.instantiate()
		_dump(root, root, 0)
		for ap: AnimationPlayer in root.find_children("*", "AnimationPlayer", true, false):
			var names := ap.get_animation_list()
			_lines.append("  anims (%d): %s" % [names.size(), ", ".join(names)])
			if names.size() > 0:
				var a := ap.get_animation(names[0])
				for t in mini(a.get_track_count(), 3):
					_lines.append("    track %s" % a.track_get_path(t))
		for sk: Skeleton3D in root.find_children("*", "Skeleton3D", true, false):
			var bones := PackedStringArray()
			for b in sk.get_bone_count():
				bones.append(sk.get_bone_name(b))
			_lines.append("  skeleton %s: %d bones: %s" % [root.get_path_to(sk), sk.get_bone_count(), ", ".join(bones)])
		root.free()
	var f := FileAccess.open("res://tests/_look/inspect_characters.txt", FileAccess.WRITE)
	f.store_string("\n".join(_lines))
	f.close()
	get_tree().quit()


func _dump(n: Node, root: Node, depth: int) -> void:
	if depth > 5:
		return
	var extra := ""
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mats := PackedStringArray()
		if mi.mesh:
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				mats.append(m.resource_name if m else "-")
		extra = " mesh=%s skin=%s mats=[%s] aabb=%s" % [mi.mesh.resource_name if mi.mesh else "-", mi.skin != null, ", ".join(mats), mi.get_aabb().size]
	if depth <= 3 or n is MeshInstance3D:
		_lines.append("  %s%s (%s)%s" % ["  ".repeat(depth), n.name, n.get_class(), extra])
	for c in n.get_children():
		_dump(c, root, depth + 1)
