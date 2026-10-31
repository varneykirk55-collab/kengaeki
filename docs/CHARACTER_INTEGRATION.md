# Character integration: AccuRIG samurai

The player's placeholder body has been replaced by the AccuRIG Kengeki samurai, with all seven
Mixamo-retargeted clips from `Kengeki/assets/animation_pipeline_output/` connected to gameplay.
Combat, AI, encounters, camera, UI and collision are unchanged; enemies keep the ronin placeholder.

Tested with Godot **4.3 stable** on Windows 10, AMD Radeon RX 560X (Vulkan / Forward+).

## Setup: the character asset is not in git

`kengeki_character_animated.glb` is a private asset, so it is ignored by `.gitignore` and must be
copied into the project once:

```
copy  Kengeki\assets\animation_pipeline_output\kengeki_character_animated.glb
  to  <project>\assets\models\kengeki\kengeki_character_animated.glb
```

Godot extracts its three textures next to it on first import (also git-ignored). If the GLB is
missing, the game still runs, but the player is invisible and an error names the missing path.
The original pipeline GLB is never modified; the project uses its own copy.

## What changed

| File | Change |
|---|---|
| `scripts/visual/kengeki_character_visual.gd` (new) | `CharacterVisual` for the AccuRIG model: AnimationTree, attack sync, katana attachment, jump compensation, procedural hit and death reactions |
| `scenes/characters/kengeki_samurai_visual.tscn` (new) | The player's `Visual` scene; `player.tscn` now instances it in place of `samurai_visual_placeholder.tscn` |
| `scripts/player/player.gd` | New `EQUIP` and `AIRBORNE` states: draw and sheathe, draw-attack, jump. All existing states and timings are unchanged. |
| `scripts/visual/character_visual.gd` | Four new interface methods with no-op defaults (`play_sword_equip`, `set_sword_drawn`, `play_jump`, `play_land`), so the placeholder and enemies are unaffected |
| `autoload/game_input.gd`, `scripts/ui/hud.gd` | Bindings for `jump` (C / pad A) and `toggle_sword` (E / D-pad up); updated HUD hint |
| `tests/gameplay_tests.gd` | 9 new tests with 42 checks for the character, animations, root motion, jump, katana and restart |
| `tools/capture_character.*` (new) | Renders reference screenshots into `build/character_shots/` (git-ignored) |

## Animations → gameplay

> **Update: KinemIQ combat clips.** Attacks, the guard and the drawn ready stance now use the
> KinemIQ clips (`Light_Slash_A`, `Light_Combo`, `Heavy_Slash_B`, `Heavy_Slash_C`, `Block`) in
> `assets/animations/kinemiq/kinemiq_combat.res`. The mapping, contact segments, blade
> clearance and tests are in [COMBAT_ANIMATIONS.md](COMBAT_ANIMATIONS.md).
> `Sword_Combo_OneHand` and the attack-timing table below are the fallback when that library is
> missing. Locomotion, jump, draw and sheathe are unchanged.

| Clip | Length | Gameplay | Layer and playback |
|---|---|---|---|
| `Idle_Unarmed` | 5.10 s | Standing (speed < 0.3 m/s) | Locomotion; loops |
| `Walk` | 0.90 s | Normal movement, lock-on strafing, walking while drawing or sheathing | Locomotion; loops; plays faster with ground speed (capped at 2.2×) |
| `Run` | 0.37 s | Sprint (> 5.4 m/s); also played fast during a dodge | Locomotion; loops; speed-matched (≈1.15× at 7.4 m/s) |
| `Jump` | 2.60 s | Jump (C / A) | Full body; airborne section 0.67–1.40 s stretched to the physics air time, then landing (cut short as soon as you move) |
| `Sword_Draw` | 1.20 s | Equip katana (E, or attacking or blocking while sheathed) | Upper body only, so the legs keep walking; 1.25× speed |
| `Sword_Sheathe` | 1.10 s | Unequip katana (E) | Upper body only; 1.25× speed |
| `Sword_Combo_OneHand` | 2.27 s | Every player attack, plus the guard pose (first frame) | Full body; the clip time follows the attack's startup, active and recovery phases (below) |

Locomotion uses an `AnimationNodeTransition` (0.18 s cross-fade). Actions use two seekable slots
that cross-fade between consecutive actions, blended over locomotion. Nothing restarts every frame;
the tests check that the run cycle keeps advancing.

