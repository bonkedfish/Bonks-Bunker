# StaticMeshMerger — put on the root of a hand-built landmark. At load it merges every MeshInstance3D
# below it into one mesh per material, so a landmark made of many small editable boxes costs only a
# handful of draw calls. Collision is untouched. Skips anything inside a node in group "loot_containers"
# or "no_merge" (things that may change at runtime). Originals are freed after merging.
extends Node3D


func _ready() -> void:
	var originals: Array[MeshInstance3D] = []
	_collect(self, originals)
	var inverse := global_transform.affine_inverse()
	var by_material := {}  # Material -> SurfaceTool
	for mi in originals:
		if mi.mesh == null:
			continue
		var xf := inverse * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if not by_material.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				by_material[mat] = st
			by_material[mat].append_from(mi.mesh, s, xf)
	for mat in by_material:
		var merged := MeshInstance3D.new()
		merged.name = "Merged"
		merged.mesh = by_material[mat].commit()
		merged.material_override = mat
		add_child(merged)
	for mi in originals:
		mi.queue_free()


func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child.is_in_group("loot_containers") or child.is_in_group("no_merge"):
			continue
		if child is MeshInstance3D:
			out.append(child)
		_collect(child, out)
