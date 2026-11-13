# WorldMapUI — full-screen map on M (D-048): the pipeline's map picture (tools/map_import/build_world_map) with
# landmark labels, an arrow for you, dots for teammates and Bonk, and a diamond on the tracked quest objective. Mouse wheel zooms about the cursor, left-drag
# pans; opens centred on you. M / Esc / Tab close. Loads the texture the first time it opens. Markers redraw
# 10x a second while open; nothing runs while closed. Group "world_map_ui".
# Depends on: DataLoader, world/generated/map/world_map.json (+ its texture), Player (group "players", "local_player"),
# Bonk (group "bonk").
extends Control

const META_PATH := "res://world/generated/map/world_map.json"
const ZOOM_MIN := 0.15
const ZOOM_MAX := 4.0
const REDRAW_SECONDS := 0.1

var _meta: Dictionary = {}
var _tex: Texture2D
var _area := Rect2()
var _px_per_m := 0.5
var _zoom := 1.0              # screen pixels per map pixel
var _offset := Vector2.ZERO    # screen position of map pixel (0, 0)
var _dragging := false
var _redraw := 0.0
var _font: Font


func _ready() -> void:
	add_to_group("world_map_ui")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("world_map"):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("inventory")):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	var me := get_tree().get_first_node_in_group("local_player")
	if me == null or not _load():
		return
	for group in ["inventory_ui", "loot_ui", "crafting_ui", "quest_book"]:
		var other := get_tree().get_first_node_in_group(group)
		if other and other.visible:
			other.close()
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_zoom = 1.0
	_offset = size * 0.5 - _to_px(me.global_position) * _zoom
	queue_redraw()


func close() -> void:
	if not visible:
		return
	hide()
	_dragging = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var z := clampf(_zoom * (1.2 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2), ZOOM_MIN, ZOOM_MAX)
		_offset = mb.position - (mb.position - _offset) * (z / _zoom)
		_zoom = z
		queue_redraw()
	elif mb and mb.button_index == MOUSE_BUTTON_LEFT:
		_dragging = mb.pressed
	var mm := event as InputEventMouseMotion
	if mm and _dragging:
		_offset += mm.relative
		queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_redraw -= delta
	if _redraw <= 0.0:
		_redraw = REDRAW_SECONDS
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.07, 0.05, 0.92))
	if _tex == null:
		return
	draw_texture_rect(_tex, Rect2(_offset, Vector2(_tex.get_size()) * _zoom), false)
	for l: Dictionary in _meta.get("labels", []):
		var major: bool = str(l.size) == "major"
		var poi: bool = str(l.size) == "poi"  # points of interest (the downtown bars, D-065): red marker, shown sooner
		if not major and _zoom < (0.3 if poi else 0.5):
			continue
		var p := _screen(Vector3(float(l.x), 0.0, float(l.z)))
		var fs := 20 if major else 14
		var w := _font.get_string_size(str(l.name), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := p + Vector2(-w * 0.5, fs + 6.0 if bool(l.get("below", false)) else -8.0)
		draw_string_outline(_font, at, str(l.name), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.85))
		draw_string(_font, at, str(l.name), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(1.0, 0.92, 0.7) if major else Color(1.0, 0.5, 0.4) if poi else Color(0.9, 0.86, 0.75))
		draw_circle(p, 5.0 if poi else 3.0, Color(0.9, 0.25, 0.15) if poi else Color(1.0, 0.92, 0.7))
	var quests := get_tree().get_first_node_in_group("quests")
	var book := get_tree().get_first_node_in_group("quest_book")
	for tq: String in (book.tracked_quests() if quests and book else []):  # a diamond per tracked quest (D-064)
		var q: Dictionary = QuestRules.defs()[tq]
		var qi := QuestRules.current(q, quests.flags)
		var qp: Vector3 = quests.objective_position(q.objectives[qi]) if qi >= 0 else Vector3.INF
		if qp != Vector3.INF:
			var c := _screen(qp)
			var d := 11.0
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d - 2), c + Vector2(d + 2, 0), c + Vector2(0, d + 2), c + Vector2(-d - 2, 0)]), Color(0, 0, 0))
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]), Color(1.0, 0.8, 0.2))
			draw_string_outline(_font, c + Vector2(16, 5), str(q.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.85))
			draw_string(_font, c + Vector2(16, 5), str(q.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.8, 0.2))
	var bonk := get_tree().get_first_node_in_group("bonk") as Node3D
	if bonk:
		_dot(bonk.global_position, Color(1.0, 0.55, 0.15), "Bonk")
	var me := get_tree().get_first_node_in_group("local_player") as Node3D
	var n := 2
	for p in get_tree().get_nodes_in_group("players"):
		if p != me and "water" in p:
			_dot(p.global_position, Color(0.4, 0.85, 1.0), "P%d" % n)
			n += 1
	if me:
		var c := _screen(me.global_position)
		var f := Vector2(-sin(me.rotation.y), -cos(me.rotation.y))
		var s := f.orthogonal()
		var pts := PackedVector2Array([c + f * 12.0, c - f * 7.0 + s * 7.0, c - f * 3.0, c - f * 7.0 - s * 7.0])
		draw_colored_polygon(pts, Color(0, 0, 0))
		draw_colored_polygon(PackedVector2Array([c + f * 10.0, c - f * 5.5 + s * 5.5, c - f * 2.0, c - f * 5.5 - s * 5.5]),
			Color(1.0, 0.85, 0.2))
	draw_string_outline(_font, Vector2(16, size.y - 16), "M / Esc  close     wheel  zoom     drag  pan", HORIZONTAL_ALIGNMENT_LEFT,
		-1, 14, 4, Color(0, 0, 0, 0.85))
	draw_string(_font, Vector2(16, size.y - 16), "M / Esc  close     wheel  zoom     drag  pan", HORIZONTAL_ALIGNMENT_LEFT,
		-1, 14, Color(0.9, 0.86, 0.75))


func _dot(pos: Vector3, col: Color, label: String) -> void:
	var p := _screen(pos)
	draw_circle(p, 7.0, Color(0, 0, 0))
	draw_circle(p, 5.0, col)
	draw_string_outline(_font, p + Vector2(9, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.85))
	draw_string(_font, p + Vector2(9, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)


func _load() -> bool:
	if _tex != null:
		return true
	_meta = DataLoader.load_json(META_PATH)
	if _meta.is_empty():
		push_error("WorldMapUI: no map - run tools/map_import/build_world_map.tscn")
		return false
	var a: Array = _meta.area
	_area = Rect2(a[0], a[1], a[2], a[3])
	_px_per_m = float(_meta.pixels[0]) / _area.size.x
	_tex = load(str(_meta.texture)) as Texture2D
	return _tex != null


func _to_px(pos: Vector3) -> Vector2:
	return (Vector2(pos.x, pos.z) - _area.position) * _px_per_m


func _screen(pos: Vector3) -> Vector2:
	return _offset + _to_px(pos) * _zoom