### Attack timing

The combo clip contains three distinct cuts, located from the right hand's speed profile.
Each `AttackData.animation` maps to one segment, and every frame the clip time is interpolated
from the `AttackRunner` phase. As a result, the visible cut always plays inside the real hit window:

| Segment | Clip time: start → hit start → hit end → end | Used by |
|---|---|---|
| A, right to left | 0.25 → 0.458 → 0.625 → 0.708 s | Light Cut I, Piercing Thrust |
| B, left to right | 0.708 → 0.958 → 1.125 → 1.208 s | Light Cut II, Rising Cut |
| C, high finishing cut | 1.208 → 1.458 → 1.583 → 2.083 s | Crescent Wheel, Overhead Cut, Kesa-giri, Kaeshi-waza, Todome |

L → L → L therefore plays A → B → C, which is the clip's own combo, continuously. Hit detection
remains the existing `ARC_SWEEP`, and damage, guard, parry and finisher logic are untouched.
Tests measure that the hand's fastest motion falls in the `ACTIVE` phase for A, B and C.

## Root motion

All seven clips carry their ground travel on `RL_BoneRoot`. The AnimationTree's
`root_motion_track` is set to `Kengeki_Rig/Skeleton3D:RL_BoneRoot`, so that travel is removed from
the pose. The extracted motion is deliberately **not** applied, because the existing controller
already moves the `CharacterBody3D` (walk and sprint speeds, attack lunges, dodges, knockback),
and applying both would double the movement.

| Clip | Root travel in the clip | In game |
|---|---|---|
| Walk | 1.04 m per cycle | In place; the controller moves at 4.6 m/s |
| Run | 1.52 m per cycle | In place; the controller moves at 7.4 m/s |
| Sword_Combo_OneHand | 0.66 m forward | In place; the existing per-attack lunge (0.6–2.2 m) moves the body during startup and active |
| Jump | about 0.05 m | In place horizontally; height comes from physics (`jump_velocity` 6 m/s, about 0.8 m). The clip's own foot lift is subtracted from the model while airborne, so the height is not doubled. |
| Idle, Draw, Sheathe | < 0.03 m | In place |

Verified: the hips stay within 0.02 m of the capsule while walking and sprinting, with at most
0.002 m change per frame across loop boundaries (no snap-back), and `RL_BoneRoot` stays at the origin.

## Katana

* The character mesh has no sword. The player wields `scenes/weapons/kengeki_katana.tscn`, which
  wraps the Kengeki katana GLB (`assets/models/weapons/kengeki_katana/`) in the existing `Katana`
  script (`build_placeholder = false`). Enemies keep the placeholder `scenes/weapons/katana.tscn`.
  A test confirms there is exactly one katana on the player.
* Drawn: it is attached to `CC_Base_R_Hand` with a `BoneAttachment3D`. The grip is computed from
  the hand's own bones: the blade runs along the knuckle line from little finger to index, its back
  faces the wrist, and the grip sits in the palm. At the middle of each hit window the blade points
  at the target.
* Sheathed: it is attached to `CC_Base_Hip`, with the hilt in front of the left hip and the blade
  angled back and down, edge up (`sheath_edge_up`).
* The saya (scabbard) is part of the GLB. `Katana.scabbard_path` names it, and the visual moves it
  to the hip attachment as `KatanaSaya`, so it stays on the left hip while the sword is drawn and
  the sheathed blade sits inside it.
* It changes attachment on the clips' own contact frames: at 0.50 s of `Sword_Draw` (right hand on
  the hilt) and at 0.83 s of `Sword_Sheathe`.
* The game starts with the katana drawn, preserving all existing behaviour. While sheathed, attack
  or block draws first, and the pressed attack then fires (draw-attack). Parry needs the blade out.
  A dodge or hit during draw or sheathe cancels it, and the katana stays where it was.
* Enemies, `WeaponComponent`, the blade trail and sparks are unchanged.

## Other states (no clip exists)

These states have no clip among the seven, so they use simple stand-ins:

| State | Stand-in |
|---|---|
| Block | KinemIQ `Block` clip (see COMBAT_ANIMATIONS.md); previously the combo clip's first frame |
| Dodge | Run clip at speed |
| Hit, parried, block impact | Procedural backward flinch of the whole body |
| Knockdown | Procedural fall back and get up (1.0 s) |
| Death | Procedural fall onto the back |

