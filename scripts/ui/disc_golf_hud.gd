# DiscGolfHud — disc golf on the HUD (D-069), added under the HUD by DiscGolfDirector. Draws, for the local player:
#   * with a disc out: the bag (carried discs, the one in hand highlighted), backhand / forehand, tilt, and the power
#     bar while charging, with a mark at the power that carries to the basket on flat ground;
#   * during a round: hole, par, length, throw number, feet to the basket and score so far (above the bag), and a
#     reminder to walk to the disc / tee when too far from it;
#   * near the course only (D-071): the scorecard (every player in the round, per hole, total, to par) while Q is held, for a few seconds after a
#     hole is scored, and longer when the round ends.
# Presentation only; redraws ~15x a second (every frame while charging). Depends on: DiscGolfDirector (group
# "disc_golf"), DiscThrower (local player's "disc"), DiscFlightRules, DiscGolfRules.
extends Control

const REDRAW_SECONDS := 0.066
const FT := 3.28084
const CARD_AFTER_HOLE := 5.0
const CARD_AFTER_ROUND := 15.0
const NAMES := {"disc_driver": "Driver", "disc_mid": "Mid", "disc_putter": "Putter"}

var _font: Font
var _bg := StyleBoxFlat.new()
var _redraw := 0.0
var _reach: Dictionary = {}  # disc id -> reach table
var _card_left := 0.0
var _near := false           # local player at (or near) the round's course
var _scored := -1            # holes scored on the local card, to pop the scorecard when it changes
var _dg: Node
var _me: Node


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_bg.bg_color = Color(0, 0, 0, 0.55)
	_bg.set_corner_radius_all(6)
	_bg.set_content_margin_all(8)
	var t := DiscFlightRules.tuning()
	for id: String in DiscFlightRules.discs():
		_reach[id] = DiscFlightRules.reach_table(DiscFlightRules.discs()[id], t)


func _process(delta: float) -> void:
	_dg = get_tree().get_first_node_in_group("disc_golf")
	_me = get_tree().get_first_node_in_group("local_player")
	if _dg == null or _me == null:
		if visible:
			hide()
		return
	var e: Dictionary = _dg.my_entry()
	var scored := -1
	if not e.is_empty():
		scored = 0
		for s: Variant in e.strokes:
			scored += 1 if int(s) > 0 else 0
	if scored > _scored and _scored >= 0:
		_card_left = CARD_AFTER_ROUND if e.done else CARD_AFTER_HOLE
	_scored = scored
	_card_left = maxf(0.0, _card_left - delta)
	_near = _dg.near_course(_me.global_position)
	if not _near:
		_card_left = 0.0  # left the course: the scorecard stays behind (D-071)
	var show_it: bool = _me.disc.active or (_dg.round_active and not e.is_empty()) or (_near and (_card_left > 0.0 \
		or (Input.is_action_pressed("scorecard") and not _dg.card.is_empty())))
	if visible != show_it:
		visible = show_it
	if not visible:
		return
	_redraw -= delta
	if _redraw <= 0.0 or _me.disc.charging:
		_redraw = REDRAW_SECONDS
		queue_redraw()


func _draw() -> void:
	if _dg == null or _me == null:
		return
	var e: Dictionary = _dg.my_entry()
	var c: DiscCourse = _dg.course_node()
	var playing: bool = _dg.round_active and not e.is_empty() and not e.done and not e.left and c != null
	var to_basket := -1.0
	if playing:
		to_basket = Vector2(_me.global_position.x, _me.global_position.z).distance_to(
			Vector2(c.basket_position(int(e.hole)).x, c.basket_position(int(e.hole)).z))
		_hole_line(e, c, to_basket)
	if _me.disc.active:
		_bag(to_basket)
	if _near and (Input.is_action_pressed("scorecard") or _card_left > 0.0) and c != null and not _dg.card.is_empty():
		_scorecard(c)


