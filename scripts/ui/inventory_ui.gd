# InventoryUI — the local player's inventory screen (D-022): category tabs, a sorted list with quantity,
# weight and value, and a carry-weight footer that turns orange/red when overweight/stuck.
# Tab or I toggles it; Esc closes. While open the mouse is free, so the player can't move or shoot.
# Use button: asks the host to use the selected item (timed, D-046). The window closes so you see the progress.
# Drop / Drop All: ask the host to drop one / the whole stack in front of you (WorldDrops, D-046).
# Gear (D-087): every weapon / armor piece is its own row, named in its rarity colour, tagged with the slot it's
# equipped in ([1] [2] [3] gun1 / gun2 / melee, [Head] [Chest] [Legs]); a stats line shows the selected piece
# (damage, rate, magazine, condition, mods, perk / damage resistance). Slot 1 / Slot 2 put a gun in that slot,
# Equip puts melee or armor on, Unequip takes it off (InventoryHolder.request_equip / request_unequip). The footer
# shows your total armor resistance.
# Builds its controls in code. Rebuilds the list only when opened or when the inventory changes.
# Group "inventory_ui". Depends on: Player (group "local_player"), InventoryHolder, ItemDB, CarryRules, GearRules,
# WorldDrops (group "world_drops").
extends Control

const TABS := ["All", "Weapons", "Armor", "Mods", "Ammo", "Aid", "Food", "Booze", "Chems", "Gear", "Junk", "Quest"]
const TAB_CATEGORY := ["", "weapon", "armor", "mod", "ammo", "aid", "food", "booze", "chem", "gear", "junk", "quest"]
const SLOT_TAGS := {"gun1": "[1]", "gun2": "[2]", "melee": "[3]", "head": "[Head]", "chest": "[Chest]", "legs": "[Legs]"}

var _tabs: TabBar
var _tree: Tree
var _footer: Label
var _stats: Label
var _use_button: Button
var _drop_button: Button
var _drop_all_button: Button
var _slot1_button: Button
var _slot2_button: Button
var _equip_button: Button
var _unequip_button: Button
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
	panel.custom_minimum_size = Vector2(640, 500)
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
	_stats = Label.new()
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats.add_theme_font_size_override("font_size", 13)
	_stats.custom_minimum_size = Vector2(0, 36)
	box.add_child(_stats)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	_use_button = _button(buttons, "Use", _on_use)
	_slot1_button = _button(buttons, "Slot 1", _on_equip.bind("gun1"))
	_slot2_button = _button(buttons, "Slot 2", _on_equip.bind("gun2"))
	_equip_button = _button(buttons, "Equip", _on_equip.bind(""))
	_unequip_button = _button(buttons, "Unequip", _on_unequip)
	_drop_button = _button(buttons, "Drop", _on_drop.bind(1))
	_drop_all_button = _button(buttons, "Drop All", _on_drop.bind(0))
	_tree.item_selected.connect(_on_selected)
	_footer = Label.new()
	box.add_child(_footer)
	var hint := Label.new()
	hint.text = "Tab / I / Esc to close     H quick heal     G eat / drink     1 / 2 / 3 weapons"
	hint.add_theme_font_size_override("font_size", 12)
	box.add_child(hint)
	hide()


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = true
	b.pressed.connect(action)
	parent.add_child(b)
	return b


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
	var keep := _selected_key()
	_tree.clear()
	var root := _tree.create_item()
	# Gear first: equipped pieces, then the rest, each by name.
	var gear := inv.gear_list().filter(func(g: Dictionary) -> bool:
		return category == "" or ItemDB.get_item(str(g.id)).get("category", "") == category)
	var slot_of := {}
	for slot: String in inv.model.equip:
		slot_of[int(inv.model.equip[slot])] = slot
	gear.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ea := slot_of.has(int(a.uid))
		var eb := slot_of.has(int(b.uid))
		if ea != eb:
			return ea
		if ea:
			return GearRules.SLOTS.find(slot_of[int(a.uid)]) < GearRules.SLOTS.find(slot_of[int(b.uid)])
		return GearRules.display_name(a) < GearRules.display_name(b))
	for g: Dictionary in gear:
		var def := ItemDB.get_item(str(g.id))
		var row := _tree.create_item(root)
		var tag := str(SLOT_TAGS.get(slot_of.get(int(g.uid), ""), ""))
		row.set_text(0, ("%s  %s" % [tag, GearRules.display_name(g)]) if tag != "" else GearRules.display_name(g))
		row.set_custom_color(0, GearRules.rarity_color(str(g.rarity)))
		row.set_metadata(0, "g:%d" % int(g.uid))
		row.set_text(1, "%d%%" % roundi(float(g.cond) * 100.0))
		row.set_text(2, "%.1f" % GearRules.weight(g))
		row.set_text(3, "%d" % roundi(float(def.value)))
		if "g:%d" % int(g.uid) == keep:
			row.select(0)
	var ids: Array = []
	for id: String in inv.model.items:
		var def := ItemDB.get_item(id)
		if category == "" or def.get("category", "") == category:
			ids.append(id)
	ids.sort_custom(_item_before)
	for id: String in ids:
		var def := ItemDB.get_item(id)
		var n := inv.count(id)
		var row := _tree.create_item(root)
		row.set_text(0, def.name)
		row.set_metadata(0, id)
		row.set_text(1, "x%d" % n)
		row.set_text(2, "%.1f" % (CarryRules.item_weight(def) * n))
		row.set_text(3, "%d" % roundi(float(def.value) * n))
		if id == keep:
			row.select(0)
	_on_selected()
	var t := CarryRules.load_tuning()
	var cap := float(t.carry_capacity)
	_footer.text = "Carry weight  %.1f / %.0f      Armor %d%%" % [inv.weight, cap, roundi(_armor_resist(inv) * 100.0)]
	if inv.weight >= cap * float(t.stuck_ratio):
		_footer.text += "   TOO HEAVY - barely moving"
		_footer.modulate = Color(1.0, 0.3, 0.25)
	elif inv.weight > cap:
		_footer.text += "   OVERWEIGHT - slowed, no sprint"
		_footer.modulate = Color(1.0, 0.7, 0.25)
	else:
		_footer.modulate = Color.WHITE


