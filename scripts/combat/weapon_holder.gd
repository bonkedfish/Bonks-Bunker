# WeaponHolder — a player's weapon slots (from the combat.json loadout), magazines, reload and attack timing.
# Spare ammo is the weapon's `ammo_item` in the player's inventory (D-025); reloading takes it from there.
# Host: host_step() runs once per processed intent, with that intent's buttons, aim and view tick.
#       It is the only place attacks happen (through CombatWorld). Slot/ammo/reload replicate as net_*.
# Owning client: client_step() mirrors attack timing locally for instant feedback only (kick, tracer, swing).
# Fire and reload are edge-triggered on the host (held flag 0 -> 1), so one dropped packet doesn't lose a click.
# Sounds (D-077): the local player hears their own fire / dry click / reload / swing here; others hear shots and
# melee hits through CombatWorld.
# Depends on: WeaponDB, CombatRules, CombatWorld (group "combat_world"), Viewmodel, InventoryHolder, parent Player, Sfx.
class_name WeaponHolder
extends Node

const FLAG_FIRE := 8
const FLAG_RELOAD := 16
const FLAG_SLOT2 := 32

# Replicated host -> clients.
var net_slot := 0
var net_mag := 0
var net_reserve := 0
var net_reloading := false

var viewmodel: Node3D  # set by Player
var inventory: InventoryHolder  # set by Player

var _weapons: Array[Dictionary] = []
var _mags := PackedInt32Array()
var _slot := 0
var _sim_time := 0.0
var _next_attack := 0.0
var _reload_end := 0.0
var _swing_at := -1.0
var _fire_prev := false
var _reload_prev := false
var _switch_time := 0.25

var _local_time := 0.0
var _local_next_attack := 0.0
var _local_fire_prev := false
var _local_reloading_prev := false

var _combat: Node
@onready var _player: CharacterBody3D = get_parent()


func _ready() -> void:
	var tuning := CombatRules.load_tuning()
	_switch_time = tuning.get("switch_time", 0.25)
	for id in tuning.get("loadout", []):
		_weapons.append(WeaponDB.get_weapon(str(id)))
	_mags.resize(_weapons.size())
	_combat = get_tree().get_first_node_in_group("combat_world")
	reset_loadout()


func weapon_in_slot(slot: int) -> Dictionary:
	return _weapons[slot] if slot >= 0 and slot < _weapons.size() else {}


func reset_loadout() -> void:
	for i in _weapons.size():
		_mags[i] = int(_weapons[i].get("mag_size", 0.0))
	_reload_end = 0.0
	_swing_at = -1.0
	_publish()


# Saves (D-037): rounds left in each slot's magazine.
func host_save_mags() -> Array:
	return Array(_mags)


func host_load_mags(mags: Array) -> void:
	for i in mini(mags.size(), _mags.size()):
		_mags[i] = clampi(int(mags[i]), 0, int(_weapons[i].get("mag_size", 0.0)))
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
	if dead or _weapons.is_empty():
		return

	var want_slot := 1 if (flags & FLAG_SLOT2) != 0 else 0
	if want_slot != _slot and want_slot < _weapons.size():
		_slot = want_slot
		_reload_end = 0.0
		_swing_at = -1.0
		_next_attack = maxf(_next_attack, _sim_time + _switch_time)

	var w := _weapons[_slot]
	if _reload_end > 0.0 and _sim_time >= _reload_end:
		_finish_reload(w)
	var eye: Vector3 = _player.eye_position()
	var dir := CombatRules.aim_direction(aim_yaw, aim_pitch)

	if w.kind == "gun":
		if reload_pressed:
			_start_reload(w)
		if fire_pressed and _reload_end == 0.0 and _sim_time >= _next_attack:
			if _mags[_slot] <= 0:
				if _player.is_local:
					Sfx.play_local(_sound(w, "dry"))
				_start_reload(w)
			else:
				_mags[_slot] -= 1
				_next_attack = _sim_time + float(w.fire_interval)
				_combat.host_fire(_player, w, eye, dir, view_tick)
				if _player.is_local:
					viewmodel.kick()
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
	_publish()


func _start_reload(w: Dictionary) -> void:
	if _reload_end > 0.0 or _mags[_slot] >= int(w.mag_size) or _spare_ammo(w) <= 0:
		return
	_reload_end = _sim_time + float(w.reload_time)
	if _player.is_local:
		Sfx.play_local(_sound(w, "reload"))


func _finish_reload(w: Dictionary) -> void:
	var took := inventory.host_remove(str(w.ammo_item), int(w.mag_size) - _mags[_slot]) if inventory else 0
	_mags[_slot] += took
	_reload_end = 0.0


func _spare_ammo(w: Dictionary) -> int:
	return inventory.count(str(w.get("ammo_item", ""))) if inventory else 0


func _publish() -> void:
	net_slot = _slot
	net_mag = _mags[_slot] if _slot < _mags.size() else 0
	net_reserve = _spare_ammo(_weapons[_slot]) if _slot < _weapons.size() else 0
	net_reloading = _reload_end > 0.0


# --- owning client (feedback only, never damage) ----------------------------------

func client_step(flags: int, slot: int, delta: float, dead: bool) -> void:
	_local_time += delta
	var fire_down := (flags & FLAG_FIRE) != 0
	var pressed := fire_down and not _local_fire_prev
	_local_fire_prev = fire_down
	if net_reloading and not _local_reloading_prev and not weapon_in_slot(net_slot).is_empty():
		Sfx.play_local(_sound(weapon_in_slot(net_slot), "reload"))
	_local_reloading_prev = net_reloading
	if dead or not pressed or _local_time < _local_next_attack:
		return
	var w := weapon_in_slot(slot)
	if w.is_empty():
		return
	if w.kind == "gun":
		if net_slot == slot and net_mag <= 0 and not net_reloading:
			Sfx.play_local(_sound(w, "dry"))
		if net_reloading or net_mag <= 0 or net_slot != slot:
			return
		_local_next_attack = _local_time + float(w.fire_interval)
		viewmodel.kick()
		Sfx.play_local(_sound(w, "fire"))
		_combat.local_tracer(_player, w)
	else:
		_local_next_attack = _local_time + float(w.swing_interval)
		viewmodel.swing(float(w.windup))
		Sfx.play_local(_sound(w, "swing"))


# Sound event id for this weapon (D-077): "<weapon id>_<what>", e.g. pistol_9mm_fire.
static func _sound(w: Dictionary, what: String) -> String:
	return "%s_%s" % [w.get("id", "gun"), what]
