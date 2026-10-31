# Combat animations: KinemIQ katana clips

The playable samurai (AccuRIG `CC_Base` rig, 101 bones) now attacks, guards and stands ready with
KinemIQ katana clips. Only animation data was added. The character model, rig, armour,
materials, katana and saya assets, courtyard, camera, controls, run and dash clips, and audio are
unchanged. The existing combat system (`PlayerCombat` → `AttackRunner` → `WeaponComponent`)
still drives everything. The clips are a visual layer on its phases, so there is no second
combat system.

## Source clips

The KinemIQ exports are not in git (about 230 MB). They were read from `kengeki_anims/`:

| File | Skeleton | Length (30 fps) | Content | Used |
|---|---|---|---|---|
| `Sword_-_light_slash_A.glb` | CC_Base (same 101-bone skin) | 0.37 s | One diagonal cut, right-high to left-low | **Yes** → `Light_Slash_A` |
| `Sword_-_light_combo_1.glb` | CC_Base | 3.37 s | Four-cut combo: cut 1 = Slash A, then horizontal L→R, rising L→R, lunging R→L | **Yes** → `Light_Combo` |
| `Sword_-_light_combo.glb` | 66-bone UE-mannequin rig, no CC_Base bones | — | Same combo on a different skeleton (the small 1.3 MB file) | No: it can't drive CC_Base, and the CC_Base version above has the same motion |
| `Sword_-_heavy_slash_B.glb` | CC_Base | 0.50 s | Rising cut, left-low to right-high | **Yes** → `Heavy_Slash_B` |
| `Sword_-_heavy_slash_C.glb` | CC_Base | 0.70 s | Wind-up, then a deep lunging horizontal cut L→R | **Yes** → `Heavy_Slash_C` |
| `Block_-_with_the_sword.glb` | CC_Base | 1.23 s | Raise the guard, hold it, lower it | **Yes** → `Block` |

The two "light_combo" files: `light_combo_1` is the CC_Base version and was used. `light_combo`
is the same move on a 66-bone UE-style skeleton, so it was not used. Retargeting it would only
duplicate `light_combo_1` with retarget error. The light combo's first cut duplicates
`Light_Slash_A`, so the game plays it from the Slash A clip and does not use that section of
the combo.

There is no parry, counter, draw-attack, dodge, hit-react or death clip in the set, so none was
invented.

## How the clips were imported

`tools/build_combat_animations.gd` (run headless) loads each GLB and keeps the `CC_Base_*` bone
tracks. The local rotations copy directly because the skin and rests are the same as the
playable character. Horizontal `CC_Base_Hip` travel is removed, since gameplay owns movement.
Mesh, texture and skeleton data are dropped, and the clips are saved as one
`AnimationLibrary`:

```
godot --headless --path . -s res://tools/build_combat_animations.gd -- <folder with the GLBs>
```

Output: `assets/animations/kinemiq/kinemiq_combat.res` (198,522 bytes, 5 clips, 101 tracks each).
It holds animation data only, with no mesh or rig.

## Mapping to gameplay

Each `AttackData.animation` key selects a clip segment, in clip seconds:
**start → hit start → hit end → end**. Every frame, the clip time is interpolated from the
`AttackRunner` phase (STARTUP → ACTIVE → RECOVERY), so the contact frames always play inside
the real hit window. Attack timings, damage, stamina, guard, parry and finisher logic are
unchanged.

| Attack (input) | Key | Clip | Segment (s) |
|---|---|---|---|
| Light Cut I: `light_1` (LMB) | `slash_rl` | Light_Slash_A | 0.0 → 0.183 → 0.317 → 0.367 |
| Light Cut II: `light_2` (L, L) | `slash_lr` | Light_Combo cut 2 | 0.367 → 0.567 → 0.70 → 0.80 |
| Crescent Wheel: `light_3` (L, L, L) | `spin` | Light_Combo cut 3 | 0.85 → 1.20 → 1.40 → 1.633 |
| Piercing Thrust: `heavy_light` (H, L) | `thrust` | Light_Combo cut 4 | 1.80 → 1.967 → 2.067 → 2.30 |
| Rising Cut: `light_heavy` (L, H) | `rising` | **Heavy_Slash_B** | 0.0 → 0.333 → 0.467 → 0.50 |
| Overhead Cut: `heavy_1` (RMB / R) | `overhead` | **Heavy_Slash_C** | 0.267 → 0.433 → 0.60 → 0.70 |
| Todome finisher: `finishing_strike` | `overhead` | Heavy_Slash_C | as above |
| Kesa-giri: `finisher_kesa` (L, L, H) | `kesa` | Light_Slash_A | as light_1 |
| Kaeshi-waza: `counter_riposte` (after a parry) | `kesa` | Light_Slash_A | as light_1 |
| Block, held (F / Ctrl) | — | **Block** | Raises over 0.167 s, then holds the 0.30 s guard frame. On release it fades back |
| Parry (tap block) | — | Block | Same guard raise (no parry clip exists). The parry window and logic are unchanged |
| Ready stance (sword drawn, standing) | — | Light_Combo frame 0 | The shared first frame of the KinemIQ clips, blended over idle |

