# WeaponHolder — a player's three weapon slots (D-087: gun1, gun2, melee - whatever gear is equipped there, Fists
# when a slot is empty), magazines, reload and attack timing. Each slot's effective stats come from
# GearRules.weapon_stats(instance) (rarity, perk, mods, condition). Rounds in the magazine and wear live in the
# instance: the host keeps live copies and writes them back (host_flush) when you switch, reload, every few seconds
# and before saves / equipment changes.
# Spare ammo is the weapon's `ammo_item` in the player's inventory (D-025); reloading takes it from there.
# Host: host_step() runs once per processed intent, with that intent's buttons, aim and view tick.
#       It is the only place attacks happen (through CombatWorld). Slot/ammo/reload replicate as net_*, plus the
#       held weapon's mesh (net_mesh) and whether it's a gun (net_armed) so other players see it in hand.
# Owning client: client_step() mirrors attack timing locally for instant feedback only (kick, tracer, swing).
# Semi-auto fire and reload are edge-triggered on the host (held flag 0 -> 1), so one dropped packet doesn't lose a
# click; "auto" guns fire while held. Thrown (Golden Ace, D-088): one throw in the air at a time.
# Sounds (D-077): the local player hears their own fire / dry click / reload / swing here; others hear shots and
# melee hits through CombatWorld.
# Depends on: WeaponDB, GearRules, CombatRules, CombatWorld (group "combat_world"), Viewmodel, InventoryHolder,
# parent Player, Sfx.
class_name WeaponHolder
extends Node

const FLAG_FIRE := 8
const FLAG_RELOAD := 16
const FLAG_SLOT2 := 32
const FLAG_SLOT3 := 128
const SLOT_NAMES := ["gun1", "gun2", "melee"]
const FLUSH_SECONDS := 5.0

# Replicated host -> clients.
var net_slot := 0
var net_mag := 0
var net_reserve := 0
var net_reloading := false
var net_mesh := ""
var net_armed := false

var viewmodel: Node3D  # set by Player
var inventory: InventoryHolder:  # set by Player
	set(value):
		inventory = value
		if inventory and not inventory.changed.is_connected(_rebuild):
			inventory.changed.connect(_rebuild)
		_rebuild()

var _defs: Array[Dictionary] = [{}, {}, {}]
var _uids := PackedInt64Array([0, 0, 0])
var _mags := PackedInt32Array([0, 0, 0])
var _wear := PackedFloat32Array([0.0, 0.0, 0.0])
var _slot := 0
var _sim_time := 0.0
var _next_attack := 0.0
var _reload_end := 0.0
var _swing_at := -1.0
var _fire_prev := false
var _reload_prev := false
var _switch_time := 0.25
var _flush_left := FLUSH_SECONDS
var _flushing := false
var _fists: Dictionary = {}

var _local_time := 0.0
var _local_next_attack := 0.0
var _local_fire_prev := false
var _local_reloading_prev := false

var _combat: Node
@onready var _player: CharacterBody3D = get_parent()


func _ready() -> void:
	_switch_time = CombatRules.load_tuning().get("switch_time", 0.25)
	_fists = WeaponDB.get_weapon("fists")
	_combat = get_tree().get_first_node_in_group("combat_world")
	_rebuild()


func weapon_in_slot(slot: int) -> Dictionary:
	return _defs[slot] if slot >= 0 and slot < _defs.size() else {}


# Slot index from intent flags.
static func slot_of_flags(flags: int) -> int:
	if (flags & FLAG_SLOT3) != 0:
		return 2
	return 1 if (flags & FLAG_SLOT2) != 0 else 0


static func slot_flags(slot: int) -> int:
	return FLAG_SLOT3 if slot == 2 else (FLAG_SLOT2 if slot == 1 else 0)


# Starting kit / respawn: every equipped gun's magazine full.
func reset_loadout() -> void:
	_rebuild()
	for i in _defs.size():
		_mags[i] = int(_defs[i].get("mag_size", 0.0))
	_reload_end = 0.0
	_swing_at = -1.0
	if multiplayer.is_server():
		host_flush()
	_publish()


