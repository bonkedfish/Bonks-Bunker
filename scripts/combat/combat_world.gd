# CombatWorld — host-side attack resolution with lag compensation, plus combat feedback RPCs.
# Hittables (group "hittable") provide: health: Health, team: StringName, hit_radius: float,
# hit_capsule_at(tick: float) -> Vector4(feet xyz, height). The host rewinds each target to the
# shooter's view tick (clamped by NetClock), tests the shot with CombatRules, and checks walls with a
# world-only raycast. Clients never decide hits.
# Depends on: CombatRules, NetClock (group "net_clock"), TracerPool (group "tracers"), HUD (group "hud"),
#             ZombieDirector (group "zombie_director", for attack noise), Sfx (shot / melee-hit sounds, D-077).
extends Node3D

const WORLD_MASK := 1   # static level geometry
const VISUAL_MASK := 3  # world + bodies, for local tracer endpoints only

var _tuning: Dictionary
var _clock: NetClock
var _tracers: Node
var _hud: Node
var _director: Node


func _ready() -> void:
	add_to_group("combat_world")
	_tuning = CombatRules.load_tuning()
	_clock = get_tree().get_first_node_in_group("net_clock")
	_tracers = get_tree().get_first_node_in_group("tracers")
	_hud = get_tree().get_first_node_in_group("hud")
	_director = get_tree().get_first_node_in_group("zombie_director")


# --- host ----------------------------------------------------------------------

# hits_teammates = false: the shot passes through the shooter's own team (Bonk). Returns true on a kill/down.
func host_fire(shooter: Node, weapon: Dictionary, origin: Vector3, dir: Vector3, view_tick: float,
		hits_teammates: bool = true) -> bool:
	var tick := _clock.rewind_tick(view_tick, _tuning.max_rewind_seconds)
	_make_noise(origin, weapon)
	var best_dist := _world_distance(origin, dir, float(weapon.range))
	var best: Node = null
	for target in get_tree().get_nodes_in_group("hittable"):
		if target == shooter or target.health.is_dead() or (not hits_teammates and target.team == shooter.team):
			continue
		var cap: Vector4 = target.hit_capsule_at(tick)
		var d := CombatRules.ray_vs_capsule(origin, dir, best_dist,
			Vector3(cap.x, cap.y, cap.z), target.hit_radius, cap.w)
		if d >= 0.0 and d < best_dist:
			best_dist = d
			best = target
	var killed := false
	if best:
		killed = _damage(best, shooter, float(weapon.damage))
	_fx_shot.rpc(origin, origin + dir * best_dist, shooter.peer_id, "%s_fire" % weapon.get("id", "gun"))
	return killed


func host_melee(shooter: Node, weapon: Dictionary, origin: Vector3, dir: Vector3, view_tick: float,
		hits_teammates: bool = true) -> bool:
	var tick := _clock.rewind_tick(view_tick, _tuning.max_rewind_seconds)
	_make_noise(origin, weapon)
	var killed := false
	var hit_any := false
	var hit_at := Vector3.ZERO
	for target in get_tree().get_nodes_in_group("hittable"):
		if target == shooter or target.health.is_dead() or (not hits_teammates and target.team == shooter.team):
			continue
		var cap: Vector4 = target.hit_capsule_at(tick)
		var base := Vector3(cap.x, cap.y, cap.z)
		if not CombatRules.melee_hits_capsule(origin, dir, float(weapon.range), float(weapon.arc_degrees),
				base, target.hit_radius, cap.w):
			continue
		if _world_blocked(origin, base + Vector3.UP * cap.w * 0.5):
			continue
		killed = _damage(target, shooter, float(weapon.damage)) or killed
		if not hit_any:
			hit_any = true
			hit_at = base + Vector3.UP * cap.w * 0.6
	if hit_any:
		_fx_melee_hit.rpc(hit_at, "%s_hit" % weapon.get("id", "melee"))
	return killed


func _damage(target: Node, shooter: Node, base_damage: float) -> bool:
	var amount := CombatRules.scaled_damage(base_damage, target.team == shooter.team,
		_tuning.friendly_fire_multiplier)
	var killed: bool = target.health.apply_damage(amount, shooter.peer_id)
	if shooter.peer_id > 0:  # AI shooters (Bonk, peer 0) get no hit marker
		_hit_confirm.rpc_id(shooter.peer_id, killed)
	return killed


# Attacks are noisy (D-017): zombies within the weapon's noise_radius come to investigate.
func _make_noise(origin: Vector3, weapon: Dictionary) -> void:
	if _director:
		_director.host_noise(origin, float(weapon.get("noise_radius", 0.0)))
	var lairs := get_tree().get_first_node_in_group("lair_director")
	if lairs:
		lairs.host_noise(origin, float(weapon.get("noise_radius", 0.0)))


func _world_distance(origin: Vector3, dir: Vector3, max_dist: float) -> float:
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_dist, WORLD_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return max_dist if hit.is_empty() else origin.distance_to(hit.position)


func _world_blocked(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# --- feedback --------------------------------------------------------------------

# Owning client draws its own tracer instantly from the gun muzzle (not authoritative, visual only).
func local_tracer(player: Node, weapon: Dictionary) -> void:
	var origin: Vector3 = player.eye_position()
	var dir: Vector3 = -player.camera.global_basis.z
	var end := origin + dir * float(weapon.range)
	var query := PhysicsRayQueryParameters3D.create(origin, end, VISUAL_MASK, [player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		end = hit.position
	_tracers.show_tracer(player.muzzle_position(), end)


@rpc("authority", "call_local", "unreliable")
func _fx_shot(from: Vector3, to: Vector3, shooter_peer: int, sound: String) -> void:
	if shooter_peer == multiplayer.get_unique_id():
		if not multiplayer.is_server():
			return  # already drawn and heard locally (local_tracer, WeaponHolder.client_step)
		var me := get_tree().get_first_node_in_group("local_player")
		if me:
			from = me.muzzle_position()
		Sfx.play_local(sound)
	else:
		Sfx.play_at(sound, from)
	_tracers.show_tracer(from, to)


@rpc("authority", "call_local", "unreliable")
func _fx_melee_hit(at: Vector3, sound: String) -> void:
	Sfx.play_at(sound, at)


@rpc("authority", "call_local", "reliable")
func _hit_confirm(killed: bool) -> void:
	if _hud:
		_hud.show_hit_marker(killed)
