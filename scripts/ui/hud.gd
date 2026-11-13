# HUD — crosshair, health + food/water (D-046) + active effects with seconds left (D-052), weapon/ammo, hit marker, and a status line (downed / bleed-out /
# revive / respawning, "Hold E to revive" near a downed teammate, or "Using Bandage 40%") for the local player.
# Polls the local player's replicated state each frame but only rebuilds text when a value changes.
# Also shows short notes from the host ("Game saved", quest news) via show_toast() (queued, one at a time), the
# tracked quest's current objective + distance (top right, D-054) and a boss bar for the nearest live boss.
# Health / food / water / Meepo / effects are icon chips in StatusBar (D-066); the Minimap sits top left (D-067).
# Group: "hud". Depends on: Player (groups "local_player", "players"), WeaponHolder, LifeState, StatusBar, Minimap.
extends Control

const HIT_MARKER_TIME := 0.15
const StatusBar := preload("res://scripts/ui/status_bar.gd")
const Minimap := preload("res://scripts/ui/minimap.gd")

@onready var health_label: Label = $Health
@onready var ammo_label: Label = $Ammo
@onready var hit_marker: Label = $HitMarker
@onready var death_label: Label = $Death

var _hit_timer := 0.0
var _last_health := -1.0
var _last_load := -1
var _last_effects: Dictionary = {}
var _last_meepo := Vector2i(-2, -2)
var _last_needs := Vector2i(-1, -1)
var _last_ammo := Vector4i(-1, -1, -1, -1)
var _last_status := Vector4i(-1, -1, -1, -1)
var _revive_target: Node = null
var _scan_timer := 0.0
var _toast: Label
var _toast_left := 0.0
var _toast_queue: Array = []
var _tracker: Label
var _tracker_timer := 0.0
var _boss: Label
var _quests: Node
var _book: Node
var status: Control


func _ready() -> void:
	add_to_group("hud")
	hit_marker.hide()
	death_label.hide()
	health_label.hide()
	status = StatusBar.new()
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	status.offset_left = 16.0
	status.offset_top = -96.0
	status.offset_right = 1200.0
	status.offset_bottom = -14.0
	add_child(status)
	add_child(Minimap.new())
	_toast = Label.new()
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 24.0
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.hide()
	add_child(_toast)
	# Tracked quest (top right) and the boss bar (top centre, under the toast line).
	_tracker = _outlined_label(16)
	_tracker.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_tracker.offset_top = 40.0
	_tracker.offset_right = -16.0
	_tracker.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_tracker.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_tracker)
	_boss = _outlined_label(20)
	_boss.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_boss.offset_top = 56.0
	_boss.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_boss.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	_boss.hide()
	add_child(_boss)
	_quests = get_tree().get_first_node_in_group("quests")
	_book = get_tree().get_first_node_in_group("quest_book")


