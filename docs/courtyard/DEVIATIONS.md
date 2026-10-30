# Courtyard: deviations from Agent 1's blueprint

Blueprint: `/workspace/kengeki_design/agent3_handoff.md` + `layout_data.py`
(sha256 `ab13ae0c…89c0d1`, Oct 30, 2026, 6:29 PM EDT), plus Bill's addendum in `agent3_handoff.md`
("Addendum, Oct 30 6:40 PM ET"). Bill reports Kirk approved the blueprint and the library
lantern at 6:36 PM EDT (relayed via Bill; not confirmed by Kirk to Agent 3 directly).
The graybox is generated from `layout_data.py`, which is read in place (never copied or
edited) by `tools/courtyard/gen_graybox.py`. Every placement, spawn, path and prefab comes
from that file; re-run the generator after the blueprint changes.

Layout, coordinates, colliders, spawns, nav AABB and Sun distance follow the blueprint.
The deviations below are about file locations and graybox detail only.

| # | Blueprint says | Built | Why |
|---|---|---|---|
| 1 | `scenes/arena/castle_courtyard.tscn` | `environment/courtyard/scenes/castle_courtyard.tscn` | Kirk's brief fixes the courtyard folder convention `res://environment/courtyard/{assets,props,modules,scenes}`. Same scene name. |
| 2 | `scenes/main_courtyard.tscn` | `environment/courtyard/scenes/main_courtyard.tscn` | Same reason. It is still a copy of `main.tscn` with only the Arena instance changed. |
| 3 | `scripts/arena/courtyard_arena.gd`, `class_name CastleCourtyardArena`, AABB hard-coded in `bake_navigation()` | `environment/courtyard/scripts/courtyard_arena.gd`, `class_name CourtyardArena extends Arena`, AABB is an `@export nav_bake_aabb` set in the scene to `AABB(-40, -0.6, -47, 80, 2.6, 82)` (addendum: bake y −0.6..2.0) | Same bake settings. Exported so a blueprint change does not need a script edit. `arena.gd` is untouched. |
| 4 | `assets/environment/courtyard/<asset>/<asset>.glb`, prefabs in `scenes/environment/courtyard/<asset>.tscn` | GLBs: `environment/courtyard/assets/<Category>/<asset>/<asset>.glb` (BJORN's library categories). Prefabs: `environment/courtyard/modules/` (architecture) and `.../props/` | Folder convention, plus matching BJORN's `library/<Category>/<asset>/` layout. Name map in `CATEGORY` in the generator. `stone_lantern_toro_2m` maps to BJORN's `Decorations/stone_lantern_toro`. |
| 5 | Props: "primitive colliders, or instanced prefab bodies, all inside this group" | Lantern, tree and rock prefabs (visual + own StaticBody3D) sit under `Collision/Props/*`, so their graybox visuals are under `Collision`, not `Visual` | Uses the blueprint's "instanced prefab bodies" option. It keeps one prefab per asset for the GLB swap. Shrubs and small rocks have no collider. |
| 6 | Walls as MultiMeshInstance3D ×68 "or 68 instances" | 68 prefab instances | Allowed by the blueprint. Switch to MultiMesh with the real GLB once draw calls have been measured. |
| 7 | Pond is an ellipse (rx 5.5, rz 5.0) | Rectangular graybox water plane (11 × 10 m at y −0.3) and basin. The 7 `pond_edge_stones_2m` sit on the ellipse as listed. | Graybox only. Collision is exactly the blueprint's rectangular hole and fences. |
| 8 | Arch bridge rails (addendum: ~1.0 m above the deck, following the arch, short box colliders) | Per side: one 4 m box over the flat deck plus one 4.61 m box per ramp tilted ±12.53° with the ramp, 0.15 m thick, top 1.00 m above the deck surface (1.02 m at the ramp sample points). Graybox visual rails follow the same line. | Implements the addendum. Pond fences and slab rails unchanged at 0.9 m. |
| 9 | Addendum: no walkable roofs or wall tops | Bake top lowered to y 2.0 as specified. That alone left 4 small unreachable islands (16 vertices at y 2.15) on top of the 1.8 m `rock_formation_large` colliders, which fit under the 2.0 m bake top. `CourtyardArena` now drops navmesh polygons that lie entirely above `nav_max_walk_height` (export, 1.8 m) after baking. The arch deck bakes at 1.4 m and is kept. | Rock tops are not roofs/walls, but the same snap risk applies. Set the export to −1 to disable. |
| 10 | Addendum lighting: late afternoon, sun ~35° up from the SW, modest shadows, no heavy post | `Sun`: elevation 35°, coming from azimuth 225° (SW), warm colour (1, 0.86, 0.7), energy 1.05, shadow opacity 0.8, blur 1.5, max distance 90 m. Environment unchanged (Filmic, exposure 0.9, light fog 0.004, no glow/SSAO/SSR). | Draft only; not looked at in a window yet. |
| 11 | Lantern collider (BJORN recommends a convex hull, or box + cylinder) | `props/stone_lantern_toro_2m.tscn` keeps the graybox cylinder: r 0.45, h 2.0, base at 0 | Simple and cheap, matches the brief's "simple collider". The lantern's footprint is 0.83 × 0.92 m, so r 0.45 covers it. |
| 12 | Blueprint lookup by asset name | `gen_graybox.py` resolves each asset to the first repo GLB under `environment/courtyard/assets/<Category>/<name>/<name>.glb`, trying the mapped category, then `Courtyard/`, then `Decorations/`, with BJORN's name and Bill's name. Missing → graybox only. | BJORN's new assets may land under `library/Courtyard/` as well as category folders. |
| 13 | Wall runs end at the turret / gate footprint edge (Bill's 8 × 8 turret, 16 m gate) | 10 extra **visual-only** wall modules, one past each run end, tucked into the turret or gate body (`Visual/Walls/*_Fill*`, generated by `wall_fillers()` from the layout). Turret fillers are full 4 m modules (N x ±38; S x ±38; E/W z −44 and 32). The 2 gate fillers are the same module scaled to 2.2 m along its length (x ±5.8…±8, `FILLER_INNER_EDGE`). Collision unchanged. Walls: 68 → 78 instances. | BJORN's turret has a battered base: at the wall line it is ±3.74 m wide at the ground and ±2.81 m at 4.5 m, so the run ends (±4 m) left 0.26–1.19 m see-through gaps at all 8 junctions. The gate body is ±6.6 m at the ground and ±5.7 m at 4 m against run ends at ±8 m (1.4–2.3 m gaps). The gate is hollow inside (an open room |x| < 5.6 m behind the doors), so its fillers stop at the pier wall instead of running into the room; this leaves a slot up to 0.08 m near the top of the pier (y ≈ 4 m). Turrets are closed shells, so a full module inside is never seen. |
| 14 | Lantern: Bill's inventory says decimate 50k → ~8k tris | Arena lanterns use BJORN's `stone_lantern_toro_lod8k.glb` (8,000 tris, 1K textures, 1.91 MB). The 25k `stone_lantern_toro.glb` from the first delivery stays in the repo, unused (assets are not deleted). `gen_graybox.py` picks the variant via `MODEL_VARIANT`. | Matches Bill's budget; 25k → 8k cuts 170k tris over 10 lanterns. |
| 15 | Building colliders are Bill's boxes | Unchanged, but BJORN's meshes are smaller than the boxes in places, so the player stops short of the visible surface: gate collider 8 m deep vs a ~6.2 m body (~0.9 m short each side); turret 8 × 8 box vs a 7.5 m base that narrows to 5.6 m at 4.5 m (0.3–1.2 m short); hall 24 m box vs a 22.9 m mesh (~0.5 m each end). Wall mesh is 4.74 m tall vs the 5.0 m collider (0.26 m invisible lip on top, unreachable). | The brief asks for simple box collision. Reported, not changed; Bill can shrink the boxes if the gap reads badly in a windowed run. |
| 16 | Tri budget: wall module 3k | BJORN's wall is 13,134 tris (4.4× budget; REPORT flags it). With 78 instances the walls are ~1.02M of the scene's tris. Used as delivered; one shared mesh (instanced), and Godot's importer generates LODs. | Flagged to BJORN. A ~3k wall LOD would cut ~0.8M tris. |
| 17 | Arch bridge: Bill's graybox ramp/deck/rail blocks; BJORN's mesh centre leg at y 0 | Model sunk 0.15 m (`MODEL_FIT` → `model_offset`, new `CourtyardProp` export). Collision rebuilt as 10 box chords following BJORN's measured deck profile (`ARCH_PROFILE`, crown 0.70 m after the sink, steepest chord 17°), each 0.3 m thick and 2.4 m wide, plus a 0.15 m rail box per chord on each side whose top sits 1.0 m above the deck (`ArchDeck*`, `ArchRailL/R*`). Lead-in chords run from the model's end to the bank at ±7 m, y 0. The graybox prefab uses the same chords. | As delivered the deck ends sat 0.15 m (N) and 0.26 m (S) above the banks, a visible step. After the sink: N end flush, S end 0.11 m above the bank (the collider ramp hides the step for walking; visually a small lip). The sink drops the centre leg 0.15 m into the pond bed; the outer legs still end ~0.38 m above the water surface (not fixable by placement; for BJORN). |
| 18 | Bill's texture spec: 2K for the barracks and keep | Shipped at 1K with a JPEG albedo (BJORN: 2K broke the 10 MB git budget). Keep has 4 roof tiers, not 5, and its height is compressed (anisotropy 1.42) to fit 30 × 28 × 22. | Accepted as delivered; listed for Bill. |
| 19 | Placement helpers | `CourtyardProp` gained `model_offset`, `model_scale_xyz` and `authored_size` (Bill's size, used by the checks). No layout change. | Needed for the bridge sink and the 10 % checks. |

## Fixed: rotation bug in the generator (affects the first graybox commit `ffcf394`)
`gen_graybox.py` wrote the basis into the `Transform3D(...)` literal column by column, but
`.tscn` stores it row by row, so every yaw and tilt was mirrored. In `ffcf394` the barracks,
kura and E/W wall segments faced outward and the arch-bridge ramps sloped the wrong way.
Positions and collider sizes were right, so the earlier nav checks did not catch it. Fixed and
checked in Godot 4.3 (transforms read back from the loaded scene); the arch crossing and rail
checks now cover the ramps.

## Open issues found while building (for Bill and Kirk)
- **Navmesh islands on roofs and wall tops.** Resolved by the addendum (bake top 2.0 m) plus
  the high-polygon prune in #9. Check: 0 navmesh vertices above 2 m.
- **Lantern textures in the repo.** Godot's glTF import extracts the 3 embedded 2048² PNGs next
  to the GLB (4.36 + 2.01 + 2.66 MB), so each lantern costs about 18.8 MB in git (9.77 MB GLB
  + 9.0 MB PNG). The PNGs are imported VRAM-compressed (S3TC; normal map in normal-map mode).
  Alternative: `gltf/embedded_image_handling` = Basis Universal (nothing extracted, smaller repo,
  slower import). Kirk is deciding GLB storage; nothing pushed to LFS.
- **Lantern look (BJORN's warnings).** Baked AO in the albedo may look double-shadowed under
  Godot lighting; metallic channel has noise up to ~0.19; tangents are generated on import.
  Needs a windowed look.
- **Navmesh height offset.** The navmesh sits up to about 0.4–0.5 m above the collider tops at cell_height 0.25 (deck top 1.0 → navmesh 1.4). This is normal for the bake settings.
- **No visual or gameplay verification yet.** Everything above was checked headless only (see INTEGRATION_PLAN.md §8).