# Saves before D-087 kept magazines here: the first one belongs to gun1 (the old pistol slot).
func host_load_mags(mags: Array) -> void:
	if mags.size() > 0 and _uids[0] != 0:
		_mags[0] = clampi(int(mags[0]), 0, int(_defs[0].get("mag_size", 0.0)))
		host_flush()
	_publish()


func host_save_mags() -> Array:
	host_flush()
	return []


# Writes live magazines and wear back into the equipped instances (one inventory publish).
func host_flush() -> void:
	if inventory == null or _flushing:
		return
	var changes := {}
	for i in _uids.size():
		if _uids[i] == 0:
			continue
		var g: Dictionary = inventory.get_gear(int(_uids[i]))
		if g.is_empty():
			continue
		var cond := maxf(float(g.get("cond", 1.0)) - _wear[i], 0.0)
		if int(g.get("mag", 0)) != _mags[i] or _wear[i] > 0.0:
			var c := g.duplicate(true)
			c.mag = _mags[i]
			c.cond = snappedf(cond, 0.0001)
			changes[int(_uids[i])] = c
		_wear[i] = 0.0
	_flushing = true
	inventory.host_set_gears(changes)
	_flushing = false


# Equipment or instance data changed: re-read the three slots.
func _rebuild() -> void:
	if _flushing:
		return
	for i in SLOT_NAMES.size():
		var g: Dictionary = inventory.equipped(SLOT_NAMES[i]) if inventory else {}
		var uid := int(g.get("uid", 0))
		if uid != _uids[i]:
			_uids[i] = uid
			_mags[i] = int(g.get("mag", 0)) if uid != 0 else 0
			_wear[i] = 0.0
			if i == _slot:
				_reload_end = 0.0
				_swing_at = -1.0
		_defs[i] = GearRules.weapon_stats(g) if uid != 0 else _fists
		if _defs[i].has("mag_size"):
			_mags[i] = mini(_mags[i], int(_defs[i].mag_size))
	if viewmodel and _player and _player.is_local and _player.has_method("show_held_weapon"):
		_player.show_held_weapon()
	_publish()


# --- host ----------------------------------------------------------------------

func host_step(flags: int, aim_yaw: float, aim_pitch: float, view_tick: float, delta: float, dead: bool) -> void:
	_sim_time += delta
	var fire_down := (flags & FLAG_FIRE) != 0
	var reload_down := (flags & FLAG_RELOAD) != 0
	var fire_pressed := fire_down and not _fire_prev
	var reload_pressed := reload_down and not _reload_prev
	_fire_prev = fire_down
	_reload_prev = reload_down
	_flush_left -= delta
	if _flush_left <= 0.0:
		_flush_left = FLUSH_SECONDS
		host_flush()
	if dead:
		return

	var want_slot := slot_of_flags(flags)
	if want_slot != _slot:
		host_flush()
		_slot = want_slot
		_reload_end = 0.0
		_swing_at = -1.0
		_next_attack = maxf(_next_attack, _sim_time + _switch_time)

	var w := _defs[_slot]
	if _reload_end > 0.0 and _sim_time >= _reload_end:
		_finish_reload(w)
	var eye: Vector3 = _player.eye_position()
	var dir := CombatRules.aim_direction(aim_yaw, aim_pitch)
	var kind := str(w.get("kind", ""))

	if kind == "gun":
		var trigger := fire_down if bool(w.get("auto", false)) else fire_pressed
		if reload_pressed:
			_start_reload(w)
		if trigger and _reload_end == 0.0 and _sim_time >= _next_attack:
			if _mags[_slot] <= 0:
				if fire_pressed:
					if _player.is_local:
						Sfx.play_local(_sound(w, "dry"))
					_start_reload(w)
			else:
				_mags[_slot] -= 1
				_wear[_slot] += float(w.get("wear", 0.0))
				_next_attack = _sim_time + float(w.fire_interval)
				_combat.host_fire(_player, w, eye, dir, view_tick)
				if _player.is_local:
					viewmodel.kick()
	elif kind == "thrown":
		if fire_pressed and _sim_time >= _next_attack and not _combat.host_has_throw(_player):
			_next_attack = _sim_time + float(w.fire_interval)
			_combat.host_throw(_player, w, eye, dir)
			if _player.is_local:
				Sfx.play_local(_sound(w, "swing"))
	else:
		if fire_pressed and _sim_time >= _next_attack and _swing_at < 0.0:
			_swing_at = _sim_time + float(w.windup)
			_next_attack = _sim_time + float(w.swing_interval)
			if _player.is_local:
				viewmodel.swing(float(w.windup))
				Sfx.play_local(_sound(w, "swing"))
		if _swing_at >= 0.0 and _sim_time >= _swing_at:
			_swing_at = -1.0
			_combat.host_melee(_player, w, eye, dir, view_tick)
			_wear[_slot] += float(w.get("wear", 0.0))
	_publish()


