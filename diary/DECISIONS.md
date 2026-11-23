# DECISIONS

Locked unless flagged. Each entry: decision — reason.

- **D-001** Godot 4.7.2, Forward+, Jolt physics (project defaults). — Already set up; Jolt is the stable 3D physics in 4.4+.
- **D-002** Host-authoritative: clients send intents only; host simulates movement and owns all state. — Project spec; stops client cheating, one source of truth.
- **D-003** Owning client predicts its own movement; host acks intent seq; client shifts by error vs its history at that seq. Other players interpolated 100 ms behind. Snapshots 20 Hz, intents 60 Hz. — Movement feels instant at any ping; cheap (no re-simulation).
- **D-004** WebRTC transport now (chosen over "ENet until combat works", 2026-11-08). Godot `WebRTCMultiplayerPeer` in server/client mode = star topology, host <-> each client. Godot maps reliable RPCs/spawns to a reliable channel and unreliable(_ordered) RPCs + synchronizers to unreliable channels. Needs the webrtc-native GDExtension in `addons/webrtc`. — Project spec; avoids a later rewrite of connection handling.
- **D-009** (2026-11-08, replaces D-007) Use the **Tube** addon (koopmyers/tube, MIT) for signaling: public WebTorrent trackers + STUN, host shares a session ID, no server to host and no port forwarding. Tube is star topology (host = server peer), so D-002/D-003 are unchanged. — Your call: zero hosting. Known risks: public trackers can be flaky (use several), Tube tested on Godot 4.5 (we're on 4.7.2), a forum report of tracker 403/TLS errors on 4.6.2, and no TURN so players behind symmetric NATs can fail until a TURN server is added to the TubeContext.
- **D-010** (2026-11-08) Hit detection is lag-compensated: clients send the host tick they are viewing with every intent; host rewinds target hit capsules (≤ max_rewind_seconds) and tests the shot in pure math, with a world raycast for walls. — Your call: "if it's on your crosshair, it hits" without trusting client hit claims.
- **D-011** (2026-11-08) Friendly fire ON, reduced (multiplier in `data/tuning/combat.json`, starts 0.25). — Your call.
- **D-012** (2026-11-08) Ammo: magazine + reload (R) + limited reserve per weapon, from data. — Your call; matches survival ammo scarcity.
- **D-013** (2026-11-08) Melee: arc swing with wind-up, hits every target in a cone in front. — Your call.
- ~~**D-014**~~ (superseded by D-015) Placeholder: respawn at spawn point after `respawn_seconds`.
- **D-015** (2026-11-08) Downed + revive: at 0 HP you're DOWNED (can't move/attack/be targeted), bleed out over `bleed_out_seconds` (30). A living teammate within `revive_range` (2 m) holds E for `revive_seconds` (3) to revive you at `revive_health` (30); bleed-out pauses while being revived. Bleeding out = DEAD, then respawn at spawn point after `respawn_seconds`. All numbers in `data/tuning/combat.json`. — Your call ("yes add that" to recommended option A); fits co-op.
- **D-016** (2026-11-08) First zombie: slow shambler (walks slower than players, dangerous in groups). — Your call.
- **D-017** (2026-11-08) Zombie awareness: sight (cone + line of sight, checked 5x/sec) + sound (weapon `noise_radius`; pistol loud, bat near-silent). They wander → investigate noise → chase what they see → give up after `lose_interest_seconds`. Downed players are ignored. — Your call.
- **D-018** (2026-11-08) Zombie attack: telegraphed swipe (arms raise during wind-up, hit lands only if you're still in reach and in front). — Your call.
- **D-019** (2026-11-08) Spawning: pooled zombies; host keeps up to `cell_cap` active, spawning at points ≥ `min_spawn_distance` from every player and either out of every player's line of sight or ≥ `far_spawn_distance` away (fog). The test yard counts as one cell until the streamed map exists. — Your call (cap) + my call on the far-distance exception, since the open yard has few hidden spots.
- **D-020** (2026-11-08) Zombie movement: runtime-baked navmesh (from group "navmesh_source") + NavigationAgent3D. — Technical; the map pipeline will bake per cell later.
- **D-021** (2026-11-08) Overweight: above `carry_capacity` you can't sprint and move at `overweight_speed_multiplier`; at `stuck_ratio` × capacity you barely move (`stuck_speed_multiplier`). Numbers in `data/tuning/inventory.json`. — Your call.
- **D-022** (2026-11-08) Inventory screen: sorted list with category tabs, weight and value per row (Tab or I). — Your call.
- **D-023** (2026-11-08) Containers are shared: one set of loot per container, host decides who gets each item (first come). — Your call.
- **D-024** (2026-11-08) Ammo is weightless (enforced in CarryRules for category "ammo"). — Your call.
- **D-025** (2026-11-08, my call, veto-able) Gun reserve ammo = that ammo item in your inventory; reload pulls from it. Weapons in the loadout are also inventory items (they have weight). — Makes looted ammo matter.
- **D-026** (2026-11-08, my call, veto-able) Containers roll loot from their loot table the first time anyone opens them; remaining contents are kept per `container_id` (what a save will store). — Saves stay small; no loot rolled for unvisited places.
- **D-027** (2026-11-08, my call, veto-able) Respawning after bleed-out keeps your inventory and magazine as they were (no free ammo, nothing lost). — Simplest; a death penalty can come later.
- **D-028** (2026-11-08) Map: OSM import pipeline (not hand blockout) for the Alpha neighborhood, ~200 m around 810 17th Ave = one cell. Steps run inside Godot on your PC (the build sandbox can't reach OSM): `tools/map_import/fetch_osm.tscn` downloads raw data → `build_cell.tscn` generates the cell. — Your call; same pipeline will do the whole city.
- **D-029** (2026-11-08) Bonk's house: generic 1-story layout for now, to be matched to the real house later. Bunker: medium multi-room (main room, bunks, storage, generator) under the backyard. Both are hand-built landmark layers placed by `data/map/landmarks.json`; the generator skips OSM buildings they replace, so re-imports never overwrite them. — Your call.
- **D-030** (2026-11-08, updates D-029) Bonk's house = OSM way 1056927162, west side of 17th Ave — confirmed by your street photo of 810 17th Ave (garage-forward L outline matches). Exterior rebuilt to match the photo (3-car garage, stone, porch columns, gables, beige siding, white fence, driveway). Interior still a guessed ranch layout until you describe the rooms. Porch made flush with the floor (no steps) so players can walk onto it. Bunker moved back so its hatch is in the fenced yard. — Your info + my layout call.
- **D-031** (2026-11-08) Bonk fights alongside the group: host-run AI follows the nearest player, shoots zombies he sees (pistol, infinite reserve ammo, some spread, reaction delay), bats them up close. His shots and swings never hit teammates. Teleports to the group if left > `teleport_distance` behind. — Your call.
- **D-032** (2026-11-08) Bonk is essential: at 0 HP he's downed; he gets himself up after `self_revive_seconds` (20) or sooner if a player holds E. Never dies. Zombies target him like a player; players' friendly fire hurts him at 25%. — Your call.
- **D-033** (2026-11-08) Dialogue = own JSON system: `data/dialogue/bonk.json` holds barks (context → lines) and trees (nodes with speaker, text, choices → next, end), validated by DialogueDB. — Your call; fits data-driven rule.
- **D-034** (2026-11-08) Co-op talk: one player talks to Bonk at a time (E); they pick replies with the mouse; everyone within `subtitle_range` sees Bonk's lines and the chosen reply as subtitles. — Your call.
- **D-035** (2026-11-08) Players and Bonk stay solid to each other; when a player walks into Bonk (within `dodge_trigger_distance`, moving toward him) he sidesteps away from their path, or the other side, or backs out ahead of them (stairwells). Spots must be on the navmesh with a clear knee-height ray. Tuning in bonk.json. — Your call (B over pass-through / leave as is).
- **D-036** (2026-11-08) Caption style like Fallout 4: speaker name over the line, centred low, white text with dark outline, no box; one speaker at a time (player's reply first, then Bonk); reply options as plain outlined text, amber on hover. — Your call (reference screenshot).
- **D-037** (2026-11-09) Saves: host-only, one JSON file per named world in `user://saves/` (menu lists worlds + "New world"). Autosave every `autosave_seconds` (300) + F5 quicksave + on window close; a leaving player's character is captured when they disconnect. The host's save holds every player's character, matched by a per-install random ID (`user://player_id.txt`) the client sends on join; characters resume where they saved (new ones get the starting kit in the bunker). Stored: version, containers opened (what's left), each character's position/health/items/magazines, Bonk's position/health. Not stored: zombies (respawn). Downed/dead saved at revive health. Writes are temp-file + rename with a `.bak` of the previous save. — Your calls: autosave+quicksave, host keeps everyone, several worlds, resume where saved.
- **D-038** (2026-11-09) Quality tiers Low/Medium/High in `data/tuning/graphics.json` (render scale + FSR, shadows on/distance/atlas, MSAA, FXAA, SSAO on High only, view distance, FPS cap). First launch auto-picks from the GPU (integrated → Low, RTX/RX 6000+/Arc → High, other discrete → Medium); Esc settings menu has Auto/Low/Medium/High, saved per PC in user://settings.cfg. Perf report: budgets (frame 16.7 ms, 2000 draw calls, 3M primitives, 2 GB RAM, 3 GB VRAM) turn F3 values red; the host logs a CSV sample per second to user://perf (newest 10 kept). — Your calls: standard set, auto + menu, budgets + log.
- **D-039** (2026-11-09) Streaming map: ~2 km square around the house (8×8 cells of 256 m), real USGS 3DEP elevation (map-center height = y 0), full-detail cells within 1 ring of a player (3×3), low-detail shells (one mesh/draw call per cell) out to the view distance. Pipeline (re-runnable): fetch_osm (bbox) → fetch_elevation (USGS) → build_cells (terrain, buildings, roads, spawns, prebaked per-cell navmesh, far shell, index.json). — Your calls: 2 km, 256 m, USGS now, shells.
- **D-040** (2026-11-09) Missing buildings come from Microsoft Global ML Building Footprints (CDLA Permissive 2.0, aerial-imagery footprints + height estimates): pipeline step fetch_buildings downloads the level-9 quadkey tile(s) for the map square; build_cells adds every footprint that doesn't overlap an OSM building (OSM wins) or a landmark. Credit in CREDITS.md. — Your call (over Overture / procedural).
- **D-041** (2026-11-09) Art direction: realistic, built from free CC0 assets (Poly Haven-style photo textures + CC0 models), procedural roofs/facades on generated buildings, instanced trees/cars/debris. Every asset download is listed (file, source, size) and approved first. — Your call (over stylized low-poly / paid assets).
- **D-047** (2026-11-09) Yanney Park + water. Build Yanney Park (Gottschalk Tower, Yanney Park Lake + the west pond,
  amphitheater, Environment Resource Center/marina, Splashground, The Gardens at Yanney Park with the 7 themed gardens,
  courtyard and Yanney Pavilion), the Tailrace canal behind Bonk's house and the Platte north channel, in the same
  style as the rest of the town (photo textures + low-poly props). WATER: swim — shallows wade, deep water = slow
  swim, no shooting/sprinting, zombies don't path into it. TOWER: climbable switchback stairs to the top deck.
  CONDITION: overgrown but recognizable (wild beds, dead grass, cracked paths, faded/rusty tower, some broken windows,
  abandoned boats). Sources: OSM (lake, canal, Platte, park, paths, tower, buildings; fetch_osm now also pulls
  water/waterway/leisure/grass), satellite view (gardens + pavilion in the NW corner off W 11th St, west pond), the
  user's photos (tower, gardens aerial, amphitheater/lake view), cityofkearney.org (tower 80 ft, gardens 12.6 acres).
  — User choices (recommended options). Survival stage 2/3 (drops, workbench) paused until this is done.
- **D-046** (2026-11-09) Survival + items. Hunger/thirst MEDIUM: meters drain over ~1 h of play (thirst faster); low =
  slower healing + sprint, empty = slow health loss that can down you; food/water can be shared. Item use is TIMED
  (quick-use keys + inventory Use button; bandage ~2 s, eat/drink ~1.5 s; moving or being hit cancels; host checks
  you own it and applies the effect). DROPPED items land in the world as pickups anyone can take, saved with the
  world, per-cell loose-loot cap (oldest removed). CRAFTING only at a workbench in Bonk's bunker, recipes in data.
  — User choices (all recommended options).
- **D-045** (2026-11-09) Phase 4 characters: Quaternius CC0 models + animations (Zombie Apocalypse Kit: survivors,
  zombie types, dogs; Universal Animation Library if more clips are needed), stylized low-poly to match the generated
  trees/cars. Animation is presentation only, driven by the host-replicated movement/state (net model unchanged).
  First person: animated arms holding the weapon; other players see the full body. Order: zombies, other players'
  bodies + FP arms, Bonk. — User choice: lightest option, no license strings, consistent style.
- **D-044** (2026-11-09) Realism phase 3 (clutter + atmosphere): 13 Poly Haven CC0 models approved (130.7 MB:
  covered_car, modular_electricity_poles, street_lamp_01, fire_hydrant, metal_trash_can, concrete_road_barrier,
  modular_chainlink_fence, old_tyre, rusted_wheel_rim_01, utility_box_01, trashbag, cardboard_box_01, Barrel_01),
  placed by the map pipeline from the street layout. Cars: MIX of generated low-poly wrecks (sedan/pickup/SUV, rust,
  faded paint, some burned) + the tarp car. Atmosphere: keep the dusty brown haze, tuned (sky gradient, warmer sun,
  softer shadows, distance haze), no download, no day/night. — User choices: variety over all-photo-real cars;
  cheapest atmosphere that keeps the established look.
- **D-043** (2026-11-09) Realism phase 2 (ground): roads and sidewalks are real meshes built by the map pipeline from
  OSM ways (strips with curbs and lane lines) on grass ground, not painted into the terrain. Trees: MIX — generated low-poly
  leafy street/yard trees + Poly Haven CC0 shrubs and dead trunks (instanced, LODs). Ground textures approved: road_damaged,
  concrete_floor_damaged_01, withered_grass, gravel_road, grey_roof_01 (44.4 MB). — User choice: sharp edges and curbs
  worth 2-4 extra draws per cell. User first picked Poly Haven trees, then switched to the mix once the listing showed
  Poly Haven has no Midwest deciduous trees and its pines/firs are 487-937 MB. Shrub/trunk model list still needs approval.
- **D-042** (2026-11-09) Building looks phase 1 (inside D-041): 5 Poly Haven CC0 textures at 2K (user approved list,
  34 MB, `tools/assets/fetch_textures.tscn` + `data/art/textures.json`, md5-checked). Looks/classes/roofs/windows in
  `data/art/building_looks.json`: shed <40 m² planks + 20° gable, house <400 m² siding 75% / brick 25% + 30° gable
  (if footprint ≥85% of its oriented rectangle, walls then follow that rectangle), large = brick/concrete + flat roof.
  Windows are drawn by `shaders/building_wall.gdshader` from UVs (no geometry); 25% boarded, 20% broken. Picks are
  hashed from the footprint centre so a re-import gives the same street. — Biggest visual jump for the cost: ≤5 extra
  draw calls per cell, no new meshes to author.
- ~~**D-007**~~ (superseded by D-009) Signaling server written in GDScript inside this project (`server/`), started with user arg `--signaling-server` (headless for hosting). Lobby = 5-char code; host is peer 1; clients may only signal the host; server forwards only whitelisted fields. — No extra runtime to install; same code locally and when hosted.
- **D-008** ICE servers + signaling URL/port live in `data/net/network.json`. STUN = Google public servers. TURN not configured yet (open: provider choice). — Data-driven so hosting changes don't touch code.
- **D-005** Movement tuning in `data/tuning/player_movement.json`, validated by `DataLoader` against `MovementRules.SCHEMA`. — Project spec: tuning by data.
- **D-006** Gray box built with CSGBox3D + use_collision. — Fast to edit in editor; throwaway, replaced by the import pipeline.
- **D-048** (2026-11-09) Bigger map = "landmarks box" 7.68 x 5.12 km (30 x 20 cells of 256 m), x -1280..+6400 m,
  z -2816..+2304 m from 810 17th Ave: Bonk's house, Yanney Park, UNK, downtown, the Platte channels and the Archway
  (40.669747 N, 99.038342 W = x +5511, z +1412). Origin stays at the house so landmark/save coordinates don't move.
  ~600 cells, ~2 GB in the project folder, ~8 min rebuild. Player map: full-screen map on M drawn from the real
  roads/buildings/water, landmark labels, markers for you, teammates and Bonk, zoom + pan; no minimap/compass;
  no fog of war (whole map shown). — User choices (all recommended options).
- **D-049** (2026-11-09) The Archway landmark + Evan "Jerkin'" Jenkins. Build the Great Platte River Road Archway
  over I-80 (its real spot, x +5511 z +1412) in the generated-landmark style: towers, timber facade, roof, stairs up
  into a walkable museum deck (exhibit rooms, Evan's camp) with LOTS of loot containers. Evan is an unhinged but
  friendly hermit living in the Archway: rambling, paranoid dialogue with hidden hints, gives/trades loot, never
  fights. He's based on a real friend who's in on the joke: keep the crazy affectionate/inside-joke, no real-life
  personal details. — User choices (recommended options).
- **D-050** (2026-11-09) Bonk is spawned by the host at session start through an NpcSpawner (MultiplayerSpawner,
  main.tscn "NPCs") instead of being a static node in main.tscn, so a client can never have its own local Bonk
  (alpha testers saw two Bonks). — Bug fix after the first real alpha session.
- **D-051** (2026-11-09) Evan is a crazy TRADER with deep lore, not a tutorial NPC: survival tips removed.
  Lore: ex-government insider ("Maintenance, Level Two") who fixed the escalator and "the machine under it" - a
  government listening/relay station hidden in the Archway (antennas in the tower eagles). It sent "ACKNOWLEDGED"
  four days before the strike; "the Suits" (he never names the government faction) went underground on a Tuesday;
  S.O.U.P. (the soup running gag) is their program that steers the glowing nuclear storms to keep the land sick
  and people small; the machine still hums nightly at 3:12; an eagle keycard is a hook he'd buy. Trades stay
  dialogue swaps (repeatable): tape->15 ammo, 3 scrap->painkillers, 2 beans->3 jerky, wrench->10 ammo,
  car battery->9mm pistol. — User: "Ex-government insider", "Dialogue trades". Names/terms are placeholders in
  data/dialogue/evan.json; the keycard is a lore hook only, no quest built.
- **D-052** (2026-11-09) Chems = timed buffs with side effects (Fallout-chem style), no addiction. Items with a use
  block "effect" start an effect from data/effects/effects.json (pure EffectRules, host ActiveEffects on the player,
  net_effects replicated). Mods multiply: damage_taken (Health.damage_mult), move_speed (owning client predicts),
  hunger/thirst drain (Needs.drain_mult); heal_per_second; local screen tint (pulsing hue) + FOV change. Effects
  chain into comedowns via "after". Not saved. Items (new "chem" category / Chems tab): Meekachu's Kush (Baked),
  Magic Mushrooms (Tripping), Acid Tab (Tripping -> Fried), Molly (Rolling -> Comedown), Black Tar (Nodding ->
  Dope Sick). All numbers are placeholders in data. — User: "Timed buffs + side effects".
- **D-053** (2026-11-09) Chillers HQ = the Nebraskan Student Union at UNK (replaces OSM way 193151052, flat pad):
  walkable ground floor (lounge, dining corner, grow room in the old ballroom, Meekachu's throne room), upper storey
  exterior only, campus camp on the south lawn. Leader "Meekachu" (nameplate) - permanently stoned, intense
  dialogue, sells chems by repeatable barter (beans->Kush, water->shrooms, painkillers->acid, bandages->molly,
  20 ammo->black tar, car battery->kush+molly; a free sample). Chillers Bongo, Skyler, Patches (shared short tree).
  Lore (placeholders in data/dialogue/meekachu.json): Chillers survived finals week in the union basement (311 in,
  42 out); the Suits visit twice a year and take one person each time, wanting people immune to the storms;
  Dr. Halvorsen (storm notebook, immune) went west along the river; janitor Gus followed Suit trucks south to where
  the tracks stop; Meekachu connects Evan's story; Bonk owes him a lighter. Real friend, in on it. — User choices:
  "One HQ + campus camp", name "Meekachu", "he's in on it".
- **D-054** (2026-11-09) Main quest + quest system. Party-shared quest flags (host-owned QuestDirector, synced,
  saved as world.quests); pure QuestRules; quests in data/quests/quests.json (file order = story order); objectives
  complete by dialogue node flags, reach_m, have, boss deaths (boss_<id>_dead) and kill counters (kills_<id>);
  rewards go to every player. Dialogue gets node "flag(s)", choice "requires", tree "starts"; NPCs get
  show_requires / hide_requires. Quest book on J (track a quest), HUD tracker top right with distance, toasts,
  yellow diamond on the M map, boss bar. Act 1 playable: Five Years of Static (Bonk -> Archway -> Evan),
  The Collector (Evan -> Meekachu: the Suits' collector), Detention (Kearney High: free Wren, kill Hunter Conner,
  take the eagle keycard), Acknowledged (keycard to Evan, printout to Meekachu, Gus). Side quests: Before the World
  Ended (Bonk's lighter), Forty Jerky and an Apology, Lab Supplies (Patches), Skyler's Sister (Wren), Hall Pass,
  Faculty Meeting. Acts 2-4 (South of the River / S.O.U.P. / Clean Shirts: Site Granary, storm relays, the Director)
  are outline only (locked_note). All text/names placeholders in data. — User request; built after an interrupted run
  (designs taken from that run, recommended defaults).
- **D-055** (2026-11-09) Kearney High School POI (OSM way 1024257250, map ~(-1500,-90), west of Yanney/Bonk's house):
  generated full interior (north classroom wing + detention/holding cells, science lab, library, front office,
  lobby, cafeteria, auditorium, gym, weight room, locker rooms) via LandmarkKit; LairDirector spawns placed enemies at
  landmark markers (wake within 42 m, sleep beyond 95 m, mobs respawn after 15 min, bosses never once killed).
  New mobs: Hall Monitor (fast, fragile), Linebacker (tank), Lunch Lady (ranged slop). Bosses: The Bearcat
  (auditorium, enrages), Big Darlene (cafeteria, ranged), Hunter Conner (gym; the Suits' collector, armed ranged boss,
  talks first then fights, enrages at 50%, drops the eagle keycard). Hunter is based on a real friend: keep it
  affectionate. Import area widened west to x -1792 (32 x 20 cells) to include the school.
- **D-056** (2026-11-09) Filler looting between landmarks: lootable spots across the generated neighborhoods
  (cars, mailboxes, porches, garages, dumpsters) placed by the import pipeline with stable IDs and per-cell caps,
  plus ~10-15 small walk-in POIs (gas stations, corner stores, pharmacy) at real OSM shop/fuel spots. — User:
  "Loot spots + small POIs".
- **D-057** (2026-11-09) The Meepo electric longboard is an explicit exception to "everything on foot": found in
  Bonk's bunker; a hotkey hops on/off; ~2.5x run speed; battery drains while riding and recharges at the bunker;
  no shooting while riding; big hits knock you off. — User: "Ride, no shooting".
- **D-058** (2026-11-09) More characters/animations: Quaternius Universal Animation Library [Standard] (13 MB) +
  Universal Base Characters [Standard] (122 MB), CC0, downloaded from quaternius.itch.io with the user's OK; base
  bodies dressed with tinted clothing materials. — User: "Quaternius", "Yes, download both".
- **D-059** (2026-11-10) Downtown bars as hand-built landmarks with full interiors on two levels: Copperfields
  (13 E 21st, NE corner of 21st & Central; ground + basement), Brix (across 21st from Copperfields; ground +
  upstairs), The Other Side (15 E 24th, north side east of MONA; ground + basement), Gillie's (1822 Central, west
  side; ground + upstairs). Positions estimated from the address numbering (odd = north / east side) and the
  Microsoft footprints; each landmark also rebuilds the rest of its merged downtown block as closed storefronts.
  One data file + one generic bar builder. — User: "Ground + basement/upstairs".
- **D-060** (2026-11-10) Raiders: a second hostile faction on the existing enemy body (enemy "faction"; bodies of
  different factions see and fight each other, ranged shots never hit their own side). Mixed gunners (ranged,
  armed) and brutes (bat melee); they guard their bases and also fight zombies that wander in. — User: "Mixed guns
  + melee".
- **D-061** (2026-11-10) Raider looks: our Quaternius base bodies with raider outfit colours plus primitive gear
  props built in code (masks, bandanas, shoulder pads, spikes, mohawks) attached to bones. No download. — User:
  "Dress our Quaternius bodies".
- **D-062** (2026-11-10) Raider district: barricades and lookouts close the Central Ave bar blocks, raider camps in
  all four bars, boss "Copperhead" in the Copperfields basement, and a side quest "Last Call" (scout the barricade,
  kill raiders, kill Copperhead) that is open from the start. — User: "Same, plus a side quest".
- **D-063** (2026-11-10) Start screen "Bonk's Bunker": Singleplayer (offline: OfflineMultiplayerPeer, no lobby,
  no internet; friends can't join), Multiplayer (the existing host/join with a lobby code), Settings, Controls
  (keybind list), and saved worlds with Delete. — User: "Offline, no lobby".
- **D-064** (2026-11-10) Quest tracking: tick/untick any number of active quests in the quest book; HUD lists up to 3
  tracked objectives, the map shows a diamond for each; newly started main quests auto-track. Per player, local only.
  — User: "Several at once".
- **D-065** (2026-11-10) Meepo tuning: ~30 minutes of riding per charge, instant recharge at the dock, a bit faster;
  no weapon bob while riding. Loot window: Take 1 / Take stack / Take all. Downtown bars on the world map. — User.
- **D-066** (2026-11-10) HUD icons drawn in code (flat vector shapes, no download): health, food, water, Meepo
  battery, and one per active chem effect. — User: "Draw them myself in code".
- **D-067** (2026-11-10) Minimap top left, rotates with the player (facing up): teammates, Bonk, tracked-quest
  diamonds, POI/landmark markers; the F3 perf overlay moves to the right. — User: "Rotates with you".
- **D-068** (2026-11-10) Pause menu on Esc: Resume, Settings, Controls, Save & Quit (to the start screen), Quit to
  desktop. Singleplayer freezes the game; co-op keeps running. Meepo cruise 15 m/s, Shift boosts to 20 m/s at 3x
  battery drain. — User: "Pause freezes solo only + boost".
- **D-069** (2026-11-12) Disc golf minigame: Centennial Park DGC (Kearney; UDisc "centennial-park-6iCA": 9 holes,
  all par 3: 193, 178, 189, 195, 214, 218, 208, 167, 283 ft; hole 1 by the south entrance; hole 6 has a long and a
  short pad; Mach II baskets). Tee/basket positions from the user's UDisc screenshots (not on the website).
  Throw: hold left click to charge power, aim with the camera, tilt hyzer/anhyzer, backhand/forehand toggle; flight
  from real speed/glide/turn/fade numbers. Three discs: driver, mid-range, putter. Played in the world with the
  party (course box at hole 1, shared scorecard, best scores saved, zombies kept out of the park during a round);
  host-authoritative flights. Small loot reward by score (par or better more, ace = rare). — User.
  Build notes (inside the approved design): tilt is Z / X or the mouse wheel, not Q / E (E is Use); F swaps
  backhand / forehand, 3 takes out / cycles discs, Q holds the scorecard (Tab is the inventory). Each player plays
  their own disc, no turn order; max 8 strokes a hole then pick up; leaving the park (60 m out) drops you out.
  The host simulates the whole flight at once on the fixed 60 Hz step at throw time and sends the path to everyone
  (no per-tick disc traffic). Course trees traced from the UDisc satellite screenshot into
  data/discgolf/centennial_trees.json (planted by build_cells through the landmark's plants_file); tree crowns
  knock discs down. Disc golf items: Wasteland Driver 12/5/-1/3, Prairie Midrange 5/5/0/1, Bunker Putter 2/3/0/1,
  Golden Ace Disc (ace trophy). Hole 6 uses the long pad only.
- **D-070** (2026-11-12) Street signs at every street intersection on the whole map (OSM names, built into cells by
  the import pipeline) and street names on the minimap. — User (whole map, as accurate as possible).
- **D-071** (2026-11-12) Disc golf scorecard is hidden once you leave the course area after a round. — User.
- **D-072** (2026-11-12) Map expanded 2 km west (8 more cell columns) to take in Hwy 30 and Cottonmill Park;
  re-download OSM (Overpass), USGS 3DEP elevation and Microsoft building footprints for the wider box. — User.
- **D-073** (2026-11-12) Cottonmill DGC added as a second disc golf course, holes traced from the user's UDisc
  screenshot (the layout drawn there, incl. the hidden "9 1/2"). — User.
- **D-074** (2026-11-12) Drop Zone (101 11th Ave by Kea Lake; 32 bays on 2 levels) at its real spot: Topgolf-style
  range target game, the 18-hole outdoor putting course and the 4 pickleball courts all playable. Swing = hold to
  power, aim with the camera, club (driver / 7-iron / wedge) sets distance and loft. Layout from the user's
  overhead screenshot (pending). — User.
- **D-075** (2026-11-12) Project + GitHub repo live in C:/1Bonks_Bunker (copied out of OneDrive; old folder kept as
  backup). Releases are built on the user's PC by tools/release/release.tscn (option A of A/B/C — not GitHub Actions)
  and published as ONE GitHub prerelease with Windows + Mac together. Version = highest alphaX.Y tag on GitHub + 0.1,
  starting at alpha2.1 ("new release" -> run the tool). Mac build is universal, ad-hoc signed, not notarized.
  world/generated/cells/ (2.4 GB) and builds are gitignored; cells are rebuilt by build_cells.tscn. Files over
  1.9 GB are split into .001/.002 parts (GitHub caps release files at 2 GiB). Repo default: Bonks-Bunker, private
  (data/release/release.json). — User picked A.
- **D-076** (2026-11-13) Disc golf group play, replaces the D-069 build note "each player plays their own disc, no
  turn order". One thrower at a time, shown to every player. Tee order = best score on the previous hole first,
  ties random (hole 1 random). Mid-hole: the player furthest from the basket throws next ("away", the real rule).
  All tee shots go before any second shot. The group moves to the next tee when everyone has holed out or picked up.
  White see-through tracer behind each thrown disc, kept until its thrower walks up to the disc. Basket: on-screen
  marker (arrow + feet, shows through trees, pinned to the screen edge) and a glowing band. The minimap shows the
  tee pad as well as the basket. Ace = kill-cam replay on every screen: all players locked and invulnerable,
  zombies frozen for the replay, then play resumes. Wind: 0-15 mph, shifts about every 30 s during a round, small
  effect on flight, speed and direction on the HUD. — User (options: freeze everyone / away from basket /
  breezier shifting wind / on-screen marker).
- **D-077** (2026-11-13) Sound. Recorded CC0 sound files (option B of A synthesize / B CC0 pack - the user downloads
  them; nothing is synthesized), played by an `Sfx` autoload from data (event ID -> folder of variant files, tuning
  in data/audio/sounds.json) with pooled 3D voices (option A of A autoload+data / B per-scene players). Ambience =
  looping wind bed + random distant one-shots every 15-60 s, 40-120 m away (option A of A / B single loop). SFX and
  Ambience volume sliders in Settings (yes). Scope asked: eerie open ambience, all weapon sounds, consuming items,
  jumping, taking damage, disc hitting the chains. - User.
  Build notes (inside the approved design): a landing thud goes with jump; the disc clanking off the tray/pole is a
  second basket sound; jump/land/reload/dry click are heard by that player only; shots, melee hits, hurt, item use
  and basket hits are heard by everyone nearby. No hurt sound for hunger/thirst damage.
- **D-078** (2026-11-13) Kenwood Elementary + Centennial Park pool. Kenwood (915 16th Ave, ~200 m east of Bonk's
  house) = loot + light zombies (option A of A loot+light zombies / B lair + boss / C survivor shelter): full
  interior, school loot, a handful of plain shamblers on lair markers, no boss. Layout = best guess fitted to the real
  footprint (option B of A user describes rooms / B best guess): OSM way 1056847663 + Microsoft footprint + Esri
  imagery show the CURRENT modern single-storey flat-roof school (the 1935 PWA building was elsewhere): north
  classroom wing, central block, tall NE hall (gym, longest roof shadow), tall south hall (cafeteria / multipurpose),
  kitchen + mechanical east of it, office + secure entry at the south tip by the parking lot, angled Pre-K wing west.
  Centennial pool = DRAINED (option B of A filled + swim / B drained / C murky): not in OSM; from Esri imagery: 24.5 x
  29.5 m basin, zero-depth beach curving across the SW corner, big mushroom spray, concrete deck, bathhouse +
  concessions on the south side (matches the Microsoft footprint), 6 ft max depth (city site). Leaves, debris,
  deflated floaties, a couple of shamblers in the deep end. Fence kept clear of disc golf holes 2 and 3. - User.

- **D-079** (2026-11-13) Five more landmarks with exterior + interior + loot, on their real footprints: Big Apple Fun
  Center (500 W 4th St), Kearney RV Park & Campground (1140 E 1st St), Kearney Country Club (2800 19th Ave; the golf
  course is scenery only - ground, greens, bunkers, ponds, cart paths, tee signs, flags - NO golf gameplay code yet),
  Cope Stadium at Foster Field (UNK), Merryman Performing Arts Center (225 W 22nd St). Dressing VARIED per place:
  Merryman nearly intact, stadium + country club looted, Big Apple partly burned, RV park lived-in as a camp. Enemies:
  light shamblers at Big Apple, Country Club, stadium and Merryman; the RV park is a raider camp (D-060 raiders).
  Loot Kenwood-level (about 12-20 containers each), existing tables plus a few new themed tables. No unique items for
  now. - User (options given: looted-like-Kenwood / varied / heavily ruined; shamblers+RV raiders / shamblers
  everywhere / mostly quiet; Kenwood-level / rich at two / sparse; no uniques / one per place / stadium only).
- **D-080** (2026-11-13) Country club course surfaces (greens, tees, fairways, bunkers, cart paths) are PAINTED onto
  the terrain by build_cells from landmark "ground_paint" polygons (OSM golf features, way ids kept): overlay triangles
  clipped to each terrain triangle at ground + a few cm, one mesh per paint material per cell, streamed with the
  cells. Flags and tee signs drop onto the ground with a ray when their cell loads (like the disc golf baskets).
  Ponds stay the existing OSM water. Still no golf gameplay (D-079). - User (options: paint onto terrain / separate
  draped mesh / flatten the whole course with a pad).
- **D-081** (2026-11-13) Player names: each character is named PER WORLD - the first time you enter a world (host or
  join, singleplayer too) a "Name your survivor" prompt opens; the name is kept on that character in the world save
  (players.<key>.name) and comes back on later visits, no prompt. Other players see it on a name tag over your head:
  fully visible to 30 m, fades out by 40 m, hidden behind walls (no health bar, not through walls). Host cleans names
  (printable, spaces collapsed, max 20 chars). - User (options: main menu field / per world character / ask every
  time; name fading with range / name + health bar / always through walls).
- **D-082** (2026-11-14) Big update — User.
  * Hunger/thirst drain 3x slower: ~3 h to empty hunger, ~2 h thirst (CHANGES D-046's "~1 h", at the user's ask).
  * Chems compound (CHANGES D-052's "using it again restarts the timer"): each dose adds its time up to a cap and
    raises strength up to max doses; effects fade out at the end; the comedown is scaled by how high you got (weak,
    slow). Stronger and longer than before. Options were: stack to a cap + comedown / no limit / overdose risk.
  * Alcohol: beers, seltzers, shots and mixed drinks give a "Drunk" level (1 per drink, ~40 s each, ~5 min max).
    BRUTAL at 8+ drinks (user pick over heavy / light): screen sway, view drift, stumbling, double vision, blurred
    edges, camera lurches, vomiting (lose food + water, stop for a moment).
  * Being drunk or high wobbles gun aim (the view drifts) AND disc throws, visibly: the power bar jitters and the
    host adds power / angle error by how impaired you are (user pick over gun-only / mild).
  * John Pork's tent at the start of both disc golf courses: vendor selling water, food, chems and booze cheap
    (barter, like Evan), a Meepo charging dock, and a course records board.
  * Records board: this world, per player — best round, best per hole, aces (user pick over all-worlds / rounds only).
  * Meepo dock is usable: E puts your board in the dock (charged instantly — D-065 kept, user pick) and E takes it
    back; you can't ride while it's docked. Standing near a dock still charges as before.
  * Throw animation other players see (wind-up + release with the disc in hand).
  * Disc in water: it stops at the surface, +1 stroke, next throw from the spot where it crossed onto the water
    (real disc golf OB rule) — the old code let it fall through the lake bed and travel on under the land.
- **D-083** (2026-11-14) Motorcycles — User. A second exception to on-foot travel (after the Meepo, D-057).
  * Five bikes, fictional makes, built in code (no download): dirt 250, supermoto 450, cafe racer 500, sport 600,
    cruiser 1200. Stock colour schemes only, one picked at random when a bike spawns (user pick over a paint
    station / both).
  * Mayhem-style handling (user pick over arcade cruising / stunt-heavy): A/D lean-steer, W throttle, S brakes,
    Space leans back (throttle wheelies, air pitch), Ctrl leans forward (brake stoppies, air pitch), jumps off
    slopes; a bad landing, looping a wheelie, an endo or a hard hit throws you off and hurts.
  * Manual gearbox WITH clutch (user pick over no clutch / manual + auto): hold Shift for the clutch, E / Q shift
    up / down, N + 5-6 gears, rev limiter per gear, the wrong gear bogs, letting the clutch out at too few revs
    stalls (B restarts, clutch in or neutral).
  * Found + fuel (user pick over a bunker garage / starter + found): parked on streets, at most one per map cell,
    the same bikes for the same world; runs on gas, gas cans from loot (gas stations, garages, car trunks,
    junk piles), R refuels while stopped. Where a moved bike was left is world state in the save.
  * No shooting and no weapon in hand while riding (user).
  * My calls: third-person chase camera while riding (V switches to first person), F gets off (only when slow),
    the host simulates the bike from the rider's intents and the rider's client predicts it.
- **D-084** (2026-11-14) Pool (billiards) at the Big Apple — User.
  * Both bar-room tables become real 7-ft tables (the decoration props are replaced), placed by the Big Apple
    generator as PoolTable nodes so a re-import keeps them.
  * Simple 8-ball (user pick over free play / 8-ball + 9-ball): solids vs stripes decided by the first ball
    pocketed after the break, sink the 8 last, a foul (scratch, hitting nothing, hitting the wrong group first)
    gives the other player ball in hand, potting your own ball keeps your turn, the 8 early or on a foul loses,
    the 8 on the break is re-spotted.
  * First person at the table (user pick over a top-down 247-style view / top-down + 3D replay): walk around the
    table, aim where you look from the cue ball (aim line + ghost ball while it's your shot), hold left click for
    power, release to shoot; ball in hand = click the felt to put the cue ball down.
  * Players + solo practice (user pick over players only / + Bonk AI): E at a table takes a seat (two seats);
    alone you practise on a full rack, a second player starts a match; others watch. E again or walking away
    leaves. Games aren't saved.
  * Host-authoritative like the other sports: the shooter sends only power + aim, the host runs the shot (pure
    PoolRules) and sends every peer the ball paths to play back.
- **D-085** (2026-11-14) alpha2.5 tweaks — User.
  * Bikes turn sharper: new tuning `turn_grip` (2.0) multiplies the turn rate a lean gives at speed, so the
    radius is half what the lean physics alone would give (11.8 m at 56 km/h on full lean, was ~24 m).
    Kept as one tuning number rather than per-bike, so lean_deg still makes the cruiser the widest.
  * Booze lasts 3x: drunk `seconds` 30 -> 90 per drink, `hold_seconds` 120 -> 360. Chems unchanged.
  * The bottom-right performance readout can be turned off: Settings > "Show performance stats (F3)", saved per
    PC in user://settings.cfg [ui] debug_overlay. F3 still toggles it and writes the same setting.
  * The riding controls are listed in the bottom-right corner above the bike gauges while on a bike; the
    performance readout hides itself while a BikeHud is up, since they share that corner.
  * Settings now opens over the pause menu (it used to draw underneath it).
- **D-086** (2026-11-14) Golf plays like a golf game, not a throw — User.
  * Swing meter (user pick over a PGA-2K mouse swing / arcade hold-and-release): camera behind the ball, pick a
    club, aim arrow + predicted shot arc, then a 3-click meter (start, power, accuracy) like Hot Shots / Mario Golf.
    Putting gets a putt line and the green's slope.
  * Replaces the throw-the-ball controls at the Drop Zone range and putting green (D-074).
  * The Kearney Country Club course (scenery only since D-079) becomes playable with the same swing.
- **D-087** (2026-11-14) Armor + more weapons, full loot game — User (pick over slots + 8 weapons / light).
  * Armor slots: helmet, chest, legs, each with damage resistance; found as loot with a condition that wears down.
  * About 8 new weapons filling the missing roles (shotgun, hunting rifle, AR, SMG, revolver, sniper, machete,
    crowbar), with their own ammo.
  * Weapon mods (scopes, mags, suppressors, ...) and rarity rolls (worn to legendary) on guns and armor.
- **D-088** (2026-11-14) The Golden Ace disc is a throwable weapon — User (pick over golf perk / trophy + trade).
  Thrown at enemies like a disc: heavy damage, flies back to the thrower.
- **D-089** (2026-11-14) Pickleball rework: real rules + timed swings — User (pick over Wii-style timing only /
  light fix). Kitchen rule (no volleys near the net), swings have a wind-up and recovery so spam clicking whiffs,
  timing grades the shot (early / perfect / late), the AI lobs players camping the net. Feedback: ball shadow,
  landing marker, timing popups, rally counter, score callouts.
- **D-090** (2026-11-14) No road blocks: the concrete road barriers the clutter pass dropped on bigger roads are
  removed (barrier_chance 0, cells rebuilt). Also asked: a pause-menu "Respawn at bunker", unique player colours on
  the minimap, player names on the minimap and in minigames instead of P1 / P2. — User.
- **D-091** (2026-11-15) Bug-fix pass after alpha2.6 — User asked; the fixes inside it are mine:
  * Lobby recovery: every failed / timed-out / ended session reloads Main with a brand-new TubeClient (Net.
    leave_to_menu, reason shown on the start screen); host goes live on LAN after 8 s if no tracker answered;
    joining gives up after 30 s with a reason. Dead trackers btorrent.xyz + ghostchu swapped for webtorrent.dev +
    novage. TURN relay: waiting on the user (needs a free account; ExpressTURN recommended).
  * Disc golf tents (DiscCourse anchors, Camp, JohnPork, Dock) get fixed node names: auto names differ per peer,
    so a client's E on John Pork (and the camp Meepo dock RPCs) reached nobody on the host.
  * Fall rescue: falling for fall_rescue_seconds (8) puts the player back where they last stood; pause menu
    "Respawn at Bunker" (owner asks, host moves them to their spawn, off bike / Meepo).
  * Country club pool: the ground hole was bigger than the kidney, its corners dropped through the map - deck fill
    over the slabs' opening, plus a ramp out of the 1.6 m deep end (higher than a jump).
  * Colliders match models: tree trunk = a cylinder along the drawn trunk (TreeMesh "tree_shape" metadata);
    collide_radius props as tall as their model (stumps had a 3 m invisible column); discs hit the drawn branches
    (always) and leaf clumps (canopy_hits_per_m), not an ellipsoid around the crown.
- **D-092** (2026-11-15) Player colours + names (user): the host gives each player the first free of 6 colours
  (data/tuning/player_colors.json, Player.net_color replicated); minimap and M map draw teammates in their colour
  with their name, your own arrow in yours; disc golf toasts / scorecard use character names ("You" for yourself
  in toasts), scorecard rows in the player's colour.
- **D-093** (2026-11-15) Gear build notes (inside D-087 / D-088, mine): equip slots gun1 / gun2 / melee (melee and
  thrown) + head / chest / legs; every weapon or armor piece is a rolled instance {uid, id, rarity, cond, mods, perk,
  mag} (GearRules, Inventory.gear, saved with the player, old saves' weapon counts rolled on load). Keys 1 / 2 =
  guns, **4 = melee / thrown slot** (3 stays the disc key), right mouse = aim / scope. Machete and crowbar
  became a combat knife and a fire axe (those meshes exist in the character pack). Armor shows only as numbers (no
  armor on the character models yet). Workbench: attach / detach mods, repair with scrap.
- **D-094** (2026-11-15) Golf build notes (inside D-086, mine): 6 clubs + putter (driver 200 m ... wedge 90 m);
  3-click SwingMeter (early = hook, late = slice, missed = shank); camera behind and a little right of the ball with
  the full-power arc and a landing ring, putts get a ground line + slope ticks; Drop Zone putting holes got slopes.
  Country club: 18 holes from the tee signs / flags / OSM tee boxes (data/golf/country_club_course.json), lies
  from the painted course (green / fairway / tee / bunker / rough), real terrain heights and slopes,
  trees knock balls down, water and out of bounds = +1. You walk (or ride) to your ball; a marker with your name
  floats over it. Best round = quest flag kcc_best_round.
- **D-095** (2026-11-15) Pickleball build notes (inside D-089, mine): a click = windup 0.12 s, contact, recovery
  0.5 s (clicks during it do nothing); grade by the ball's time to its closest pass at contact (PERFECT within
  0.06 s, GOOD 0.15 s, else EARLY / LATE, out of reach = WHIFF). Two-bounce rule + kitchen volley faults for both
  sides; the CPU lobs a player within 3 m of the net and smashes LATE floaters, misses more against PERFECT shots.
- **D-096** (2026-11-15) Character creator (user: "Full creator", shown on every load-in). Built from the parts the
  project already has (Quaternius UBC male / female bodies, 6 hairstyles, beard, eyebrows; the outfit shader for
  skin / shirt / pants / shoes colours) plus hats and extras made as bone-attached shapes (gear pieces) - no new
  asset pack needed. Options live in data/art/appearance.json; a look is a small dict saved per character and synced
  as Player.net_look (Sync prop 28); the host sanitizes it (AppearanceRules). The creator replaces the name prompt
  and opens every load-in, filled in. New characters (and pre-3.0 saves) start with a random look. First-person arms
  stay the survivor arms. The boxy utility vest looked wrong on the female body, so it became a bandolier.
- **D-097** (2026-11-20) Golf fixes from playing (bugs, no design change): tee signs floated because GroundProps'
  ground ray hit the 50 m tall golf tee E-spot boxes (and tree collider cylinders) - it now only sees world + water
  bed and passes through vegetation; flags got a drawn cup + rim; a pin marker like the disc golf basket marker
  (arrow + yards / feet, pinned to the screen edge) on the course HUD; a shot tracer like the disc golf one
  (BallTrails, the same DiscTracer) on the course and the range.
- **D-098** (2026-11-20) Nature + course detail (user picked every recommended option): generated Kearney species
  - American elm, green ash, silver maple, cottonwood, spruce, ponderosa pine, eastern red cedar, plus honey locust
  and willow in mixes - and bushes (round, juniper, lilac); tall prairie grass, wildflowers, cattails/reeds
  (PlantMesh). Placement: street / yard mixes, patches per cell, reeds + cottonwoods / willows along every shore,
  the country club gets tree lines in the rough (kept 7 m off fairways, greens, tees, bunkers, cart paths). No
  OSM trees exist for Kearney, so species follow where they really grow. Course furniture: blue tee markers, a
  bench + ball washer at each tee, 150-yard posts, white OB stakes along the OSM course boundary.
- **D-099** (2026-11-20) Sky + weather (user picks): warm dusty sky with more blue and drifting procedural clouds
  (sky shader, incremental radiance) that darken with the weather. Weather states clear / fog / rain / storm on a
  host schedule ("balanced": a storm about once an hour, never the same state twice), host can force any state or
  Auto from the pause menu. Storms are dangerous: lightning warns a player standing outside (screen warning +
  ground glow) then strikes where they stood 1.6 s later (70 damage, falling off over 4.5 m); under a roof is
  safe, trees are not shelter. Rain and storms make zombies hear less; storms blow disc golf wind harder. Rain
  and thunder sounds are generated in code (no downloads). Not chosen: wind gusts, hail, tornado, day/night.
- **D-100** (2026-11-20) Open-world zombie types (user picks): Runner (fast, fragile, sprints at gunfire), Bloater
  (slow; bursts on death or when close, hurting players AND zombies nearby), Riot Cop (helmet + vest shrug off body
  shots; headshots or melee), Spitter (ranged acid lob, reuses the Lunch Lady's ranged attack). Spawning: harder
  farther from the bunker - mostly Shamblers near home, more special types the farther out. Cap: user picked "raise to 10"
  after I wrongly said the cap was 8; corrected (it was 4), user still chose 10 per cell. Pool 24 -> 40 bodies. Themed drops: Riot Cop armor piece or ammo, Bloater crafting chemicals,
  Runner nothing extra; Spitter not specified (treated like Bloater: chemicals). Not chosen: themed-by-area, night /
  storm only, specials on top of the cap, rare named items. TURN relay: user skipped for now.
- **D-101** (2026-11-21) Safe zones (user pick "always safe, 60 m"): Centennial + Cottonmill disc golf, the Country
  Club course and the Drop Zone range are always free of hostiles: no street spawns or lair wakes within 60 m of
  them, hostiles don't target or hear players inside a zone (chasers give up at the edge), and any hostile that ends
  up inside walks back out. The country club's placed shamblers therefore never wake. Not chosen: 150 m, only during
  a round, despawn inside.
- **D-102** (2026-11-21) Act 1 finale = "ambush the collection truck" (user pick): after Gus, the printout's next
  pickup is a real truck-dock lot; the party ambushes the Suits' collection truck and its escort, takes the
  manifest and route from the truck, and brings it to Gus; that closes Act 1 and opens Act 2. Note: "at night" from
  the option text is not possible - there is no day/night cycle (D-099 left it out). Not chosen: defend the
  Chillers camp, epilogue only.
- **D-103** (2026-11-21) Act 2 starts at a grain elevator by the real tracks (user pick), no map extension. User
  approved one Overpass lookup (data/map/source/kearney_elevators.osm.json, tools/map_import/fetch_elevators): OSM
  has NO grain elevator inside our map (only 2 small silos by the RV park), so the elevator is hand-built on the real
  OSM industrial lot beside the UP spurs east of downtown (way 314364584, map ~(3300,-1280)); Gus's "south of the
  river" becomes "south of the tracks". Not chosen: extend the map to the Platte, separate zone.
- **D-104** (2026-11-21) The Suit watcher (user pick "every 10-15 min, one player"): a man in a black suit appears to
  ONE player at a time, 60-120 m away, watching; only that player sees him (purely local presentation, no gameplay,
  never attacks, not hittable); he vanishes when that player gets within ~25 m (and repositions out of view now and
  then while he "follows").
- **D-105** (2026-11-21) Random encounters are a weighted table picked by the host on a timer, not scripted
  placements: `data/encounters/encounters.json` holds 25 definitions (rarity common/uncommon/rare/legendary ×
  weight, own cooldown, `once`, hour window, weather, distance from the bunker, quest `requires`, category), and
  `data/tuning/encounters.json` holds the global cooldown (240 s), max_active (3), the 70-190 m spawn band, keep
  (320 m) and min_apart (150 m). Chosen: a site opens on a REAL road marker from the streamer, out of sight of
  every player, on flat clear ground - never in front of somebody. Every peer builds the same site locally from
  (slot, id, position, yaw, seed), so nothing dynamic is replicated and dialogue paths match. Not chosen:
  MultiplayerSpawner replication, hand-placed encounters, spawning in the player's view.
- **D-106** (2026-11-21) The comedic world oddities are AUTHORED, not random: 18 scenes at real roadside points next
  to known Kearney landmarks (`data/encounters/oddities.json`), built when their cell loads and skipped if the spot
  has no ground or no room. One `use` each, fired once per world and saved. The mannequin shop re-rolls its
  mannequins on every rebuild, so they are never where you left them. Not chosen: random spawning, one-off scripted
  rooms.
- **D-107** (2026-11-21) Collectibles are 15 junk items on 105 hand-spread roadside spots (7 each, ≥120 m apart,
  `data/encounters/collectibles.json`). Picking one up is an E spot; the host adds the item and tells everyone.
  A rack outside the bunker shows one of each type the party owns and rebuilds itself as the collection grows.
  Open: the rack sits in the back yard (bunker landmark + [0,0,-3.2]); moving it into the bunker interior needs a
  local offset from the bunker scene.
- **D-108** (2026-11-21) Rare secret events are shown to ONE player and nothing else: the host rolls every 150 s
  (`chance` 0.3), picks an event whose conditions hold (in-game hour, distance from the bunker, weather, quest
  flags, own cooldown, max_times) and sends it to one peer, which places a figure, prop, sound or light and takes
  it away when that player gets close, looks away or its time runs out. Nothing fights, blocks or drops anything,
  so nobody can corroborate it. Deliberately quiet: no jumpscares, no stingers.
- **D-109** (2026-11-21) The in-game clock for "hours" conditions is derived from `world.play_seconds`
  (30 in-game minutes per real minute, day starts at 08:00) - it drives encounter and rare-event windows ONLY.
  There is still no day/night lighting cycle (D-099 left it out), so 3 AM is a number, not a dark sky. Flagged
  because the 3 AM watcher and the night events read differently without one.
- **D-110** (2026-11-21) Day/night cycle, night spawns and sleeping (all four user picks). One full day takes
  **48 real minutes** - the same clock the encounters already ran on (30 in-game minutes a real minute), so
  nothing had to be re-timed; sunrise 06:30, sunset 19:30, and the world clock (DayNight, saved and host-synced)
  now owns the hour that the encounters and rare events read. Night is **moonlit, not black**: after sunset the
  sun light is mirrored to the other side of the sky, recoloured blue and dimmed, so it is still a real light
  with soft shadows, and the sky goes deep blue with stars. No flashlight was added (not needed at this
  darkness). Night spawns: the per-cell zombie cap **doubles** (10 -> 20) and the type weights shift toward the
  specials (Runner x2.2, Riot Cop x2.0, Spitter and Bloater x1.8, plain Shambler x0.65), both faded in through
  dusk; pool_size 40 -> 48 is still the hard ceiling on how many can be awake at once. Sleeping: the bunks
  already in the bunker scene became usable; **one player sleeping skips the whole server to 07:00** and everyone
  wakes at full health, fed and watered. The bed refuses by day. Not chosen: 24 or 72 minute days, a dark night
  with a flashlight, 1.5x or 3x spawns, sleep that only skips time.
- **D-111** (2026-11-21) No building stands in a street. Microsoft's ML building footprints (used wherever OSM
  has none, D-040) are derived from imagery and some of them land on the carriageway; nothing checked for it,
  because the road corridors (`_clear_hash`) were only built AFTER the buildings were placed and were only ever
  used for vegetation. `_build_roads` now runs first, and a footprint is dropped if its centre is on a road
  surface (carriageway + curb, no extra padding, so buildings may still sit right against the kerb) - and a
  Microsoft one is also dropped when over half its corners are. The counts are printed in the build summary.
  Applies to OSM footprints too: a footprint centred on a road is bad data whatever produced it. Needs a full
  cell re-bake (~1 h) to take effect; the fix is in the importer, not in the already-generated cells.
- **D-112** (2026-11-21) Realistic zombies come from MIXAMO (user's pick over reusing the raider bodies, a paid
  pack, or free CC-BY models - the CC0/CC-BY realistic zombies that exist are low-poly mobile models or unrigged
  sculpts). Licence: free for any game, but "the only thing you can't do is distribute the raw character and
  animation files" (Adobe's Mixamo FAQ) - and the repo is public, so assets/characters/mixamo/ is GITIGNORED and
  only ever ships baked into the exported game. Every Mixamo model has a "fallback" to the old CC0 model, so a
  fresh clone of the repo still runs (with cartoon zombies) instead of failing to load. Animation: Mixamo saves one
  clip per FBX, keyed to whichever character was selected at download; MixamoRetarget copies rotations by bone name
  with the mixamorig/mixamorig5 prefix stripped, keeps only the hips' position (scaled by hip height, so a 2.2 m
  body doesn't sink on a 1.8 m body's walk) and pins locomotion clips in place. Mapping: Warzombie + Zombiegirl =
  shambler, Parasite = runner, Copzombie = riot cop, Zombiegirl = spitter, Warrok = bloater (provisional - it reads
  as a fantasy beast; user to decide). Cartoon tints dropped on these five (a coloured film over a real skin reads
  as paint). Kearney High bosses and the giant jackrabbit still use the CC0 models.
- **D-113** (2026-11-21) Every release ships the real zombies (user: "make the Mixamo files in the newest updates
  every time"). They always went into the export (all_resources; the folder isn't excluded) but nothing
  guaranteed it - a build made without them would fall back to cartoon zombies in silence. Now ModelCheck gates the
  release twice: in the editor before exporting, and inside the packaged Windows exe after (`-- --check-models`,
  answered by main.gd). Any missing model or clip stops the release before anything is published. The raw files
  still never go into the public repo (Mixamo licence). Also: Warrok STAYS the Bloater (user); Ch10 joins the
  shamblers; all Mixamo textures are VRAM-compressed (S3TC for Windows, ETC2 for Mac) and capped at 2048 - they had
  been imported lossless, which is what headless imports do (the editor's "used in 3D -> compress" switch never
  fires), and the 48-zombie crowd fell from 585 to 272 MB of video memory.
- **D-114** (2026-11-21) Zombie scare features, all four levers the user picked, for the five open-world zombie
  types only (data/tuning/scare.json `roles`; raiders, bosses and the jackrabbit untouched). Each activation rolls
  traits from one replicated int (`net_style`), so every peer agrees with no extra traffic: screamer, stumbler,
  crawler, feigner, lurker, stalker, flanker, twitchy, plus +/-18% speed. Host-only behaviour lives in ZombieScare
  (returns a speed multiplier to Zombie._host_step); `net_pose` (NORMAL / DOWN / RISE) replicates the feign.
  Feigning is in Health (`down_once`: first lethal hit leaves 1 HP and emits `downed`, not `died`), so kill credit,
  loot and corpses only ever happen on the real death. ADAPTATION: "wait inside buildings" - the generated town
  buildings are solid shells, not enterable, so lurkers wait pressed against the nearest wall or doorway within
  10 m (and inside the hand-built interiors, where walls are real) until you're within 7 m. Sounds made with no
  downloads (tools/audio/build_scare_sounds.py): heartbeat + breathing synthesized, groan / scream / snarl derived
  from the in-repo CC0 moans; each event is a folder, so better CC0 recordings can replace them by dropping files
  in. Heartbeat is on the Master bus so the muffling low-pass (SFX + Ambience) doesn't swallow it. Only the nearest
  4 zombies get voices, so a horde can't steal the 24 voices gunfire needs. Old tests that need plain zombies set
  `ZombieScare.roles_off`.
- **D-115** (2026-11-21) Realistic ground and roads (user picks: layered ground, roads five years abandoned, 3D grass
  near the player). Four CC0 Poly Haven sets added (grass_ground, dirt_floor, gravel_ground_01, asphalt_02; 2K,
  VRAM-compressed). Everything is SHADER + DATA, no re-bake: ground.gdshader blends a dirtier grass and bare dirt in
  noise patches and on steep slopes; street_surface.gdshader adds a second asphalt, dirt drifted in from the edges,
  a crack network with weeds, potholes and repaired patches (per surface in data/art/streets.json "decay").
  The baked cells turned out to carry their OWN copies of the ground/street materials (not the shared .tres), so
  WorldStreamer now points each near cell's Terrain/Mesh and Street_* meshes at the shared materials
  (streaming.json materials_dir) - any future look change is refresh_street_materials + restart, never a re-bake.
  3D grass: GrassField builds MultiMesh clumps (code-made tapered blades, no texture, no shadows) in 16 m chunks
  around the camera, placed from per-cell density masks (new pipeline step build_grass_masks, run after
  build_cells: roads 4% = weeds, road edges 43%, sidewalks 10%, buildings/water/greens 0) plus a ray onto the
  Terrain body. Tiers: low none, medium 0.8/m2 to 32 m, high 1.6/m2 to 45 m; blades shrink to nothing in the last
  30% so chunks never pop.
- **D-116** (2026-11-21) Realistic cars: 8 Sketchfab CC-BY 4.0 models picked by me, downloaded by the user (Sketchfab
  needs an account): two generic sedans, a crashed car, a rusty truck, a crashed truck (Rashad Ibrahimli), a blue
  pickup (Skeleton_games), a 1953 Cadillac (ROH3D) and a wrecked bus lying on its side (BytesCrafter). CC-BY allows
  redistribution, so the unpacked models ARE in the public repo (assets/models/vehicles/, textures cut to 2K) and
  credited in CREDITS.md; the original zips in assets/vehicles/ are gitignored. They are ordinary clutter props
  (VegetationBuilder merges each into one mesh, the new "fit" turns it along +Z / scales to a real length / stands it
  on the ground, and regenerates LODs), so they are baked into the cells: placement is a pipeline step, not hand
  work. Placement (user picks): abandoned traffic on motorway/trunk/primary/secondary (jams of 3-9 in one or both
  lanes, the front one often a crashed model, sometimes the bus), parking lots (stalls along the 189 OSM parking
  aisles, ~35% full) and driveways (35% of houses, some sunk on flat tyres). The curb cars and the lone street cars
  are OFF - the user did not tick "keep curbside", so the loot "Car Trunk" spots moved onto the new cars. Box
  colliders. Needs a full build_cells re-bake + build_grass_masks.
- **D-117** (2026-11-22) Realistic disc golf: new discs, baskets, tee boxes, throws and animations. User picks:
  (1) models BUILT IN CODE (real rim profiles, chain baskets with link chains, real tee pads; data-driven, no
  downloads) over downloaded CC0 / mix; (2) throw animations HAND-MADE IN CODE (reach-back, pull-through,
  follow-through per style, on every survivor model + first-person hand and disc) over Mixamo clips / first-person
  only; (3) ALL THROW STYLES - backhand, forehand (sidearm), putt, tomahawk (overhand) and roller - each flying
  differently, over backhand+forehand+putt / backhand+putt; (4) REAL COURSES, WEATHERED (Centennial + Cottonmill
  baskets, tee pads and signs matched to photos, then aged: rust, cracked pads, faded signs) over clean / generic.
  No real brand names or logos on discs/baskets (made-up stamps). Perf: Centennial was already 724 draw calls -
  new pieces must stay instanced / one mesh per material.
- **D-118** (2026-11-22) Realistic houses (numbered after D-117 disc golf from another chat). User picks: REAL 3D
  DETAIL (window frames + sills, front doors with steps, porches, garage doors, fascia + gutters, chimneys, parapets,
  weathering in the wall shader) over shader-only / imported house models; ABANDONED, MIXED (most grimy, some broken
  windows, some boarded up, a few caved-in roofs or burned) over lived-in / uniformly wrecked. Built by the importer
  (tools/map_import/house_details.gd, numbers in data/art/building_looks.json "details"), so a re-import regenerates
  it; condition is deterministic per footprint. Frames are placed with the same layout maths as the wall shader's
  windows so they line up; boarded windows are now 3D boards (the shader's painted boards are off). Detail draws to
  220 m (visibility range), the far shells are unchanged. Sheds get none. Driveway cars moved out to 5.4 m and porch
  packages to 2.9 m so they clear porches and steps. Needs a full build_cells re-bake + build_grass_masks.
- **D-119** (2026-11-22) Disc catalog at John Pork's. User picks: BIG CATALOG (10 made-up molds x base + premium
  plastic = 20 discs: Platte Comet, Long Haul, Sandhill Crane, Fence Post, Buffalo, Tumbleweed, Grain Elevator,
  Cornhusk, The Brick, Anvil - no real brands) over a 9-disc bag / 4-disc set; EXPENSIVE, 50-150 BOTTLE CAPS (base
  50-75, premium 90-140) over tiered 15-50 / cheap 5-10; 3 STILL CYCLES the discs you own (fastest first) over a
  bag wheel. Plastic matters: base slips more on release (aim 2.5 deg / tilt 5 deg, 1 sigma, host-rolled) and beats
  in 4x faster (0.012 per throw, +0.03 per tree hit; premium 0.7 deg, 0.003 / 0.01); a beaten-in disc flies with
  more turn (up to -1.5) and less fade (up to -50%). Wear is per player character per disc id (copies share it),
  host-owned, saved in the world as disc_wear. The course box now hands out only the three starters. Also: the
  user chose to LEAVE first-person throws as they are (the chibi survivor's swing happens below the camera; others
  see it in third person) over a disc-only FP swing or a dedicated FP arm.
- **D-120** (2026-11-22) Polish after alpha3.3. User picks: FIRST-PERSON DISC-ONLY SWING (reverses the D-119 "leave
  it") over a dedicated FP throwing arm - while a disc is in hand in first person the body is hidden and only the
  disc moves through the swing in front of the camera (throw_styles.json fp disc_anchor_m + hand offset x
  disc_swing_m). Also, inside approved work: the disc HUD panel moves up above NPC captions while one shows
  (SubtitleUI.caption_top); the ground shader fades into a 7x larger rotated copy of the grass past 20-90 m and
  adds broad 70 m brightness / dry-green patches to break up the distance (streets.json ground "far"; shared
  ground material, no re-bake - run refresh_street_materials after changing it).
