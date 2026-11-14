# Architecture map

Godot 4.7.2 · Forward+ · Jolt physics · 60 Hz physics tick.

| Path | Purpose |
|---|---|
| `project.godot` | Main scene, autoloads `Net`, `Graphics`, `Perf`, `Sfx`, input map |
| `scripts/net/net.gd` | Autoload `Net`: wraps Tube's TubeClient (host/join by lobby code, lifecycle signals). Only file that knows the transport. |
| `data/net/network.json` | Tube app ID, lobby code alphabet, trackers, STUN/TURN servers, signaling timeouts |
| `addons/tube/` | Tube addon (third-party, MIT): WebRTC signaling via public WebTorrent trackers + LAN broadcast |
| `addons/webrtc_native/` | webrtc-native GDExtension (third-party) |
| `server/` | UNUSED old signaling server — delete |
| `tools/release/release.gd` | One-run GitHub release: next alphaX.Y from tags, export Windows + Mac, smoke, zip/split, push, publish |
| `data/release/release.json` | Release settings: repo name, private/public, first version, title, exe name, split size |
| `scripts/main.gd` + `scenes/main.tscn` | Gray-box test level, host/join menu, host spawns/removes players (MultiplayerSpawner replicates) |
| `scripts/player/player.gd` + `scenes/player.tscn` | Player body: host simulates from intents, owner predicts + reconciles, others interpolate |
| `scripts/rules/movement_rules.gd` | Pure movement math (no nodes) shared by host and predicting client; wading + swimming (D-047) |
| `scripts/data/data_loader.gd` | JSON loader with schema validation |
| `data/tuning/player_movement.json` | Movement tuning numbers |
| `scripts/net/net_clock.gd` | NetClock (in main.tscn): host tick, replicated; client "view tick" for lag compensation |
| `scripts/rules/combat_rules.gd` | Pure combat math: aim dir, ray vs capsule, melee arc, friendly-fire scaling, combat tuning loader |
| `scripts/data/weapon_db.gd` + `data/weapons/weapons.json` | Weapon definitions by string ID, validated per kind (gun / melee) |
| `data/tuning/combat.json` | Health, friendly fire, respawn, rewind limit, switch time, dummy stats, loadout |
| `scripts/combat/combat_world.gd` | "Combat" node: host hit resolution (rewind + test + walls), damage, tracer/hit-marker RPCs |
| `scripts/combat/weapon_holder.gd` | Player child "Weapons": slots, ammo, reload, attack timing (host); local feedback mirror (client) |
| `scripts/combat/health.gd` | Health node, host-only damage, replicated `current` |
| `scripts/combat/life_state.gd` | Player child "Life": ALIVE / DOWNED / DEAD, bleed-out timer, revive progress (host), replicated |
| `scripts/combat/position_history.gd` | Per-hittable ring of past positions by tick |
| `scripts/combat/training_dummy.gd` + `scenes/training_dummy.tscn` | Test targets; moving one is a pure function of tick |
| `scripts/player/viewmodel.gd` | Placeholder first-person pistol/bat, kick + swing |
| `scripts/fx/tracer_pool.gd` | Pooled bullet tracers |
| `scripts/ui/hud.gd` | Crosshair, HP, weapon/ammo, hit marker, death notice |
| `scripts/rules/zombie_brain.gd` | Pure zombie decisions: WANDER → INVESTIGATE → CHASE → ATTACK, timers |
| `scripts/data/enemy_db.gd` + `data/enemies/enemies.json` | Enemy definitions by string ID, validated |
| `data/tuning/zombies.json` | Spawning: enemy id, cell cap, interval, spawn distances, perception rate, corpse time |
| `scripts/ai/zombie.gd` + `scenes/zombie.tscn` | Pooled zombie: host perception/brain/nav/swipe + hit history; client interpolation |
| `scripts/ai/zombie_director.gd` | "Zombies" node: pool (pool_size), per-cell cap, spawns only in cells near players, despawns in unloaded cells, host_noise() |
| `scripts/ai/nav_region.gd` | Runtime navmesh bake — now only used by the test yard (main map cells carry prebaked navmeshes) |
| `scripts/net/snapshot_buffer.gd` | Client-side interpolation ring for host-owned objects (zombies) |
| `data/items/items.json` + `scripts/data/item_db.gd` | Item definitions by ID: name, category (weapon/ammo/aid/food/junk), weight, value |
| `data/loot/loot_tables.json` + `scripts/data/loot_db.gd` | Loot tables by ID: rolls, weighted entries (item "" = nothing) |
| `data/tuning/inventory.json` | Carry capacity, overweight/stuck thresholds, interact range, starting items |
| `scripts/rules/inventory.gd` / `carry_rules.gd` / `loot_rules.gd` | Pure: item counts + weight; overweight speed/sprint, ammo weightless; loot rolling |
| `scripts/inventory/inventory_holder.gd` | Player child "Inventory": host-owned, replicated `net_items`, cached weight |
| `scripts/inventory/loot_container.gd` + `scenes/loot_container.tscn` | Shared container: lazy roll, open/take/take-all/close RPCs validated by host |
| `scripts/ui/inventory_ui.gd` / `loot_ui.gd` | Inventory screen (Tab/I) and container window; controls built in code |
| `data/map/import_config.json` | Cell name, address/center lat-lon, radius, source + output paths, OSM endpoints |
| `tools/map_import/fetch_osm.tscn` | Pipeline step 1 (needs internet): geocode, download OSM buildings + roads (square, half-size radius_m) → `data/map/source/` |
| `tools/map_import/fetch_elevation.tscn` + `tiff_reader.gd` | Pipeline step 2 (needs internet): USGS 3DEP elevation GeoTIFF for the same square; pure float-TIFF reader |
| `tools/map_import/build_cells.tscn` | Pipeline step 3: the import config area in 256 m cells (30×20 since D-048), built 3 rows at a time → `world/generated/cells/` (cell_x_z.scn full detail + navmesh, cell_x_z_far.scn shell, index.json, shared materials) |
| `tools/map_import/building_looks.gd` + `footprint_shape.gd` | Building looks for build_cells: class/look/roof picks from `data/art/building_looks.json`, wall ShaderMaterials; oriented-rectangle footprint geometry for gable roofs |
| `shaders/building_wall.gdshader` | Generated-building walls: tiled photo texture + lap lines + procedural windows (UV/UV2/COLOR contract in its header) |
| `tools/assets/fetch_textures.tscn` | Asset step (needs internet): downloads the approved Poly Haven textures in `data/art/textures.json` → `assets/textures/<key>/{albedo,normal,arm}.jpg` + manifest |
| `tools/map_import/street_looks.gd` | Street looks for build_cells (D-043): road surface by OSM tag/kind, centre lines, sidewalk kinds from `data/art/streets.json`; ground, street-surface and shingled-roof materials |
| `shaders/street_surface.gdshader` + `shaders/ground.gdshader` | Roads/sidewalks/curbs: world-tiled photo texture, slab joints, worn lane lines (contract in header); terrain: grass texture with anti-tiling blend |
| `tools/assets/list_polyhaven.tscn` | Read-only helper (needs internet): lists matching Poly Haven textures/models with exact sizes → `tests/_look/polyhaven_list.txt`, for approving download lists |
| `tools/map_import/vegetation_builder.gd` + `tree_mesh.gd` | Instanced scatter for build_cells: vegetation (D-043, `data/art/vegetation.json`) and street clutter (D-044, `data/art/clutter.json`): generated low-poly trees + reduced-LOD Poly Haven shrubs/stumps/trunks/grass → `world/generated/vegetation/`; per-cell MultiMeshes in 64 m blocks (visibility ranges) + simple colliders |
| `tools/assets/fetch_models.tscn` | Asset step (needs internet): downloads the approved Poly Haven glTFs in `data/art/models.json` → `assets/models/<key>/` + manifest (model textures imported at 1K) |
| `tools/map_import/car_mesh.gd` | Generated low-poly wreck cars (D-044) for the clutter builder |
| `tools/map_import/water_builder.gd` + `shaders/water.gdshader` | Lakes/ponds/rivers for build_cells (D-047, `data/map/water.json`): carves the terrain, WaterBed collider (layer 16, skipped by the navmesh), water surface mesh + swim collider (layer 32), far-shell water |
| `tools/landmarks/build_yanney_park.tscn` + `landmark_kit.gd` + `yanney_*.gd` | Generated landmark scenes for Yanney Park (D-047) from `data/landmarks/yanney_park.json` → `world/landmarks/yanney_*.scn` + `data/landmarks/yanney_plants.json` (run before build_cells) |
| `tools/landmarks/build_archway.tscn` + `archway.gd` | The Archway over I-80 (D-049) from `data/landmarks/archway.json` → `world/landmarks/archway.scn`: towers, span, museum rooms, 25 loot containers + Evan placed via `LandmarkKit.place()` (run before build_cells) |
| `tools/landmarks/build_chillers_hq.tscn` + `chillers_hq.gd` | Chillers HQ in the UNK student union (D-053) from `data/landmarks/chillers_hq.json` → `world/landmarks/chillers_hq.scn`: union shell, lounge, grow room, throne room, camp, 12 loot containers, Meekachu + Chillers |
| `tools/landmarks/build_kearney_high.tscn` + `kearney_high.gd` + `kearney_high_rooms.gd` | Kearney High (D-055) from `data/landmarks/kearney_high.json` → `world/landmarks/kearney_high.scn`: full school interior, 22 loot containers, Wren + Hunter NPCs, 38 enemy spawn markers (group lair_spawns) |
| `tools/landmarks/build_kenwood.tscn` + `kenwood.gd` + `kenwood_rooms.gd` | Kenwood Elementary (D-078) from `data/landmarks/kenwood.json` → `world/landmarks/kenwood.scn`: real footprint (rotated 25.54°), gym + cafeteria halls, 31 furnished rooms, 19 loot containers, 8 shambler markers, playgrounds |
| `tools/landmarks/build_centennial_pool.tscn` + `centennial_pool.gd` | Drained Centennial pool (D-078) from `data/landmarks/centennial_pool.json` → `world/landmarks/centennial_pool.scn`: sunk basin (depth profile + zero-depth beach, ground hole), deck, bathhouse, fence, junk, 7 loot, 2 deep-end shamblers |
| `tools/landmarks/landmark_parts.gd` | Data-driven parts shared by the D-079 generators: masses, outlines, walls, floors, stairs, stepped seating rows, props, signs, lights, loot containers, lair markers |
| `tools/landmarks/build_<id>.tscn` + `<id>.gd` for big_apple, merryman, cope_stadium, rv_park, country_club | The five D-079 landmarks from `data/landmarks/<id>.json` → `world/landmarks/<id>.scn` (exterior + interior + loot + enemies; RV park = raider camp). Site sources in `data/landmarks/source/five_pois_osm.json` |
| `tools/map_import/ground_paint.gd` | D-080: build_cells paints a landmark's `ground_paint` polygons/paths (the country club's greens, tees, fairways, bunkers, cart paths from `data/landmarks/country_club_paint.json`) onto the terrain triangles, one mesh per layer per cell |
| `scripts/world/ground_props.gd` | D-080: the country club's `CourseProps` node - hole flags and tee signs as MultiMeshes + Label3Ds, each dropped onto the ground with a ray when its cell loads. Visual only, no golf gameplay |
| `shaders/wild_flowers.gdshader` | Overgrown flower beds/weeds on generated landmarks: stems + petal heads cut out of each vertical quad |
| `tests/hitch_test.tscn` | Frame-spike hunt: fast run across the park + tower-deck spin, logs frames > 25 ms and WorldStreamer.slow_events |
| `tests/coop_test.tscn` | Two-player check: hosts, spawns a 2nd game process that joins via the real lobby, drives both by RPC |
| `tools/map_import/build_world_map.tscn` + `data/map/world_map.json` | Renders the players' map picture (D-048) -> `world/generated/map/world_map.res` + `.json` (area, labels) |
| `scripts/ui/world_map_ui.gd` | Full-screen map on M: zoom/pan, labels, you/teammates/Bonk markers |
| `tests/big_map_test.tscn` | Streams UNK/downtown/Archway/east edge with perf numbers, opens the M map |
| `scripts/world/atmosphere.gd` | "Atmosphere" node in main.tscn: applies `data/art/atmosphere.json` (sky, sun, fog, tonemap) at start |
| `scripts/visual/character_animator.gd` | CharacterAnimator (presentation only, D-045): rigged Quaternius model by ID from `data/art/character_models.json`, clip picked from speed/attacking/dead/armed/crouched/health drop, per-slot weapon meshes, first-person mode; used as the Body of zombies, players and Bonk and as the local first-person Arms |
| `scripts/rules/survival_rules.gd` | Pure hunger/thirst + item-use math (D-046), tuning in `data/tuning/survival.json`, item effects in items.json "use" |
| `scripts/player/needs.gd` + `item_use.gd` | Player children: PlayerNeeds (host drain, starving damage, low = no sprint) and ItemUse (quick-use keys, host-validated timed use) |
| `scripts/inventory/world_drops.gd` + `scripts/rules/drop_rules.gd` | "Drops" node: dropped items as host-validated world pickups (D-046), per-cell cap, saved as `drops`; tuning `data/tuning/drops.json` |
| `scripts/inventory/workbench.gd` + `scenes/workbench.tscn` + `scripts/ui/crafting_ui.gd` | Bunker workbench (D-046): crafting window, host-validated instant crafts |
| `data/crafting/recipes.json` + `scripts/data/recipe_db.gd` + `scripts/rules/crafting_rules.gd` | Recipes by ID (needs/gives item stacks), validated; pure have/need checks |
| `tools/map_import/build_cell.tscn` | SUPERSEDED single-cell builder (old 400 m neighbourhood); not used |
| `scripts/world/height_field.gd` | Pure: elevation grid → game-space height (centre = y 0), flat landmark pads |
| `scripts/world/cell_grid.gd` | Pure: cell ↔ position maths, square rings; rectangular map area from the import config (D-048) |
| `scripts/world/world_streamer.gd` + `data/map/streaming.json` | "World" node: streams full cells (3×3 around players; host: all players + Bonk) and far shells (to view distance) |
| `scripts/world/map_projection.gd` | Pure lat/lon ↔ metres (+X east, -Z north) shared by importer and landmark loader |
| `data/map/landmarks.json` + `scripts/world/landmark_loader.gd` | Hand-built landmark scenes placed by lat/lon at the terrain height from the cell index; replace OSM buildings, punch ground holes, flatten their lot (terrain_pad). Always loaded |
| `world/landmarks/*.tscn` | Bonk's house, bunker: editable boxes, merged at load by `scripts/world/static_mesh_merger.gd` |
| `scenes/test_yard.tscn` | Old gray-box yard with training dummies (aim/lag-comp testing) |
| `tests/*.tscn` | Run directly: combat/zombie logic checks, tracker probe, zombie smoke test (hosts the real level), Bonk follow/stuck test |
| `data/companions/bonk.json` + `scripts/rules/companion_brain.gd` | Bonk's tuning; pure FOLLOW / COMBAT decisions (move, run, fire, melee timers) |
| `data/npcs/<id>.json` + `scripts/ai/resident_npc.gd` + `scenes/resident_npc.tscn` | Stationary talkable NPCs (Evan, D-049): can't fight or be hurt, host barks/greets, faces nearby players, tinfoil hat |
| `data/effects/effects.json` + `scripts/rules/effect_rules.gd` + `scripts/player/active_effects.gd` | Chem effects (D-052): pure add/tick/comedown/mods; Player child "Effects" (host-run, net_effects synced) → Health.damage_mult, Needs.drain_mult, move speed, local tint + FOV |
| `data/quests/quests.json` + `scripts/rules/quest_rules.gd` + `scripts/quests/quest_director.gd` | Main/side quests (D-054): pure status/current/watched/requires from party flags; "Quests" node (host-owned flags, synced, saved; reach/have checks, rewards, toasts) |
| `scripts/ui/quest_book_ui.gd` | Quest book on J: active / completed / story-ahead lists, summary, objectives, reward, Track on HUD (HUD tracker + map diamond) |
| `scripts/ai/lair_director.gd` + `data/tuning/lairs.json` | Placed enemies + bosses at landmark markers (D-055): pooled zombie bodies change type via net_enemy; wake/sleep by distance; kill counters + boss flags into quests; boss drops |
| `scripts/ai/bonk.gd` + `scenes/bonk.tscn` | Spawned by the host at session start (Main → NPCs via NpcSpawner, D-050). Bonk: host perception, nav follow, shooting/melee via CombatWorld, self-revive, barks; client interpolation |
| `data/dialogue/*.json` (bonk, evan, meekachu + chillers) + `scripts/data/dialogue_db.gd` | Barks by context + conversation trees by ID, merged from FILES, validated (choices/cost_fail must point at real nodes); node `give` + choice `cost` = gifts/trades |
| `scripts/dialogue/dialogue_director.gd` | "Dialogue" node: host runs one conversation at a time with any talkable NPC, gifts/trades, broadcasts lines/barks |
| `scripts/ui/subtitle_ui.gd` | Subtitles for players near Bonk; reply buttons for the talker |
| `scripts/save/save_format.gd` | Pure save shape: VERSION, new_world, migrate, check, clean_items, slug |
| `scripts/save/save_store.gd` | World save files in user://saves (list/read/write atomically/delete) |
| `scripts/save/player_identity.gd` | Per-install random player ID (user://player_id.txt) |
| `scripts/save/save_director.gd` + `data/tuning/save.json` | "Saves" node: host opens/starts a world, restores containers/Bonk/characters, autosave/F5/quit saves |
| `scripts/ui/world_picker.gd` | Menu world list + new world name |
| `scripts/ui/debug_overlay.gd` | F3 perf readout from the Perf autoload; over-budget values red |
| `data/tuning/graphics.json` + `scripts/rules/graphics_rules.gd` | Quality tiers, GPU auto-pick rules, perf budgets, log settings; pure tier pick |
| `scripts/settings/graphics.gd` | Autoload `Graphics`: applies the tier (window, environment, sun, cameras), remembers choice |
| `scripts/perf/perf_monitor.gd` | Autoload `Perf`: per-second samples vs budgets; host CSV log in user://perf |
| `scripts/ui/settings_menu.gd` | Esc settings panel: graphics tier |
| `diary/` | STATE, DECISIONS, FAILED logs |

## Network flow
Connect: host `Net.host()` → Tube announces on trackers, gets 5-char code, is peer 1. Client `Net.join(code)` →
Tube exchanges WebRTC offer/answer via trackers (or LAN broadcast) → direct data channels. No server we host.
Client → host: `Player._send_intent(seq, move, flags, yaw, pitch)` every tick, unreliable-ordered.
Host: validates sender + values, queues, simulates ≤2 intents/tick per player.
Host → clients: `Sync` (MultiplayerSynchronizer) replicates `net_position/yaw/pitch/crouched/ack_seq` at 20 Hz.
Owner: shifts by (host pos − predicted pos at ack_seq). Others: interpolate 100 ms behind.

## Combat flow
Intent carries buttons (fire/reload/slot) + view tick. Host, per intent: WeaponHolder.host_step → edge-detect
fire → CombatWorld.host_fire/host_melee → rewind every hittable to clamp(view tick) → CombatRules test →
world raycast for walls → Health.apply_damage (friendly fire scaled) → hit marker RPC to shooter, tracer RPC to all.
Collision layers: 1 = world, 2 = players + dummies + zombies + Bonk, 4 = interactables (containers are 1 + 4, Bonk 2 + 4).

## Loot flow
Local player raycasts 10x/s for a container (layers 1+4) → HUD "E Search X" → E → `request_open` RPC to host →
host checks alive + in range, rolls loot table once, adds viewer → `_show_contents` RPC → LootUI. Take/Take All →
host moves items into the player's InventoryHolder (`net_items` replicates) → pushes new contents to all viewers.
Reload pulls the weapon's `ammo_item` from the inventory.
Death: Health hits 0 → LifeState DOWNED → teammate holds E in range (Player._host_try_revive per intent) →
revived at revive_health, or bleeds out → DEAD → respawn timer → Player._respawn.

## Dialogue flow
Player looks at an NPC (group "talkable": Bonk, Evan) → HUD "E Talk to <display_name>" → E →
`Dialogue.request_talk(npc_path)` RPC to host → host checks alive, in range, nobody else talking, takes the NPC's
dialogue_tree → `_show_line` to all with the NPC's position + subtitle_range (SubtitleUI shows it if near; talker
gets reply buttons) → `request_choice(i)` → next node … until an `end` node, Esc (`request_leave`), or the talker
walks away / goes down. Barks: npc.bark(context) on the host → random line from DialogueDB → `_show_bark` to all (heard within range).