L → L → L therefore plays Slash A, then the combo's cuts 2 and 3. The heavy follow-ups use the
dedicated heavy clips. Heavy clips get a slightly longer cross-fade in (up to 0.15 s) so their
wind-up doesn't snap.

**Heavy_Slash_C starts at 0.267 s.** Between about 0.07 and 0.27 s, the clip's `CC_Base_Hip`
rotation is 150–172° away from rest. Godot's AnimationTree blends rotations relative to the
rest pose, so a partly faded-in blend there flips the whole body the "short way" round. That
produced a visible one-frame pop that the tests caught. Starting after it keeps the cut and the
lunge, but skips most of the wind-up.

## Hit-timing alignment

Contact frames were found from the per-frame speed of the blade tip and right hand in each clip.
The segments above put them inside ACTIVE. `test_combat_hit_windows` checks this in-game: for
`light_1`, `light_2`, `light_3`, `light_heavy`, `heavy_1` and `heavy_light`, the fastest
right-hand frame of the swing falls in the ACTIVE phase. Hit detection is still
`WeaponComponent`'s ARC_SWEEP, so blade orientation can't change what hits.

## Katana

* While drawn, the katana stays on `CC_Base_R_Hand` through every attack, guard and locomotion
  state (tested). The grip, saya and assets are unchanged. `toggle_sword` (E / D-pad Up) still
  draws and sheathes.
* **Blade clearance** (`KengekiCharacterVisual.blade_clearance`, on by default): after every
  skeleton pose update, the drawn blade is turned about the grip just enough to keep it out of
  two body capsules: torso (Waist → NeckTwist01, r 0.13 m) and right thigh (R_Thigh → R_Calf,
  r 0.08 m). The margin is 2 cm and the turn is capped at 50°. The turn is solved fresh each
  frame (no lag) with half-step iterations, so a blade wedged between thigh and torso walks out
  sideways instead of bouncing. Near the draw grab (0.4 s) and the sheathe release (0.25 s), the
  blade also blends toward its saya pose, so it slides along the hip instead of cutting through
  the waist. This is purely a grip-side correction: the run/dash clips and the character are not
  modified.
* Measured overlap (`test_katana_body_clearance`, 60 Hz):

  | State | Before | After |
  |---|---|---|
  | Run, drawn: thigh | 7.5 cm inside, 50 / 90 frames | 3.6 cm max, 8 / 90 frames |
  | Run, drawn: torso | — | 1.7 cm max, 6 / 90 frames |
  | Sheathe: torso | 12.3 cm, 21 frames | 7.4 cm, 6 frames |
  | Draw: torso | 11.7 cm, 9 frames | 0.3 cm, 2 frames |
  | Idle / walk | clear | clear |

## Tests

* `test_combat_clip_library`: 5 clips, all CC_Base tracks, and every attack key maps to a valid
  segment.
* `test_combat_clip_selection`: ready stance when drawn and still, and the right clip for
  light 1/2/3, heavy, light → heavy and guard. Releasing the guard clears it.
* `test_combat_hit_windows`: contact inside ACTIVE (see above).
* `test_katana_body_clearance`: the overlap limits in the table above, and the katana stays in
  the right hand.

## Known limitations

* **Sweep direction:** the arc-sweep hit shape doesn't change. A couple of cuts swing the
  opposite way from the old placeholder (e.g. the heavy C cut is left to right). This is only
  cosmetic, because hits use the existing sweep.
* **Ready stance:** frame 0 of the KinemIQ clips is a fairly static, arms-low stance. There is
  no ready-idle loop in the set.
* **Light_Combo cut 2:** the source data whirls the hips, so the hand moves about 1 m per frame
  for a few frames (0.57–0.67 s). That is the clip's own motion, inside the hit window.
* **Heavy_Slash_C** skips most of its wind-up (see above).
* Residual blade overlap, as in the table: mostly a few frames of run, and the end of the
  sheathe before the hand-over.
* There are no parry, counter or draw-attack clips. Those mechanics reuse Block / Slash A.
* Verification was automated plus llvmpipe screenshots. Nobody has playtested it by hand yet.
