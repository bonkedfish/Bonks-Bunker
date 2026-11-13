# DzHud — Drop Zone on the HUD (D-074), added under the HUD by DropZone. Draws for the local player's SportInput mode:
#   range:  bay, balls left, score, last shot (above the bar); the clubs (3 = next), power bar with a mark per target
#           colour at the power that carries to it from your bay, the carry in yards at the current power;
#           the bays' leaderboard (top right, under the quest tracker).
#   putt:   hole / par / strokes / feet to the cup, power bar with the "reaches the cup" mark; Q = card.
#   pickle: score You - CPU and who serves.
# Presentation only, redraws ~15x a second (every frame while charging). Depends on: SportInput (local player
# "sport"), DropZone (group "drop_zone": Range, Putting, courts), GolfBallRules.
extends Control

const REDRAW_SECONDS := 0.066
const YD := 1.09361
const FT := 3.28084
const BAR_W := 440.0

var _font: Font
var _bg := StyleBoxFlat.new()
var _redraw := 0.0
var _carry: Dictionary = {}  # club id -> PackedFloat32Array carry (m) at power 0, 0.05 .. 1
var _me: Node


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_bg.bg_color = Color(0, 0, 0, 0.55)
	_bg.set_corner_radius_all(6)
	var t := GolfBallRules.tuning()
	for id: String in t.clubs:
		var table := PackedFloat32Array()
		for i in 21:
			table.append(0.0 if i == 0 else GolfBallRules.carry(t.clubs[id], i / 20.0, t))
		_carry[id] = table


func _process(delta: float) -> void:
	_me = get_tree().get_first_node_in_group("local_player")
	var show_it: bool = _me != null and "sport" in _me and _me.sport.mode != ""
	if visible != show_it:
		visible = show_it
	if not visible:
		return
	_redraw -= delta
	if _redraw <= 0.0 or _me.sport.charging:
		_redraw = REDRAW_SECONDS
		queue_redraw()


func _draw() -> void:
	if _me == null:
		return
	var sp: Node = _me.sport
	match str(sp.mode):
		"range":
			_range(sp)
		"putt":
			_putt(sp)
		"pickle":
			_pickle(sp)


func _range(sp: Node) -> void:
	var rg: Node = sp.game
	var me := multiplayer.get_unique_id()
	if rg == null or not rg.games.has(me):
		return
	var g: Dictionary = rg.games[me]
	var t := GolfBallRules.tuning()
	_line(Vector2(size.x * 0.5, size.y - 252.0), "BAY %d      Balls %d / %d      Score %d%s" % [int(g.bay) + 1, int(g.balls), int(t.range.balls),
		int(g.score), ("      Last +%d" % int(g.last)) if int(g.last) > 0 else ("      Last: miss" if int(g.last) == 0 else "")], 18)
	var r := Rect2(size.x * 0.5 - BAR_W * 0.5 - 12.0, size.y - 190.0, BAR_W + 24.0, 86.0)
	draw_style_box(_bg, r)
	var x := r.position.x + 12.0
	for id: String in t.club_order:
		var sel: bool = id == sp.club_id()
		var label := str(t.clubs[id].name)
		_text(Vector2(x, r.position.y + 24.0), label, 16, Color(1, 1, 1) if sel else Color(0.55, 0.55, 0.55))
		var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		if sel:
			draw_line(Vector2(x, r.position.y + 30.0), Vector2(x + w, r.position.y + 30.0), Color(1.0, 0.85, 0.3), 2.0)
		x += w + 26.0
	var table: PackedFloat32Array = _carry[sp.club_id()]
	var carry := _lookup(table, float(sp.charge))
	_text(Vector2(r.end.x - 150.0, r.position.y + 24.0), "carry %d yd" % roundi(carry * YD), 15, Color(0.9, 0.85, 0.7))
	var bar := Rect2(r.position.x + 12.0, r.position.y + 42.0, BAR_W, 16.0)
	_bar(bar, float(sp.charge))
	var dz: Node = rg.get_parent()
	var tee: Vector3 = rg.bay_spot(int(g.bay))
	var colors: Dictionary = dz.data.target_colors
	for tg: Dictionary in dz.data.targets:
		var dist := Vector2(float(tg.x) - tee.x, float(tg.z) - tee.z).length()
		var pw := _power_for(table, dist)
		if pw <= 1.0:
			var c: Array = colors[str(tg.color)]
			var mx := bar.position.x + bar.size.x * pw
			draw_line(Vector2(mx, bar.position.y - 5.0), Vector2(mx, bar.end.y + 5.0), Color(c[0], c[1], c[2]), 3.0)
	_text(Vector2(bar.position.x, bar.end.y + 18.0), "Hold left click: power   aim with the mouse   3: next club   right click: cancel", 12, Color(0.7, 0.7, 0.65))
	# Leaderboard of everyone in a bay.
	var ids: Array = rg.games.keys()
	ids.sort_custom(func(a: int, b: int) -> bool: return int(rg.games[a].score) > int(rg.games[b].score))
	var y := 160.0
	_text(Vector2(size.x - 230.0, y), "DROP ZONE", 15, Color(1.0, 0.85, 0.45))
	for peer: int in ids:
		y += 20.0
		var e: Dictionary = rg.games[peer]
		_text(Vector2(size.x - 230.0, y), "%s  bay %d   %d" % ["You" if peer == me else "Player", int(e.bay) + 1, int(e.score)], 14,
			Color(1, 1, 1) if peer == me else Color(0.8, 0.8, 0.8))


