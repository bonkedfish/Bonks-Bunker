# Workbench — the crafting bench in Bonk's bunker (D-046; crafting only happens here). E opens the crafting
# window (CraftingUI, group "crafting_ui") locally; Craft asks the host, which checks the player is alive and in
# reach and holds every ingredient, then takes the ingredients and gives the result. Instant. Recipes are data
# (RecipeDB). Group "workbenches". Built from `size` in code like a loot container (bench top, legs, a vise).
# Depends on: RecipeDB, CraftingRules, CarryRules (interact range), InventoryHolder.
extends StaticBody3D

signal crafted(recipe_id: String)

@export var display_name := "Workbench"
@export var size := Vector3(1.6, 0.85, 0.9)

var _range := 2.5


func _ready() -> void:
	add_to_group("workbenches")
	_range = float(CarryRules.load_tuning().get("interact_range", 2.5))
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.3, 0.2)
	wood.roughness = 0.9
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.25, 0.25, 0.27)
	steel.metallic = 0.5
	steel.roughness = 0.6
	_part(Vector3(0, size.y - 0.04, 0), Vector3(size.x, 0.08, size.z), wood)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_part(Vector3(sx * (size.x * 0.5 - 0.06), (size.y - 0.08) * 0.5, sz * (size.z * 0.5 - 0.06)),
				Vector3(0.08, size.y - 0.08, 0.08), wood)
	_part(Vector3(0, 0.15, 0), Vector3(size.x - 0.2, 0.04, size.z - 0.2), wood)  # lower shelf
	_part(Vector3(size.x * 0.5 - 0.2, size.y + 0.08, size.z * 0.3), Vector3(0.18, 0.16, 0.14), steel)  # vise
	_part(Vector3(-size.x * 0.2, size.y + 0.03, -size.z * 0.15), Vector3(0.35, 0.05, 0.08), steel)  # tools
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = size.y * 0.5
	add_child(col)


@rpc("any_peer", "call_local", "reliable")
func request_craft(recipe_id: String) -> void:
	if not multiplayer.is_server():
		return
	var player := _sender_player()
	var recipe := RecipeDB.get_recipe(recipe_id)
	if player == null or recipe.is_empty():
		return
	var inv: InventoryHolder = player.inventory
	if not CraftingRules.can_craft(recipe, inv.count):
		return
	for item: String in recipe.needs:
		inv.host_remove(item, int(recipe.needs[item]))
	for item: String in recipe.gives:
		inv.host_add(item, int(recipe.gives[item]))
	crafted.emit(recipe_id)


func _sender_player() -> Node:
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0:
		peer = multiplayer.get_unique_id()
	for p in get_tree().get_nodes_in_group("players"):
		if p.peer_id == peer:
			if p.health.is_dead() or p.global_position.distance_to(global_position) > _range + 1.0:
				return null
			return p
	return null


func _part(pos: Vector3, part_size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = part_size
	box.material = mat
	mi.mesh = box
	mi.position = pos
	add_child(mi)