# Bottom centre, above the bag: HOLE 3 · PAR 3 · 189 ft    Throw 2    54 ft to basket    +1
func _hole_line(e: Dictionary, c: DiscCourse, to_basket: float) -> void:
	var hole := int(e.hole)
	var h: Dictionary = c.course.holes[hole]
	var done_strokes := 0
	var done_par := 0
	for i in hole:
		done_strokes += int(e.strokes[i])
		done_par += int(c.course.holes[i].par)
	var text := "HOLE %s  ·  PAR %d  ·  %d ft      Throw %d      %d ft to basket      %s" % [DiscGolfRules.hole_label(c.course, hole), int(h.par),
		int(h.length_ft), int(e.throws) + 1, roundi(to_basket * FT), DiscGolfRules.to_par_text(done_strokes, done_par)]
	var t := DiscFlightRules.tuning()
	var reach := float(t.tee_radius_m) if int(e.throws) == 0 else float(t.lie_radius_m)
	var lie: Vector3 = e.lie
	var away := Vector2(_me.global_position.x, _me.global_position.z).distance_to(Vector2(lie.x, lie.z))
	var hint := ""
	if _dg.is_flying(multiplayer.get_unique_id()):
		hint = "In flight..."
	elif away > reach:
		hint = ("Go to the tee  (%d ft)" if int(e.throws) == 0 else "Walk to your disc  (%d ft)") % roundi(away * FT)
	elif not _me.disc.active:
		hint = "Press 3 to take out a disc"
	_panel_text(Vector2(size.x * 0.5, size.y - 262.0), [text, hint], 17, [Color(1.0, 0.92, 0.7), Color(0.6, 0.9, 1.0)])


# Bottom centre: the bag, grip, tilt, power bar.
func _bag(to_basket: float) -> void:
	var th: Node = _me.disc
	var have: PackedStringArray = th.carried()
	var w := 520.0
	var r := Rect2(size.x * 0.5 - w * 0.5, size.y - 190.0, w, 86.0)
	draw_style_box(_bg, r)
	var x := r.position.x + 12.0
	for id: String in have:
		var col: Array = DiscFlightRules.discs()[id].color
		var sel: bool = id == th.disc_id
		var label := str(NAMES.get(id, id))
		draw_circle(Vector2(x + 8.0, r.position.y + 18.0), 8.0 if sel else 6.0, Color(col[0], col[1], col[2]))
		_text(Vector2(x + 20.0, r.position.y + 24.0), label, 16, Color(1, 1, 1) if sel else Color(0.6, 0.6, 0.6))
		if sel:
			draw_line(Vector2(x, r.position.y + 31.0), Vector2(x + 24.0 + _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x, r.position.y + 31.0), Color(col[0], col[1], col[2]), 2.0)
		x += 40.0 + _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var tilt: float = th.tilt_deg
	var tilt_text := "flat" if is_zero_approx(tilt) else "%d° %s" % [absi(roundi(tilt)), "left" if tilt > 0.0 else "right"]
	var grip := "%s   tilt %s" % ["Forehand" if th.forehand else "Backhand", tilt_text]
	_text(Vector2(r.end.x - 12.0 - _font.get_string_size(grip, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, r.position.y + 24.0), grip, 15, Color(0.9, 0.85, 0.7))
	var bar := Rect2(r.position.x + 12.0, r.position.y + 42.0, w - 24.0, 16.0)
	draw_rect(bar, Color(0.1, 0.1, 0.1, 0.9))
	var charge: float = th.charge
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * charge, bar.size.y)), Color(0.3, 0.85, 0.35).lerp(Color(1.0, 0.45, 0.2), charge))
	if to_basket > 0.0 and _reach.has(th.disc_id):
		var need := DiscFlightRules.power_for(_reach[th.disc_id], to_basket)
		var mx := bar.position.x + bar.size.x * need
		draw_line(Vector2(mx, bar.position.y - 4.0), Vector2(mx, bar.end.y + 4.0), Color(1.0, 0.85, 0.2), 2.0)
	draw_rect(bar, Color(1, 1, 1, 0.5), false, 1.0)
	_text(Vector2(bar.position.x, bar.end.y + 18.0), "Hold left click: power   Z / X or wheel: tilt   F: grip   3: next disc   right click: cancel", 12, Color(0.7, 0.7, 0.65))


