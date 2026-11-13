# SettingsMenu — opened from the start screen (button or Esc) or the pause menu (D-068); Esc or Back closes it (D-038).
# Graphics: Auto (shows what it picked) / Low / Medium / High, applied at once and remembered per PC.
# Sound effects / Ambience volume sliders (D-077): applied while dragging, saved by Sfx when the panel closes.
# Doesn't pause (co-op). Leaves Esc alone while the inventory, a loot window or a dialogue choice is open.
# Builds its controls in code. Group "settings_menu". Depends on: Graphics autoload, groups
# "inventory_ui", "loot_ui", "subtitles"; Main's menu ($UI/Menu, read through the parent); Sfx autoload.
extends Control

const CHOICES := ["auto", "low", "medium", "high"]

var _graphics: OptionButton
var _gpu: Label
var _sfx: HSlider
var _amb: HSlider


func _ready() -> void:
	add_to_group("settings_menu")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var label := Label.new()
	label.text = "Graphics quality"
	box.add_child(label)
	_graphics = OptionButton.new()
	_graphics.item_selected.connect(_on_graphics_selected)
	box.add_child(_graphics)
	_gpu = Label.new()
	_gpu.add_theme_font_size_override("font_size", 12)
	_gpu.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_gpu)
	_sfx = _volume_slider(box, "Sound effects", "SFX")
	_amb = _volume_slider(box, "Ambience", "Ambience")
	var resume := Button.new()
	resume.text = "Back"
	resume.pressed.connect(close)
	box.add_child(resume)
	Graphics.tier_changed.connect(func(_t: String) -> void: _refresh())
	_refresh()
	hide()


func open() -> void:
	_refresh()
	_sfx.set_value_no_signal(Sfx.get_volume("SFX"))
	_amb.set_value_no_signal(Sfx.get_volume("Ambience"))
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	hide()
	Sfx.save_volumes()
	var menu: Control = get_parent().get_node_or_null("Menu")
	var pause := get_tree().get_first_node_in_group("pause_menu") as Control
	if (menu == null or not menu.visible) and not (pause and pause.visible):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh() -> void:
	_graphics.clear()
	_graphics.add_item("Auto (%s)" % Graphics.auto_tier().capitalize())
	for t in ["Low", "Medium", "High"]:
		_graphics.add_item(t)
	_graphics.select(maxi(CHOICES.find(Graphics.choice), 0))
	_gpu.text = "GPU: %s   now: %s" % [Graphics.adapter_name, Graphics.tier.capitalize()]


func _volume_slider(box: VBoxContainer, text: String, bus: String) -> HSlider:
	var label := Label.new()
	label.text = text
	box.add_child(label)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = Sfx.get_volume(bus)
	s.value_changed.connect(func(v: float) -> void: Sfx.set_volume(bus, v))
	box.add_child(s)
	return s


func _on_graphics_selected(index: int) -> void:
	Graphics.set_choice(CHOICES[index])


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if visible:
		close()
		get_viewport().set_input_as_handled()
		return
	var menu: Control = get_parent().get_node_or_null("Menu")
	if menu == null or not menu.visible or _other_ui_wants_esc():
		return  # in game, Esc belongs to the pause menu
	open()
	get_viewport().set_input_as_handled()


func _other_ui_wants_esc() -> bool:
	for group in ["inventory_ui", "loot_ui"]:
		var ui := get_tree().get_first_node_in_group(group)
		if ui and ui.visible:
			return true
	var subs := get_tree().get_first_node_in_group("subtitles")
	return subs != null and subs.choosing
