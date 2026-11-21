# CharacterCreator — "Your survivor" (D-096), opened by the host on the owner's screen every time they load into a
# world (Player.ask_name), filled in with the character's name and look. Left: a turntable preview of the look
# (its own small 3D world in a SubViewport, idle animation, drag to spin). Right: the name, and < > pickers for
# body, skin, hair, hair colour, beard, shirt, pants, shoes, hat, extra and accent colour, Randomize and Play.
# Play (or Enter in the name field) sends both to the host (Player.submit_look), which cleans and saves them. A
# blank name keeps it open. Esc can't skip it. Builds its controls in code; added under $UI by Main as "Creator".
# Group "name_prompt" (tests call submit("Name")). Depends on: AppearanceRules, CharacterAnimator, NameTag.
extends Control

const NameTag := preload("res://scripts/player/name_tag.gd")
const ROWS := [["body", "Body"], ["skin", "Skin"], ["hair", "Hair"], ["hair_color", "Hair colour"], ["beard", "Beard"],
	["shirt", "Shirt"], ["pants", "Pants"], ["shoes", "Shoes"], ["hat", "Hat"], ["extra", "Extra"], ["accent", "Hat / extra colour"]]
const SPIN_SPEED := 0.6

var look: Dictionary = {}

var _player: Node
var _field: LineEdit
var _values: Dictionary = {}  # key -> Label
var _swatches: Dictionary = {}  # key -> ColorRect
var _viewport: SubViewport
var _pivot: Node3D
var _preview: CharacterAnimator
var _dragging := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("name_prompt")
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rng.randomize()
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.03, 0.04, 0.88)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	center.add_child(row)
	row.add_child(_build_preview())
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 0)
	row.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var title := Label.new()
	title.text = "YOUR SURVIVOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45))
	box.add_child(title)
	var note := Label.new()
	note.text = "Saved with this world. Other players see your look and the name over your head."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
	box.add_child(note)
	_field = LineEdit.new()
	_field.placeholder_text = "Name"
	_field.max_length = int(NameTag.load_tuning().get("max_length", 20))
	_field.custom_minimum_size = Vector2(0, 34)
	_field.text_submitted.connect(func(_t: String) -> void: submit())
	box.add_child(_field)
	for r: Array in ROWS:
		box.add_child(_picker(str(r[0]), str(r[1])))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var rand := Button.new()
	rand.text = "Randomize"
	rand.custom_minimum_size = Vector2(0, 36)
	rand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rand.pressed.connect(func() -> void: _set_look(AppearanceRules.random_look(_rng)))
	buttons.add_child(rand)
	var play := Button.new()
	play.text = "Play"
	play.custom_minimum_size = Vector2(0, 36)
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.pressed.connect(submit)
	buttons.add_child(play)
	hide()


func _build_preview() -> Control:
	var frame := SubViewportContainer.new()
	frame.custom_minimum_size = Vector2(340, 520)
	frame.stretch = true
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.gui_input.connect(_on_preview_input)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	frame.add_child(_viewport)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	_viewport.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.2
	_viewport.add_child(sun)
	var cam := Camera3D.new()
	var eye := Vector3(0, 1.05, 3.1)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 0.95, 0) - eye), eye)  # look_at needs the tree; this doesn't
	cam.fov = 38.0
	_viewport.add_child(cam)
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	_preview = CharacterAnimator.new()
	_pivot.add_child(_preview)
	return frame


func _picker(key: String, title: String) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	var name_label := Label.new()
	name_label.text = title
	name_label.custom_minimum_size = Vector2(140, 0)
	line.add_child(name_label)
	var left := Button.new()
	left.text = "<"
	left.custom_minimum_size = Vector2(32, 28)
	left.pressed.connect(func() -> void: _step(key, -1))
	line.add_child(left)
	if AppearanceRules.COLOR_KEYS.has(key):
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(28, 24)
		line.add_child(sw)
		_swatches[key] = sw
	var value := Label.new()
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(value)
	_values[key] = value
	var right := Button.new()
	right.text = ">"
	right.custom_minimum_size = Vector2(32, 28)
	right.pressed.connect(func() -> void: _step(key, 1))
	line.add_child(right)
	return line


func open(player: Node, char_name := "", start_look := {}) -> void:
	_player = player
	_field.text = char_name
	_set_look(AppearanceRules.sanitize(start_look) if not start_look.is_empty() else AppearanceRules.random_look(_rng))
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_field.grab_focus()


# Sends the name + look (tests call this with a name). A blank name keeps the creator open.
func submit(typed := "") -> void:
	var t := (typed if typed != "" else _field.text).strip_edges()
	if t == "" or not is_instance_valid(_player):
		return
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_player.submit_look.rpc_id(1, t, look)


func _step(key: String, dir: int) -> void:
	var opts := AppearanceRules.choices(key)
	var i := opts.find(look[key])
	var next := look.duplicate()
	next[key] = opts[posmod(i + dir, opts.size())]
	if key == "body" and next.body != "male":
		next.beard = false
	_set_look(next)


func _set_look(new_look: Dictionary) -> void:
	look = AppearanceRules.sanitize(new_look)
	for key: String in _values:
		(_values[key] as Label).text = AppearanceRules.label(key, look[key]) if not AppearanceRules.COLOR_KEYS.has(key) else ""
		if _swatches.has(key):
			(_swatches[key] as ColorRect).color = AppearanceRules.color_of(key, int(look[key]))
	_values.beard.get_parent().visible = look.body == "male"
	_preview.set_model(AppearanceRules.model_of(look), false, AppearanceRules.dress(look))


func _process(delta: float) -> void:
	if not visible:
		return
	if not _dragging:
		_pivot.rotation.y += SPIN_SPEED * delta
	_preview.update(delta, false, false, 100.0, false, false)


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (event as InputEventMouseButton).pressed
	elif event is InputEventMouseMotion and _dragging:
		_pivot.rotation.y += (event as InputEventMouseMotion).relative.x * 0.01


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()  # no pause menu over the creator