func _scorecard(c: DiscCourse) -> void:
	var holes: Array = c.course.holes
	var ids: Array = _dg.card.keys()
	ids.sort()
	var name_w := 70.0
	var cell := 34.0
	var row_h := 24.0
	var w := name_w + cell * holes.size() + 110.0
	var h := row_h * (ids.size() + 3) + 16.0
	var r := Rect2(size.x * 0.5 - w * 0.5, size.y * 0.5 - h * 0.5 - 40.0, w, h)
	draw_style_box(_bg, r)
	var y := r.position.y + 24.0
	_text(Vector2(r.position.x + 10.0, y), str(c.course.name), 16, Color(1.0, 0.85, 0.45))
	var best := int(get_tree().get_first_node_in_group("quests").flags.get("dg_best_" + c.course_id, 0)) if get_tree().get_first_node_in_group("quests") else 0
	if best > 0:
		_text(Vector2(r.end.x - 130.0, y), "Best: %d" % best, 14, Color(0.8, 0.8, 0.7))
	y += row_h
	_text(Vector2(r.position.x + 10.0, y), "Hole", 14, Color(0.7, 0.7, 0.65))
	for i in holes.size():
		_text(Vector2(r.position.x + name_w + cell * i + 8.0, y), DiscGolfRules.hole_label(c.course, i), 14, Color(0.7, 0.7, 0.65))
	_text(Vector2(r.position.x + name_w + cell * holes.size() + 8.0, y), "Tot", 14, Color(0.7, 0.7, 0.65))
	y += row_h
	_text(Vector2(r.position.x + 10.0, y), "Par", 14, Color(0.7, 0.7, 0.65))
	for i in holes.size():
		_text(Vector2(r.position.x + name_w + cell * i + 10.0, y), str(int(holes[i].par)), 14, Color(0.7, 0.7, 0.65))
	_text(Vector2(r.position.x + name_w + cell * holes.size() + 8.0, y), str(DiscGolfRules.par_total(c.course)), 14, Color(0.7, 0.7, 0.65))
	for peer: int in ids:
		y += row_h
		var e: Dictionary = _dg.card[peer]
		_text(Vector2(r.position.x + 10.0, y), _dg.player_label(peer), 15, Color(1, 1, 1) if peer == multiplayer.get_unique_id() else Color(0.85, 0.85, 0.85))
		var total := 0
		var par := 0
		for i in holes.size():
			var s := int(e.strokes[i])
			var cx := r.position.x + name_w + cell * i
			if s > 0:
				total += s
				par += int(holes[i].par)
				var d := s - int(holes[i].par)
				var col := Color(1.0, 0.8, 0.2) if s == 1 else (Color(0.4, 0.9, 0.45) if d < 0 else (Color(1, 1, 1) if d == 0 else Color(1.0, 0.55, 0.45)))
				_text(Vector2(cx + 10.0, y), str(s), 15, col)
			elif i == int(e.hole) and not e.done and not e.left:
				draw_rect(Rect2(cx + 2.0, y - 16.0, cell - 4.0, 20.0), Color(1, 1, 1, 0.12))
		var tail := "%d  %s" % [total, DiscGolfRules.to_par_text(total, par)] if total > 0 else "-"
		if e.left:
			tail += "  (left)"
		_text(Vector2(r.position.x + name_w + cell * holes.size() + 8.0, y), tail, 15, Color(1, 1, 1))


func _panel_text(top_centre: Vector2, lines: Array, font_size: int, colors: Array) -> void:
	var w := 0.0
	var n := 0
	for l: String in lines:
		if l != "":
			w = maxf(w, _font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
			n += 1
	var r := Rect2(top_centre.x - w * 0.5 - 12.0, top_centre.y, w + 24.0, 10.0 + n * (font_size + 8.0))
	draw_style_box(_bg, r)
	var y := r.position.y + font_size + 4.0
	for i in lines.size():
		var l: String = lines[i]
		if l == "":
			continue
		var lw := _font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		_text(Vector2(top_centre.x - lw * 0.5, y), l, font_size, colors[i])
		y += font_size + 8.0


func _text(at: Vector2, text: String, font_size: int, col: Color) -> void:
	draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.85))
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
