# ParseCheck — loads the given scripts and prints whether each compiled (parse errors print above). Dev helper.
extends Node

const PATHS := ["res://scripts/rules/disc_flight_rules.gd", "res://scripts/rules/disc_golf_rules.gd",
	"res://scripts/discgolf/disc_course.gd", "res://scripts/discgolf/disc_golf_director.gd",
	"res://scripts/player/disc_thrower.gd", "res://scripts/ui/disc_golf_hud.gd", "res://scripts/player/player.gd",
	"res://scripts/ui/hud.gd", "res://scripts/ui/minimap.gd", "res://scripts/ui/controls_list.gd",
	"res://scripts/ai/zombie_director.gd", "res://tests/disc_golf_test.gd",
	"res://scripts/rules/golf_ball_rules.gd", "res://scripts/rules/pickleball_rules.gd", "res://scripts/dropzone/ball_playback.gd",
	"res://scripts/dropzone/drop_zone.gd", "res://scripts/dropzone/dz_range.gd", "res://scripts/dropzone/dz_putting.gd",
	"res://scripts/dropzone/dz_court.gd", "res://scripts/player/sport_input.gd", "res://scripts/ui/drop_zone_hud.gd",
	"res://scripts/player/item_use.gd", "res://tools/map_import/street_signs.gd", "res://tools/map_import/build_cells.gd",
	"res://tools/map_import/build_world_map.gd", "res://tools/map_import/water_builder.gd", "res://tools/landmarks/build_dropzone.gd",
	"res://scripts/ui/disc_golf_hud.gd", "res://scripts/discgolf/disc_tracer.gd", "res://scripts/discgolf/ace_replay.gd",
	"res://scripts/ai/zombie.gd", "res://scripts/combat/health.gd",
	"res://scripts/audio/sfx.gd", "res://scripts/audio/ambience.gd", "res://scripts/combat/weapon_holder.gd",
	"res://scripts/combat/combat_world.gd", "res://scripts/data/weapon_db.gd", "res://scripts/ui/settings_menu.gd"]


func _ready() -> void:
	var lines := PackedStringArray()
	for p: String in PATHS:
		var s := load(p) as Script
		lines.append("%s %s" % ["OK  " if s != null and s.can_instantiate() else "FAIL", p])
		print("PARSE: " + lines[-1])
	var f := FileAccess.open("res://tests/_look/parse_check.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	get_tree().quit()
