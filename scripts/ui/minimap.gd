# Minimap — top-left corner map (D-067): the same pipeline map picture as the M map, turned so the way you face is
# always up, about view_m across. Shows landmark / bar markers, teammates, Bonk and a diamond per tracked quest
# objective (pinned to the edge when it's off the map), your disc golf basket and tee pad during a round (D-076), street names
# (upright, from the map meta, D-070), plus a north tick. Hidden when you have no body or a
# full-screen window (map, quest book, inventory, pause) is open. Redraws 20x a second. Presentation only.
# Depends on: world/generated/map/world_map.json (+ texture), Player (groups "local_player", "players"), Bonk
# (group "bonk"), QuestBookUI (group "quest_book"), QuestDirector (group "quests"), QuestRules, DiscGolfDirector (group "disc_golf").
extends Control

const META_PATH := "res://world/generated/map/world_map.json"
const SIZE := 210.0
const VIEW_M := 360.0          # metres across the minimap
const REDRAW_SECONDS := 0.05
const COVERING := ["world_map_ui", "quest_book", "inventory_ui", "pause_menu", "crafting_ui"]

var _meta: Dictionary = {}
var _tex: Texture2D
var _area := Rect2()
var _px_per_m := 0.5
var _font: Font
var _redraw := 0.0
var _border := StyleBoxFlat.new()
var _me: Node3D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	position = Vector2(14, 14)
	size = Vector2(SIZE, SIZE)
	_font = ThemeDB.fallback_font
	_border.draw_center = false
	_border.border_color = Color(0.85, 0.75, 0.55, 0.9)
	_border.set_border_width_all(2)
	_border.set_corner_radius_all(8)
	_meta = DataLoader.load_json(META_PATH)
	if not _meta.is_empty():
		var a: Array = _meta.area
		_area = Rect2(a[0], a[1], a[2], a[3])
		_px_per_m = float(_meta.pixels[0]) / _area.size.x
		_tex = load(str(_meta.texture)) as Texture2D


func _process(delta: float) -> void:
	_me = get_tree().get_first_node_in_group("local_player") as Node3D
	var show_it := _me != null and _tex != null
	for g: String in COVERING:
		var n := get_tree().get_first_node_in_group(g) as CanvasItem
		show_it = show_it and not (n and n.visible)
	if visible != show_it:
		visible = show_it
	if not visible:
		return
	_redraw -= delta
	if _redraw <= 0.0:
		_redraw = REDRAW_SECONDS
		queue_redraw()