func _putt(sp: Node) -> void:
	var pg: Node = sp.game
	var me := multiplayer.get_unique_id()
	if pg == null or not pg.cards.has(me):
		return
	var c: Dictionary = pg.cards[me]
	var hole := int(c.hole)
	var h: Dictionary = pg.hole_def(hole)
	var cup := Vector2(h.cup[0], h.cup[1])
	var ball: Vector2 = c.ball
	var dist := ball.distance_to(cup)
	var total := 0
	for s: Variant in c.strokes:
		total += int(s)
	_line(Vector2(size.x * 0.5, size.y - 252.0), "HOLE %d / 18      Par %d      Stroke %d      %d ft to the cup      Total %d" % [hole + 1, int(h.par),
		int(c.throws) + 1, roundi(dist * FT), total], 18)
	var r := Rect2(size.x * 0.5 - BAR_W * 0.5 - 12.0, size.y - 160.0, BAR_W + 24.0, 60.0)
	draw_style_box(_bg, r)
	var bar := Rect2(r.position.x + 12.0, r.position.y + 14.0, BAR_W, 16.0)
	_bar(bar, float(sp.charge))
	var mx := bar.position.x + bar.size.x * GolfBallRules.putt_power(dist + 0.15, GolfBallRules.tuning())
	draw_line(Vector2(mx, bar.position.y - 5.0), Vector2(mx, bar.end.y + 5.0), Color(1.0, 0.85, 0.2), 3.0)
	_text(Vector2(bar.position.x, bar.end.y + 18.0), "Stand by your ball, aim with the mouse, hold left click: power   Q: card", 12, Color(0.7, 0.7, 0.65))
	if Input.is_action_pressed("scorecard"):
		var holes: Array = pg.get_parent().data.putting.holes
		var text := PackedStringArray()
		for i in holes.size():
			text.append("%d:%s" % [i + 1, str(int(c.strokes[i])) if int(c.strokes[i]) > 0 else "-"])
		_line(Vector2(size.x * 0.5, size.y * 0.5 - 40.0), "  ".join(text), 15)


func _pickle(sp: Node) -> void:
	var ct: Node = sp.game
	if ct == null:
		return
	var s: Vector2i = ct.score
	var who := "you serve - click" if int(ct.serving) == 1 and str(ct.phase) == "serve" else ("CPU serves" if int(ct.serving) == -1 and str(ct.phase) == "serve" else "")
	_line(Vector2(size.x * 0.5, size.y - 252.0), "PICKLEBALL  court %d      You %d  -  %d CPU      %s" % [int(ct.index) + 1, s.x, s.y, who], 18)
	_text(Vector2(size.x * 0.5 - 170.0, size.y - 120.0), "Get to the ball and left click to hit where you look", 13, Color(0.75, 0.75, 0.7))


func _bar(bar: Rect2, charge: float) -> void:
	draw_rect(bar, Color(0.1, 0.1, 0.1, 0.9))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * charge, bar.size.y)), Color(0.3, 0.85, 0.35).lerp(Color(1.0, 0.45, 0.2), charge))
	draw_rect(bar, Color(1, 1, 1, 0.5), false, 1.0)


func _lookup(table: PackedFloat32Array, power: float) -> float:
	var k := clampf(power, 0.0, 1.0) * 20.0
	var i := mini(int(k), 19)
	return lerpf(table[i], table[i + 1], k - i)


func _power_for(table: PackedFloat32Array, metres: float) -> float:
	for i in range(1, table.size()):
		if table[i] >= metres:
			return (i - 1 + inverse_lerp(table[i - 1], table[i], metres)) / 20.0
	return 2.0


func _line(top_centre: Vector2, text: String, font_size: int) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_style_box(_bg, Rect2(top_centre.x - w * 0.5 - 12.0, top_centre.y, w + 24.0, font_size + 16.0))
	_text(Vector2(top_centre.x - w * 0.5, top_centre.y + font_size + 4.0), text, font_size, Color(1.0, 0.92, 0.7))


func _text(at: Vector2, text: String, font_size: int, col: Color) -> void:
	draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.85))
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