func _outlined_label(font_size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	return l


func show_toast(text: String, seconds: float) -> void:
	if _toast_left > 0.0:  # one at a time: the rest wait their turn
		_toast_queue.append([text, seconds])
		return
	_toast.text = text
	_toast.show()
	_toast_left = seconds


func show_hit_marker(killed: bool) -> void:
	hit_marker.modulate = Color(1.0, 0.25, 0.2) if killed else Color.WHITE
	hit_marker.show()
	_hit_timer = HIT_MARKER_TIME


func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			_toast.hide()
			if not _toast_queue.is_empty():
				var next: Array = _toast_queue.pop_front()
				show_toast(str(next[0]), float(next[1]))
	if _hit_timer > 0.0:
		_hit_timer -= delta
		if _hit_timer <= 0.0:
			hit_marker.hide()

	var player := get_tree().get_first_node_in_group("local_player")
	if player == null or player.cutscene:  # no player yet, or the ace replay (D-076) has the screen
		if visible:
			hide()
		return
	if not visible:
		show()

	var hp: float = player.health.current
	var load_state := _load_state(player.inventory.weight)
	var needs := Vector2i(ceili(player.needs.net_hunger), ceili(player.needs.net_thirst))
	var fx: Dictionary = player.effects.net_effects
	var mp := Vector2i(roundi(player.meepo.net_battery), int(player.meepo.net_riding)) if player.meepo.has_board() else Vector2i(-1, -1)
	if hp != _last_health or load_state != _last_load or needs != _last_needs or fx != _last_effects or mp != _last_meepo:
		_last_meepo = mp
		_last_health = hp
		_last_load = load_state
		_last_needs = needs
		_last_effects = fx
		var warn: String = ("HUNGRY/THIRSTY - no sprint   " if player.needs.is_low() else "") + ["", "OVERWEIGHT", "TOO HEAVY"][load_state]
		status.set_state(hp, needs.x, needs.y, mp, fx, warn.strip_edges())

	_tracker_timer -= delta
	if _tracker_timer <= 0.0:
		_tracker_timer = 0.25
		_update_tracker(player)
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 0.1  # rescan for a downed teammate 10x/sec, not every frame
		_revive_target = _nearest_downed_teammate(player)
	_update_status(player)

	var w: WeaponHolder = player.weapons
	var slot: int = player.selected_slot
	var state := Vector4i(slot, w.net_mag, w.net_reserve, int(w.net_reloading) + 2 * w.net_slot)
	if state != _last_ammo:
		_last_ammo = state
		var weapon := w.weapon_in_slot(slot)
		var text := str(weapon.get("name", ""))
		if weapon.get("kind", "") == "gun" and w.net_slot == slot:
			text += "   %d / %d" % [w.net_mag, w.net_reserve]
			if w.net_reloading:
				text += "   RELOADING"
		ammo_label.text = text


# Status line (the "Death" label): downed / bleed-out / being revived, dead, or reviving a teammate.
func _update_status(player: Node) -> void:
	var life: LifeState = player.life
	var kind := 0  # 0 none, 1 downed, 2 dead, 3 revive hint, 4 reviving, 5 search prompt, 6 talk prompt, 7 using,
	# 8 take a dropped item, 9 use the workbench, 10 disc golf course box (a: 0 start, 1 join, 2 playing),
	# 11 Drop Zone spot (a = its instance id)
	var a := 0
	var b := 0
	if life.net_state == LifeState.DOWNED:
		kind = 1
		a = ceili(life.net_bleed_left)
		b = roundi(life.net_revive_progress * 100.0)
	elif life.net_state == LifeState.DEAD:
		kind = 2
	elif player.item_use.net_use_item != "":
		kind = 7
		a = player.item_use.net_use_item.hash()
		b = roundi(player.item_use.net_use_progress * 100.0)
	elif is_instance_valid(_revive_target) and _revive_target.life.is_downed():
		b = roundi(_revive_target.life.net_revive_progress * 100.0)
		kind = 4 if b > 0 else 3
	elif player.looked_container != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		kind = 5
		a = player.looked_container.get_index()
		b = 1 if player.looked_container.net_remaining == 0 else 0
	elif player.looked_talkable != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		kind = 6
		a = 1 if player.looked_talkable.is_in_group("bonk") else 2
	elif player.looked_pickup > 0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		kind = 8
		a = player.looked_pickup
	elif player.looked_workbench != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		kind = 9
	elif player.looked_course_box != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		kind = 10
		var dg := get_tree().get_first_node_in_group("disc_golf")
		var e: Dictionary = dg.my_entry() if dg else {}
		a = 0 if dg == null or not dg.round_active else (2 if not e.is_empty() and not e.done and not e.left else 1)
	elif player.looked_sport_spot != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		kind = 11
		a = player.looked_sport_spot.get_instance_id()
	var line_state := Vector4i(kind, a, b, 0)
	if line_state == _last_status:
		return
	_last_status = line_state
	death_label.visible = kind != 0
	match kind:
		1:
			death_label.text = "DOWNED - bleeding out %ds" % a
			if b > 0:
				death_label.text += "\nBeing revived %d%%" % b
		2:
			death_label.text = "You bled out - respawning..."
		3:
			death_label.text = "Hold E to revive"
		4:
			death_label.text = "Reviving %d%%" % b
		5:
			death_label.text = "E  Search %s%s" % [player.looked_container.display_name, "  (empty)" if b == 1 else ""]
		6:
			death_label.text = "E  Talk to %s" % player.looked_talkable.display_name
		7:
			death_label.text = "Using %s  %d%%" % [ItemDB.get_item(player.item_use.net_use_item).get("name", "?"), b]
		8:
			var drops := get_tree().get_first_node_in_group("world_drops")
			death_label.text = "E  Take %s" % (drops.display_name(a) if drops else "")
		9:
			death_label.text = "E  Use %s" % player.looked_workbench.display_name
		10:
			var course := str(player.looked_course_box.get_meta("display_name", "disc golf"))
			death_label.text = ["E  Start a round at %s" % course, "E  Join the round (from hole 1)", "Round in progress - Q for the scorecard"][a]
		11:
			death_label.text = "E  %s" % str(player.looked_sport_spot.get_meta("display_name", ""))


# 0 fine, 1 overweight (slowed, no sprint), 2 stuck.
func _load_state(weight: float) -> int:
	var t := CarryRules.load_tuning()
	var cap := float(t.get("carry_capacity", 60.0))
	if weight >= cap * float(t.get("stuck_ratio", 1.25)):
		return 2
	return 1 if weight > cap else 0


func _nearest_downed_teammate(player: Node) -> Node:
	var range_sq: float = pow(CombatRules.load_tuning().get("revive_range", 2.0), 2)
	var best: Node = null
	for p in get_tree().get_nodes_in_group("players"):
		if p == player or not p.life.is_downed():
			continue
		var d: float = player.global_position.distance_squared_to(p.global_position)
		if d <= range_sq:
			best = p
			range_sq = d
	return best


# Tracked quests (up to 3, D-064): name, current objective (with count) and distance to its marker; plus the boss bar.
func _update_tracker(player: Node) -> void:
	var text := ""
	if _book == null:
		_book = get_tree().get_first_node_in_group("quest_book")
	if _quests == null:
		_quests = get_tree().get_first_node_in_group("quests")
	if _quests and _book:
		var ids: Array[String] = _book.tracked_quests()
		for id: String in ids.slice(0, 3):
			var q: Dictionary = QuestRules.defs()[id]
			var i := QuestRules.current(q, _quests.flags)
			if i >= 0:
				var o: Dictionary = q.objectives[i]
				text += ("\n\n" if text != "" else "") + "%s\n%s" % [q.name, o.text]
				if int(o.get("count", 1)) > 1:
					text += "  (%d / %d)" % [int(_quests.flags.get(str(o.flag), 0)), int(o.count)]
				var at: Vector3 = _quests.objective_position(o)
				if at != Vector3.INF:
					var d: float = player.global_position.distance_to(at)
					text += "\n%s" % ("%.1f km" % (d / 1000.0) if d >= 1000.0 else "%d m" % roundi(d))
	if text != _tracker.text:
		_tracker.text = text
	_tracker.visible = not (_book and _book.visible)
	var boss: Node = null
	var best := 60.0
	for b in get_tree().get_nodes_in_group("bosses"):
		var d: float = b.global_position.distance_to(player.global_position)
		if d < best and not b.health.is_dead():
			best = d
			boss = b
	_boss.visible = boss != null and not (_book and _book.visible)
	if boss:
		var n := clampi(ceili(boss.health.current / boss.health.max_health * 30.0), 0, 30)
		_boss.text = "%s\n%s%s" % [str(boss.display_name).to_upper(), "|".repeat(n), ".".repeat(30 - n)]