func _draw() -> void:
	if _me == null:
		return
	var c := size * 0.5
	var zoom := SIZE / VIEW_M / _px_per_m  # screen pixels per map pixel
	var yaw := _me.rotation.y
	var me_px := _to_px(_me.global_position)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.07, 0.05, 0.85))
	draw_set_transform(c, yaw, Vector2(zoom, zoom))
	draw_texture(_tex, -me_px)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Street names along the streets, kept upright (D-070).
	var inner_rect := Rect2(Vector2.ZERO, size).grow(-12.0)
	var reach := VIEW_M * 0.75
	for st: Array in _meta.get("streets", []):
		var sx := float(st[1])
		var sz := float(st[2])
		if absf(sx - _me.global_position.x) > reach or absf(sz - _me.global_position.z) > reach:
			continue
		var sp := _screen(Vector3(sx, 0.0, sz), c, yaw)
		if not inner_rect.has_point(sp):
			continue
		var ang := wrapf(float(st[3]) + yaw, -PI * 0.5, PI * 0.5)
		var w := _font.get_string_size(str(st[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_set_transform(sp, ang, Vector2.ONE)
		draw_string_outline(_font, Vector2(-w * 0.5, 3.5), str(st[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color(0, 0, 0, 0.8))
		draw_string(_font, Vector2(-w * 0.5, 3.5), str(st[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.92, 0.9, 0.82))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Landmark and point-of-interest markers that are on the map.
	for l: Dictionary in _meta.get("labels", []):
		var p := _screen(Vector3(float(l.x), 0.0, float(l.z)), c, yaw)
		if not Rect2(Vector2.ZERO, size).grow(-4.0).has_point(p):
			continue
		var poi: bool = str(l.size) == "poi"
		draw_circle(p, 4.0 if poi else 3.0, Color(0.9, 0.25, 0.15) if poi else Color(1.0, 0.92, 0.7))
		var label := str(l.name).trim_suffix(" (raiders)")
		draw_string_outline(_font, p + Vector2(6, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color(0, 0, 0, 0.9))
		draw_string(_font, p + Vector2(6, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.55, 0.45) if poi else Color(0.95, 0.9, 0.78))
	# Tracked quest objectives (pinned to the edge when off the map).
	var quests := get_tree().get_first_node_in_group("quests")
	var book := get_tree().get_first_node_in_group("quest_book")
	if quests and book:
		for id: String in book.tracked_quests():
			var q: Dictionary = QuestRules.defs()[id]
			var i := QuestRules.current(q, quests.flags)
			var at: Vector3 = quests.objective_position(q.objectives[i]) if i >= 0 else Vector3.INF
			if at == Vector3.INF:
				continue
			var p := _screen(at, c, yaw)
			var inner := Rect2(Vector2.ZERO, size).grow(-10.0)
			if not inner.has_point(p):  # pin to the edge along the line from the centre
				var dir := (p - c).normalized()
				var t := minf(absf((inner.size.x * 0.5) / dir.x) if dir.x != 0.0 else INF, absf((inner.size.y * 0.5) / dir.y) if dir.y != 0.0 else INF)
				p = c + dir * t
			var d := 7.0
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -d - 2), p + Vector2(d + 2, 0), p + Vector2(0, d + 2), p + Vector2(-d - 2, 0)]), Color(0, 0, 0))
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)]), Color(1.0, 0.8, 0.2))
	# Disc golf: your current hole's tee pad (D-076) and basket (D-069).
	var dg := get_tree().get_first_node_in_group("disc_golf")
	var tee: Vector3 = dg.local_tee() if dg else Vector3.INF
	if tee != Vector3.INF:
		var tp := _screen(tee, c, yaw)
		if Rect2(Vector2.ZERO, size).has_point(tp):
			draw_rect(Rect2(tp - Vector2(6, 6), Vector2(12, 12)), Color(0, 0, 0))
			draw_rect(Rect2(tp - Vector2(4.5, 4.5), Vector2(9, 9)), Color(0.85, 0.85, 0.85))
			draw_string(_font, tp + Vector2(-3.5, 4.0), "T", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.1, 0.1, 0.1))
	var target: Vector3 = dg.local_target() if dg else Vector3.INF
	if target != Vector3.INF:
		var bp := _screen(target, c, yaw)
		if Rect2(Vector2.ZERO, size).has_point(bp):
			draw_circle(bp, 6.0, Color(0, 0, 0))
			draw_circle(bp, 4.5, Color(0.95, 0.78, 0.15))
			draw_circle(bp, 1.8, Color(0.2, 0.2, 0.2))
	# Bonk and teammates.
	var bonk := get_tree().get_first_node_in_group("bonk") as Node3D
	if bonk:
		_dot(_screen(bonk.global_position, c, yaw), Color(1.0, 0.55, 0.15))
	for pl in get_tree().get_nodes_in_group("players"):
		if pl != _me and "water" in pl:
			_dot(_screen(pl.global_position, c, yaw), Color(0.4, 0.85, 1.0))
	# You: an arrow pointing up. North tick on the rim.
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -11), c + Vector2(8, 8), c + Vector2(0, 3), c + Vector2(-8, 8)]), Color(0, 0, 0))
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(6, 6), c + Vector2(0, 2), c + Vector2(-6, 6)]), Color(1.0, 0.85, 0.2))
	var north := (Vector2(0, -1).rotated(yaw)).normalized()
	var np := c + north * (SIZE * 0.5 - 12.0)
	draw_string_outline(_font, np - Vector2(5, -5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.9))
	draw_string(_font, np - Vector2(5, -5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.4, 0.3))
	draw_style_box(_border, Rect2(Vector2.ZERO, size))


func _dot(p: Vector2, col: Color) -> void:
	if Rect2(Vector2.ZERO, size).has_point(p):
		draw_circle(p, 5.0, Color(0, 0, 0))
		draw_circle(p, 3.5, col)


func _to_px(pos: Vector3) -> Vector2:
	return (Vector2(pos.x, pos.z) - _area.position) * _px_per_m


# Map position -> minimap pixel: relative to you, turned so your facing is up.
func _screen(pos: Vector3, c: Vector2, yaw: float) -> Vector2:
	var rel := Vector2(pos.x - _me.global_position.x, pos.z - _me.global_position.z) * (SIZE / VIEW_M)
	return c + rel.rotated(yaw)
