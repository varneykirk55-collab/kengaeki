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
Latest run (addendum + lantern, Oct 30, 2026, ~6:50 PM EDT):
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