## Validation

* **Automated (headless, 60 Hz):** `godot --headless --path . --fixed-fps 60 res://tests/gameplay_tests.tscn`
  gives **143 passed, 0 failed**: the 101 original checks plus 42 new ones (see `docs/TEST_RESULTS.txt`).
  The baseline before any change was 101 / 101.
* **Exported Windows build:** `KENGEKI.exe -- --kengeki-smoke` passed 5 of 5 runs, with and
  without rendering. Normal launch: the window was responsive after 20 s, with no errors.
* **Rendered review:** `godot --path . res://tools/capture_character.tscn` produced 21 shots
  covering idle, walk, run, all three swings, guard, sheathe, sheathed, draw grab, jump apex and
  the gameplay camera. All were reviewed.

Not verified: a human actually playing with keyboard, mouse or gamepad. All input was simulated.

### Katana asset

* Source: `kengeki katana` GLB (Blender I/O 4.0.43 export), 30,037,624 bytes,
  sha256 `f7fd208e8b5cad9440910055930b20ea4ae59ab9a0e370339dee18c2d185a5d8`. It is not in git.
* Repacked to 4.99 MB without remodelling. The vertex data is unchanged.
  * The single mesh is split into its two parts, `Katana_Sword` and `Katana_Saya`.
  * Node transforms scale it by 0.85: the blade is 0.71 m and the overall length is 1.0 m.
  * The origin is moved to the grip point, 6.5 cm behind the tsuba. The blade runs along -Z with
    its back toward +Y, which is the `Katana` convention.
  * The saya is aligned over the blade.
  * The three 4096² textures are now 2048²: normal as PNG, base colour and metal/roughness as JPEG.
* `BladeBase` / `BladeTip` sit at the real blade root and tip, so the trail and sparks follow
  the curved blade.

## Known issues

1. **Release build, shutdown only:** two `Attempt to disconnect a nonexistent connection …
   'skeleton_updated'` messages print when `KENGEKI.exe` exits. They come from the two
   `BoneAttachment3D` nodes. They do not appear in the editor or in a debug export, and they do not
   affect gameplay or the exit code. This appears to be a Godot 4.3 release-template quirk.
2. **Smoke-test flakiness (existing before this work):** `--kengeki-smoke` sometimes fails with
   `enemy hits 0`, when the god-mode bot kills all three enemies before any of them lands a blow.
   The original placeholder build fails the same way (1 of 3 runs here).
3. **Walk foot slide:** Walk is a slow catwalk (1.8 m/s at this scale), but gameplay walks at
   4.6 m/s. Cadence is capped at 2.2×, so some foot slide remains. Tune with
   `max_walk_time_scale` on the visual, or lower `walk_speed`.
4. **No dedicated clips** for strafe, back-step, dodge, hit, knockdown or death (block now has one). The stand-ins
   above are readable but basic. Lock-on strafing plays the forward walk.
5. **Cosmetic, from the asset (not changed):**
   * Knuckle edges stretch during the fist grip. No visible collapse at gameplay distance.
   * The thigh armour plates flare outward while running (skin weights).
   * The Run, Jump and Dodge poses hold the hand behind the hip, and `Sword_Draw` / `Sword_Sheathe`
     have no prop, so the blade used to cut through the right thigh and torso. The grip-side blade
     clearance now turns the blade out of the body and eases it along the saya at the hand-over.
     A few centimetres of overlap remain on some frames (measured in COMBAT_ANIMATIONS.md).
6. The Jump has no anticipation crouch, so it is responsive: take-off is immediate and the
   clip starts at its take-off frame.

## Launching and testing

* **Play:** unzip `Kengeki/builds/KENGEKI-character-integration-windows-x86_64.zip` and run
  `KENGEKI.exe`.
* **From source:** open `project.godot` in Godot 4.3, after copying the GLB as described above, and
  press F5.
* **What to try:**
  * Walk with WASD, sprint with Shift, jump with C.
  * Press E to sheathe while walking, then E again to draw, or left-click while sheathed to
    draw-attack.
  * Use the light combo L-L-L and the heavy attack (right mouse).
  * Hold F to block; tap F just before a hit to parry.
  * Spawn enemies from the Esc menu, then die and use Restart.
