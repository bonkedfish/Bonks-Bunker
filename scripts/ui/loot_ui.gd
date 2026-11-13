# LootUI — window for a container the local player opened. Shows what's inside (updated live when a
# teammate takes something), Take 1 (selected item, or double-click), Take Stack (all of the selected item) and
# Take All (everything, or R) (D-065). Closes with
# E / Esc / Tab, or automatically if you die or walk out of reach. Requests go to the host, which decides.
# Builds its controls in code. Group "loot_ui". Depends on: LootContainer, ItemDB, CarryRules, Player.
extends Control

var _title: Label
var _tree: Tree
var _empty: Label
var _container: Node
var _range := 2.5


func _ready() -> void:
	add_to_group("loot_ui")
	_range = CarryRules.load_tuning().get("interact_range", 2.5)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 360)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_tree = Tree.new()
	_tree.focus_mode = Control.FOCUS_NONE
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.columns = 3
	_tree.column_titles_visible = true
	for i in 3:
		_tree.set_column_title(i, ["Item", "Qty", "Weight"][i])
		_tree.set_column_expand(i, i == 0)
		if i > 0:
			_tree.set_column_custom_minimum_width(i, 80)
	_tree.item_activated.connect(_take_one)
	box.add_child(_tree)
	_empty = Label.new()
	_empty.text = "(empty)"
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_empty)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	for spec in [["Take 1", _take_one], ["Take Stack", _take_selected], ["Take All (R)", _take_all], ["Close (E)", close]]:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(spec[1])
		buttons.add_child(b)
	hide()


# Called by the container's host RPC, both when first opened and on every change.
func show_container(container: Node, items: Dictionary) -> void:
	_container = container
	_title.text = str(container.display_name).to_upper()
	var keep: Variant = _tree.get_selected().get_metadata(0) if _tree.get_selected() else null  # stays selected for repeated Take 1
	_tree.clear()
	var root := _tree.create_item()
	var ids := items.keys()
	ids.sort()
	for id: String in ids:
		var def := ItemDB.get_item(id)
		var n := int(items[id])
		var row := _tree.create_item(root)
		row.set_text(0, def.get("name", id))
		row.set_text(1, "x%d" % n)
		row.set_text(2, "%.1f" % (CarryRules.item_weight(def) * n))
		row.set_metadata(0, id)
		if keep != null and id == str(keep):
			row.select(0)
	if _tree.get_selected() == null and root.get_first_child():
		root.get_first_child().select(0)
	_empty.visible = ids.is_empty()
	if not visible:
		var inv := get_tree().get_first_node_in_group("inventory_ui")
		if inv and inv.visible:
			inv.hide()
		show()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not visible:
		return
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if is_instance_valid(_container):
		_container.request_close.rpc_id(1)
	_container = null


func _take_selected() -> void:
	var row := _tree.get_selected()
	if row and is_instance_valid(_container):
		_container.request_take.rpc_id(1, str(row.get_metadata(0)), 0)


func _take_one() -> void:
	var row := _tree.get_selected()
	if row and is_instance_valid(_container):
		_container.request_take.rpc_id(1, str(row.get_metadata(0)), 1)


func _take_all() -> void:
	if is_instance_valid(_container):
		_container.request_take_all.rpc_id(1)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact") or event.is_action_pressed("inventory"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reload"):
		_take_all()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible:
		return
	var player := get_tree().get_first_node_in_group("local_player")
	if player == null or not is_instance_valid(_container) or player.health.is_dead() \
			or player.global_position.distance_to(_container.global_position) > _range + 0.5:
		close()
