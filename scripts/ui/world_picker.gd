# WorldPicker — the host's world choice in the main menu (D-037): a list of saved worlds (newest first,
# with when they were last saved) plus "+ New world", which shows a name field. Join ignores it.
# "Delete" removes the selected saved world after a confirmation (D-063).
# Builds its controls in code. Depends on: SaveStore.
extends VBoxContainer

const NEW_WORLD := "+ New world"

var _list: OptionButton
var _name: LineEdit
var _delete: Button
var _confirm: ConfirmationDialog
var _worlds: Array[Dictionary] = []


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.text = "World"
	add_child(label)
	var row := HBoxContainer.new()
	add_child(row)
	_list = OptionButton.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_selected)
	row.add_child(_list)
	_delete = Button.new()
	_delete.text = "Delete"
	_delete.pressed.connect(_ask_delete)
	row.add_child(_delete)
	_confirm = ConfirmationDialog.new()
	_confirm.ok_button_text = "Delete forever"
	_confirm.confirmed.connect(_do_delete)
	add_child(_confirm)
	_name = LineEdit.new()
	_name.placeholder_text = "New world name"
	_name.max_length = 32
	add_child(_name)
	refresh()


func refresh() -> void:
	_worlds = SaveStore.list_worlds()
	_list.clear()
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	for w in _worlds:
		var when := Time.get_datetime_string_from_unix_time(int(w.saved) + bias, true)
		_list.add_item("%s   (%s)" % [w.name, when])
	_list.add_item(NEW_WORLD)
	_list.select(0)
	_on_selected(0)


# "" means a new world.
func selected_slug() -> String:
	var i := _list.selected
	return str(_worlds[i].slug) if i >= 0 and i < _worlds.size() else ""


func new_world_name() -> String:
	var n := _name.text.strip_edges()
	return n if n != "" else "Kearney"


# For tests: pick "+ New world" with this name.
func choose_new(world_name: String) -> void:
	_list.select(_worlds.size())
	_on_selected(_worlds.size())
	_name.text = world_name


func _on_selected(index: int) -> void:
	_name.visible = index >= _worlds.size()
	_delete.disabled = index >= _worlds.size()


func _ask_delete() -> void:
	var i := _list.selected
	if i < 0 or i >= _worlds.size():
		return
	_confirm.dialog_text = "Delete the world \"%s\"?\nIts save file is removed and can't be brought back." % _worlds[i].name
	_confirm.popup_centered()


func _do_delete() -> void:
	var slug := selected_slug()
	if slug != "":
		SaveStore.delete(slug)
	refresh()
