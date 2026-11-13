# STATE

_Last updated: 2026-11-12 (disc golf)_

## Where we are
First playable slice: 1–6 players over WebRTC (lobby codes via our signaling server), first-person
movement (walk, sprint, jump, crouch with headroom check) on a gray-box test level, host-authoritative
with client prediction and remote interpolation. F3 perf overlay.
Verified: ENet version imported and ran clean on RTX 4060 / D3D12. WebRTC version: see below.

## Networking (D-009)
Tube addon (`addons/tube`) + WebRTC GDExtension (`addons/webrtc_native`) installed.
`scripts/net/net.gd` wraps TubeClient; config (app ID, trackers, STUN, TURN, timeouts) in `data/net/network.json`.
`server/` (old self-hosted signaling server) is unused — safe to delete.
Verified 2026-11-08: main scene loads clean with Tube; `tests/net_host_probe.tscn` created a lobby (a public tracker
accepted it, code issued, no 403/TLS errors on 4.7.2). Not yet verified: a second player joining.
Tube quirk handled: if all trackers fail during create, Tube never emits session_created; Net starts the session anyway (LAN-only).

## How to test co-op locally
Editor → Debug → Customize Run Instances → enable multiple instances, set 2. Run (F5).
Instance 1: Host → lobby code shows top right. Instance 2: type code → Join.
Online: friend runs the game, types the code. Nobody port-forwards.

## Combat slice (2026-11-08)
Pistol (slot 1) + bat (slot 2), lag-compensated hits, friendly fire 25%, mag/reload/reserve, arc melee,
health + downed/revive (E) / bleed-out / respawn (D-015), HUD status line, tracers, 3 training dummies.
Verified: `tests/combat_rules_test.tscn` 23/23 pass on your PC (incl. downed/revive timing); main scene loads clean.
Not yet verified by playing: shooting/swinging feel, hit markers, reload, friendly-fire downing, revive over network.

## Zombie slice (2026-11-08)
Shambler (D-016..D-020): pooled ×8 (cell cap), spawns out of sight / far away, wanders on runtime navmesh,
investigates noise (pistol 35 m, bat 3 m), chases on sight, telegraphed swipe (15 dmg), ignores downed players.
Verified: logic tests pass on your PC; `tests/zombie_smoke_test.tscn` hosts the real level → 8 spawn and
wander on the navmesh (see FAILED/notes for noise→chase result). Not yet verified by playing with 2 windows.

## Loot + inventory slice (2026-11-08)
D-021..D-027. 12 items, 5 loot tables, 5 containers in the yard (ammo crate, toolbox, kitchen cabinet,
fridge, junk pile with heavy junk for testing overweight). Inventory screen Tab/I; containers E; Take All R.
Pistol spare ammo = 9mm Rounds in inventory (start 36). Capacity 60; >60 slowed + no sprint; ≥75 barely moves.
Verified: 43/43 logic tests on your PC. Smoke test in the real level: you looted by hand during it (ammo 36→44,
+3 duct tape), the crate then reported empty and Take All on it changed nothing. Same run: noise → 3 zombies
INVESTIGATE (only those within 35 m) → 2 spotted the player → CHASE.

Host/Join now ignore extra presses while a session is starting or running (double-click showed an error).