## Save flow
Menu WorldPicker → Main._on_host_pressed → Saves.host_open_world (read file or new) → Net.host → session up →
Saves.host_start (containers, Bonk) → host body spawns → host_player_spawned (own ID). Client joins →
register_player(uid) RPC → host applies that character. Saves.host_save: capture players/containers/Bonk → SaveStore.write.

## Streaming flow
Pipeline (on a PC with internet): fetch_osm → fetch_elevation → build_cells. Runtime: World node reads
cells/index.json; boots 3×3 cells around the bunker synchronously; every 0.25 s gathers positions (host: all
"players" bodies; client: own player), loads missing near cells on a thread (one instantiated per frame; the cell
under a body loads immediately), frees cells 2+ rings away, shows far shells elsewhere to the tier's view distance.
Each cell has its own NavigationRegion3D (tile-aligned bake, border 2 m) so paths cross cell edges.
| `tools/landmarks/build_pois.tscn` + `poi_building.gd` | Small walk-in POIs (D-056) from tagged OSM buildings per `data/landmarks/pois.json` → `world/landmarks/poi_NN.scn` + `data/map/pois.json` (same shape as landmarks.json; merged by the loader and build_cells). Run before build_cells |
| `LootSpots` in generated cells | Streamed LootContainers (`streamed = true`, no mesh/Sync) on cars, trash, porches, yard junk; host restores/stores contents via SaveDirector.world on cell load/unload (D-056) |
| `scripts/player/meepo_rider.gd` + `scripts/rules/meepo_rules.gd` + `data/tuning/meepo.json` | Meepo longboard (D-057): ride toggle (B), ride movement tuning, battery drain/recharge near group meepo_chargers, knock-off on big hits |
| `shaders/outfit.gdshader` | Recolours Quaternius UBC bodies by dominant bone region (skin/shirt/pants/shoes) for the ubc_* player models (D-058) |
| `tools/landmarks/build_downtown_bars.tscn` + `bar_building.gd` + `bar_furniture.gd` | The four downtown bars (D-059) from `data/landmarks/downtown_bars.json`: shell, ground floor + basement/upstairs, partitions, stairs, furniture, loot, raider spawn markers, the rest of each merged block as closed storefronts, and the raider barricades / lookouts / camp (D-062). Landmarks in `data/map/landmarks.json` |
| Raiders (D-060/D-061) | Enemy defs with `faction: "raiders"` on the shared enemy body (`scripts/ai/zombie.gd`: `team` from faction; bodies of another faction are targets like players). Placed by LairDirector at the bars' markers; every raider kill counts as `kills_raider`. Looks: `raider_*` models in `character_models.json` with primitive `gear` props on bones (CharacterAnimator). Barks in `data/dialogue/raiders.json` |
| `scripts/ui/start_menu.gd` | Start screen (D-063) on Main's `$UI/Menu`: Singleplayer (offline peer via `Net.start_offline`), Multiplayer (host/join), Settings, Controls (InputMap), Quit; shares the WorldPicker (with Delete) |
| `scripts/ui/status_bar.gd` + `hud_icons.gd` | HUD icon chips (D-066): HP, food, water, Meepo battery, active effects; icons drawn in code |
| `scripts/ui/minimap.gd` | Rotating top-left minimap (D-067) from the pipeline map texture + markers |
| `scripts/ui/pause_menu.gd` + `controls_list.gd` | Esc pause menu (D-068): resume, settings, controls, Save & Quit (`Net.leave_to_menu`), quit; solo freezes the tree |
| `scripts/ui/name_prompt.gd` | "Name your survivor" prompt (D-081): opened by the host for a character with no name in this world; sends `Player.submit_name` |
| `scripts/player/name_tag.gd` + `data/tuning/name_tags.json` | Floating name over other players' bodies (D-081): billboard Label3D, fades out past `visible_m`, hidden by walls |
| `scripts/rules/name_rules.gd` | Pure: cleans a typed character name (printable, spaces collapsed, max length) |
| Disc golf (D-069) | `data/discgolf/courses.json` (holes in map coords, from UDisc), `discs.json` (speed/glide/turn/fade), `centennial_trees.json` (traced trees, planted by build_cells via the landmark `plants_file`), `data/tuning/disc_golf.json`. Pure: `scripts/rules/disc_flight_rules.gd` (flight step, canopy, reach table), `disc_golf_rules.gd` (basket catch/spit/bounce, scores, rewards). `scripts/discgolf/disc_course.gd` = landmark scene `scenes/disc_course.tscn` (baskets, tee pads, signs, course box; snaps to ground on cell load). `scripts/discgolf/disc_golf_director.gd` = Main's `DiscGolf` node (rounds, host flight simulation, scorecard sync, rewards, zombie keep-out). `scripts/player/disc_thrower.gd` = Player's `Disc` child (3 / hold LMB / Z X wheel / F). `scripts/ui/disc_golf_hud.gd` (bag, power + reach mark, hole line, scorecard on Q) |
| Disc golf group play (D-076) | Host `DiscGolfDirector`: `turn` (one thrower; `DiscGolfRules.next_thrower` = tee order first, then furthest from the basket; `tee_order` = best last-hole score first, ties random), group moves tee to tee when everyone is `out`, `wind` (`DiscFlightRules.next_wind`, Flight.wind in the drag) shifting every `wind_shift_s`. `scripts/discgolf/disc_tracer.gd` + `shaders/disc_tracer.gdshader` (ribbon built once per throw, revealed by `progress`, faces the camera). `scripts/discgolf/ace_replay.gd` (AceReplay: own camera, letterbox overlay; locks players via `Player.cutscene`, host sets `Health.invulnerable` and `zombie.gd` static `frozen`; HUD hides itself while `cutscene`). DiscGolfHud: turn banner, wind rose, basket marker; Minimap: tee pad. Basket top band = its own glowing surface |
| Street signs (D-070) | `tools/map_import/street_signs.gd` + `data/art/street_signs.json`: build_cells finds every intersection of two named OSM streets, puts a post + two green blades on a clear corner (MultiMeshes) with the names as Label3D pairs (culled at 45 m), in each cell's `StreetSigns` node. `build_world_map` also writes `streets` (shortened names every ~220 m with their angle) into the map meta; the Minimap draws them upright |
| Map west to Cottonmill (D-072) | `data/map/import_config.json` area x_min −3840, 40 × 20 cells. `data/map/water.json` `overrides`: inside a rect, OSM's lake carve is replaced by traced rings at the OSM water level (Cottonmill Lake's east arm, D-073) |
| Cottonmill DGC (D-073) | Second course in `data/discgolf/courses.json` (+ `cottonmill_trees.json`), landmark `cottonmill_dgc` using the same `scenes/disc_course.tscn` (DiscCourse picks its course by landmark key). Holes may have `label` ("9½") and `via` (dogleg points). One round at a time across courses |
| Drop Zone (D-074) | `data/dropzone/dropzone.json` (layout, landmark-local) + `data/tuning/drop_zone.json`. `tools/landmarks/build_dropzone.tscn` → `world/landmarks/dropzone.scn` (building, 32 bays, range + targets + nets, putting course, 4 courts). Runtime root `scripts/dropzone/drop_zone.gd` adds `Range` (DzRange), `Putting` (DzPutting), `Court0..3` (DzCourt) and the E spots (group `sport_spots`). Pure: `scripts/rules/golf_ball_rules.gd`, `pickleball_rules.gd`. Input: Player child `Sport` (`scripts/player/sport_input.gd`). HUD: `scripts/ui/drop_zone_hud.gd`. Shared ball playback: `scripts/dropzone/ball_playback.gd` |
| Sound (D-077) | Autoload `Sfx` (`scripts/audio/sfx.gd`): plays events by string ID, tuning in `data/audio/sounds.json`, files = every .ogg/.wav/.mp3 in `assets/audio/<event id>/` (random variant). Makes buses SFX + Ambience (volumes in user://settings.cfg [audio], sliders in SettingsMenu). Pooled voices (24 × 3D + 6 × 2D, oldest stolen, out-of-range 3D skipped). Child `Ambience` (`scripts/audio/ambience.gd`): wind loop + random distant one-shots. Hooks: WeaponHolder (own fire/dry/reload/swing), CombatWorld `_fx_shot` / `_fx_melee_hit` (others' shots, melee hits), Player `_fx_hurt` + jump/land in `_simulate` (local), ItemUse `_fx_use` (start / cancel), DiscGolfDirector (basket hits timed along the flight path) |
