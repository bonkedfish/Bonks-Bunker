# InventoryUI — the local player's inventory screen (D-022): category tabs, a sorted list with quantity,
# weight and value, and a carry-weight footer that turns orange/red when overweight/stuck.
# Tab or I toggles it; Esc closes. While open the mouse is free, so the player can't move or shoot.
# Use button: asks the host to use the selected item (timed, D-046). The window closes so you see the progress.
# Drop / Drop All: ask the host to drop one / the whole stack in front of you (WorldDrops, D-046).
# Builds its controls in code. Rebuilds the list only when opened or when the inventory changes.
# Group "inventory_ui". Depends on: Player (group "local_player"), InventoryHolder, ItemDB, CarryRules.
extends Control

const TABS := ["All", "Weapons", "Ammo", "Aid", "Food", "Chems", "Gear", "Junk", "Quest"]
const TAB_CATEGORY := ["", "weapon", "ammo", "aid", "food", "chem", "gear", "junk", "quest"]

var _tabs: TabBar
var _tree: Tree
var _footer: Label
var _use_button: Button
var _drop_button: Button
var _drop_all_button: Button
var _player: Node


func _ready() -> void:
	add_to_group("inventory_ui")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 440)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "INVENTORY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_tabs = TabBar.new()
	_tabs.focus_mode = Control.FOCUS_NONE
	for t in TABS:
		_tabs.add_tab(t)
	_tabs.tab_changed.connect(func(_i: int) -> void: _refresh())
	box.add_child(_tabs)
	_tree = Tree.new()
	_tree.focus_mode = Control.FOCUS_NONE
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.columns = 4
	_tree.column_titles_visible = true
	for i in 4:
		_tree.set_column_title(i, ["Item", "Qty", "Weight", "Value"][i])
		_tree.set_column_expand(i, i == 0)
		if i > 0:
			_tree.set_column_custom_minimum_width(i, 80)
	box.add_child(_tree)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	_use_button = Button.new()
	_use_button.text = "Use"
	_use_button.focus_mode = Control.FOCUS_NONE
	_use_button.disabled = true
	_use_button.pressed.connect(_on_use)
	buttons.add_child(_use_button)
	_drop_button = Button.new()
	_drop_button.text = "Drop"
	_drop_button.focus_mode = Control.FOCUS_NONE
	_drop_button.disabled = true
	_drop_button.pressed.connect(_on_drop.bind(1))
	buttons.add_child(_drop_button)
	_drop_all_button = Button.new()
	_drop_all_button.text = "Drop All"
	_drop_all_button.focus_mode = Control.FOCUS_NONE
	_drop_all_button.disabled = true
	_drop_all_button.pressed.connect(_on_drop.bind(0))
	buttons.add_child(_drop_all_button)
	_tree.item_selected.connect(_on_selected)
	_footer = Label.new()
	box.add_child(_footer)
	var hint := Label.new()
	hint.text = "Tab / I / Esc to close     H quick heal     G eat / drink"
	hint.add_theme_font_size_override("font_size", 12)
	box.add_child(hint)
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	_player = get_tree().get_first_node_in_group("local_player")
	if _player == null:
		return
	var loot := get_tree().get_first_node_in_group("loot_ui")
	if loot and loot.visible:
		loot.close()
	if not _player.inventory.changed.is_connected(_refresh):
		_player.inventory.changed.connect(_refresh)
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# Sort by category order (weapons first), then by name.
static func _item_before(a: String, b: String) -> bool:
	var da := ItemDB.get_item(a)
	var db := ItemDB.get_item(b)
	if da.category != db.category:
		return ItemDB.CATEGORIES.find(da.category) < ItemDB.CATEGORIES.find(db.category)
	return da.name < db.name


func _refresh() -> void:
	if not visible or not is_instance_valid(_player):
		return
	var category: String = TAB_CATEGORY[_tabs.current_tab]
	var inv: InventoryHolder = _player.inventory
	var ids: Array = []
	for id: String in inv.model.items:
		var def := ItemDB.get_item(id)
		if category == "" or def.get("category", "") == category:
			ids.append(id)
	ids.sort_custom(_item_before)
	_tree.clear()
	var root := _tree.create_item()
	for id: String in ids:
		var def := ItemDB.get_item(id)
		var n := inv.count(id)
		var row := _tree.create_item(root)
		row.set_text(0, def.name)
		row.set_metadata(0, id)
		row.set_text(1, "x%d" % n)
		row.set_text(2, "%.1f" % (CarryRules.item_weight(def) * n))
		row.set_text(3, "%d" % roundi(float(def.value) * n))
	_on_selected()
	var t := CarryRules.load_tuning()
	var cap := float(t.carry_capacity)
	_footer.text = "Carry weight  %.1f / %.0f" % [inv.weight, cap]
	if inv.weight >= cap * float(t.stuck_ratio):
		_footer.text += "   TOO HEAVY - barely moving"
		_footer.modulate = Color(1.0, 0.3, 0.25)
	elif inv.weight > cap:
		_footer.text += "   OVERWEIGHT - slowed, no sprint"
		_footer.modulate = Color(1.0, 0.7, 0.25)
	else:
		_footer.modulate = Color.WHITE


func _selected_id() -> String:
	var row := _tree.get_selected()
	return str(row.get_metadata(0)) if row else ""


func _on_selected() -> void:
	var id := _selected_id()
	_use_button.disabled = id == "" or SurvivalRules.use_def(ItemDB.get_item(id)).is_empty()
	_drop_button.disabled = id == ""
	_drop_all_button.disabled = id == ""


func _on_use() -> void:
	var id := _selected_id()
	if id != "" and is_instance_valid(_player):
		_player.item_use.request(id)
		close()


func _on_drop(n: int) -> void:
	var id := _selected_id()
	var drops := get_tree().get_first_node_in_group("world_drops")
	if id != "" and drops:
		drops.request_drop.rpc_id(1, id, n)