## Neighborhood slice (2026-11-08) — Alpha map
Main scene is now the real block around 810 17th Ave (gray box moved to `scenes/test_yard.tscn`, dummies too).
Pipeline (re-runnable, on your PC): `tools/map_import/fetch_osm.tscn` (geocodes + downloads OSM, writes
center back into `data/map/import_config.json`) → `tools/map_import/build_cell.tscn` → `world/generated/neighborhood_17th_ave.scn`
(35 buildings merged into 1 mesh + 1 collider, roads, ground with bunker-stair hole, boundary walls, 40 zombie spawns).
Landmarks (`data/map/landmarks.json` → `scripts/world/landmark_loader.gd`): `world/landmarks/bonk_house.tscn`
(generic 14×11 m 1-story: living, kitchen, hall, 2 bedrooms, laundry; 4 loot containers) replaces OSM way
1056927162 (west side of 17th Ave, nearest the geocoded address — CONFIRM with user it's the right house);
`bonk_bunker.tscn` under the backyard (main room, bunks, storage, generator room; ramp+steps from hatch; 4 containers
incl. backyard junk pile; player spawns). Landmark boxes merge to a few meshes at load (static_mesh_merger.gd).
Navmesh baked at runtime from collision shapes (no GPU read-back warning anymore).
Verified (smoke test, real level): navmesh 1254 polys; host spawns standing in the bunker main room (y -4);
8 zombies spawn on neighborhood streets 60-230 m out and wander; bunker ammo crate refuses from spawn,
opens in reach, rolled 11 rounds, Take All 36→47. Not yet verified: walking the stair ramp up/down by hand.
Geocoder labelled the address "Riverside Mobile Home Court" — OSM houses there have no house numbers.
UPDATE (D-030): user sent a street photo of 810 17th Ave → confirmed the west-side house. bonk_house.tscn rebuilt
to the real exterior on the real L-shaped outline (3-car garage, stone, porch, gables, siding, white backyard fence
with gate on the garage side, driveway, sidewalk); interior = guessed ranch layout (office, entry, great room +
kitchen, hall, master, bath, laundry→garage, bedroom 2), 6 containers. Bunker moved to cell (-41.8, 0.4), inside
the fence. Cell rebuilt (hole moved). Verified loads clean, navmesh 1317 polys, spawn on bunker floor.
Generator scripts for landmark scenes live outside the project (Claude's scratchpad); the .tscn files are the source of truth now.

## Bonk slice (2026-11-08) — D-031..D-034
`scenes/bonk.tscn` (orange capsule + blue cap, nameplate) in main.tscn, starts beside the bunker spawns.
Host-only AI (`scripts/ai/bonk.gd` + pure `scripts/rules/companion_brain.gd`, numbers in `data/companions/bonk.json`):
follows the nearest player on the navmesh (walk >3.5 m, run >12 m, teleports behind them >60 m), 5 Hz sight check for
zombies, 0.5 s reaction then pistol every 0.6 s with spread (infinite reserve, reloads), bat inside 2 m. Never hurts
players. Downed like a player; gets himself up after 20 s (or a player revives him with E) at 60 HP.
Dialogue: own JSON (`data/dialogue/bonk.json`: barks per context + tree `bonk_talk`), validated by `scripts/data/dialogue_db.gd`.
E on Bonk → host `scripts/dialogue/dialogue_director.gd` runs the conversation; lines show as subtitles for every
player within 25 m, reply buttons only for the talker; Esc or walking away ends it. Barks: idle, combat, kills,
reload, downed, revived, a player downed, friendly fire.
Verified: 54/54 logic tests on your PC; smoke test in the real level: Bonk spawns 1.9 m from the host at 150 HP,
talk → first line + choices → choice 1 → reply → leave all work over the real RPCs.
Not yet verified by playing: Bonk fighting zombies, getting downed, 2-window conversation.
Fix 2026-11-08 (user: "glitching on objects, can't get out of the basement"): bunker table moved off the stair-foot
walkway, hatch curbs 0.3→0.6 m, navmesh agent_max_climb 0.5→0.25, Bonk repaths only when the leader moves >1 m.
`tests/bonk_follow_test.tscn` checks the ramp navmesh + path bunker→yard and logs "STUCK" with what he's touching.
Verified: path reaches the yard; Bonk followed up the stairs, through the yard, down again and into the house, no STUCK.
D-035 sidestep when a player walks into him; D-036 Fallout-style captions (scripts/ui/subtitle_ui.gd).
Verified: 60/60 logic tests; follow test walked the player straight at Bonk: he moved 2.3 m aside, closest 1.0 m
(contact 0.7), player walked 9.2 m through. Smoke: reply caption "You: …" shows first, then "Bonk" line + 2 options.
Not yet seen by eye: caption look on screen; sidestep inside the stairwell (should back out down/up the ramp).

## Saves (2026-11-09) — D-037
Menu: pick a world (or "+ New world" + name) before Host. `scripts/save/`: save_format.gd (pure shape/version/
migrate/check), save_store.gd (files, atomic write + .bak), player_identity.gd (per-install ID), save_director.gd
("Saves" node: open/start/apply/capture/autosave/F5/quit). Tuning `data/tuning/save.json`. HUD shows "Game saved".
Verified: 69/69 logic tests (9 save-format checks); `tests/save_test.tscn` real round trip: loot crate, move, hurt,
move Bonk → save → scramble → reload from disk → position, items, health, empty crate, unopened toolbox, Bonk all back.
Tests now host a throwaway "zz test" world and delete it. Two game windows on one PC share the install ID, so the
second window gets a separate guest character each session (by design, see D-037).
Not yet verified by hand: menu world list, autosave toast, client rejoin restoring their character.

## Next up (post-Alpha, user order 2026-11-09)
A. ~~Save/load~~  B. ~~Quality tiers + perf report~~  C. ~~Map streaming~~ (2 km square; UNK/downtown not inside yet)

## Quality tiers + perf (2026-11-09) — D-038
Autoloads `Graphics` (scripts/settings/graphics.gd, applies tiers to window + WorldEnvironment/Sun/cameras as they
appear) and `Perf` (scripts/perf/perf_monitor.gd, 1 s samples, budgets, host CSV). Pure tier pick: scripts/rules/
graphics_rules.gd. Esc → settings menu (scripts/ui/settings_menu.gd). F3 overlay now a RichTextLabel fed by Perf.
Verified: 74/74 logic tests; real level on your RTX 4060: auto → High (scale 1.0, MSAA 2x, SSAO, far 1000, shadows);
switching to Low applied scale 0.67, FXAA, far 250, no shadows, 60 FPS cap, then back. Bunker spawn: 5.6 ms/frame
(~178 FPS), 83-87 draw calls, 206 MB VRAM. CSV log written while hosting (not offline).
Not yet seen by eye: Esc menu, red over-budget values.

## Map streaming (DONE 2026-11-09) — D-039
Code written + pushed: tools/map_import/{tiff_reader,fetch_elevation,build_cells}.gd(+.tscn), scripts/world/
{height_field,cell_grid,world_streamer}.gd, landmark_loader (y from index), zombie_director (pool_size 24,
cell_cap 4 per cell, spawn only in cells near players, despawn in unloaded cells), main.tscn (World streamer
replaces Neighborhood + runtime Navigation bake), data/map/{import_config,landmarks (house terrain_pad),streaming}.json.
Pure tests 88/88 (cell grid, height field + pads, TIFF plain/deflate/float-predictor).
Pipeline run order on the PC: fetch_osm.tscn (2.2 km Overpass, slow) -> fetch_elevation.tscn (USGS 3DEP
exportImage, uncompressed F32 TIFF) -> build_cells.tscn (64 cells + shells + navmesh + index.json) ->
tests/streaming_test.tscn, then smoke/save tests (they need the cells; main.tscn has no ground without them).
Landmarks stay resident (not streamed) so container/sync node paths match on all peers; generated cells hold
no networked nodes, so each peer streams on its own (host: around all players + Bonk; client: own player).
Pipeline ran on the PC 2026-11-09: OSM 237 buildings / 273 highway ways (OSM is sparse here — most Kearney houses
aren't mapped); USGS 550x550 px, 650.7–662.8 m, map centre 655.4 m; build_cells 77.7 s: 212 buildings, 1116 zombie
spawns, 26316 navmesh polys, landmark lot y 0.067. Verified (tests/streaming_test.tscn): spawn on terrain, 9–12 near
cells + 64 shells, 5.6 ms/frame, 178 draw calls, 229 MB VRAM; teleport 800 m east -> new cells loaded, old freed,
worst frame while streaming 11.6 ms (budget 16.7), zombies only in new cells (≤1/cell), 47 m nav path reaches target;
back at bunker worst 9.0 ms. Save test 11/11 on the new terrain.
Buildings (D-040, 2026-11-09): Microsoft footprints (fetch_buildings.tscn, 1148 kept, 857 with heights, 3 MB) fill
gaps where OSM has no building; OSM wins on overlap, landmarks excluded. build_cells 63.9 s: 212 OSM + 801 Microsoft
buildings (203 dupes of OSM, 1 at landmarks), 50137 navmesh polys. Navmesh cell-border gap found + fixed (FAILED.md).
Streaming test after rebake: 5.6 ms/frame, 108-183 draw calls, 167-210k prims, 229 MB VRAM, worst streaming frame
9.5 ms; nav paths now cross cell borders (bunker -> street 20 pts, 0.0 m off; east 0.0 m off).
Realism phase 1 (D-042, 2026-11-09): user approved 5 Poly Haven CC0 textures (34 MB, md5-checked, imported as
VRAM-compressed + mipmaps). build_cells now gives each building a class/look (data/art/building_looks.json), gable
roofs on near-rectangular sheds/houses, flat roofs elsewhere, photo-textured walls with procedural windows
(shaders/building_wall.gdshader). Rebuilt OK (64.5 s). tests/look_test.tscn saves screenshots to tests/_look/.
Siding recolored (recolor 0.8, paint colors in data) — look_test confirms gray lap siding, windows, gables.
look_test perf: 5.7-6.0 ms frame, 105-181 draw calls, 305 MB VRAM (+76 MB textures); one-off worst-frame spikes
(22-145 ms) during camera jumps, not investigated (suspect first-use shader compile). PHASE 1 DONE.
Phase 2 (D-043, 2026-11-09): 5 more textures downloaded (44 MB; fetch_textures now skips ones already on disk).
build_cells: textured dry-grass ground (shaders/ground.gdshader), Street_<surface> meshes (asphalt/concrete/gravel/
sidewalk by OSM surface tag; alleys gravel, driveways concrete), worn centre/lane lines, curbs + 1.5 m sidewalks with a
2 m grass parkway along residential/tertiary/secondary streets, all stopping at intersections (no corner ramps yet);
shingle texture on pitched roofs. Rebuilt OK (64.7 s, 234 road ways). look_test: ground/sidewalks/curbs read well;
asphalt looks dark brown in the fog (tint in data/art/streets.json if wanted). Tier was LOW (user's saved choice):
51-88 draw calls, 263 MB VRAM, 16.7 ms vsync idle, ~21 ms while capturing WITH THE EDITOR OPEN (not a clean number).
Trees (2026-11-09): user approved 6 Poly Haven models (38 MB, tools/assets/fetch_models.tscn; textures capped at 1K
to save VRAM). build_cells places ~30k plants: street trees in the grass strip, yard trees + foundation bushes per
house, grass clumps/stumps/fallen trunks scattered (data/art/vegetation.json); 30% of trees bare. Trees/stumps/trunks
have colliders (navmesh goes around them). streaming_test (LOW tier, editor open): 16.7 ms vsync-capped, 106-129 draw
calls, 99-103k prims, 357-376 MB VRAM, worst streaming frame 35.8 ms, nav paths 0.0 m off. PHASE 2 DONE.
Known: generated trees are stylized low-poly (vertex colour), no trees in far shells (pop-in at the near-cell edge),
no curb ramps/corner sidewalks, asphalt reads dark brown in fog. Phase 3 next: clutter + atmosphere.
Phase 3 (D-044, 2026-11-09): 13 Poly Haven models (130.7 MB, textures at 1K). build_cells places ~1,900 clutter props
from data/art/clutter.json via a second VegetationBuilder (now generic: "nodes" regexes merge parts of modular glTF
sets, auto box/cylinder colliders from the mesh bounds): power poles (alleys + streets), lamps on bigger streets,
hydrants at corners, utility boxes, barrier checkpoints, generated low-poly wreck cars (CarMesh: sedan/pickup/SUV,
faded/rusty/burned) + tarp cars at curbs and in the street, trash cans/bags by the curb, yard + alley junk,
chain-link fence runs on alleys (one collider per run). Atmosphere node (scripts/world/atmosphere.gd +
data/art/atmosphere.json): warmer sun, sky gradient, height + distance fog, filmic tonemap, softer shadows.
streaming_test (LOW, editor open): 16.7 ms vsync-capped, 79-105 draw calls (look_test up to 174), 413-471 MB VRAM,
worst streaming frame 25.0 ms, nav paths 0.0 m off. PHASE 3 DONE. Known: VRAM up ~95 MB (imported models keep full
vertex buffers; only index LODs are reduced), wreck cars are stylized boxes, no power lines between poles.
Next (roadmap): phase 4 characters (D-045) — user downloaded the kit by hand (Drive quota blocked the tool):
14 self-contained glTFs in assets/characters/zombie_apocalypse_kit/glTF/ (one skin each, embedded textures).
Zombie clips: Crawl Death HitReact Idle Idle_Attack Jump* No Punch Run Run_Arms Run_Attack Walk Wave Yes.
Survivor clips: Death Duck HitReact Idle Idle_Gun Jump* No Punch Run Run_Gun Run_Slash Run_Stab Slash Stab Walk
Walk_Gun Wave Yes.
ZOMBIES DONE (2026-11-09): scripts/visual/character_animator.gd (CharacterAnimator, models by ID in
data/art/character_models.json) replaces the capsule Body in scenes/zombie.tscn; enemies.json "models" lists the 4
zombie types, picked per pool slot. Clip from measured speed (walk/run speed-scaled), net_attacking -> Punch,
health drop -> HitReact, dead -> Death (corpse now visible until it despawns). Far (>35 m) zombies animate at 10 Hz.
tests/zombie_look_test.tscn: all 4 load, face the camera, switch idle/walk/attack/death correctly; 100-110 draw
calls, 479 MB VRAM, 60 fps (LOW). PLAYERS + BONK DONE (2026-11-09): capsules replaced by CharacterAnimator survivors (data/art/character_models.json:
player_models Lis/Sam/Shaun picked by peer id until character creation; Bonk = survivor_matt via bonk.json "model").
Other players: gun clips when slot 0, weapon mesh per slot (weapons_by_slot), Duck when crouched, Death pose when
downed/dead (old rotate/scale capsule hacks removed). Local player: Viewmodel/Arms = same model in first-person mode
(fp_offset, head/legs/feet bones shrunk, no shadows), slash clip on melee swing, old box gun/bat hidden (Muzzle kept
for tracers). tests/character_look_test.tscn screenshots. KNOWN: first-person view only shows the weapon from behind
at the bottom of the screen, arms barely visible (Quaternius proportions: short arms, big head) — needs hand-tuning
of fp_offset in the editor or a dedicated FP arms asset. Remote players don't play an attack clip (no fire flag is
replicated). VRAM ~500 MB.
Known: Godot warns "navigation region synchronization had N edge errors" (overlapping edges where tile borders meet);
paths still work. UNK (~2 km N) and downtown (~2.5 km NE) are OUTSIDE the 2 km square — needs a bigger/offset grid.

## Next up (Alpha order)
1. ~~Networked gray box + FP controller~~
2. ~~Transport: WebRTC + Tube signaling~~ — remaining: optional TURN relay for strict NATs (open decision)
3. ~~One hitscan gun + one melee, host-validated damage, health~~ (needs a play test)
4. ~~One zombie type (host AI, navmesh), pooled, per-cell cap~~ (needs a play test)
5. ~~Loot containers + weight inventory (data-driven by string ID)~~ (needs a play test). No item use/drop yet.
6. ~~Bonk's house / bunker / 17th Ave blockout~~ (OSM pipeline; needs a play test)
7. ~~Bonk follows group + dialogue~~ (needs a play test) → Alpha feature-complete

## Known gaps
- Public trackers can be flaky (5 configured)
- No TURN relay: players behind symmetric NATs can't connect yet
- Remote interpolation uses packet arrival time (jitter shows on bad connections)
- Host sees remote players move in packet-sized steps (no host-side smoothing yet)
- Exports: `data/*.json` must be added to export include filter
- No quality tiers yet
- Client can show 1–2 phantom tracers when the mag empties (ammo count lags by ping); host never fires them
- Other players don't see your viewmodel or a third-person swing (no character model yet)
- Downed players are shown as a lying capsule; no crawl, no downed pistol

## Survival + items (D-046, started 2026-11-09)
STAGE 1 DONE (needs + timed use): data/tuning/survival.json + scripts/rules/survival_rules.gd (pure);
Player children "Needs" (PlayerNeeds: host drains, empty meter = 0.5 HP/s with attacker -1, low = no sprint) and
"ItemUse" (H quick heal, G eat/drink, inventory Use button; host-validated timer, cancelled by moving >1 m/s or a
hit, heal halved while a meter is low). items.json "use" blocks on bandage/painkillers/beans/water. HUD line
"HP / FOOD / WATER" + "Using X 40%". Saves store needs (optional field, old saves load full). Respawn floors needs
at 50. tests/survival_test.tscn: 8/8 PASS.
NEXT: stage 2 world drops/pickups (Drop button, saved, per-cell cap), stage 3 bunker workbench + recipes.

## Yanney Park + water (D-047, started 2026-11-09) — survival stages 2/3 paused
OSM re-fetched with water/waterway/leisure/grass (kearney_2km.osm.json). Local coords (x east, z south, m from
810 17th Ave): Tailrace canal way 334903861 x -106..-66 (N-S, ~80 m W of the house) + Tailrace Trail; park polygon
way 150846440 x -485..-75 z -283..623; Yanney Park Lake way 150636879 x -420..-124 z -105..456; tower way 421567213
at (-327, 40); Environment Resource Center (-346, 206); Peterson Senior Center (-231, -85); Splashground
(-383, 256); park entrance road from W 11th (z -289) at x -245 to a loop at (-290, -110); Yanney Ave x -480.
Gardens + pavilion (not in OSM): NW corner, x ~-470..-260, z ~-280..-70, pavilion near 11th St (satellite).
Platte north channel z ~490..700. Plan: (A) water pipeline: lakes/waterways carve terrain, water surface + swim
volumes, lake bed on its own collision layer so the navmesh skips it; swim movement. (B) Yanney landmark scene:
tower (climbable), pavilion, gardens layout, amphitheater, marina/boathouse, splashground, overgrown dressing.
STAGE A DONE (2026-11-09): tools/map_import/water_builder.gd (WaterBuilder) + data/map/water.json +
shaders/water.gdshader. 11 water bodies carved on the 4 m terrain lattice (lakes: flat surface 0.35 m under the
lowest shore point, bed sloping to 3.5 m; waterways: surface = centre-line ground - 0.9 m, rounded channel; Platte
by name override 45 m/1.6 m; never within 2 m of a drivable road). Bed collider = WaterBed body on layer 16, water
surface collider layer 32 (mask 0); navmesh parse mask excludes 16+32; player/zombie/Bonk mask 3 -> 19.
Player swims (MovementRules.water_mode/swim_velocity, tuning in player_movement.json): wade >0.5 m x0.6 no
sprint, swim >1.2 m floats feet 1.4 m down, Space up / Ctrl down, no firing. tests/water_look_test.tscn: lake
centre depth 3.5 m, canal ~2 m, player floats eye 0.28 m above water in lake + canal. Perf: unchanged (draw calls
87-262 high tier, frame 5.6 ms). Next: stage B (Yanney landmark scene).
STAGE B DONE (2026-11-09): tools/landmarks/ (LandmarkKit + yanney_tower/gardens/amphitheater/erc/splashground +
build_yanney_park.tscn) generates 5 landmark scenes world/landmarks/yanney_*.scn from data/landmarks/yanney_park.json
(one merged mesh per material, box/trimesh collision) + data/landmarks/yanney_plants.json (327 trees/shrubs/grass,
planted by build_cells via the landmark's "plants_file"). Registered in data/map/landmarks.json with terrain pads.
Order to regenerate: build_yanney_park.tscn, then build_cells.tscn. tests/yanney_look_test.tscn: screenshots +
scripted climb of the tower (reached the deck, 21.0 m, in 24.7 s). Perf (high tier): draw calls 51-253, frame
5.6 ms, VRAM ~656-669 MB (+~80 MB), one 144 ms hitch while turning on the tower deck (streaming many cells in view
from height?) - watch it. Known rough spots: footway strips render dark; flower clumps blocky up close; band shell
plain; ERC/pavilion solid-ish (pavilion enterable, ERC not). Next: user review, then survival stage 2 (drops).
POLISH + PERF PASS (2026-11-09): tests/hitch_test.tscn (10 m/s run across the park, 360 spin on the tower deck):
no frame over 25 ms, no cell add/blocking load over 12 ms -> the earlier 144 ms spike was a one-time shader compile
(cached), not streaming. WorldStreamer now prints + keeps slow_events for any cell add/blocking load > slow_ms
(streaming.json). Far shells now have low-poly trees (6-sided double cones in the shell mesh, no extra draws).
Street strips wound clockwise (were back faces); concrete_slab texture is very dark (avg 79/67/53), so concrete +
sidewalk tints raised in streets.json and the Yanney "path" colour -> paths read as concrete. Flower beds use
shaders/wild_flowers.gdshader (stems + petal heads cut from each quad). Band shell is a quarter-dome with a rust rim.
Perf high tier: draw calls 171-249, frame 5.5-5.6 ms, VRAM ~664 MB. Climb test still reaches the deck (21.0 m).
Next (user's earlier list): survival stage 2 (drops/pickups).
SURVIVAL STAGE 2 DONE (2026-11-09, D-046): world drops. Inventory Drop / Drop All -> WorldDrops ("Drops" node in
main.tscn, scripts/inventory/world_drops.gd) host validates (alive, owns it), removes from the inventory, puts a
pickup ~1.1 m in front (scattered 0.35 m) on the ground; per-cell cap 20 (oldest removed, DropRules.over_cap);
anyone takes it with E ("E  Take X" on the HUD, host checks reach). Pickups = pooled small coloured boxes by
category on layer 4 (interactables), no collision with movement, no shadows. Spawns/removes go to every peer by
reliable RPC; joining peers get the full list. Saved as world "drops" [[item, count, x, y, z]] oldest first
(optional key, no version bump; SaveFormat.drops_of cleans it). Tuning data/tuning/drops.json.
tests/drops_test.tscn 11/11 PASS (drop one/stack, refusing unowned, cap, pickup, out-of-reach refused, save
round trip); save_test still ALL PASS. Not yet tried with a real second client. Next: stage 3 bunker workbench.
SURVIVAL STAGE 3 DONE (2026-11-09, D-046): Workbench in Bonk's bunker (scenes/workbench.tscn, replaces the old
table at the same spot/footprint, so the navmesh is unchanged). E -> "E  Use Workbench" -> CraftingUI lists every
recipe (makes / needs have-need, short items red); Craft is instant; host checks alive + in reach + ingredients,
takes them, gives the result. Recipes are data: data/crafting/recipes.json via RecipeDB (validated against
items.json); pure CraftingRules.missing/can_craft. Starter recipes (placeholders, edit freely): Patch-up Bandage
(1 duct tape), Hand-load 9mm x10 (2 scrap), Break Down Wrench (-> 2 scrap), Strip Car Battery (-> 3 scrap),
Make a Baseball Bat (3 scrap + 1 tape). tests/crafting_test.tscn 9/9 PASS. Survival D-046 complete.
NOTE: test spots must be on the room side of the bench - it backs onto the bunker's south wall (inner face z 5.0).
TWO-PLAYER CHECK (2026-11-09): tests/coop_test.tscn hosts, then launches a 2nd game process
(OS.create_process, same scene, --role=client --code=XXXXX) that joins through the real Tube/WebRTC lobby; host
drives steps by RPC, both sides report. 19/19 PASS: lobby 0.5 s, join + body 3.0 s; client sees host, Bonk,
zombies and a drop made before it joined; client prediction moved 7.2 m and host agreed; client's copy of the
host 0.00 m off (standing still); timed bandage over the network (HP 50->75); drop + pickup both ways;
crafting at the workbench after a host-side teleport (client reconciled); firing host-confirmed (mag 12->11);
swimming in Yanney lake (mode SWIM both sides, eyes 0.28 m above water); client leaves cleanly; save keeps host +
guest characters. Screenshots tests/_look/coop_client_*.png. Same PC + LAN broadcast only: a real internet
connection (STUN/NAT) still untested; no TURN relay yet. Also: main.gd no longer recaptures the mouse while the
crafting window is open.
BIGGER MAP + PLAYER MAP DONE (2026-11-09, D-048): import config "area" = 30 x 20 cells (x -1280..6400,
z -2816..2304; CellGrid.from_config / area_rect). Fetched for the new box: kearney_landmarks.osm.json (4.0 MB),
kearney_landmarks_elevation.tif (15.1 MB, 2580x1330, server-confirmed extent - see FAILED), msbuildings (2.2 MB).
build_cells now builds 3 rows at a time + 1 context row each side (never saved) and frees each batch: 600 cells
in ~14 min, 1.93 GB on disk (3.2 MB/cell avg, 6.0 max), 7530 buildings, 258k plants, 12.3k zombie spawns, 779k
navmesh polys, 80 water bodies. Landmark heights: house 0.071, tower 3.356 (on its mound again).
In-game map: tools/map_import/build_world_map.tscn renders parks/water/rivers/9024 buildings/2140 roads at 2 m/px
(3840x2560) in a SubViewport -> world/generated/map/world_map.res (1.1 MB lossless) + world_map.json (area,
labels). Look + labels in data/map/world_map.json. WorldMapUI (M, scripts/ui/world_map_ui.gd): wheel zoom about
cursor, drag pan, centred on you; arrow for you, P2.. for teammates, Bonk; major labels always, minor when zoomed
in. tests/big_map_test.tscn: UNK / downtown / Archway area / east edge all stream in, 5.6 ms frames, 128-409 draw
calls, VRAM 584-825 MB (downtown highest); teleport-only blocking loads 20-35 ms. Map open: 5.8 ms.
Pipeline order now: fetch_osm -> fetch_elevation -> fetch_buildings -> build_yanney_park -> build_cells ->
build_world_map. NOTE: the Archway landmark itself isn't modelled yet (just the real I-80/roads there).
ARCHWAY + EVAN (2026-11-09, D-049) DONE: tools/landmarks/build_archway.tscn (archway.gd, data
data/landmarks/archway.json) -> world/landmarks/archway.scn: 26 meshes, 4.8k tris, 74 collision shapes (incl. step-free door ramp). Cells + world map rebuilt (archway ground y -6.5). Placed by
landmarks.json "archway" at the span middle (map x 5495.5 z 1405; replaces OSM way 140213931, exclusion 95 m, no
terrain pad so I-80 stays). Span 19.8 x 80 m, deck floor 9 m up, between a north tower (east-face lobby door,
switchback stairs) and a south tower (Evan's camp); brick + stone towers, copper roofs, bronze eagles, "THE
ARCHWAY" signs, visitor centre (closed) by the parking lot. Rooms: wagon trail, buffalo/Pony Express + jerky
smoker, 1950s diner with broken overlook window, gift shop (raccoon). 25 loot containers (new tables
archway_exhibit / archway_gift_shop / archway_diner / evan_stash), 7 shadowless omni lights.
Evan "Jerkin'" Jenkins: ResidentNpc (scripts/ai/resident_npc.gd, data/npcs/evan.json, survivor_shaun + tinfoil
hat at hat_y): never fights, can't be hurt, greets / idle-barks, faces you. Dialogue data/dialogue/evan.json: jerky
(gives 2 new item evans_jerky), raccoon/Gary/bridge-soup rambling, trades (1 duct tape -> 15 ammo, 3 scrap ->
painkillers, repeatable), 5 survival tips that are real hints. Dialogue system generalised: request_talk(npc_path),
NPCs give display_name/dialogue_tree/def; DialogueDB merges FILES; node "give" (+give_every_time) and choice
"cost"/"cost_fail". Gifts reset per session (not saved).
Pipeline order: ... -> build_yanney_park -> build_archway -> build_cells -> build_world_map.
tests/archway_test.tscn 0 failures: walks in the lobby door, up the stairs, through all 4 rooms to Evan (37 s,
ends on the 9 m deck), jerky gift +2, trade fails without tape, tape -> +15 ammo, talk ends, container rolls.
Perf at Evan: 5.6 ms frames, 181-317 draw calls, VRAM 534-540 MB. Shots tests/_look/archway_*.png.
Known: hat_y set to 1.7 by eye after the 1.9 test shot (not re-shot). Exterior rendering is blocky (box towers,
no windows); span clearance over I-80 is lower than the real one where the terrain rises at the towers.
ALPHA BUILD (2026-11-09): tools/export/export_alpha.tscn runs the editor headless --export-release
"Bonks_Bunker_Alpha1" -> C:/Users/Fishb/BonksAlpha/ (BonksGame.exe 104 MB, BonksGame.pck 2045 MB,
libwebrtc_native...template_release.x86_64.dll 3.9 MB) and zips it to C:/Users/Fishb/BonksAlpha.zip (2006 MB),
~3 min total. Preset now includes *.json and excludes tests/tools/data/map/source/diary/server.
tools/export/smoke_alpha.tscn launched the exported exe for 600 frames: exit 0, no extension errors (only the
usual forced-quit sync warnings). The headless export logs a harmless "can't open debug webrtc dll" when a game
instance is running at the same time. Real-internet join still untested (no TURN).
FIRST ALPHA FEEDBACK (2026-11-09): online co-op worked between two PCs. Bug: "two Bonks on one screen" - could not
reproduce on one PC (coop_test step 10 added: client sees exactly 1 Bonk at the host's Bonk position after the host
teleports him - PASS). Fix anyway by construction (D-050): Bonk no longer a static main.tscn node; host spawns him
via NpcSpawner at session start, clients only get the replicated one; freed on session end. Evan rewritten (D-051):
trader + government-conspiracy lore, tips removed, 5 repeatable dialogue trades. Needs a new alpha build + a
real two-PC retest to confirm the Bonk fix.
CHILLERS + CHEMS (2026-11-09, D-052/D-053) - built, cells rebuilding, test pending: effects system
(data/effects/effects.json, EffectRules, ActiveEffects "Effects" on Player + synced net_effects, Health.damage_mult,
Needs.drain_mult, ItemUse "effect", HUD effect list, Chems inventory tab); 5 chem items; chiller_stash loot table.
tools/landmarks/build_chillers_hq.tscn -> world/landmarks/chillers_hq.scn (27 meshes, 6.2k tris, 223 shapes):
union with walkable ground floor, grow room (emissive grow lights - LandmarkKit materials now take "emission"),
throne room (ramp up the dais), camp (tents, bonfire, van). 12 loot containers; Meekachu + 3 Chillers
(ResidentNpc: hat now optional via hat_color, new "smoke" wisp). Dialogue data/dialogue/meekachu.json (FILES).
MAIN QUEST + KEARNEY HIGH (2026-11-09, D-054/D-055): an earlier run of this request was interrupted after writing
the quest system, quest book, lairs/bosses, Kearney High builder and quest dialogue locally (only the re-fetched,
widened map sources had reached the PC). Resumed: added missing NPC data (hunter, wren, wren_home, gus; Skyler/
Patches quest trees; Gus + Wren-at-home in chillers_hq.json), school.json in DialogueDB.FILES, wren_free flag,
Hunter boss model -> survivor_shaun (not Bonk's Matt), KHS world-map label, zombie.gd Vector3 inference fix.
world/landmarks/kearney_high.scn: 20 meshes, 10.1k tris, 325 shapes. Cells rebuilding for the 32 x 20 area.
NOTE: after adding a script with a new class_name, run tools/refresh_classes.tscn (headless --import) before
running scenes from the command line, or they fail with "Identifier not declared".
Cells rebuilt for 32 x 20 (kearney_high ground 2.14). tests/khs_quest_test.tscn 0 failures: Act 1 starts, mq1/mq2
complete with rewards, reach KHS ticks, lair enemies wake (3 near gym, 11-12 in the north hall), Wren -> mq_wren,
Hunter talk -> fight (NPC hides, boss + guards spawn), Hunter + guards did 20 HP in 2 s, enrage at 50%, boss flag,
keycard drop -> pickup -> Detention done -> Acknowledged active, Wren freed and walks home, quest book on J.
Perf in the school: 5.6 ms frames, 148-257 draw calls, VRAM ~730 MB. Boss bar hides while the quest book is open.
Known: lobby + gym interiors are dark and bare; toasts queue (5 s each) so a burst of quest news lags; if every
player goes down near a boss it sleeps and comes back at full health.
BONK BARKS + FILLER LOOT + MEEPO + NEW MODELS (2026-11-09, D-056/D-057/D-058) - built + pushed, tests pending:
Bonk: 27 idle barks + context barks (landmark arrivals once each, bosses within 30 m, players riding/high) and a
deeper "Let's just talk" tree (bonk.json; bonk.gd _context_barks). Meepo: "meepo" gear item from the bunker's
MeepoDock (group meepo_chargers), B rides (MeepoRider "Meepo" player child, MeepoRules pure, data/tuning/meepo.json),
11 m/s, battery drains rolling / recharges near the dock, no firing, >=15 dmg knocks you off, HUD shows battery.
Models: Quaternius UBC male/female + UAL anims unpacked into assets/characters/{ubc,ual}; 6 new player models
(ubc_* in character_models.json) dressed by shaders/outfit.gdshader (bone-region colours) + hair + hand props;
first-person arms use fp_model. Filler loot: tools/landmarks/build_pois.tscn (+ poi_building.gd) built 14 small
POIs (diners, gas station, pharmacy/vet, stores, garage, offices) from tagged OSM buildings -> world/landmarks/
poi_NN.scn + data/map/pois.json (merged into landmarks by landmark_loader + build_cells); build_cells now writes
LootSpots (invisible streamed LootContainers, layer 8 only, no Sync) on curb cars, trash cans, porch packages and
yard barrels/boxes, <=40 per cell; streamed spots save/restore their contents through SaveDirector.world on
cell load/unload (host). New loot tables poi_*, porch, trash, car_trunk. Cells rebuilding.
PAUSED by user (2026-11-09 23:42). Done: POIs built (14), cells + world map rebuilt (640 cells, POI heights in
index), tests/filler_loot_test.tscn 0 failures (14/14 POIs placed, POI + loot-spot open/take, spot contents survive
cell unload/reload; perf at Perkins 5.6 ms, 357 draw calls, VRAM 910 MB). POI interiors are dark (one dim light).
NEXT: run tests/meepo_test.tscn (was stopped mid-run, no result), tests/ubc_look_test.tscn, khs + coop
regressions, then export a new alpha (tools/export/export_alpha.tscn + smoke_alpha). Harmless noise: enemies.json
schema warns on unknown keys (scale, tint, boss, ranged...) - schema never updated for D-055 fields.
RESUMED + FINISHED (2026-11-10): meepo_test 0 failures after fixing the battery (see FAILED), riding 9.6 vs walking
4.3 m/s. ubc pistol prop now rot_deg [0,90,90] (grip down, barrel forward; side close-ups ubc_cand_*.png).
khs_quest_test 0 failures, coop_test PASS (0 failed). New alpha exported: C:/Users/Fishb/BonksAlpha.zip 2160 MB
(pck 2201 MB, up from 2045 - new models + POIs); smoke run exit 0 with the usual forced-quit sync noise only.
DOWNTOWN BARS + RAIDERS (2026-11-10, D-059..D-062) - built + pushed, cells rebuilding, tests pending:
Raider faction on the enemy body (zombie.gd team from "faction"; perceives players + other-faction bodies);
EnemyDB now ignores optional keys in validation (no more unknown-key warnings). Enemies raider_gunner (ranged,
armed), raider_brute (bat via weapon_slot 1, melee), boss copperhead (Pit under Copperfields, enrages at 50%,
drops). Models raider_gunner_m / raider_scout_f / raider_brute_m / raider_brute_f / raider_boss: UBC bodies +
outfit + primitive "gear" props (bone axes measured with tools/assets/bone_axes.tscn: Head/spine/pelvis axes =
model axes, upperarm_l +X down +Y outward; model faces +Z, metres). Bars built by
tools/landmarks/build_downtown_bars.tscn (Copperfields 37 meshes/10k tris, Brix 26/4.7k, The Other Side 30/4.2k,
Gillie's 30/6k). Side quest sq_last_call (auto start). Test: tests/downtown_test.tscn.
DOWNTOWN DONE (2026-11-10): after the exclusion fix (see FAILED) downtown_test 0 failures (bars placed, interiors
clear, raider vs zombie fight, kills_raider counted, Copperhead spawn/enrage/death/drops, Last Call reward,
strongbox), perf at the 21st St camp 5.6 ms, 589 draw calls, VRAM 1330 MB, 8 lair bodies active. coop_test PASS,
khs_quest_test 0 failures. Alpha exported: C:/Users/Fishb/BonksAlpha.zip 2166 MB; smoke exit 0.
Bar positions are estimates from the addresses (Brix and The Other Side least certain) - user to confirm.
START SCREEN + FIXES (2026-11-10, D-063..D-065): StartMenu (scripts/ui/start_menu.gd on $UI/Menu, built in code):
BONK'S BUNKER, Singleplayer (Net.start_offline: OfflineMultiplayerPeer, no Tube), Multiplayer (host/join by code),
Settings (shared SettingsMenu), Controls (from the InputMap), Quit; WorldPicker gained Delete + confirm. main.gd keeps
world_picker / code_field / status_label as getters (tests unchanged). Loot window: Take 1 / Take Stack / Take All,
selection kept between updates. Quest book: tick/untick any active quests (main quests tracked unless unticked),
HUD lists up to 3, map draws a diamond per tracked quest; tracker hidden while the book is open. Meepo: 13 m/s,
drain 0.055/s (~30 min), instant recharge, idle arms/body while riding (no walk bob). World map labels for the four
bars (size "poi": red marker). Tests: menu_test 0 failures, meepo_test 0, coop_test PASS.
HUD ICONS + MINIMAP + PAUSE (2026-11-10, D-066..D-068): StatusBar (scripts/ui/status_bar.gd) draws icon chips
(HudIcons, vector icons in code) for HP/food/water/Meepo, effects on a row above; the old Health label is hidden.
Minimap (scripts/ui/minimap.gd, child of HUD) top-left, rotates with yaw, 360 m across, labels/POIs, Bonk,
teammates, tracked-quest diamonds pinned to the edge; hidden under full-screen windows. F3 perf overlay moved
bottom-right. PauseMenu (scripts/ui/pause_menu.gd, added under $UI by Main): Esc; solo pauses the tree; Save & Quit
-> Net.leave_to_menu swaps Main for a fresh copy (not reload_current_scene, so it also works under tests);
SettingsMenu now only opens on Esc from the start screen. ControlsList shared by start + pause. Meepo cruise 15 m/s,
sprint boost 20 m/s at 3x drain (boost when speed > ride_speed + 0.5). Tests: hud_pause_test 0, meepo_test 0
(13.1 cruise / 17.4 boost avg over 2 s), menu_test 0, chillers_test 0, coop_test PASS.
DISC GOLF (2026-11-12, D-069): Centennial Park DGC, 9 holes par 27 (UDisc lengths exactly; spots traced from the
user's UDisc screenshot, tees on the white pads, baskets at the "Main" icons). E at the course box (by hole 1 tee)
starts a round for everyone within 40 m and hands out Wasteland Driver / Prairie Midrange / Bunker Putter. 3 = disc
out / next disc, hold LMB charge, release throw, RMB cancel, Z/X or wheel tilt, F backhand/forehand, Q scorecard.
Host simulates the whole flight at throw time (60 Hz, physics rays for ground/walls/trunks, crown hits from the
planted trees, basket rules) and sends the path; lie = landing spot, max 8 a hole, 60 m outside the park = out.
Rewards dg_finish / dg_par / dg_ace (Golden Ace Disc); world best in quest flag dg_best_centennial.
Zombies cleared from / not spawned in the park during a round. 265 course trees traced from the satellite image.
Flight: driver 115 m, mid 79 m, putter 54 m at full power on flat ground; fade only once a disc has slowed to 85% of
its launch speed, so putts fly straight. HUD power mark = power that reaches the chains (1 m up).
Cells + world map rebuilt with the course (356 trees around the course incl. street/yard trees; map label added).
Host gathers the course trees once at round start (~75 ms) and again only if a course cell reloads; each throw
then simulates in ~1 ms. tests/disc_golf_test.tscn 0 failures (one run: drive clipped a crown and dropped 18 m
short, holed in 5; another aced), perf at the course 5.7 ms, ~530-550 draw calls, 265 MB.
Regressions after: coop_test PASS, hud_pause_test 0, menu_test 0 (controls list shows the disc keys).
tests/parse_check.tscn = dev helper that loads the disc golf scripts and reports parse errors with line numbers.
STREETS + COTTONMILL + DROP ZONE (2026-11-12, D-070..D-074): map widened 2 km west (x_min -3840, 40 x 20 = 800
cells; OSM, MS buildings and 3DEP re-fetched). Street signs at all 725 named-street intersections (StreetSigns in
cells; Label3D culled at 45 m); 1,151 street names on the minimap (upright). Disc golf scorecard only near the
course (D-071). Quick eat/heal keys work with the inventory open; moving cancels with a "Stand still" note (D-046
kept). Cottonmill DGC: 19 holes (incl. 9½) from the user's UDisc screenshot at 0.53 m/px, 5,296 ft for the 18,
par 4 on 3/10/15; 981 traced trees; Cottonmill Lake's east arm traced into water.json overrides. Drop Zone at 101
11th Ave: building (25 meshes, 7.2k tris), 32 bays, range + 7 targets, nets; target game (20 balls, clubs driver /
7-iron / wedge, carries 200 / 140 / 90 m), 18-hole putting course (generated layout, par 44), 4 pickleball courts
vs CPU. Tests: dropzone_test 0 (range bullseye, putt, rallies: CPU returned 12), disc_golf_test 0 (+ street
signs, Cottonmill built/snapped/round), coop PASS, menu 0, hud_pause 0, quick_use OK. Perf: Drop Zone 6.3 ms /
263 draw calls; Centennial 5.9 ms / 554. Existing saves: streamed loot spots re-key (cell indexes shifted by 8).
RELEASES (2026-11-12, D-075): project now at C:/1Bonks_Bunker (robocopy copy, 3.1 GB, .godot kept; OneDrive original
untouched). tools/release/release.tscn + data/release/release.json: preflight (export templates, git, gh logged in) ->
git init / gh repo create on first run -> export Windows + macOS presets -> smoke the Windows exe 600 frames -> zip,
split >1.9 GB -> commit + push main -> gh release create alphaX.Y --prerelease with both. Added macOS preset
"Bonks_Bunker_Mac" (universal, built-in ad-hoc codesign, library validation off for the WebRTC framework) and
rendering/textures/vram_compression/import_etc2_astc=true (Apple Silicon needs ASTC; first export re-imports textures).
Both presets exclude build/*. First run: preflight stopped — Git and GitHub CLI not installed. Not yet verified: a full
release, the Mac build on a real Mac. tools/export/copy_to_new_home.* is a one-off (safe to delete).
