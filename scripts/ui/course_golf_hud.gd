# CourseGolfHud — the country club round on the HUD (D-086), added under the HUD by CourseGolf. While the local
# player's SportInput is in "course" mode: hole / par / stroke / yards to the pin / lie / round total (to par) on
# top; the bag (3 / wheel to change, the putter picked on the green), carry of the club from this lie, the swing
# meter (SwingMeterDraw) with the "reaches the pin" mark, the green's slope while putting; Q shows the card.
# Away from the ball: "walk to your ball - N yd". Presentation only, redraws ~15x a second (every frame mid-swing).
# Depends on: SportInput (local player "sport"), CourseGolf (sp.game), GolfBallRules, SwingMeterDraw, DzHud
# (slope_text).
extends Control

const DzHud := preload("res://scripts/ui/drop_zone_hud.gd")
const REDRAW_SECONDS := 0.066
const YD := 1.09361
const FT := 3.28084
const BAR_W := 560.0

var _font: Font
var _bg := StyleBoxFlat.new()
var _redraw := 0.0
var _me: Node
var _aim_key := ""
var _full := 0.0
var _pin_power := 2.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_bg.bg_color = Color(0, 0, 0, 0.55)
	_bg.set_corner_radius_all(6)


func _process(delta: float) -> void:
	_me = get_tree().get_first_node_in_group("local_player")
	var show_it: bool = _me != null and "sport" in _me and _me.sport.mode == "course"
	if visible != show_it:
		visible = show_it
	if not visible:
		return
	_redraw -= delta
	if _redraw <= 0.0 or _me.sport.meter.busy() or _me.sport.grade_time > 0.0:
		_redraw = REDRAW_SECONDS
		queue_redraw()


func _draw() -> void:
	if _me == null:
		return
	var sp: SportInput = _me.sport
	var cg: Node = sp.game
	if cg == null:
		return
	var c: Dictionary = cg.my_card()
	if c.is_empty():
		return
	var t := GolfBallRules.tuning()
	var hole := int(c.hole)
	var h: Dictionary = cg.hole_def(hole)
	var ball: Vector3 = c.ball
	var cup: Vector3 = cg.cup_pos(hole)
	var dist := Vector2(cup.x - ball.x, cup.z - ball.z).length() if cup != Vector3.INF else float(h.yards) / YD
	var total := 0
	var par_so_far := 0
	for i in c.strokes.size():
		if int(c.strokes[i]) > 0:
			total += int(c.strokes[i])
			par_so_far += int(cg.hole_def(i).par)
	var to_par := DiscGolfRules.to_par_text(total, par_so_far) if total > 0 else "E"
	var lie := str(c.get("lie", "rough")).capitalize()
	_line(Vector2(size.x * 0.5, size.y - 262.0), "HOLE %d   Par %d   Stroke %d   %s   %s   Round %d (%s)   %d of 18" % [hole + 1, int(h.par),
		int(c.throws) + 1, ("%d ft" % roundi(dist * FT)) if cg.aim_on_green() else ("%d yd to the pin" % roundi(dist * YD)), lie,
		total, to_par, int(c.played) + 1], 17)
	if not cg.aim_ready() and not cg.aim_flying() and not sp.meter.busy():
		var walk: float = Vector2(_me.global_position.x - ball.x, _me.global_position.z - ball.z).length()
		_line(Vector2(size.x * 0.5, size.y - 200.0), "Walk to your ball - %d yd  (follow the marker)" % roundi(walk * YD), 15)
		_card(cg, c)
		return
	var r := Rect2(size.x * 0.5 - BAR_W * 0.5 - 12.0, size.y - 200.0, BAR_W + 24.0, 96.0)
	draw_style_box(_bg, r)
	var x := r.position.x + 12.0
	for id: String in sp.clubs():
		var sel: bool = id == sp.club_id()
		var label := "Putter" if id == "putter" else str(t.clubs[id].name)
		_text(Vector2(x, r.position.y + 22.0), label, 14, Color(1, 1, 1) if sel else Color(0.55, 0.55, 0.55))
		var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		if sel:
			draw_line(Vector2(x, r.position.y + 27.0), Vector2(x + w, r.position.y + 27.0), Color(1.0, 0.85, 0.3), 2.0)
		x += w + 12.0
	var bar := Rect2(r.position.x + 12.0, r.position.y + 54.0, BAR_W, 16.0)
	var club := sp.club_id()
	var marks: Array = []
	if club == "putter":
		var dec := float(cg.course.lies.get(str(c.get("lie", "green")), cg.course.lies.rough).putt_decel)
		marks.append([clampf(sqrt(2.0 * dec * (dist + 0.3)) / float(t.putting.max_speed), 0.0, 1.0), Color(1.0, 0.85, 0.2)])
		_text(Vector2(r.end.x - 230.0, r.position.y + 44.0), DzHud.slope_text(cg.aim_slope(), _me.yaw), 13, Color(0.6, 0.85, 1.0))
	elif t.clubs.has(club):
		var key := "%s|%.2f|%.0f" % [club, float(cg.aim_power_mult()), dist]
		if key != _aim_key:  # the carry sims only rerun when the club, lie or distance changes
			_aim_key = key
			_full = GolfBallRules.carry(t.clubs[club], float(cg.aim_power_mult()), t)
			_pin_power = _power_for(t.clubs[club], float(cg.aim_power_mult()), dist, t)
		_text(Vector2(r.end.x - 120.0, r.position.y + 22.0), "%d yd max" % roundi(_full * YD), 14, Color(0.9, 0.85, 0.7))
		marks.append([_pin_power, Color(1.0, 0.85, 0.2)])
	SwingMeterDraw.draw(self, _font, bar, sp, marks)
	_text(Vector2(bar.position.x, bar.end.y + 18.0), "Click: swing / power / accuracy   mouse: aim   3 or wheel: club   right click: cancel   Q: card", 12,
		Color(0.7, 0.7, 0.65))
	_card(cg, c)


# Power (0..1) whose carry from this lie reaches `metres` (power^power_curve scales launch speed: bisect), 2 = never.
func _power_for(club: Dictionary, mult: float, metres: float, t: Dictionary) -> float:
	if GolfBallRules.carry(club, mult, t) < metres:
		return 2.0
	var lo := 0.0
	var hi := 1.0
	for i in 8:
		var mid := (lo + hi) * 0.5
		if GolfBallRules.carry(club, mid * mult, t) < metres:
			lo = mid
		else:
			hi = mid
	return hi


func _card(cg: Node, c: Dictionary) -> void:
	if not Input.is_action_pressed("scorecard"):
		return
	var text := PackedStringArray()
	for i in cg.hole_count():
		var s := int(c.strokes[i])
		text.append("%d:%s" % [i + 1, str(s) if s > 0 else "-"])
	_line(Vector2(size.x * 0.5, size.y * 0.5 - 60.0), "  ".join(text.slice(0, 9)), 15)
	_line(Vector2(size.x * 0.5, size.y * 0.5 - 20.0), "  ".join(text.slice(9)), 15)


func _line(top_centre: Vector2, text: String, font_size: int) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_style_box(_bg, Rect2(top_centre.x - w * 0.5 - 12.0, top_centre.y, w + 24.0, font_size + 16.0))
	_text(Vector2(top_centre.x - w * 0.5, top_centre.y + font_size + 4.0), text, font_size, Color(1.0, 0.92, 0.7))


func _text(at: Vector2, text: String, font_size: int, col: Color) -> void:
	SwingMeterDraw.text(self, _font, at, text, font_size, col)
