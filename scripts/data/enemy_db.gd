# EnemyDB — enemy definitions from data/enemies/enemies.json, looked up by string ID and validated.
# Optional per enemy (D-055): scale, tint [r,g,b,a], boss, armed, ranged {damage, range, noise_radius, spread_degrees},
# enrage {below, speed_mult, cooldown_mult}, drops {item: n}, bark_prefix + subtitle_range; faction ("zombies" or
# "raiders", D-060), weapon_slot (prop shown without gun animations), kill_count_as (quest kill counter name).
# Pure: no scene or rendering dependencies. Depends on: DataLoader.
class_name EnemyDB
extends RefCounted

const PATH := "res://data/enemies/enemies.json"
const SCHEMA := {
	"name": TYPE_STRING, "max_health": TYPE_FLOAT, "walk_speed": TYPE_FLOAT, "chase_speed": TYPE_FLOAT,
	"turn_speed": TYPE_FLOAT, "sight_range": TYPE_FLOAT, "sight_fov_degrees": TYPE_FLOAT,
	"close_sense_range": TYPE_FLOAT, "lose_interest_seconds": TYPE_FLOAT, "attack_range": TYPE_FLOAT,
	"attack_reach": TYPE_FLOAT, "attack_windup": TYPE_FLOAT, "attack_cooldown": TYPE_FLOAT,
	"attack_damage": TYPE_FLOAT, "wander_radius": TYPE_FLOAT, "wander_pause": TYPE_FLOAT,
	"models": TYPE_ARRAY,  # CharacterAnimator model IDs (data/art/character_models.json), picked per pool slot
}
const OPTIONAL := ["scale", "tint", "boss", "armed", "ranged", "enrage", "drops", "bark_prefix", "subtitle_range",
	"faction", "weapon_slot", "kill_count_as"]

static var _enemies: Dictionary = {}
static var _loaded := false


static func get_enemy(id: String) -> Dictionary:
	if not _loaded:
		_loaded = true
		var raw := DataLoader.load_json(PATH)
		for key: String in raw:
			var entry: Variant = raw[key]
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var core: Dictionary = entry.duplicate()
			for k: String in OPTIONAL:
				core.erase(k)
			if DataLoader.validate(core, SCHEMA, "%s:%s" % [PATH, key]):
				_enemies[key] = entry
	if not _enemies.has(id):
		push_error("EnemyDB: unknown enemy id '%s'" % id)
		return {}
	return _enemies[id]