func _start_reload(w: Dictionary) -> void:
	if _reload_end > 0.0 or _mags[_slot] >= int(w.get("mag_size", 0)) or _spare_ammo(w) <= 0:
		return
	_reload_end = _sim_time + float(w.reload_time)
	if _player.is_local:
		Sfx.play_local(_sound(w, "reload"))


func _finish_reload(w: Dictionary) -> void:
	var took := inventory.host_remove(str(w.ammo_item), int(w.mag_size) - _mags[_slot]) if inventory else 0
	_mags[_slot] += took
	_reload_end = 0.0
	host_flush()


func _spare_ammo(w: Dictionary) -> int:
	return inventory.count(str(w.get("ammo_item", ""))) if inventory else 0


func _publish() -> void:
	var w := _defs[_slot]
	net_slot = _slot
	net_mag = _mags[_slot]
	net_reserve = _spare_ammo(w)
	net_reloading = _reload_end > 0.0
	net_mesh = str(w.get("mesh", ""))
	net_armed = str(w.get("kind", "")) == "gun"


# --- owning client (feedback only, never damage) ----------------------------------

func client_step(flags: int, slot: int, delta: float, dead: bool) -> void:
	_local_time += delta
	var fire_down := (flags & FLAG_FIRE) != 0
	var pressed := fire_down and not _local_fire_prev
	_local_fire_prev = fire_down
	if net_reloading and not _local_reloading_prev and not weapon_in_slot(net_slot).is_empty():
		Sfx.play_local(_sound(weapon_in_slot(net_slot), "reload"))
	_local_reloading_prev = net_reloading
	var w := weapon_in_slot(slot)
	if w.is_empty() or dead or _local_time < _local_next_attack:
		return
	var kind := str(w.get("kind", ""))
	if not (pressed or (fire_down and kind == "gun" and bool(w.get("auto", false)))):
		return
	if kind == "gun":
		if net_slot == slot and net_mag <= 0 and not net_reloading and pressed:
			Sfx.play_local(_sound(w, "dry"))
		if net_reloading or net_mag <= 0 or net_slot != slot:
			return
		_local_next_attack = _local_time + float(w.fire_interval)
		viewmodel.kick()
		Sfx.play_local(_sound(w, "fire"))
		_combat.local_tracer(_player, w)
	elif kind == "thrown":
		_local_next_attack = _local_time + float(w.fire_interval)
		Sfx.play_local(_sound(w, "swing"))
	else:
		_local_next_attack = _local_time + float(w.swing_interval)
		viewmodel.swing(float(w.windup))
		Sfx.play_local(_sound(w, "swing"))


# Sound event id for this weapon (D-077): "<weapon id>_<what>", e.g. pistol_9mm_fire.
static func _sound(w: Dictionary, what: String) -> String:
	return "%s_%s" % [w.get("id", "gun"), what]
