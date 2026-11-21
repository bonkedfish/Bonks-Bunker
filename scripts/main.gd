# Main — boots the level, runs the start screen (StartMenu: singleplayer offline / host / join, D-063), and (host only) spawns and
# removes player bodies as peers connect and leave; spawns Bonk once per session (NpcSpawner), so clients only ever
# have the host's Bonk. MultiplayerSpawners replicate them to clients.
# Hosting opens the world picked in the menu through the Saves node (D-037).
# Also makes "Bikes" (BikeDirector, D-083: the parked motorcycles), "Weather" (WeatherDirector, D-099) and
# "SafeZones" (D-101: where hostiles stay away), "SuitWatcher" (D-104: the man in the suit) and the world-event
# nodes "DayNight", "Bed", "Encounters", "Oddities", "Collectibles" and "RareEvents" (D-105..D-110) on every peer,
# plus "Dread" and "ZombieVoices" (D-114: heartbeat, muffling, shake, grab overlay; zombie groans).
# Any failed, timed-out or ended session reloads Main with a fresh lobby client (Net.leave_to_menu, D-091) and the
# start screen shows why (Net.menu_message).
# Depends on: Net autoload, scenes/player.tscn, SaveDirector ("Saves"), WorldPicker, PlayerIdentity, PauseMenu,
# CharacterCreator, AppearanceRules (a new body starts with a random look, D-096), BikeDirector, WeatherDirector,
# SafeZones, SuitWatcher, DayNight, BunkerBed, EncounterDirector, WorldOddities, CollectibleManager, RareEventDirector,
# Dread, ZombieVoices.
extends Node3D

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const BONK_SCENE := preload("res://scenes/bonk.tscn")
const PauseMenu := preload("res://scripts/ui/pause_menu.gd")
const CharacterCreator := preload("res://scripts/ui/character_creator.gd")

@onready var players: Node3D = $Players
@onready var spawn_points: Node3D = $SpawnPoints
@onready var menu: Control = $UI/Menu
@onready var lobby_label: Label = $UI/LobbyLabel
@onready var saves: Node = $Saves

var code_field: LineEdit:
	get:
		return menu.code_field
var status_label: Label:
	get:
		return menu.status_label
var world_picker: VBoxContainer:
	get:
		return menu.world_picker


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--check-models"):  # release.gd: are the real models in this build? (D-112)
		var problems := ModelCheck.check(self)
		print("MODELS: " + ("OK" if problems.is_empty() else "MISSING\n" + "\n".join(problems)))
		get_tree().quit(0 if problems.is_empty() else 3)
		return
	var pause := PauseMenu.new()
	pause.name = "Pause"
	$UI.add_child(pause)
	var creator := CharacterCreator.new()
	creator.name = "Creator"
	$UI.add_child(creator)  # after Pause: it sees Esc first and keeps the pause menu shut while open
	var bikes := BikeDirector.new()
	bikes.name = "Bikes"
	add_child(bikes)
	var weather := WeatherDirector.new()
	weather.name = "Weather"
	add_child(weather)
	var safe := SafeZones.new()
	safe.name = "SafeZones"
	add_child(safe)
	var watcher := SuitWatcher.new()
	watcher.name = "SuitWatcher"
	add_child(watcher)
	for pair: Array in [[DayNight.new(), "DayNight"], [BunkerBed.new(), "Bed"],
			[EncounterDirector.new(), "Encounters"], [WorldOddities.new(), "Oddities"],
			[CollectibleManager.new(), "Collectibles"], [RareEventDirector.new(), "RareEvents"],
			[Dread.new(), "Dread"], [ZombieVoices.new(), "ZombieVoices"]]:
		var node: Node = pair[0]
		node.name = str(pair[1])  # fixed names: their RPCs need the same path on every peer
		add_child(node)
	menu.play_offline.connect(_on_singleplayer_pressed)
	menu.host.connect(_on_host_pressed)
	menu.join.connect(_on_join_pressed)
	Net.session_started.connect(_on_session_started)
	Net.session_failed.connect(_on_session_failed)
	Net.session_ended.connect(_on_session_ended)
	Net.lobby_code_changed.connect(_on_lobby_code_changed)
	multiplayer.peer_connected.connect(_spawn_player)
	multiplayer.peer_disconnected.connect(_remove_player)
	if Net.menu_message != "":
		status_label.text = Net.menu_message
		Net.menu_message = ""


func _unhandled_input(event: InputEvent) -> void:
	if menu.visible or $UI/InventoryUI.visible or $UI/LootUI.visible or $UI/CraftingUI.visible or $UI/WorldMapUI.visible or $UI/QuestBookUI.visible or $UI/Subtitles.choosing \
			or $UI/Settings.visible or $UI/Pause.visible or $UI/Creator.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.is_pressed() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_host_pressed() -> void:
	if not saves.host_open_world(world_picker.selected_slug(), world_picker.new_world_name()):
		status_label.text = "That save can't be read (see the output log)"
		return
	status_label.text = "Creating lobby..."
	Net.host()


# Singleplayer (D-063): the same host flow on Godot's offline peer - no lobby, no internet.
func _on_singleplayer_pressed() -> void:
	if not saves.host_open_world(world_picker.selected_slug(), world_picker.new_world_name()):
		status_label.text = "That save can't be read (see the output log)"
		return
	Net.start_offline()


func _on_join_pressed() -> void:
	status_label.text = "Connecting..."
	Net.join(code_field.text)


func _on_lobby_code_changed(code: String) -> void:
	lobby_label.text = "Lobby code: %s" % code
	lobby_label.visible = not code.is_empty()


func _on_session_started() -> void:
	menu.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if multiplayer.is_server():
		if $NPCs.get_child_count() == 0:
			var bonk := BONK_SCENE.instantiate()
			bonk.name = "Bonk"
			$NPCs.add_child(bonk, true)
		saves.host_start()
		_spawn_player(1)
	else:
		saves.register_player.rpc_id(1, PlayerIdentity.uid())


func _on_session_failed(reason: String) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Net.leave_to_menu.call_deferred(self, reason)


func _on_session_ended() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Net.leave_to_menu.call_deferred(self, "Lost the connection to the host (they quit, or the network dropped).")


func _spawn_player(id: int) -> void:
	if not multiplayer.is_server() or players.has_node(str(id)):
		return
	# Prefer a landmark's spawn markers (group "player_spawns", e.g. inside Bonk's bunker).
	var holder := get_tree().get_first_node_in_group("player_spawns")
	var points := (holder if holder else spawn_points).get_children()
	var spot: Vector3 = points[players.get_child_count() % points.size()].global_position
	var used := []
	for other in players.get_children():
		used.append(int(other.net_color))
	var p := PLAYER_SCENE.instantiate()
	p.name = str(id)
	p.net_color = PlayerColors.pick(used)  # D-092
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	p.net_look = AppearanceRules.random_look(rng)  # D-096: a saved character's own look replaces it
	p.position = spot
	p.net_position = spot
	players.add_child(p, true)
	saves.host_player_spawned(p)


func _remove_player(id: int) -> void:
	if multiplayer.is_server() and players.has_node(str(id)):
		players.get_node(str(id)).queue_free()