func _armor_resist(inv: InventoryHolder) -> float:
	var pieces := []
	for s: String in GearRules.ARMOR_SLOTS:
		var g: Dictionary = inv.equipped(s)
		if not g.is_empty():
			pieces.append(g)
	return GearRules.total_resist(pieces)


func _selected_key() -> String:
	var row := _tree.get_selected()
	return str(row.get_metadata(0)) if row else ""


func _selected_gear() -> Dictionary:
	var key := _selected_key()
	if not key.begins_with("g:") or not is_instance_valid(_player):
		return {}
	return _player.inventory.get_gear(int(key.trim_prefix("g:")))


func _equipped_slot(uid: int) -> String:
	var equip: Dictionary = _player.inventory.model.equip
	for slot: String in equip:
		if int(equip[slot]) == uid:
			return slot
	return ""


func _on_selected() -> void:
	var key := _selected_key()
	var g := _selected_gear()
	var is_gear := not g.is_empty()
	var id := "" if is_gear else key
	_use_button.disabled = id == "" or SurvivalRules.use_def(ItemDB.get_item(id)).is_empty()
	_drop_button.disabled = key == ""
	_drop_all_button.disabled = id == ""
	var kind := GearRules.kind_of(str(g.id)) if is_gear else ""
	var slot := _equipped_slot(int(g.uid)) if is_gear else ""
	_slot1_button.visible = kind == "gun"
	_slot2_button.visible = kind == "gun"
	_slot1_button.disabled = slot == "gun1"
	_slot2_button.disabled = slot == "gun2"
	_equip_button.visible = is_gear and kind != "gun"
	_equip_button.disabled = slot != ""
	_unequip_button.visible = is_gear
	_unequip_button.disabled = slot == ""
	_stats.text = _describe(g) if is_gear else ""


# One line about a gear instance.
static func _describe(g: Dictionary) -> String:
	var parts: Array[String] = []
	var id := str(g.id)
	if GearRules.is_armor(id):
		parts.append("Blocks %d%% of damage" % roundi(GearRules.armor_dr(g) * 100.0))
	else:
		var w := GearRules.weapon_stats(g)
		var kind := str(w.get("kind", ""))
		if kind == "gun":
			var pellets := int(w.get("pellets", 1.0))
			parts.append("Damage %d%s" % [roundi(float(w.damage)), (" x%d" % pellets) if pellets > 1 else ""])
			parts.append("%.1f shots/s%s" % [1.0 / float(w.fire_interval), " auto" if bool(w.get("auto", false)) else ""])
			parts.append("Mag %d (%s)" % [int(w.mag_size), ItemDB.get_item(str(w.ammo_item)).get("name", w.ammo_item)])
			if float(w.get("zoom", 1.0)) > 1.0:
				parts.append("Zoom %.1fx (right mouse)" % float(w.zoom))
		elif kind == "thrown":
			parts.append("Damage %d, comes back" % roundi(float(w.damage)))
		else:
			parts.append("Damage %d, %.1f swings/s" % [roundi(float(w.damage)), 1.0 / float(w.swing_interval)])
	parts.append("Condition %d%%" % roundi(float(g.cond) * 100.0))
	var mods: Array[String] = []
	for m: String in g.get("mods", []):
		mods.append(str(ItemDB.get_item(m).get("name", m)))
	if not mods.is_empty():
		parts.append("Mods: " + ", ".join(mods))
	return "   ".join(parts)


func _on_use() -> void:
	var id := _selected_key()
	if id != "" and not id.begins_with("g:") and is_instance_valid(_player):
		_player.item_use.request(id)
		close()


func _on_equip(slot: String) -> void:
	var g := _selected_gear()
	if g.is_empty():
		return
	if slot == "":
		var slots := GearRules.slots_for(str(g.id))
		if slots.is_empty():
			return
		slot = slots[0]
	_player.inventory.request_equip.rpc_id(1, int(g.uid), slot)


func _on_unequip() -> void:
	var g := _selected_gear()
	var slot := _equipped_slot(int(g.get("uid", 0))) if not g.is_empty() else ""
	if slot != "":
		_player.inventory.request_unequip.rpc_id(1, slot)


func _on_drop(n: int) -> void:
	var key := _selected_key()
	var drops := get_tree().get_first_node_in_group("world_drops")
	if key == "" or drops == null:
		return
	if key.begins_with("g:"):
		drops.request_drop_gear.rpc_id(1, int(key.trim_prefix("g:")))
	else:
		drops.request_drop.rpc_id(1, key, n)
