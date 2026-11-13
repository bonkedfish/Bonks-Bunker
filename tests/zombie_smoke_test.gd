# ZombieSmokeTest — loads the real level, hosts a session, waits, then prints what the zombies are doing
# (count, AI state, distance walked from their spawn, distance to the host player). Run this scene directly.
# Depends on: scenes/main.tscn, Net autoload, ZombieDirector, ZombieBrain.
extends Node


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	main.world_picker.choose_new("zz test")  # throwaway world, deleted below
	main._on_host_pressed()
	await get_tree().create_timer(3.0).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("SMOKE: hosting = %s, lobby = %s" % [multiplayer.has_multiplayer_peer() and multiplayer.is_server(), Net.lobby_code])
	var me := get_tree().get_first_node_in_group("local_player")
	var bunker := main.get_node("Landmarks/bonk_bunker")
	var house := main.get_node("Landmarks/bonk_house")
	print("SMOKE MAP: player at %s, bunker at %s, house at %s, on floor = %s" % [
		me.global_position.snapped(Vector3.ONE * 0.1), bunker.global_position.snapped(Vector3.ONE * 0.1),
		house.global_position.snapped(Vector3.ONE * 0.1), me.is_on_floor()])
	var vp := get_viewport()
	print("SMOKE GFX: tier %s (%s) on %s, render scale %.2f, msaa %d, fxaa %s, cam far %.0f, sun shadows %s" % [
		Graphics.tier, Graphics.choice, Graphics.adapter_name, vp.scaling_3d_scale, vp.msaa_3d,
		vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA, me.get_node("Head/Camera3D").far, main.get_node("Sun").shadow_enabled])
	var remembered: String = Graphics.choice
	Graphics.set_choice("low")
	await get_tree().process_frame
	print("SMOKE GFX LOW: render scale %.2f, fxaa %s, cam far %.0f, sun shadows %s, max fps %d" % [vp.scaling_3d_scale,
		vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA, me.get_node("Head/Camera3D").far, main.get_node("Sun").shadow_enabled, Engine.max_fps])
	Graphics.set_choice(remembered)
	print("SMOKE PERF: frame %.1f ms, draw calls %d, VRAM %d MB, log %s (%s)" % [Perf.frame_ms, int(Perf.draw_calls), int(Perf.vram_mb),
		Perf.log_path, FileAccess.file_exists(Perf.log_path)])
	# Talking to Bonk end to end (same RPCs the E key and reply buttons use).
	var bonk_node := get_tree().get_first_node_in_group("bonk")
	var dialogue := get_tree().get_first_node_in_group("dialogue")
	var subs := get_tree().get_first_node_in_group("subtitles")
	print("SMOKE BONK: at %s, %.1f m from player, HP %d" % [bonk_node.global_position.snapped(Vector3.ONE * 0.1),
		bonk_node.global_position.distance_to(me.global_position), bonk_node.health.current])
	dialogue.request_talk.rpc_id(1, get_tree().get_first_node_in_group("bonk").get_path())
	await get_tree().create_timer(0.5).timeout
	print("SMOKE TALK: choosing=%s text=%s" % [subs.choosing, subs._label.text.left(60)])
	dialogue.request_choice.rpc_id(1, 0)
	await get_tree().create_timer(0.5).timeout
	print("SMOKE TALK: reply caption: %s: %s" % [subs._name.text, subs._label.text.left(60)])
	await get_tree().create_timer(2.0).timeout
	print("SMOKE TALK: then: %s: %s  (%d options)" % [subs._name.text, subs._label.text.left(80), subs._choices.get_child_count()])
	dialogue.request_leave.rpc_id(1)
	subs.end_conversation()
	await get_tree().create_timer(0.5).timeout
	print("SMOKE TALK: left conversation, choosing=%s" % subs.choosing)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().create_timer(10.0).timeout
	print("SMOKE BONK: after 10 s: %.1f m from player, state=%s" % [
		bonk_node.global_position.distance_to(me.global_position), CompanionBrain.State.keys()[bonk_node.brain.state]])
	var director := get_tree().get_first_node_in_group("zombie_director")
	var player := get_tree().get_first_node_in_group("local_player")
	_report("after 15 s", director, player)
	print("SMOKE: making a pistol-sized noise (35 m) at the player")
	director.host_noise(player.global_position, 35.0)
	await get_tree().create_timer(4.0).timeout
	_report("4 s after noise", director, player)
	await get_tree().create_timer(16.0).timeout
	_report("20 s after noise", director, player)

	# Looting end to end: walk up to the ammo crate, open it, take everything (same RPCs the UI uses).
	var crate := main.get_node("Landmarks/bonk_bunker/Loot/AmmoCrate")
	print("SMOKE LOOT: before: items=%s weight=%.1f" % [player.inventory.net_items, player.inventory.weight])
	crate.request_open.rpc_id(1)  # too far away: host must refuse
	await get_tree().create_timer(0.5).timeout
	print("SMOKE LOOT: open from spawn refused = %s" % (not get_tree().get_first_node_in_group("loot_ui").visible))
	player.global_position = crate.global_position + Vector3(-1.2, 0.1, 0)
	await get_tree().create_timer(0.5).timeout
	crate.request_open.rpc_id(1)
	await get_tree().create_timer(0.5).timeout
	print("SMOKE LOOT: crate rolled %s, loot window open = %s" % [crate.contents, get_tree().get_first_node_in_group("loot_ui").visible])
	crate.request_take_all.rpc_id(1)
	await get_tree().create_timer(0.5).timeout
	print("SMOKE LOOT: after take all: items=%s weight=%.1f crate left=%d" % [player.inventory.net_items, player.inventory.weight, crate.net_remaining])
	SaveStore.delete(main.saves.world_slug)
	await get_tree().create_timer(20.0).timeout
	get_tree().quit()


func _report(label: String, director: Node, player: Node) -> void:
	print("SMOKE [%s]: active zombies = %d, player HP = %s, player state = %s" % [
		label, director.active_count, str(player.health.current),
		["ALIVE", "DOWNED", "DEAD"][player.life.net_state]])
	for z in director.get_children():
		if not z.net_active:
			continue
		print("SMOKE:   %s state=%s walked=%.1f m  to_player=%.1f m" % [
			z.name, ZombieBrain.State.keys()[z.brain.state],
			z.global_position.distance_to(z._home),
			z.global_position.distance_to(player.global_position)])
