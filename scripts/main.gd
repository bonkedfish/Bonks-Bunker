# Main — boots the level, runs the start screen (StartMenu: singleplayer offline / host / join, D-063), and (host only) spawns and
# removes player bodies as peers connect and leave; spawns Bonk once per session (NpcSpawner), so clients only ever
# have the host's Bonk. MultiplayerSpawners replicate them to clients.
# Hosting opens the world picked in the menu through the Saves node (D-037).
# Depends on: Net autoload, scenes/player.tscn, SaveDirector ("Saves"), WorldPicker, PlayerIdentity.
extends Node3D

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const BONK_SCENE := preload("res://scenes/bonk.tscn")
const PauseMenu := preload("res://scripts/ui/pause_menu.gd")

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
	var pause := PauseMenu.new()
	pause.name = "Pause"
	$UI.add_child(pause)
	menu.play_offline.connect(_on_singleplayer_pressed)
	menu.host.connect(_on_host_pressed)
	menu.join.connect(_on_join_pressed)
	Net.session_started.connect(_on_session_started)
	Net.session_failed.connect(_on_session_failed)
	Net.session_ended.connect(_on_session_ended)
	Net.lobby_code_changed.connect(_on_lobby_code_changed)
	multiplayer.peer_connected.connect(_spawn_player)
	multiplayer.peer_disconnected.connect(_remove_player)


func _unhandled_input(event: InputEvent) -> void:
	if menu.visible or $UI/InventoryUI.visible or $UI/LootUI.visible or $UI/CraftingUI.visible or $UI/WorldMapUI.visible or $UI/QuestBookUI.visible or $UI/Subtitles.choosing \
			or $UI/Settings.visible or $UI/Pause.visible:
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
	status_label.text = reason


func _on_session_ended() -> void:
	for p in players.get_children() + $NPCs.get_children():
		p.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	status_label.text = "Host ended the session"
	menu.show()


func _spawn_player(id: int) -> void:
	if not multiplayer.is_server() or players.has_node(str(id)):
		return
	# Prefer a landmark's spawn markers (group "player_spawns", e.g. inside Bonk's bunker).
	var holder := get_tree().get_first_node_in_group("player_spawns")
	var points := (holder if holder else spawn_points).get_children()
	var spot: Vector3 = points[players.get_child_count() % points.size()].global_position
	var p := PLAYER_SCENE.instantiate()
	p.name = str(id)
	p.position = spot
	p.net_position = spot
	players.add_child(p, true)
	saves.host_player_spawned(p)


func _remove_player(id: int) -> void:
	if multiplayer.is_server() and players.has_node(str(id)):
		players.get_node(str(id)).queue_free()
