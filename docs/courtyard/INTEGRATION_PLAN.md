# Kengeki courtyard: integration plan (Agent 3, environment integrator)

Branch: `feature/kengeki-courtyard`, created from `origin/character-integration` at `ed5cba4`.
Engine: official Godot **4.3-stable** (`v4.3.stable.official.77dcf97d8`) only.
Status: Phase 1 inspection done; asset-independent prep (graybox skeleton) in place.
Nothing here has been visually or gameplay tested. All checks so far are headless.

## 1. Findings (Phase 1)

### Repository and branches (as of Oct 30, 2026, 6:25 PM EDT)
| Branch | Head | Notes |
|---|---|---|
| `claude/gallant-bardeen-ubrjum` (GitHub default; there is **no `main`**) | `c3a0b68` | foundation + AccuRIG character + Overhead Cut tweak |
| `character-integration` | `ed5cba4` | same as above (tweak re-applied as `b7eb3f0`) + music system. Newest; chosen as base |
| `character-assets` | `75a63e1` | older ancestor |

No blueprint, asset manifest, GLB or environment docs exist on any remote branch
(`assets/environment/` holds only `.gitkeep`). On the shared box there was no
`/workspace/kengeki_assets/library/` yet and no blueprint from Agent 1. The only environment
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

1. **New arena scene, same interface.** `res://environment/courtyard/scenes/courtyard_arena.tscn`
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
5. Spawn markers, player start and the four lantern / one tree obstacle positions are copied
   from the placeholder until Agent 1's blueprint gives new ones.

## 3. Conventions

```
res://environment/courtyard/
  assets/<Category>/<asset>/<asset>.glb   optimised GLBs copied from BJORN's library (read-only source)
  modules/   architecture & landscape wrappers (walls, gate, bridge, pond, buildings, paths)
  props/     smaller props (lanterns, trees, rocks, ...)
  materials/ shared graybox materials gb_*.tres (one instance per material, reused)
  scenes/    courtyard_arena.tscn, main_courtyard.tscn, modules_gallery.tscn
  scripts/   courtyard_prop.gd, courtyard_arena.gd
tools/courtyard/  gen_graybox.py (regenerates graybox), check_courtyard.gd (headless checks)
```
- Names: `snake_case`, size in the name where it matters (`wall_straight_6m`, `pond_12x7`).
- Units metres, Y-up, −Z forward. Module origin = bottom centre; length on local X;
  courtyard-facing side +Z. Instances are placed only by translation + Y rotation (no scale).
- Each wrapper: `Graybox` (meshes) / `Collision` (StaticBody3D) / runtime `Model`.
- Graybox sizes: walls 5.4 m tall, 1.2 m thick (6 m and 4 m), corner 1.6 m, main gate
  8 m wide / 4 × 4.2 m opening / ~7.2 m tall (doors closed), arched bridge 8 × 2.2 m with 0.6 m
  crown (11.3° ramps, 1 m rails), pond 12 × 7 m with 1 m invisible barrier and a 2.6 m bridge
  corridor, hall 10 × 7 m, tōrō 2.0 m, pine ~5 m, rock 1.5 m, stone path 4 m.

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
- Default: commit an optimised GLB directly if it is ≤ 10 MB (GitHub hard limit is 100 MB per
  file; the repo already carries a 34 MB release zip). Larger GLBs stay out of git: they are
  listed in `environment/courtyard/assets/MANIFEST.md` with sha256 and box source path and copied
  in by a sync script. Because wrappers fall back to graybox, the branch still opens cleanly
  without them.
- Reference point: the test tōrō is 33.7 MB with 3 × 4K textures, too big to commit as is; an
  optimised version with 1K–2K textures should fit.

## 6. Needed from Agent 1 (Bill): blueprint
1. Courtyard footprint and wall line. Keep 40 × 40 m inner (±20 m), or change it? (Changes the
   bake AABB and `EncounterManager.arena_half_extent = 18.8`, which lives in main.)
2. A coordinate table (x, z, yaw in degrees, Y-up, origin = courtyard centre, −Z = north / keep side)
   for every gate, wall run, building, pond, bridge, lantern, tree, rock and path.
3. Central combat area: exact clear radius/rectangle with no obstacles (current lanterns at
   ±8 m leave a ~16 m clear square).
4. Player start and ≥ 6–8 enemy spawn points, each ≥ 7 m from the player start and with a clear
   3.5 m walk toward the centre (enemies walk inward when they spawn).
5. Which areas are walkable vs. blocked (pond, behind buildings, gardens), bridge count and
   whether bridges are on the combat route or decorative only.
6. Gate: functional entry (opens) or closed backdrop? (Currently closed.)
7. Backdrop beyond the walls (keep, tower, trees) and time of day / lighting mood.

## 7. Needed from Agent 2 (BJORN): per asset
1. Optimised GLB path in the library and sha256; file size.
2. Real-world dimensions after scaling, and confirmation that the origin is bottom centre,
   Y-up, front facing −Z or +Z (state which).
3. Triangle count, texture resolution per map, material count, and whether lighting/AO is baked
   into the albedo.
4. Suggested collision (box/cylinder sizes) or confirmation that I author it.
5. Known problems (holes, double-sided faces, pivot offsets, licence/redistribution limits
   for a public GitHub repo).
6. Priority order and ETA for: wall 6 m / 4 m / corner, main gate, bridge, pond edge, a hall
   building, path stones, pine/sakura, rocks.
