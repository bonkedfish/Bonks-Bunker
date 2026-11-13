# QuestBookUI — the party's quest book (D-054), J to open: quests on the left (active first, main quests marked,
# then completed, then the locked story outline), the selected quest on the right: act, summary, objectives
# ([x] done, > current, later ones hidden until reached), reward. Track / Untrack (or double-click) ticks any number
# of active quests for this player (D-064): the HUD lists up to 3, the map shows a diamond for each. Active main
# quests are tracked until you untick them. Refreshes when the party's flags change. Closes with J / Esc.
# Builds its controls in code. Group "quest_book". Depends on: QuestRules, QuestDirector (group "quests"), ItemDB.
extends Control

var _picked := {}   # quest id -> true: ticked by this player
var _dropped := {}  # quest id -> true: main quests this player unticked (they're tracked by default)

var _list: Tree
var _title: Label
var _body: RichTextLabel
var _track: Button
var _quests: Node


func _ready() -> void:
	add_to_group("quest_book")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(980, 520)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var head := Label.new()
	head.text = "QUEST BOOK"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 12)
	box.add_child(split)
	_list = Tree.new()
	_list.focus_mode = Control.FOCUS_NONE
	_list.hide_root = true
	_list.custom_minimum_size = Vector2(340, 0)
	_list.item_selected.connect(_show_selected)
	_list.item_activated.connect(_track_selected)
	split.add_child(_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_title)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.focus_mode = Control.FOCUS_NONE
	right.add_child(_body)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	_track = Button.new()
	_track.text = "Track"
	_track.focus_mode = Control.FOCUS_NONE
	_track.pressed.connect(_track_selected)
	buttons.add_child(_track)
	var close_b := Button.new()
	close_b.text = "Close (J)"
	close_b.focus_mode = Control.FOCUS_NONE
	close_b.pressed.connect(close)
	buttons.add_child(close_b)
	hide()
	_quests = get_tree().get_first_node_in_group("quests")
	if _quests:
		_quests.flags_changed.connect(_refresh)


# Active quests this player tracks, in story order (HUD + map).
func tracked_quests() -> Array[String]:
	var out: Array[String] = []
	for id: String in QuestRules.order():
		if is_tracked(id):
			out.append(id)
	return out


# The first tracked quest ("" if none).
func tracked_quest() -> String:
	var t := tracked_quests()
	return t[0] if not t.is_empty() else ""


func is_tracked(id: String) -> bool:
	var defs := QuestRules.defs()
	if not defs.has(id) or QuestRules.status(defs[id], _quests.flags if _quests else {}) != QuestRules.Status.ACTIVE:
		return false
	return _picked.has(id) or (bool(defs[id].get("main", false)) and not _dropped.has(id))


func set_tracked(id: String, on: bool) -> void:
	if on:
		_picked[id] = true
		_dropped.erase(id)
	else:
		_picked.erase(id)
		_dropped[id] = true
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quest_book"):
		if visible:
			close()
		elif get_tree().get_first_node_in_group("local_player") != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			open()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	for group in ["inventory_ui", "loot_ui", "crafting_ui", "world_map_ui"]:
		var other := get_tree().get_first_node_in_group(group)
		if other and other.visible:
			other.close()
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	if not visible:
		return
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh() -> void:
	if not visible:
		return
	var flags: Dictionary = _quests.flags if _quests else {}
	var defs := QuestRules.defs()
	var keep := _selected_id()
	if keep == "":
		keep = tracked_quest()
	var tracked := tracked_quests()
	_list.clear()
	var root := _list.create_item()
	var groups := [["ACTIVE", QuestRules.Status.ACTIVE], ["COMPLETED", QuestRules.Status.DONE], ["THE STORY AHEAD", QuestRules.Status.LOCKED]]
	for g: Array in groups:
		var header: TreeItem = null
		for id: String in QuestRules.order():
			var q: Dictionary = defs[id]
			if QuestRules.status(q, flags) != g[1]:
				continue
			if g[1] == QuestRules.Status.LOCKED and not q.has("locked_note"):
				continue  # side quests you haven't found stay hidden
			if header == null:
				header = _list.create_item(root)
				header.set_text(0, str(g[0]))
				header.set_selectable(0, false)
				header.set_custom_color(0, Color(0.7, 0.65, 0.5))
			var row := _list.create_item(header)
			var tick := ("[x] " if id in tracked else "[  ] ") if g[1] == QuestRules.Status.ACTIVE else ""
			row.set_text(0, tick + ("* " if bool(q.get("main", false)) else "") + str(q.name))
			row.set_metadata(0, id)
			if g[1] != QuestRules.Status.ACTIVE:
				row.set_custom_color(0, Color(0.6, 0.6, 0.6))
			if id == keep:
				row.select(0)
	_show_selected()


func _show_selected() -> void:
	var id := _selected_id()
	var defs := QuestRules.defs()
	if id == "" or not defs.has(id):
		_title.text = "No quest selected"
		_body.text = ""
		_track.disabled = true
		return
	var flags: Dictionary = _quests.flags if _quests else {}
	var q: Dictionary = defs[id]
	var st := QuestRules.status(q, flags)
	_title.text = str(q.name)
	var t := "[color=#b0a070]%s  -  Act %d[/color]\n\n%s\n" % ["MAIN QUEST" if bool(q.get("main", false)) else "SIDE QUEST",
		int(q.get("act", 1)), str(q.get("summary", ""))]
	if q.has("locked_note"):
		t += "\n[color=#909090]%s[/color]\n" % str(q.locked_note)
	else:
		t += "\n[color=#b0a070]OBJECTIVES[/color]\n"
		var cur := QuestRules.current(q, flags)
		var ordered := bool(q.get("ordered", true))
		for i in QuestRules.visible_count(q, flags):
			var o: Dictionary = q.objectives[i]
			var text := str(o.text)
			if int(o.get("count", 1)) > 1:
				text += "  (%d / %d)" % [mini(int(flags.get(str(o.flag), 0)), int(o.count)), int(o.count)]
			if QuestRules.objective_done(o, flags):
				t += "[color=#70a070]  [x]  %s[/color]\n" % text
			elif i == cur or not ordered:
				t += "[color=#ffd060]  >    %s[/color]\n" % text
			else:
				t += "  [ ]  %s\n" % text
		var reward: Dictionary = q.get("reward", {})
		if not reward.is_empty():
			var parts := PackedStringArray()
			for item: String in reward:
				parts.append("%d x %s" % [int(reward[item]), ItemDB.get_item(item).get("name", item)])
			t += "\n[color=#b0a070]REWARD (each player)[/color]\n  %s\n" % ", ".join(parts)
		if st == QuestRules.Status.DONE:
			t += "\n[color=#70a070]COMPLETED[/color]\n"
	_body.text = t
	_track.disabled = st != QuestRules.Status.ACTIVE
	_track.text = "Untrack" if is_tracked(id) else "Track"


func _track_selected() -> void:
	var id := _selected_id()
	if id != "":
		set_tracked(id, not is_tracked(id))


func _selected_id() -> String:
	var row := _list.get_selected()
	return str(row.get_metadata(0)) if row and row.get_metadata(0) != null else ""
