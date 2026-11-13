# CraftingUI — window for the workbench the local player is using (D-046): every recipe with what it makes and
# what it needs ("have / need", short items in red), Craft for the selected one (or double-click). Craft is only
# enabled when you hold everything; the host checks again. Updates live as the inventory changes. Closes with
# E / Esc / Tab, or if you die or walk out of reach. Builds its controls in code. Group "crafting_ui".
# Depends on: RecipeDB, CraftingRules, ItemDB, Workbench, Player (group "local_player").
extends Control

var _tree: Tree
var _craft: Button
var _bench: Node
var _player: Node
var _range := 2.5


func _ready() -> void:
	add_to_group("crafting_ui")
	_range = float(CarryRules.load_tuning().get("interact_range", 2.5))
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(780, 380)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "WORKBENCH"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_tree = Tree.new()
	_tree.focus_mode = Control.FOCUS_NONE
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.columns = 3
	_tree.column_titles_visible = true
	for i in 3:
		_tree.set_column_title(i, ["Recipe", "Makes", "Needs (have / need)"][i])
		_tree.set_column_expand(i, true)
	_tree.item_selected.connect(_update_button)
	_tree.item_activated.connect(_craft_selected)
	box.add_child(_tree)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	_craft = Button.new()
	_craft.text = "Craft"
	_craft.focus_mode = Control.FOCUS_NONE
	_craft.disabled = true
	_craft.pressed.connect(_craft_selected)
	buttons.add_child(_craft)
	var close_b := Button.new()
	close_b.text = "Close (E)"
	close_b.focus_mode = Control.FOCUS_NONE
	close_b.pressed.connect(close)
	buttons.add_child(close_b)
	hide()


func open(bench: Node) -> void:
	_player = get_tree().get_first_node_in_group("local_player")
	if _player == null:
		return
	_bench = bench
	for group in ["inventory_ui", "loot_ui"]:
		var other := get_tree().get_first_node_in_group(group)
		if other and other.visible:
			other.close()
	if not _player.inventory.changed.is_connected(_refresh):
		_player.inventory.changed.connect(_refresh)
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	if not visible:
		return
	hide()
	_bench = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh() -> void:
	if not visible or not is_instance_valid(_player):
		return
	var keep := _selected_id()
	var inv: InventoryHolder = _player.inventory
	_tree.clear()
	var root := _tree.create_item()
	for id: String in RecipeDB.ids():
		var r := RecipeDB.get_recipe(id)
		var row := _tree.create_item(root)
		row.set_text(0, str(r.name))
		row.set_metadata(0, id)
		row.set_text(1, _stacks(r.gives))
		var needs := PackedStringArray()
		var short := CraftingRules.missing(r, inv.count)
		for item: String in r.needs:
			needs.append("%s %d/%d" % [ItemDB.get_item(item).get("name", item), inv.count(item), int(r.needs[item])])
		row.set_text(2, ", ".join(needs))
		if not short.is_empty():
			row.set_custom_color(0, Color(0.65, 0.65, 0.65))
			row.set_custom_color(2, Color(1.0, 0.45, 0.4))
		if id == keep:
			row.select(0)
	_update_button()


func _stacks(stacks: Dictionary) -> String:
	var out := PackedStringArray()
	for item: String in stacks:
		out.append("%dx %s" % [int(stacks[item]), ItemDB.get_item(item).get("name", item)])
	return ", ".join(out)


func _selected_id() -> String:
	var row: TreeItem = _tree.get_selected() if _tree else null
	return str(row.get_metadata(0)) if row else ""


func _update_button() -> void:
	var id := _selected_id()
	_craft.disabled = id == "" or not is_instance_valid(_player) \
		or not CraftingRules.can_craft(RecipeDB.get_recipe(id), _player.inventory.count)


func _craft_selected() -> void:
	var id := _selected_id()
	if id != "" and is_instance_valid(_bench) and not _craft.disabled:
		_bench.request_craft.rpc_id(1, id)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact") or event.is_action_pressed("inventory"):
		close()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible:
		return
	if not is_instance_valid(_player) or not is_instance_valid(_bench) or _player.health.is_dead() \
			or _player.global_position.distance_to(_bench.global_position) > _range + 1.0:
		close()
