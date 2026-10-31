# Kengeki courtyard: integration plan (Agent 3, environment integrator)

Branch: `feature/kengeki-courtyard`, created from `origin/character-integration` at `ed5cba4`.
Engine: official Godot **4.3-stable** (`v4.3.stable.official.77dcf97d8`) only.
Status: graybox built from `/workspace/kengeki_design/layout_data.py` (sha256 `ab13ae0c…89c0d1`) with
Bill's 6:40 PM addendum applied (nav bake y −0.6..2.0, no roof nav, 1.0 m arch rails, closed gate,
collision-free keep, late-afternoon draft sun). Kirk approved the blueprint and the library lantern
at 6:36 PM EDT per Bill. First real asset in: BJORN's `stone_lantern_toro` on all 10 lanterns.
Deviations: `DEVIATIONS.md`. Asset ledger: `environment/courtyard/assets/ASSETS.md`.
Nothing here has been visually or gameplay tested. All checks so far are headless.

## 1. Findings (Phase 1)

### Repository and branches (as of Oct 30, 2026, 6:25 PM EDT)
| Branch | Head | Notes |
|---|---|---|
| `claude/gallant-bardeen-ubrjum` (GitHub default; there is **no `main`**) | `c3a0b68` | foundation + AccuRIG character + Overhead Cut tweak |
| `character-integration` | `ed5cba4` | same as above (tweak re-applied as `b7eb3f0`) + music system. Newest; chosen as base |
| `character-assets` | `75a63e1` | older ancestor |

No blueprint, asset manifest, GLB or environment docs exist on any remote branch
(`assets/environment/` holds only `.gitkeep`). At 6:25 PM EDT the shared box had no
`/workspace/kengeki_assets/library/` and no blueprint. Bill's DRAFT blueprint appeared at 6:28 PM in
`/workspace/kengeki_design/` (handoff, design doc, layout PNG, `layout_data.py`). The library category
folders appeared at about 6:26 PM, still empty. The only environment
asset found is a test import at `/workspace/kengeki_assets/hunyuan_test/` (tōrō lantern, 50,012
tris, 3 × 4K textures, native height 1.09 m, `_2m` scaled copy, clean Godot 4.3 import; see
its `REPORT.md`).

### Main scene and hierarchy
`scenes/main.tscn` (main_scene) → `Main` (`scripts/main.gd`):
`Arena` (instance of `scenes/arena/arena.tscn`), `Player`, `CameraRig`, `Enemies`,
`EncounterManager/SpawnManager`, `UI/{HUD, EncounterMenu, DeathScreen}`.
`main.gd` uses only `arena.player_start` and `arena.get_spawn_points()` (typed `Arena`).

### Placeholder arena (`scenes/arena/arena.tscn`, `scripts/arena/arena.gd`)
- `Arena` (class `Arena`) → `Blockout` (`courtyard_blockout.gd`, @tool, generated at runtime),
  `Visual` (empty), `NavigationRegion3D`, `PlayerStart` (0, 0.05, 8), `SpawnPoints` (8 markers:
  N/S/E/W at ±17, diagonals at ±13, y 0.1), `Sun`, `WorldEnvironment`.
- Blockout: 40 × 40 m walled courtyard (inner faces at ±20 m, walls 3.6 m tall, 1 m thick),
  ground box 60 × 60, 4 closed gatehouses (visual only), 4 lanterns at (±8, ±8), a sakura at
  (−17, −17), 2 weapon racks at (±19.4, 8), castle-keep backdrop beyond the north wall.
  Collision and visuals are separate layers.

### Player and camera
- Player `CharacterBody3D`, layer 2 (`player`), mask 5 (world + enemy), floor snap 0.3, default
  floor_max_angle (45°). Movement/jump in `scripts/player/player.gd`.
- Camera `CameraRig` → `Pitch` → `SpringArm3D` (length 4.2, default ray probe,
  **default collision mask 1**: every layer‑1 object can push the camera in).

### Enemies, spawning, navigation
- Enemy `CharacterBody3D` layer 3 (4), mask 7 (world + player + enemy), `NavigationAgent3D`.
  Spawned by `SpawnManager` at the arena markers (≥ 7 m from the player, farthest half preferred);
  the `enter` state walks 3.5 m toward the world origin, then approaches.
- Navmesh is **baked at runtime** in `Arena._ready()` from StaticBody3D colliders on layer 1 in
  group `nav_source` (with children), agent r 0.5 / h 1.75 / climb 0.25, cell 0.25, bake AABB
  hard-coded to x/z −21…21.
- `EncounterManager.arena_half_extent = 18.8` clamps enemy ring slots (set in code/main scene).

### Collision layers (`project.godot`)
1 `world`, 2 `player`, 3 `enemy`, 4 `hurtbox` (katana blade area masks layer 4 only).

### Lighting / environment / rendering
- `Sun` DirectionalLight3D (warm, energy 1, shadows, max distance 70 m); WorldEnvironment with
  procedural sky, Filmic tonemap (exposure 0.9), light fog (density 0.004), saturation 0.92.
- Forward+ renderer, MSAA 3D ×2, 60 physics ticks. No LOD/occlusion settings changed from defaults.

