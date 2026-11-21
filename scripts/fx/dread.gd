# Dread — what being hunted feels like, for the local player only (D-114). Main child "Dread", group "dread".
#   Heartbeat: a beat (Sfx "heartbeat") that speeds up as the nearest zombie closes in (ScareRules).
#   Muffled hearing: a low-pass on the SFX and Ambience buses when one is right on you or has you.
#   Grabbed: desaturation + dark vignette (shaders/dread.gdshader) while a zombie within grab_m is swinging at you.
#   Camera shake: trauma from a scream nearby (heard_scream, called by Zombie._fx_scream) or from getting hit;
#     applied as camera h/v offset + roll, which nothing else uses.
#   Night eyes: hands DayNight.night() to EyeShine twice a second.
# Scans zombies 10x a second (only ones with scare traits, alive and standing). Presentation only.
# Depends on: ScareRules, ZombieScare (tuning), EyeShine, Sfx, shaders/dread.gdshader; groups "local_player",
# "hittable", "daynight".
class_name Dread
extends Node

const SHADER := preload("res://shaders/dread.gdshader")
const SCAN_S := 0.1

var nearest := INF  # metres to the nearest zombie (read by tests)
var grab := 0.0  # 0..1
var trauma := 0.0  # 0..1
var muffle := 0.0  # 0..1

var _t: Dictionary
var _scan := 0.0
var _night_in := 0.0
var _beat_in := 0.0
var _grab_target := 0.0
var _last_hp := INF
var _filters: Array[AudioEffectLowPassFilter] = []
var _buses := PackedInt32Array()
var _rect: ColorRect
var _mat: ShaderMaterial
var _cam: Camera3D
var _time := 0.0


func _ready() -> void:
	add_to_group("dread")
	_t = ZombieScare.load_tuning()
	for bus: String in ["SFX", "Ambience"]:
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			continue
		var f := AudioEffectLowPassFilter.new()
		f.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(i, f)
		AudioServer.set_bus_effect_enabled(i, AudioServer.get_bus_effect_count(i) - 1, false)
		_filters.append(f)
		_buses.append(i)
	var layer := CanvasLayer.new()
	layer.layer = 0  # under the HUD (layer 1)
	add_child(layer)
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect.material = _mat
	_rect.visible = false
	layer.add_child(_rect)


func _exit_tree() -> void:
	for k in _buses.size():
		var i := _buses[k]
		for e in AudioServer.get_bus_effect_count(i):
			if AudioServer.get_bus_effect(i, e) == _filters[k]:
				AudioServer.remove_bus_effect(i, e)
				break


# A zombie screamed at `at` (every peer runs this from the scream RPC).
func heard_scream(at: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		add_trauma(ScareRules.scream_shake(cam.global_position.distance_to(at), _t.scream))


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func _process(delta: float) -> void:
	_time += delta
	var d: Dictionary = _t.dread
	_scan -= delta
	if _scan <= 0.0:
		_scan = SCAN_S
		_rescan(d)
	_night_in -= delta
	if _night_in <= 0.0:
		_night_in = 0.5
		var dn := get_tree().get_first_node_in_group("daynight")
		if dn:
			EyeShine.set_night(dn.night(), _t.eyes)
	# heartbeat
	var interval := ScareRules.heartbeat_interval(nearest, d)
	if interval > 0.0:
		_beat_in -= delta
		if _beat_in <= 0.0:
			_beat_in = interval
			Sfx.play_local("heartbeat")
	else:
		_beat_in = 0.0
	# grabbed + muffled
	grab = move_toward(grab, _grab_target, delta / maxf(float(d.grab_fade_s), 0.01))
	muffle = maxf(ScareRules.muffle(nearest, d), grab)
	var on := muffle > 0.01
	var hz := ScareRules.muffle_cutoff(muffle, d)
	for k in _filters.size():
		_filters[k].cutoff_hz = hz
		if AudioServer.is_bus_effect_enabled(_buses[k], _effect_index(k)) != on:
			AudioServer.set_bus_effect_enabled(_buses[k], _effect_index(k), on)
	_rect.visible = grab > 0.01
	if _rect.visible:
		_mat.set_shader_parameter("vignette", grab * float(d.vignette))
		_mat.set_shader_parameter("desaturate", grab * float(d.desaturate))
	_shake(delta, d)


func _rescan(d: Dictionary) -> void:
	var me := get_tree().get_first_node_in_group("local_player")
	nearest = INF
	_grab_target = 0.0
	if me == null or me.health.is_dead():
		_last_hp = INF
		return
	if me.health.current < _last_hp - 0.5:
		add_trauma(float(d.hit_shake))
	_last_hp = me.health.current
	var grab_sq := float(d.grab_m) * float(d.grab_m)
	var from: Vector3 = me.global_position
	var best := INF
	for n in get_tree().get_nodes_in_group("hittable"):
		if not n.has_method("has_scare") or not n.has_scare() or not n.net_active or n.health.is_dead() \
				or n.net_pose == ZombieScare.Pose.DOWN:
			continue
		var dsq: float = from.distance_squared_to(n.global_position)
		if dsq < best:
			best = dsq
		if dsq < grab_sq and n.net_attacking:
			_grab_target = 1.0
	nearest = sqrt(best) if best < INF else INF


func _shake(delta: float, d: Dictionary) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != _cam:
		if _cam and is_instance_valid(_cam):
			_reset(_cam)
		_cam = cam
	trauma = maxf(trauma - float(d.shake_decay) * delta, 0.0)
	if _cam == null:
		return
	if trauma <= 0.0:
		if _cam.h_offset != 0.0 or _cam.v_offset != 0.0 or _cam.rotation.z != 0.0:
			_reset(_cam)
		return
	var a := trauma * trauma
	var off := float(d.shake_max_offset_m) * a
	_cam.h_offset = off * sin(_time * 37.0) * cos(_time * 23.0)
	_cam.v_offset = off * sin(_time * 41.0 + 1.7)
	_cam.rotation.z = deg_to_rad(float(d.shake_max_roll_degrees)) * a * sin(_time * 29.0 + 0.6)


func _reset(cam: Camera3D) -> void:
	cam.h_offset = 0.0
	cam.v_offset = 0.0
	cam.rotation.z = 0.0


func _effect_index(k: int) -> int:
	var i := _buses[k]
	for e in AudioServer.get_bus_effect_count(i):
		if AudioServer.get_bus_effect(i, e) == _filters[k]:
			return e
	return 0
