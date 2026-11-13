# NavRegion — bakes the navigation mesh at runtime from nodes in group "navmesh_source" (the gray box)
# so zombies path around walls (D-020). Prints the result so a bad bake is visible in the output.
# The map import pipeline will bake per cell later.
extends NavigationRegion3D


func _ready() -> void:
	bake_finished.connect(_on_bake_finished)
	# Let CSG geometry build first.
	await get_tree().physics_frame
	await get_tree().physics_frame
	bake_navigation_mesh(true)


func _on_bake_finished() -> void:
	print("Navmesh baked: %d polygons" % navigation_mesh.get_polygon_count())