### Import and test results on the base commit (headless; not visual/gameplay verification)
- `--headless --import`: exit 0. Only noise: 105 × `Parameter "m" is null` from
  `mesh_get_surface_count` in the dummy renderer (the repo's `run_tests.sh` already filters it).
- `tests/gameplay_tests.tscn`: **109 passed, 8 failed**. All 8 failures are character/animation
  tests and follow from the private `assets/models/kengeki/kengeki_character_animated.glb`
  being absent (gitignored, not on this box). Same 109/8 result on this branch.
- `--kengeki-smoke` is nondeterministic: on `main.tscn` it passed 1 of 3 runs (fails on
  "enemy hits 0"), so it is not a reliable gate by itself.

## 2. Safest replacement method

1. **New arena scene, same interface.** `res://environment/courtyard/scenes/castle_courtyard.tscn`
   has root `Arena` with `CourtyardArena` (extends `Arena`) and keeps the exact child names
   `PlayerStart`, `SpawnPoints/*`, `NavigationRegion3D`, `Sun`, `WorldEnvironment`. Nothing in
   player, camera, combat, enemy or encounter code changes. `CourtyardArena` only exports the
   navmesh bake AABB so the blueprint footprint does not require edits to `arena.gd`.
2. **Original arena untouched and selectable.** `scenes/arena/arena.tscn` and `scenes/main.tscn`
   are unchanged (the game still boots into the placeholder). The courtyard runs from
   `res://environment/courtyard/scenes/main_courtyard.tscn`, a copy of `main.tscn` whose only
   difference is the Arena instance. The final swap (after review) is a one-line change of the
   Arena `ext_resource` in `main.tscn`; reverting is the same line.
3. **Collision is authored, never derived from Hunyuan meshes.** Each module/prop wrapper has a
   `Collision` StaticBody3D with simple box/cylinder shapes on layer 1. All gameplay geometry
   sits under `Layout` (group `nav_source`), so the runtime navmesh bake picks it up.
4. **Models are optional at load time.** `CourtyardProp` loads `model_path` only if the file
   exists in the project, otherwise the graybox stays. Scenes never hold a hard reference to a
   GLB, so a missing/uncommitted GLB cannot produce a broken reference.
5. Everything placed (144 objects, 10 spawns, player start, paths) is generated by
   `tools/courtyard/gen_graybox.py`, which reads Bill's `layout_data.py` in place. The
   section 7 colliders are written by the generator with the blueprint's values. Re-run the
   generator after the blueprint changes. `castle_courtyard.tscn` is generated, so don't hand-edit it.

## 3. Conventions

```
res://environment/courtyard/
  assets/<Category>/<asset>/<asset>.glb   optimised GLBs copied from BJORN's library (read-only source)
  modules/   architecture prefabs, visual only (walls, turrets, gate, hall, barracks, kura, keep, bridges, pond stones)
  props/     prop prefabs with their own primitive collider (lantern, trees, rocks; shrubs/small rocks none)
  materials/ shared graybox materials gb_*.tres
  scenes/    castle_courtyard.tscn (generated), main_courtyard.tscn, prefab_gallery.tscn (generated)
  scripts/   courtyard_prop.gd (GLB drop-in wrapper), courtyard_arena.gd (Arena subclass, nav AABB export)
tools/courtyard/  gen_graybox.py (blueprint -> scenes), check_courtyard.gd (headless checks)
```
- Prefab names are Bill's asset names (`wall_segment_4m`, `main_gate_yaguramon`, ...).
  BJORN's library category for each one is in `CATEGORY` in the generator.
- Units are metres, Y-up, −Z north. The origin is the combat centre. Prefab origin is the base
  centre. Front (courtyard side) is +Z and the long axis is X. These match both Bill's handoff and
  BJORN's pipeline MANIFEST convention. Placement is translation plus yaw only.
- Each prefab has a `Graybox` (meshes), an optional `Collision` (StaticBody3D, props only) and a
  runtime `Model`.
- Arena tree: `Collision` (group `nav_source`: Ground, WallRuns, Turrets, Gate, Buildings,
  Pond fences, Bridges, Props/*) and `Visual` (Ground, Paths, Pond, Walls, Turrets, Gate,
  Buildings, Keep, Bridges), plus the gameplay interface nodes.

## 4. Collision layer use
| Layer | Use in the courtyard |
|---|---|
| 1 `world` | all environment collision (ground, walls, gate, bridge deck and rails, pond barriers, building/lantern/tree/rock shapes). Mask 0. Baked into the navmesh. |
| 2–4 | untouched (player, enemy, hurtbox). |

Decorative-only meshes (paths, canopies, roof overhangs, water surface) have no collision.
Open question for review: small props on layer 1 also push the camera spring arm. If that is
distracting, a later change could put decor on a new layer the player/enemies mask but the
camera does not; that touches `player.tscn`/`enemy.tscn` masks, so it needs approval first.

## 5. GLB storage plan
**Decision (Kirk, via Bill, Oct 30 6:48 PM EDT):** no LFS for now; commit optimised GLBs ≤ 10 MB
directly. PR target: new branch `map-assets` (from `character-integration` @ `ed5cba4`); draft PR #1.
Bill OK'd the rock-top nav cull (DEVIATIONS #9).

- Source of truth: BJORN's library on the shared box,
  `/workspace/kengeki_assets/library/<Category>/<asset>/{original,optimised}/`, read-only for me.
- Only **optimised** GLBs are copied into `res://environment/courtyard/assets/...`.
- Git LFS: `git-lfs` is not installed on the box and the repo is public; LFS would add a
  quota/bandwidth dependency and a client requirement for everyone who clones. Not adopted
  without Kirk's approval.
- Library status at 6:30 PM EDT: `library/<Category>/` folders exist but are empty, and there is no
  `stone_lantern_toro` yet. BJORN's pipeline self-test manifest (`pipeline/selftest/lib/MANIFEST.md`)
  shows the format I will consume: optimised path, sha256, dimensions, tris, textures ≤2048,
  origin at base centre, +Z front.
- Default: commit an optimised GLB directly if it is ≤ 10 MB (GitHub hard limit is 100 MB per
  file; the repo already carries a 34 MB release zip). Larger GLBs stay out of git: they are
  listed in `environment/courtyard/assets/MANIFEST.md` with sha256 and box source path and copied
  in by a sync script. Because wrappers fall back to graybox, the branch still opens cleanly
  without them.
- Reference point: the test tōrō is 33.7 MB with 3 × 4K textures, too big to commit as is; an
  optimised version with 1K–2K textures should fit.

### Asset intake (`tools/courtyard/sync_assets.py`)
- `python3 tools/courtyard/sync_assets.py` lists every blueprint asset and where it is found in
  BJORN's library (`<Category>/`, `Courtyard/` or `Decorations/`, under BJORN's or Bill's name).
- `--apply NAME` copies the optimised GLB only if it exists, is ≤ 10 MB, has a `REPORT.md`, and has
  a `MANIFEST.json` entry whose `validation_status` starts with PASS. It then logs it in
  `ASSETS.md` (bytes, sha256, time) and regenerates the scenes. I read the HANDOFF/REPORT by hand
  before each apply. Then: Godot 4.3 `--import`, set texture imports to VRAM, run the checks.
- Lantern (first asset): GLB 9,765,812 B; with the 3 extracted PNGs about 18.8 MB in git. No LFS.

## 6. Needed from Agent 1 (Bill)
Answered by the 6:40 PM addendum (nav height, no walkable roofs, rail heights, gate/keep,
lighting). Open: Kirk's direct confirmation of the approval, and the final time of day.

## 7. Needed from Agent 2 (BJORN): per asset
1. The library path and MANIFEST entry for each optimised GLB. Names should match Bill's asset
   names (the lantern is `Decorations/stone_lantern_toro` in your plan, and `stone_lantern_toro_2m`
   in Bill's; I map one to the other).
2. Dimensions within 10 % of Bill's authored sizes, origin at the base centre, +Z front, long axis X.
3. Tris and textures to Bill's budget (optimised ≤ 2K). File size per GLB, for the commit and LFS
   decision (§5).
4. Licence and redistribution notes: the GitHub repo is public.
5. A heads-up when each asset lands, so I can copy it (read-only) and swap it in.

## 8. Verification status (headless only)
Latest run (addendum + lantern, Oct 30, 2026, ~6:42 PM EDT):
- Godot 4.3 `--import`: exit 0, with no errors beyond the known dummy-renderer noise
  (`Parameter "m" is null`). The lantern material has albedo, normal and metallic/roughness
  textures (2048²) and is back-face culled (single-sided).
- `tools/courtyard/check_courtyard.gd`: **PASS (97 checks)**, navmesh 376 polygons. New since last run:
  - 0 navmesh vertices above 2 m; hall, barracks, kura, N wall, E wall and gate roofs not walkable
  - arch bridge crossable end to end over the deck (path max y 1.40, 15.2 m)
  - arch rails 1.00–1.02 m above the deck at z 0, ±3, ±5.5 on both sides
  - main gate blocks at z 30; keep volume has no colliders
  - sun 35.0° elevation from the SW
  - all 10 lanterns load the real GLB: 0.83 × 2.00 × 0.92 m, base at origin
  - all earlier checks (spawn clearance, nav paths from all 10 spawns, combat area, routes)
- `tests/gameplay_tests.tscn`: 109 passed, 8 failed, identical to the base commit (all 8 from the
  missing private character GLB).
- `--kengeki-smoke` on `main_courtyard.tscn`: 4 of 8 runs PASS; on the previous commit 2 of 3; on
  `main.tscn` 2 of 2 this time (1 of 3 earlier). Failures are always "kills 3 … enemy hits 0":
  the bot kills all enemies before one lands a hit. Flaky on both arenas; not changed (combat is
  out of scope).
- **Not done:** visual check (lighting, lantern look, baked AO), camera near walls, bridges and
  pond, FPS/draw calls, real play with 6–10 enemies. These need a windowed run and Kirk's eyes.

## 9. BJORN batch 1 (Oct 30, 2026, integrated ~8:30 PM EDT)
Read `library/HANDOFF.md`, `MANIFEST.json` and each asset's `stats.json` / `REPORT.md` (read only).
Copied with `tools/courtyard/sync_assets.py --apply` (sha256 matched against stats.json, git cost
≤ 10 MB, REPORT + MANIFEST PASS, bounding box measured with `glb_probe.py` within 10% of Bill):

| Asset | Measured vs Bill (m) | Facing |
|---|---|---|
| wall_segment_4m | 4.00 × 4.74 × 1.59 vs 4 × 5 × 1.6 (Y −5.2%) | front/back symmetric; BJORN's tiling check TILES_CLEANLY (gap 0, overlap 0) |
| corner_turret | 7.48 × 10.72 × 7.46 vs 8 × 10 × 8 (−6.5/+7.2/−6.7%) | symmetric square plan |
| main_gate_yaguramon | 14.67 × 10.91 × 8.00 vs 16 × 10 × 8 (−8.3/+9.1/0%) | doors on +Z; yaw 180 puts them facing into the courtyard |
| main_hall_goten | 22.93 × 9.42 × 12.00 vs 24 × 9 × 12 (−4.5/+4.7/0%) | veranda/steps on +Z (REPORT; candidate 3), facing the courtyard at yaw 0 |
| stone_lantern_toro lod8k | 0.83 × 2.00 × 0.92 | unchanged; replaces the 25k file in the arena (DEVIATIONS #14) |

Fit: see DEVIATIONS #13 (turret/gate gaps closed with filler modules), #15 (generous colliders),
#16 (wall tris). No z-fighting found in the geometry: wall modules butt end to end without overlap;
the only overlapping filler pairs sit inside the closed turret shells. The graybox fallback is kept
in every prefab (`force_graybox`, or delete a GLB to see it).

Texture imports set to VRAM-compressed with `tools/courtyard/vram_textures.py` (normal maps in
normal-map mode). Budget (`tools/courtyard/asset_budget.py`, .ctex sizes after import):

| Asset | GLB | Tris | Instances | Tris in scene | Texture VRAM (MB) | Git (MB) |
|---|---|---|---|---|---|---|
| corner_turret | corner_turret.glb | 12,000 | 4 | 48,000 | 4.89 | 5.48 |
| main_gate_yaguramon | main_gate_yaguramon.glb | 20,000 | 1 | 20,000 | 4.89 | 5.12 |
| main_hall_goten | main_hall_goten.glb | 25,000 | 1 | 25,000 | 4.89 | 6.23 |
| stone_lantern_toro_2m | stone_lantern_toro_lod8k.glb | 8,000 | 10 | 80,000 | 2.80 | 3.54 |
| wall_segment_4m | wall_segment_4m.glb | 13,134 | 78 | 1,024,452 | 2.80 | 5.27 |
| **Total** | | 78,134 unique | | **1,197,452** | **20.27** | 25.63 |

Headless results: Godot 4.3 `--import` exit 0 (only the dummy-renderer `Parameter "m" is null`
noise); `check_courtyard.gd` PASS (112 checks, navmesh 376 polygons) including new per-asset checks
(model shown on every instance, AABB within 10% of Bill, base at y 0, 78 wall instances sharing one
mesh); gameplay tests 109 passed / 8 failed (same 8 character-GLB failures as the base).

## 10. BJORN batch 2 (Oct 30, 2026, integrated ~8:50 PM EDT)
Same procedure as batch 1 (HANDOFF "Batch 2 notes", MANIFEST and stats read only).

| Asset | Measured vs Bill (m) | Facing / fit |
|---|---|---|
| bridge_arched_taikobashi | 13.00 × 1.80 × 2.40 (0%) | long axis X; yaw 90 spans the pond N–S. Sunk 0.15 m; box chords follow the arch (DEVIATIONS #17) |
| barracks_nagaya | 24.00 × 6.00 × 6.00 (0%) | long axis X, symmetric; yaw 90 runs it along the west lane |
| storehouse_kura | 8.00 × 7.00 × 6.00 (0%) | door on +Z; Bill's yaw 90 turns it to +X, facing path P8c (east) |
| castle_keep_tenshu | 30.00 × 28.00 × 22.00 (0%) | backdrop only: no collider (checked: no shapes in its volume) |

Budget after batch 2 (.ctex sizes after import):

| Asset | GLB | Tris | Instances | Tris in scene | Texture VRAM (MB) | Git (MB) |
|---|---|---|---|---|---|---|
| barracks_nagaya | barracks_nagaya.glb | 12,000 | 1 | 12,000 | 2.80 | 4.74 |
| bridge_arched_taikobashi | bridge_arched_taikobashi.glb | 8,000 | 1 | 8,000 | 2.80 | 4.59 |
| castle_keep_tenshu | castle_keep_tenshu.glb | 20,000 | 1 | 20,000 | 2.80 | 5.30 |
| corner_turret | corner_turret.glb | 12,000 | 4 | 48,000 | 4.89 | 5.48 |
| main_gate_yaguramon | main_gate_yaguramon.glb | 20,000 | 1 | 20,000 | 4.89 | 5.12 |
| main_hall_goten | main_hall_goten.glb | 25,000 | 1 | 25,000 | 4.89 | 6.23 |
| stone_lantern_toro_2m | stone_lantern_toro_lod8k.glb | 8,000 | 10 | 80,000 | 2.80 | 3.54 |
| storehouse_kura | storehouse_kura.glb | 6,000 | 1 | 6,000 | 2.80 | 4.82 |
| wall_segment_4m | wall_segment_4m.glb | 13,134 | 78 | 1,024,452 | 2.80 | 5.27 |
| **Total** | | 124,134 unique | | **1,243,452** | **31.46** | 45.09 |

Headless results: Godot 4.3 `--import` exit 0 (dummy-renderer noise only); `check_courtyard.gd`
PASS (124 checks, navmesh 374 polygons): arch bridge on the navmesh at its crown, crossable end to
end over the deck (path y 0.40–1.15, 15.1 m, never dips into the basin), rails 1.00–1.02 m above the
deck at z 0, ±3, ±5.5, gate blocking at z 30, keep without collision, spawns, routes and combat area
unchanged; gameplay tests 109 passed / 8 failed (the same 8 character-GLB failures as the base).
Not verified: anything visual (seams, the 0.11 m bridge lip, z-fighting, lighting), FPS and draw
calls. These need a windowed run.

## 11. Performance pass, tighter colliders, bridge v2 and windowed screenshots (Oct 30, 2026, ~8:20 PM EDT)
Kirk's 7:52 PM brief plus BJORN's bridge v2 (8:06 PM).

**Bridge v2.** Synced with `sync_assets.py --apply bridge_arched_taikobashi` (sha256 `ed0d5937…`,
13.00 × 2.05 × 2.40 m, 8,000 tris, git 4.59 MB). Placement unchanged; sink 0.40 m, new symmetric
`ARCH_PROFILE`, 14 deck chords + 28 rail boxes (DEVIATIONS #17). Measured: both deck ends within
0.007 m of the banks; piers end at −0.40 (0.10 m under the water). Arch crossing PASS (path y
0.40–1.15, 15.2 m), rails 1.00–1.05 m above the deck.

**Mesh LOD.** `generate_lods=true` is set in all 10 BJORN `.glb.import` files. Godot's generator
output (ImporterMesh probe, merge/split angles 60/25, 90/60, 180/180): wall 13,134 → one LOD of
~5.4k; hall 25k → 14.6k; gate 20k → 13.0k; keep 20k → 14.6k; bridge 8k → 3.9k; lantern 8k → 5.9k /
3.0k; turret, barracks, kura: no LOD. UV seams lock most vertices, so a hand-made LOD from BJORN is
the real fix (DEVIATIONS #16). Applied per instance: wall `model_lod_bias` 0.3; lanterns hidden
beyond 55 m (+5 m margin). Collisions were already one box per straight wall run (5 boxes).

**Render cost** (`tools/courtyard/render_views.gd`, windowed Forward+ on Vulkan llvmpipe under
xvfb, 1280 × 720, `Performance` monitors after 8 frames per view; primitives include shadow passes).
"Before" = the previous settings reproduced with `--lod-bias=1 --shadow-mode=2 --shadow-dist=90`.

| View | Draw calls before → after | Primitives before → after | Objects before → after |
|---|---|---|---|
| 01 overview from gate | 149 → 98 | 2,202,486 → 853,630 | 336 → 226 |
| 02 combat centre, eye height | 109 → 66 | 1,857,352 → 692,652 | 244 → 159 |
| 03 pond + arch bridge | 110 → 74 | 897,742 → 620,292 | 174 → 132 |
| 04 wall / turret seam | 46 → 27 | 893,742 → 457,154 | 87 → 48 |
| 05 gate interior | 28 → 16 | 482,602 → 271,188 | 47 → 28 |
| 06 keep backdrop | 71 → 35 | 1,219,604 → 661,636 | 129 → 71 |
| **Total** | **513 → 316 (−38%)** | **7,553,528 → 3,556,552 (−53%)** | **1017 → 664** |

Breakdown (totals, same views): shadows off entirely 1.91M primitives / 139 draw calls (so shadow
passes were ~74% of the cost); 2 splits alone 4.67M; LOD bias 0.2 on every mesh alone 4.79M; 2 splits + LOD bias 0.3 on every mesh 3.50M; shipped (2 splits, bias 0.3 on walls only) 3.56M.
VRAM: 312 MB video memory, 166.5 MB textures (unchanged). llvmpipe FPS is not representative of a
Windows GPU, so no FPS is reported.

**Colliders** fitted to the measured meshes (DEVIATIONS #20). `check_courtyard.gd` PASS, 140
checks (navmesh 377 polygons): spawns, nav paths, routes, combat area, roofs/wall tops not
walkable, arch crossing and rails, gate blocking at z 30.68, keep without collision, model sizes,
and a new camera-clearance check (worst free arm 2.81 m, at the hall forecourt and barracks lane,
vs the 2.2 m minimum). Gameplay tests: 109 passed / 8 failed (the same 8 as the base).

**Screenshots** (`docs/courtyard/screenshots/*.jpg`, 41–75 KB each; also `/workspace/kengeki_shots/`):
- No missing textures on BJORN's models. Trees, rocks, shrubs and paths are still untextured
  graybox primitives (expected until those assets arrive).
- No z-fighting seen (gravel, paths and ground planes are offset).
- Wall/turret seams (04) and wall/gate junctions (05): closed, no see-through gaps; the patched gate
  fillers read as continuous wall.
- Bridge v2 (03): both ends sit on the banks with no lip; piers reach into the water; nothing floats.
- Found and fixed: the pond water was hidden under the outer grass plane in all earlier builds
  (DEVIATIONS #22).
- Lighting: readable at eye height (02, 05, 06) with warm late-afternoon light and soft shadows.
  The overview (01) is washed out: fog 0.004 plus a flat beige sky make the far half hazy and low
  in contrast. Worth a look on a real GPU before tuning.
- Keep backdrop (06): from the courtyard the main hall hides the keep's lower tiers; only the top
  two tiers show above the hall roof.

## 12. BJORN batch 3: stone slab bridge and trees (Oct 30, 2026, ~8:55 PM EDT)
Kirk's 8:38 PM brief; BJORN's "Batch 3 notes" in `library/HANDOFF.md` (read only).

**Intake.** `sync_assets.py --apply` for `tree_pine_kuromatsu`, `tree_sakura`, `tree_maple_momiji`,
and `bridge_stone_slab --variant deck2m` (only `bridge_stone_slab_deck2m.glb` is copied; the main
2.667 m-deck file is not needed because `MODEL_VARIANT` points the generator at the variant).
`generate_lods=true` on all four imports; textures VRAM-compressed by `vram_textures.py`. Graybox
fallbacks kept (trunk cylinder + canopy, slab deck box) and used whenever a GLB is missing.
Size checks: trees fitted to Bill's height (±10%, footprint may only be smaller or ≤ +10%), slab
11 × 0.4 × 2.667 exact (authored size).

**Slab bridge** (DEVIATIONS #25): (26, 0, 0), yaw 90, `model_offset` y −0.394. Deck top at y 0.000
(−0.005 … +0.002 along the walkable deck), supports to −0.394 (0.094 m under the water),
deck ends 0.5 m onto each bank. Deck box collider 2.0 m wide; invisible rail boxes at x 24.925 /
27.075, 0.90 m above the deck. Nav crossing: path low y 0.40 (navmesh), 16.0 m, centred on x 26.

**Trees** (DEVIATIONS #23): 6 pines, 5 sakura, 3 maples, one shared mesh per species, placed by
trunk at Bill's (x, z). Trunk-only cylinders (pine r0.45 h2.5 offset, sakura r0.4 h2.3, maple
r0.2 h2.0); canopies don't collide. PINE3 / PINE6 yaws changed to stop canopy clipping
(`tools/courtyard/tree_fit.py`: 0 clips at 0.25 m margin). Visibility range end 100 m (+10 m
margin); Godot's auto-LOD only saved ~3% at bias 0.05. Path spurs P5/P6 split at the pond (#24).

**Checks (headless, not visual/gameplay verification).** `check_courtyard.gd` PASS, 188 checks
(navmesh 379 polygons): 14 trees with 1 collider each, all outside the 40 × 40 combat square,
nearest spawn 4.0 m (SAKURA5); new routes (east path N/S, west path, gate forecourt → sakura
lawn W/E) pass; camera clearance PASS incl. the slab deck (worst 4.20 m there). Gameplay tests
109 passed / 8 failed (same 8 as the base).

**Budget** (`asset_budget.py`) before → after:

| | Before batch 3 | After batch 3 |
|---|---|---|
| Scene triangles (instanced) | 1,243,452 (124,134 unique) | 1,407,382 (160,120 unique) |
| Texture VRAM (BJORN assets, compressed) | 31.46 MB | 42.64 MB |
| Git cost (BJORN assets) | 45.09 MB | 67.98 MB |
| Godot monitors, video / texture memory | 312.0 / 166.5 MB | 324.8 / 177.2 MB |

**Render cost** (same method as §11, windowed llvmpipe, primitives include shadow passes):

| View | Draw calls before → after | Primitives before → after |
|---|---|---|
| 01 overview from gate | 98 → 89 | 853,630 → 1,057,958 |
| 02 combat centre, eye height | 66 → 58 | 692,652 → 859,532 |
| 03 pond + arch bridge | 74 → 71 | 620,292 → 700,754 |
| 04 wall / turret seam | 27 → 25 | 457,154 → 551,624 |
| 05 gate interior | 16 → 15 | 271,188 → 306,138 |
| 06 keep backdrop | 35 → 31 | 661,636 → 767,760 |
| **Total** | **316 → 289** | **3,556,552 → 4,243,766 (+19%)** |

Draw calls fell because each graybox tree (trunk + canopy, 2 meshes) became one mesh; primitives
rose with the 10–12k-triangle trees, mostly in shadow passes. Real tree LODs (~3–4k) from BJORN
are the fix if this matters on modest PCs.

**Screenshots** replaced (`docs/courtyard/screenshots/`, `/workspace/kengeki_shots/`); the
previous set is in `/workspace/kengeki_shots/before_batch3/`. Seen in the screenshots: trees stand
on the ground with no floating or wall/turret clipping (01, 02, 04, 06 + close-ups of PINE3, PINE6,
sakura and maples); no path strip over the pond; slab supports visible under the deck and the deck
meets the path ends flush (03). The slab stone reads near-white in sunlight, paler than the wall
stone. Maple trunks look slim; the pine root flare extends past its collider.

## 13. BJORN LOD pack, slab albedo v2, tree scales and batch 4 rocks (Oct 30, 2026, ~10:30 PM EDT)
Integrated from `/workspace/kengeki_assets/library/Courtyard/` (read only; HANDOFF "LOD pack + slab
albedo" and batch 4 notes). Not integrated: `rock_medium` (BJORN is regenerating it; stays graybox)
and `pond_edge_stones_2m`. Still to come from BJORN: rock_medium, pond stones, azalea, 16 m gate.

**LODs (DEVIATIONS #27).** Tree `_lod3k` (all three species), `wall_segment_4m_lod1/2`,
`corner_turret_lod1/2`, `barracks_nagaya_lod1/2`, `storehouse_kura_lod1/2`, wired as distance LODs
with `visibility_range_begin/end` and a FADE_SELF dithered crossfade (margin = fade width):

| Asset | LOD0 → lod1 | lod1 → lod2 | Fade | Tris LOD0 / lod1 / lod2 | lod1 textures |
|---|---|---|---|---|---|
| wall_segment_4m | 20 m | 45 m | 2 m | 13,134 / 5,000 / 404 | own (rebaked) |
| corner_turret | 30 m | 60 m | 3 m | 12,000 / 5,400 / 1,997 | **LOD0's** |
| barracks_nagaya | 30 m | 55 m | 3 m | 12,000 / 5,379 / 1,978 | own |
| storehouse_kura | 25 m | 50 m | 3 m | 6,000 / 2,700 / 1,000 | own |
| trees (lod3k) | 25 m | — | 3 m | 12,000 / 10,000 / 11,986 → 4,000 / 3,986 / 3,491 | **LOD0's** |

Shared-material LODs are imported with `gltf/embedded_image_handling=0` (`vram_textures.py`), so
only the GLB is committed. Mixed wall LODs tile: all three span exactly x −2.000…2.000 and the same
height; joint outline steps LOD0|LOD1 and LOD0|LOD2 are no worse than LOD0|LOD0
(`python3 tools/courtyard/wall_lod_seams.py`); no gap visible at the LOD0/LOD1 boundary in
screenshot 08.

**Slab albedo v2.** `bridge_stone_slab_deck2m.glb` re-synced (mean albedo 150/150/139 → 112/108/95);
mesh, fit and the invisible 0.9 m rail colliders unchanged (Bill's design). `_v1` backups not copied.

**Tree scales (DEVIATIONS #26).** Pine node scale (1, 1, 1.3), maple (1.237, 1, 1.238). PINE3 / PINE6
yaws re-fitted to 92 / 304 (0.10 / 0.05 m clearance to WE11 / TNE eaves).

**Rocks (DEVIATIONS #28).** `rock_formation_large` (+ `_b` at 0.9) and `rock_small_cluster`
(+ `_b`, both at 0.9), alternating over Bill's instances, one fitted box collider each. Nav cull
above 1.8 m unchanged.

**Checks (headless, not visual/gameplay verification).** `check_courtyard.gd` PASS, 264 checks, 0
FAIL (navmesh 426 polygons / 378 vertices, 0 above 2 m): LOD presence/ranges/fade/AABB per level,
shared-material LODs use LOD0's material with no texture of their own, rock colliders, small-rock
walk-around (longest path round one 5.6 m), combat area 0 hits, spawns/routes/camera clearance
PASS. Gameplay tests 109 passed / 8 failed (same 8 pre-existing character/animation/sheathe
failures as the base).

**Budget** (`python3 tools/courtyard/asset_budget.py --files`):

| | Before (after batch 3) | After LOD pack + rocks |
|---|---|---|
| Scene triangles at LOD0 (instanced) | 1,407,382 (160,120 unique) | 1,433,382 (170,120 unique LOD0) |
| Triangles drawn from the combat centre (LOD selection, no frustum culling) | — | 443,062 |
| Texture VRAM (BJORN assets, compressed) | 42.64 MB | 54.53 MB (+4.9 LOD textures, +7.0 rocks) |
| Git cost (BJORN assets, GLB + extracted textures) | 67.98 MB | 100.57 MB |
| Godot monitors, video / texture memory | 324.8 / 177.2 MB | 338.9 / 188.5 MB |

Git cost per new file (GLB + its extracted textures): wall lod1 3.73 / lod2 0.91; turret lod1 2.77
(GLB only, shared) / lod2 1.24; barracks lod1 4.05 / lod2 1.25; kura lod1 3.30 / lod2 1.08; pine
lod3k 1.16, sakura lod3k 1.03, maple lod3k 0.95 (GLB only, shared); rock_formation_large 3.46,
`_b` 5.15; rock_small_cluster 1.43, `_b` 1.35; slab v2 5.50 MB.

**Render cost** (windowed llvmpipe, primitives include shadow passes):

| View | Draw calls before → after | Primitives before → after |
|---|---|---|
| 01 overview from gate | 89 → 86 | 1,057,958 → 360,332 |
| 02 combat centre, eye height | 58 → 56 | 859,532 → 284,929 |
| 03 pond + arch bridge | 71 → 76 | 700,754 → 464,567 |
| 04 wall / turret seam | 25 → 26 | 551,624 → 545,356 |
| 05 gate interior | 15 → 18 | 306,138 → 331,138 |
| 06 keep backdrop | 31 → 33 | 767,760 → 404,668 |
| **Total** | **289 → 295** | **4,243,766 → 2,390,990 (−44%)** |

LOD views, LOD pack vs LOD0 at every distance (`render_views.gd --no-lods`):

| View | Draw calls | Primitives | LOD0 only: draw calls | LOD0 only: primitives |
|---|---|---|---|---|
| 07 LOD overview (30, 22, 46 → −8, 0, −28) | 118 | 566,876 | 127 | 2,623,370 |
| 08 wall LOD seam (34.5, 1.8, 27 → 38.6, 3.2, −30) | 101 | 720,964 | 103 | 1,864,272 |
| 09 long-range (85, 55, 95 → 0, 0, −8) | 83 | 234,573 | 95 | 1,572,000 |

Draw calls rose slightly in 03/05/06 (the 14 rocks are now textured models instead of graybox, and
instances inside a crossfade band draw two levels); primitives fell where walls and
trees are beyond 20–25 m. Views 04 and 05 are close-ups, so they stay mostly at LOD0.

**Screenshots** replaced (`docs/courtyard/screenshots/`, `/workspace/kengeki_shots/`); the previous
set is in `/workspace/kengeki_shots/before_lodpack/`. New: `07_lod_overview`, `09_lod_far` and their
`_tinted` versions (`--tint-lods`: LOD0 green, lod1 yellow, lod2 red) to show the LOD transitions,
and `08_wall_lod_seam` (LOD0/LOD1 wall boundary). Seen in the screenshots: LOD bands as expected
in the tinted views, no gap at the wall LOD boundary, slab less white, rocks seated on the ground
(the grey spheres are graybox `rock_medium`). Crossfade quality and popping need a windowed,
moving-camera look; a headless/llvmpipe still frame can't show them.

## 14. BJORN batch 4 final and the LOD texture-sharing rework (Oct 30, 2026, ~11:00 PM EDT)
Integrated from `/workspace/kengeki_assets/library/Courtyard/` (read only; HANDOFF batch 4 notes and the
corrected LOD section). This completes Bill's 16-item inventory: every item is placed with a BJORN mesh, no
graybox stand-ins remain (final table in `environment/courtyard/assets/ASSETS.md`).

**Pond stones (DEVIATIONS #29).** `pond_edge_stones_2m` + `_b`, 7 stones, node scale main (1, 2.0, 1.4) /
`_b` (1, 1.6, 1.4), sunk 0.32 m so each stone crosses the water and bank planes (no coplanar faces).
PSTONE3–6 moved 0.1–0.4 m off the slab bridge (Bill's spots were 0.01–0.47 m inside it; `pond_fit.py`).
One box collider each (`Collision/PondStones`); none over the bridge ends or the P5/P6 paths; the basin
stays non-walkable.

**Shrubs (#30).** `shrub_azalea` + `_b`, 12 shrubs, Y ×1.2, main sunk 0.08 m, no collision (Bill's
spec), hidden beyond 45 m.

**Gate (#31).** `main_gate_yaguramon_wide.glb` (15.34 m) replaces the 14.67 m gate (removed from the
repo). Closed-door blocking box refitted (x ±7.08, z 30.16…37.82, h 10.43). It is still short of the wall
ends at x ±8, so both gate fillers stay, shortened 2.2 → 2.0 m. Gap per side: ground 1.22 → 0.92 m,
wall top 2.30 → 1.83 m.

**rock_medium (#32).** BJORN's 1.5 × 1.0 × 1.2 m boulder at Bill's 8 positions, sunk 0.03 m, one box
collider 1.44 × 0.98 × 1.10 m. `rock_medium_stool` not copied.

**LOD rework (#33).** Wall lod1 (7,588), barracks lod1 (8,650), turret lod1 and the three tree lod3k use
LOD0's texture files (no textures of their own); wall/barracks/kura lod2 have their own 256 px textures
(JPEG albedo). Kura lod1 dropped: LOD0 → lod2 at 35 m. Old extracted lod1/lod2 textures removed. Tree
LOD size check back to ±5%. Wall seams (`wall_lod_seams.py`): LOD0|LOD1 joint p90 0.954 → 0.932 m
(LOD0|LOD0 baseline 0.949), LOD2 joints unchanged.

**Checks (headless, not visual/gameplay verification).** `check_courtyard.gd` PASS, 318 checks, 0 FAIL
(navmesh 442 polygons / 404 vertices, 0 above 2 m; spawns, routes, camera clearance, combat area,
pond basin, bridge crossings, gate collider, the new pond stone / shrub / rock_medium / filler checks).
`ref_check.gd` (new): 113 roots, 223 resources reached, 0 broken references, 0 unreferenced courtyard
textures/GLBs (the unused 25k lantern is allowlisted, DEVIATIONS #14). Gameplay tests 109 passed /
8 failed (the same 8 pre-existing character/animation/sheathe failures).

**Budget** (`python3 tools/courtyard/asset_budget.py --files`):

| | Before (`a3288d7`) | After batch 4 + LOD rework |
|---|---|---|
| Scene triangles at LOD0 (instanced) | 1,433,382 (170,120 unique) | 1,487,064 (180,066 unique) |
| Triangles drawn from the combat centre (LOD selection, no frustum culling) | 443,062 | 586,307 |
| Texture VRAM (BJORN assets, compressed) | 54.53 MB | 53.96 MB |
| Git cost (referenced GLBs + extracted textures) | 100.57 MB | 91.23 MB |

Git cost without the batch 4 additions (stones 2.69, shrubs 3.48, rock_medium 0.72, wide gate +0.77
over the old gate) is 83.57 MB, in line with BJORN's ~83.9 MB estimate for the LOD rework alone. With
batch 4 but the old LODs it was 108.24 MB. The drawn-from-centre count rises because the seam-preserving
lod1s are heavier (wall 5,000 → 7,588 × 78 instances) and batch 4 adds ~30k triangles near the centre.
Not counted: the unreferenced 25k lantern (18.80 MB in git).

**Render cost** (windowed llvmpipe, primitives include shadow passes):

| View | Draw calls before → after | Primitives before → after |
|---|---|---|
| 01 overview from gate | 86 → 88 | 360,332 → 413,568 (+15%) |
| 02 combat centre, eye height | 56 → 54 | 284,929 → 309,504 (+9%) |
| 03 pond + arch bridge | 76 → 78 | 464,567 → 610,355 (+31%) |
| 04 wall / turret seam | 26 → 26 | 545,356 → 555,708 (+2%) |
| 05 gate interior | 18 → 18 | 331,138 → 344,078 (+4%) |
| 06 keep backdrop | 33 → 33 | 404,668 → 484,998 (+20%) |
| 07 LOD overview | 118 → 114 | 566,876 → 654,064 (+15%) |
| 08 wall LOD seam | 101 → 103 | 720,964 → 800,030 (+11%) |
| 09 long-range | 83 → 78 | 234,573 → 241,133 (+3%) |
| **Total 01–09** | **597 → 592** | **3,913,403 → 4,413,438 (+13%)** |
| 10 pond stones close (21.5, 1.9, −7.5 → 28, 0, 0) | new | 79 / 642,573 |
| 11 pond stones east (33, 1.6, 6.5 → 30, 0, −1) | new | 113 / 662,936 |
| 12 gate exterior (10, 3, 48 → 0, 4, 34) | new | 81 / 600,452 |
| 13 gate seam close (−11, 2, 27.5 → −7, 3, 32) | new | 39 / 452,874 |
| 14 shrubs + rock close (19, 1.7, −8 → 24, 0.5, −12) | new | 84 / 916,523 |
| 15 shrub + rock west (−22, 1.7, −14 → −27, 0.5, −19) | new | 45 / 587,338 |

Split for 01–06 (batch 4 with the old LODs, then the LOD rework): batch 4 alone took the total from
2,390,990 to 2,487,530 (+4%), the heavier lod1s to 2,718,211 (+9%).

**Screenshots** replaced (`docs/courtyard/screenshots/`, `/workspace/kengeki_shots/`); the previous set is
in `/workspace/kengeki_shots/before_batch4/`. Seen in the stills: stones line the pond with no visible
z-fighting (they read pale, and one top has a dark patch); shrubs read well with a slightly dark base ring;
rock_medium sits on the ground; the gate meets the walls with no gap from inside (05, 13) or outside (12);
LOD bands in the tinted views as expected (kura shows lod2 in the lod1 colour, since it has only one
lower level); no gap at the wall LOD boundary (08). Crossfades and popping need a windowed,
moving-camera look.

## 15. Lantern cleanup and gate-side seal (Oct 30, 2026, ~11:15 PM EDT)

- **Unused 25k lantern removed** (Kirk, 10:58 PM EDT): `stone_lantern_toro.glb` and its 3 extracted
  2048² PNGs (+ `.import` files) are deleted from the branch; they remain in git history. The arena
  uses the lod8k file (DEVIATIONS #14). `ref_check.gd`'s allowlist is now empty. Git cost: the
  referenced-asset total stays **91.23 MB** (the budget never counted the unused file); the tracked
  `environment/courtyard/assets` directory drops from 110.15 MB to **91.35 MB** (−18.80 MB, incl.
  `.import`/docs).
- **Gate kept as is** (Bill): doors face the courtyard, not flipped.
- **Gate-side seal** (Bill: fillers close the wall line as blocking colliders in nav_source): the S
  wall-run boxes already reach 0.1 m into the gate box over the full wall height and thickness, so
  the filler volumes are fully inside nav_source colliders and no filler boxes were added.
  New `_gate_seal_checks` in `check_courtyard.gd`: filler volumes inside nav_source colliders,
  player-capsule sweeps blocked on both sides, no navmesh through the seam. The check found a small
  unreachable navmesh island inside the closed gate box (the bake box clips its roof); a nav-only slab
  `GateNavSlab` inside the gate box removes it (DEVIATIONS #31). Deviations #29–#33 approved by Bill.
- **Checks (headless):** `check_courtyard.gd` PASS, 325 checks, 0 FAIL (navmesh 439 polygons / 399
  vertices); `ref_check.gd` PASS (0 broken, 0 unreferenced); gameplay tests 109 passed / 8 failed (the same 8 pre-existing failures).

## 16. Navmesh island cull and connectivity check (Oct 30, 2026, ~11:25 PM EDT)

- A connectivity scan of the baked navmesh found 15 unreachable islands (29 of 439 polygons):
  the ground inside the 4 turrets, hall, barracks, kura, ROCKL1 and ROCKL3, and the tops of
  ROCKM1/2/3/6/7/8 (~1.4 m). The gate's island was already gone (`GateNavSlab`, §15).
- Fix: `courtyard_arena.gd` now culls every polygon not edge-connected to the polygon nearest the
  combat centre, after the existing >1.8 m prune (`nav_cull_islands`, `nav_main_seed`). No collider
  changed. Navmesh: 439 → 410 polygons, 1 region. DEVIATIONS #34.
- New `_nav_connectivity_checks` in `check_courtyard.gd`: one edge-connected region; a server path from
  the centre reaches all polygon centres; no polygon centre inside a collider; no navmesh inside the
  turrets / hall / barracks / kura. No intentional exceptions. Verified that it fails with the cull off.
- Checks (headless): `check_courtyard.gd` PASS, 335 checks, 0 FAIL; `ref_check.gd` PASS; gameplay tests 109 passed / 8 failed (same 8 pre-existing).
