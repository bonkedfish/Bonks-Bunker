# TRIED AND FAILED

Approach — why it failed — what replaced it.

- **Running the game right after adding new `class_name` scripts from outside the editor** — fails with
  "Identifier X not declared": Godot only registers named classes in `.godot/global_script_class_cache.cfg`
  when the editor rescans (on focus). Fix used: add the entries to that cache file (editor regenerates the same
  content later), or click into the editor window before running. (2026-11-08)
- **Re-pushing a file shortly after a previous push of the same path** (Claude's file bridge) sometimes wrote the
  OLD content while reporting success (seen twice on test scripts). Fix: after pushing, compare the device file
  size with the local one and push again if they differ. (2026-11-08)
- **Runtime navmesh bake from CSG gray box, collision-only parsing** — Godot still parses CSG as visual meshes
  (GPU read-back warning, one-time hitch at load). Kept for the test yard only; the map pipeline must bake from
  collision shapes or offline. Also: agent height/radius/climb must be multiples of cell size/height (0.25)
  or Godot rounds them with warnings. (2026-11-08)
- **Reading a test scene's output when it calls `get_tree().quit()` immediately** — the run tool lost all output.
  Fix: tests wait ~20 s before quitting. (2026-11-08)
- 2026-11-08 Bonk: `var x := node.health.is_dead()` on an untyped `Node` var → parser error "Cannot infer the type". Fix: type the var (`Node3D`) or the local (`var x: bool =`). Same-size re-push can't be checked by size: stage the file back and `cmp`.
- 2026-11-08 Bonk couldn't leave the bunker: the main-room table sat 1.2 m from the stair foot; with agent radius 0.5
  its erosion met the door-frame walls' erosion, so the stairs were a separate navmesh island (players fit, the bake
  didn't). Fix: table moved to the room's south side. Rule: keep ≥ 2 m clear in front of any doorway/stair foot.
- 2026-11-08 Bonk ground into the stairwell wall near the top: navmesh agent_max_climb 0.5 let paths climb onto the
  0.3 m hatch curb and out the side of the stairwell, but a CharacterBody3D can't step up. Fix: max climb 0.25 and
  curbs 0.6 m. Rule: nothing walk-over taller than ~0.1 m unless it's a ramp; max climb stays one cell (0.25).
- 2026-11-09 Map scope: I told the user the 2 km square "should reach UNK and downtown" — wrong; UNK is ~2 km north and
  downtown ~2.5 km NE of the house. Check real distances before describing an area option.
- 2026-11-09 Navmesh bake for 64 cells parses all cells once then bakes per cell with filter_baking_aabb + border 2 m:
  ~1 s/cell (77 s total build). Whole city (~600 cells) would be ~10+ min; fine offline, but don't bake at runtime.
- 2026-11-09 Offline counts as "server" in Godot (OfflineMultiplayerPeer): anything gated on is_server() runs in the
  menu/tests too. Perf CSV now also requires a non-offline peer.
- 2026-11-09 Per-cell navmesh: border_size is trimmed OFF filter_baking_aabb, so baking with the exact cell rect left a
  4 m gap at every cell edge (paths stopped 2 m short of the border; earlier "path reaches target" never crossed one).
  Fix: grow the bake AABB by border_size on each side + edge_max_error 1.0 (Godot's tile-aligned bake recipe).
- 2026-11-09 Quaternius Zombie Apocalypse Kit download (tools/assets/fetch_characters.tscn, Drive ids in
  data/art/characters.json): every file returned Google Drive's "Quota exceeded" HTML page (public share hit its
  download quota). Not a code bug: retry later, or the user downloads while signed in to Google. GDevelop's copy of
  the pack has no characters; no itch.io mirror found.
- 2026-11-09 (D-047) Generated landmark meshes looked black: triangles were emitted counter-clockwise with outward
  normals, but Godot treats clockwise as front and flips the normal on back faces (cull disabled) -> lit from
  below. Fix: LandmarkKit.tri emits (a, c, b); flat pieces always face up; flower quads use both windings + cull back.
- 2026-11-09 (D-047) River water as flat quads at the max corner height made visible stair steps along the canal.
  Fix: each water corner at its own surface height.
- 2026-11-09 Hunted a 144 ms spike seen once on the tower deck: could not reproduce with a 10 m/s park run + deck
  spin (no frame > 25 ms, no slow cell loads). Most likely a first-time shader/pipeline compile. If it shows up for
  the user, check WorldStreamer slow_events first, then shader warm-up.
- 2026-11-09 "Dark footpaths" were not (only) a lighting bug: the concrete_slab photo texture itself averages
  RGB 79/67/53. Fixed with tints, not by changing the strip geometry.
- 2026-11-09 Automated tests: teleporting a player into solid geometry (e.g. 30 m sideways while in the
  underground bunker, or behind the workbench into the south wall) gets them ejected/relocated - later steps then
  fail on distance. Move the other object instead, or pick open floor. Walking west from the bunker spawn hits the
  bunk room after 0.3 m; walk north from the room side of the workbench instead.
- 2026-11-09 (D-048) USGS 3DEP exportImage keeps pixels square IN DEGREES: when the requested size doesn't match
  the bbox's degree aspect it silently returns a taller/wider extent. We stored the requested bbox, so terrain was
  misregistered (scaled about the bbox centre; up to ~100 m off at the edges, lake dips smeared). The old 2 km file
  had the same error. Fix: fetch_elevation asks f=json first, saves the server's actual extent, downloads its href,
  and requests square-degree pixels. Verified: lake-vs-shore contrast peaks at 0 m offset (1.6 m).
- 2026-11-09 Archway lobby door: player stuck at the door - lobby floor top (0.05) was a 0.25 m ledge above the
  ground outside (-0.2); the controller doesn't step up that. Fixed with a threshold block + outside ramp.
- 2026-11-09 Evan's tinfoil hat on a BoneAttachment3D("Head") never showed up (scale/rest-pose maths unclear);
  replaced by a cone at a fixed height on the NPC root (hat_y in data/npcs/evan.json).
- 2026-11-09 device_commit_files stale-write hit 3 times this session (archway.gd, archway_test.gd,
  resident_npc.gd): always stage back + cmp.
- 2026-11-10 MeepoRider battery never changed: host_tick recomputed from net_battery each tick and only published
  changes >= 0.5, so the ~0.007/tick drain was always discarded. Fix: keep an exact host-side _level, publish it
  to net_battery in 0.5 steps.
- 2026-11-10 UBC pistol prop rot_deg [0,90,0] (picked from a far shot) actually hangs barrel-down in the hand;
  [0,90,-90] points backwards, x +-90/180 are off. [0,90,90] is right. Judge prop rotations from close side shots.
- 2026-11-10 Downtown bars first cell build: generated buildings still stood inside Copperfields and Gillie's
  (camera inside a concrete box; a roof through Gillie's floor). Cause: I placed exclusion circles at the
  footprints' bounding-box centres, but build_cells tests the polygon vertex average, and downtown blocks also
  have OSM ways (1339896636, 1339896648) I'd missed because my scan only looked near the bar's own address.
  Fix: replaces_osm_ways for those + exclusions at the vertex-average centroids; Brix's annex extended to the
  whole OSM block (to 20th St). Check overlaps of every building polygon against bar + annex rects, not by centre.
- 2026-11-10 LairDirector `m.get_meta("requires", null)` errors every check for markers without the meta (null
  default = no default in Godot 4). Fixed with has_meta.

- 2026-11-12 (D-069) Disc golf putting: the HUD/bot power came from the distance to where the disc touches the
  ground, so short putts arrived at ground level under the basket (pole/tray bounces, 7 strokes from 1 m). Fixed:
  the reach table measures to aim_height_m (1.0 m, the chains). Also: a function named _box clashed with the
  _box variable (parse error), Bonk is in group "players" (filter people by the "disc" child), and the bridge
  wrote stale copies twice again (always cmp after pushing).
- 2026-11-12 (D-069) Short putts still missed by 0.3-0.5 m: a low-power throw starts below fade_start of the disc's
  full speed, so it faded from the first frame. Fixed with fade_after_slow (fade only after slowing to 85% of its
  own launch speed). Gathering tree crowns on every throw (MultiMesh instance transforms across loaded cells) cost
  ~30-75 ms on the host; now cached and refreshed only when a cell overlapping the course loads.
- 2026-11-12 (D-073) Cottonmill Lake in OSM (relation 20670164) sits ~40 m west of the imagery around the course's
  east arm, which would have flooded holes 4/8. Fixed with water.json "overrides" (traced rings inside a rect at the
  OSM water level). Tree tracing on the Cottonmill screenshot picked up the dark lake as canopy until texture
  (local std dev) was required and the traced water was excluded.
- 2026-11-12 (D-074) First Drop Zone run: every range shot "hit the net" at once — the back-net check used the bay
  face (x 29.3) but the mats are inside the building (x 27.2). Now only a ball going 1 m behind the mat stops.
  The CPU at pickleball returned nothing (it ran to the predicted first bounce, then the ball hopped past it); it now
  runs to the top of the hop after the bounce (look-ahead on a copy of the ball, 10x a second) and reaches by
  horizontal distance.
- 2026-11-12 Quick eat (G) "didn't work": it does in game standing still; walking cancels it (D-046, kept) silently,
  and with the inventory open the key was ignored. Now works with the bag open and says "Stand still".
- (2026-11-12) Getting each release under GitHub's 2 GiB file cap by compressing harder: NO GAIN. World cells are
  already compressed binary resources (header RSCC); zlib and LZMA shrink them ~1%, and the Windows zip came out only
  ~7% smaller than the pck. Size has to come from less data (every land cell carries ~1.9 MB even when empty), not
  from compression.

- 2026-11-13 Ace replay hid the HUD by setting its `visible` = false: the HUD shows itself again every frame while a
  local player exists (hud.gd `_process`), so it stayed up. Fix: hud.gd hides itself while `player.cutscene`.
- 2026-11-13 Two chats edited the project at once (disc golf + sound) and both took D-076; the sound chat moved to
  D-077. Before writing a shared file (player.gd, director, diary), re-stage it and merge, never commit an old copy.
- 2026-11-13 Two sessions editing disc_golf_director.gd at once: the D-076 session saved its copy after the D-077
  session's commit, silently dropping the basket-sound hook; alpha2.2 shipped without disc golf sounds. Why it failed:
  device_commit_files only guards the file version the committer staged, not edits made after. Lesson: after any
  overlap, re-grep the shared file for your hooks before releasing (the disc golf test now checks contact sounds).

- 2026-11-13: device_commit_files pushed STALE content twice when the container file had been edited in place after
  an earlier commit or an earlier write to the same path (sed -i on kenwood_pool_test.gd; Edit on a p5/ copy of
  country_club.gd). The write is reported OK but the device file keeps the old bytes. Fix that works: copy the final
  file into a brand-new folder right before committing, then check the device size with device_list_dir.
- 2026-11-13: the two chats shared /mnt/user-data/outputs (p5/c2 already held the other chat's files) - always use
  a new, unique folder name per commit.
