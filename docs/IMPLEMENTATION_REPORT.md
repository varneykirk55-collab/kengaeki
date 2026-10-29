# KENGEKI — Implementation report (playable foundation, v0.1.0)

## 1. Summary

The foundation is a complete Godot 4.3 project. You can play duels and group fights against 1–10
katana-wielding ronin in a placeholder castle courtyard. All gameplay systems in the brief are
implemented and run in the engine. An automated suite of **101 gameplay checks** drives the real
main scene with simulated input, and **all 101 pass**. A Windows x86_64 build was exported.

Verification sources:

| Source | What it shows |
|---|---|
| `tests/gameplay_tests.gd`, headless, 60 Hz fixed timestep | Combat, AI, spawning and UI flows, checked against real game state |
| Screenshots in `docs/screenshots/` | Rendered from the running game (OpenGL / llvmpipe under Xvfb) |
| `--kengeki-smoke` self-test | Exported Linux build loads the packed data and wins a 3-enemy fight |
| Windows `.exe` | Exported, but **not launched**: no Windows machine was available |

## 2. Architecture

```
Main (scripts/main.gd)                      wires everything, menu/pause/death flow
├─ Arena (arena.tscn)                       spawn points, player start, runtime navmesh bake
│  ├─ Blockout (courtyard_blockout.gd)      Collision layer + placeholder Visual layer (independent)
│  ├─ Visual                                empty slot for the Hunyuan courtyard
│  ├─ NavigationRegion3D, Sun, WorldEnvironment
├─ Player (player.tscn) ─ Player : Combatant
│  ├─ Visual (CharacterVisual)              PlaceholderHumanoid now, ImportedHumanoidVisual later
│  ├─ Health / Stamina (components)
│  ├─ Weapon (WeaponComponent)              hit detection
│  ├─ AttackRunner                          startup → active → recovery timeline
│  └─ Combat (PlayerCombat)                 combo graph, input buffer, parry, counter, finisher
├─ CameraRig (CameraController)             orbit, lock-on framing, SpringArm collision, shake
├─ Enemies/ Enemy (enemy.tscn) ─ Enemy : Combatant
│  ├─ Visual, Health, Stamina(guard), Weapon, AttackRunner
│  ├─ AI (EnemyAI) → states/*.gd            enter, idle, approach, circle, engage, attack, block, stagger, dead
│  └─ NavigationAgent3D
├─ EncounterManager                         registry, attack tokens, ring slots, spawn/clear/reset
│  └─ SpawnManager                          sequential, safe spawning
└─ UI (CanvasLayer): HUD, EncounterMenu, DeathScreen

Autoloads: GameInput (all bindings), CombatManager (hit resolution rules),
           CombatFX (hit-stop, slow-mo, shake, particles), AudioManager (folder-driven SFX/music)
```

Key design decisions:

* **One hit pipeline for everyone.** `WeaponComponent → CombatManager.resolve_hit()` decides
  between dodged, parried, blocked, guard-broken and hit. It applies damage and guard cost,
  calls the reaction hooks on both fighters, then triggers feedback. Visual effects never
  decide whether a hit landed.
* **Hit detection follows real timing.** The default `ARC_SWEEP` mode models the blade path as
  an arc that is swept across the active window. Each physics tick tests only the newly swept
  slice, so fast swings cannot tunnel through targets, each target is struck when the blade
  actually reaches it, and one swing can hit several enemies. A per-swing hit list prevents
  repeated damage. `BLADE_AREA` mode, which uses the katana's own Area3D, is available for when
  real swing animations exist.
* **Data-driven techniques.** Every attack is an `AttackData` `.tres` file holding timing, damage,
  guard damage, stagger, reach and arc, lunge, hyper armor, i-frames and feedback values.
  Combos are a small graph in `PlayerCombat.COMBO`.
* **Gameplay and visuals are separate.** Controllers only call the `CharacterVisual` interface.
  The placeholder visual reads the AttackRunner phase every frame, so the animation always
  matches the real hit window. `AttackData.timing_source = ANIMATION_EVENTS` hands timing to
  animation method tracks instead (this path was tested with a synthetic rigged model).
* **Player and enemies share** `Combatant`, the components, `AttackRunner`, the katana scene and
  the visual implementations. They use different controllers: Player + PlayerCombat versus
  Enemy + EnemyAI.

## 3. Feature status

### Player
* **Movement:** camera-relative WASD, smooth acceleration and deceleration, sprint that drains
  stamina, turning toward the direction of travel, strafing while locked on.
* **Camera:** orbit with mouse or right stick, adjustable distance, SpringArm collision
  avoidance, lock-on (Q) and target switching (Tab or mouse flick), lock-on framing that
  shifts focus between you and the target, auto-pull-back when several enemies are near, and
  trauma-based shake.
* **Attacks:** light and heavy attacks; a three-hit light combo; light→heavy, heavy→light,
  light-light-light (Crescent Wheel) and light-light-heavy (Kesa-giri) combos; a buffered input
  queue (0.4 s); cancel windows; dodge cancels; soft target magnetism and lunge.
* **Defence:** hold to block (chip damage plus guard/stamina cost), tap to parry (0.2 s window
  with anti-mash cooldown), directional dodge with i-frames (0.02–0.30 s of 0.42 s), a guard
  break when stamina runs out, and stamina regeneration with a delay.
* **Advanced techniques:**
  * Parry counter (**Kaeshi-waza**): cinematic, invulnerable dash-cut with slow motion.
  * Finishing strike (**Todome**): available on parried, guard-broken or knocked-down enemies.
  * Two combo finishers.
  * Hyper armor on heavies and finishers. Light-attack startups can be interrupted.
* **Damage and death:** health regenerates after 8 s without taking damage; hit-stun scales
  with stagger power; there is a death state with a death screen offering restart or
  return-to-arena.

### Enemies
* **Behaviour:** a modular state machine:
  * Enter: walk in from a gate.
  * Approach: move to an assigned ring slot.
  * Circle: wait for a turn while strafing, feinting and keeping spacing and facing.
  * Engage, then attack: strings of one or two attacks — slash, return cut, thrust, and an
    overhead that is telegraphed and has hyper armor.
  * Retreat.
  * Block: reacts to incoming attacks. The chance rises with every consecutive hit taken, and
    the enemy may riposte afterwards.
  * Stagger: from flinch up to knockdown. A parry or a guard break makes the enemy vulnerable.
  * Death, then the corpse sinks away after 5 s.
* **Group coordination:**
  * Attack tokens are capped by `max_active_attackers` (default 2, adjustable 1–4 in the menu).
  * Waiting enemies form a first-come-first-served queue, tokens expire after 5 s, and there is
    a short cooldown after attacking. Every enemy therefore gets a turn; the tests confirm all
    6 of 6 attacked within 30 s.
  * Waiting enemies are spread evenly around the player while keeping their order around the
    circle. Ring slots are clamped inside the arena walls.
  * Separation steering prevents enemies from stacking, and runtime navmesh pathing routes them
    around lanterns, the tree and the racks.

### Sandbox
* **Spawning:** exact counts from 1 to 10. The interval is adjustable from 0.5 to 6 s (default
  2 s). The first enemy enters immediately; the rest follow sequentially.
* **Spawn points:** enemies appear at one of 8 gate or corner points. A point is never within
  7 m of the player or within 2.2 m of another enemy; if none qualifies, the spawn is retried.
* **Safety:** there are caps on alive and queued enemies. Spawn requests made during a wave are
  appended. Clear cancels the queue.
* **Menu actions:** clear enemies, reset the encounter, restore health, and restart after
  death. Everything works repeatedly.

### Presentation
* **Placeholder humanoid:** about 20 primitives. Two-bone IK keeps both hands on the grip.
  Animation is keyed sword poses: a wind-up in startup, the cut across the hit window and a
  follow-through in recovery. There are walk and strafe gaits, guard and block poses, dodge
  lean, hit reactions, stagger, knockdown, a parried recoil and a death fall.
* **Effects:**
  * A pale blade trail, visible only during the hit window.
  * Sword-clash sparks, larger on a parry.
  * Impact droplets, a red hit flash and dust from spawns and dodges.
  * Hit-stop and slow motion.
  * Callouts for parries, guard breaks and finishers, and technique names on screen.
* **Audio:** 35 original procedurally synthesized placeholder files covering 17 SFX categories,
  plus a looping placeholder theme. All are loaded and played through `AudioManager`.

## 4. Testing

**Automated gameplay tests:** `tools/run_tests.sh`. Full log: [`TEST_RESULTS.txt`](TEST_RESULTS.txt).
The suite runs about 6 minutes of game time in about 20 s real time. It ran 6 times in a row
with 101/101 passing each time, so random AI choices did not cause flaky results.

| Area | Checks (all passing) |
|---|---|
| Movement and camera | Camera-relative movement and turning, deceleration, sprint speed and drain, stamina regeneration, mouse yaw, zoom, camera pulled in front of a wall |
| Basic combat | Light hit for exactly 14 damage with no repeat hits; 3-hit combo; input buffer; L→H; H→L; L-L-H finisher; one swing damaging 3 enemies; Crescent Wheel hitting behind |
| Defence | Block (chip only, stamina cost); timed parry (no damage, enemy vulnerable, counter window); counterattack (≥60 damage); parry anti-mash; dodge i-frames start, protect and end; dodge refused without stamina; player hit-stun and recovery |
| Enemy reactions | Enemy block reduces damage; heavies break guard; finishing strike on vulnerable enemies; death, count update and corpse cleanup |
| Targeting and feedback | Lock-on acquire, switch, camera tracking, auto-hop on kill, toggle off; blade visibly moves (>1 m tip travel); hit-stop and camera shake fire |
| AI | Duel: spawns far away, approaches, engages and attacks. Group of 6: never more than 2 attackers, all 6 get turns, ≥4 different strikers, minimum spacing >0.6 m, enemies in 4 quadrants. Limit of 3 respected |
| Full fight | A scripted bot defeats 3 live-AI enemies |
| Sandbox | Sequential timing (±0.05 s), exact counts, spawn distance from player, clear cancels the queue, 5 spawn/clear cycles, 10 enemies, cap under spammed requests |
| UI flows | Menu pause and resume, spawn exact count, attacker limit, restore, clear, reset; death screen, restart with same count, return to arena |
| Asset pipeline | Synthetic rigged model in `ImportedHumanoidVisual`: katana on the hand bone, mapped clip plays, animation-event hit window, strike resolves |
| Audio | All 17 categories and music loaded |

**Bugs found and fixed through testing:**
* A crash when a swing was parried in the middle of its sweep: the null attack after a cancel.
* Too much player knockback: a passive player was shoved into a corner, so enemies could only
  stand on one side. The player now takes half knockback, and ring slots are clamped inside
  the arena.

**What was *not* verified:**
* **The Windows `.exe` was not launched.** The same pack, exported for Linux, passes the smoke
  self-test, and the `.exe` is a valid PE32+ file.
* **Real-time game feel** was not judged by a human at full frame rate with a mouse and
  keyboard. Input in the tests was simulated through actions, and screenshots came from
  software rendering.
* **Forward+ rendering**, the Windows default, was not seen; screenshots used the GL
  Compatibility renderer.
* **Audio output** was not heard: the container has no sound device. Files load and play calls
  run.
* **Gamepad bindings** are defined but were not tested with hardware.
* **Performance on target hardware** was not measured. The headless simulation of 10 enemies
  runs far faster than real time.

## 5. Known limitations

* **Placeholder art and animation:** primitive characters and pose-keyed procedural animation.
  These show that the states work but are **not cinematic animation quality**. There is no
  root motion, no real hand animation, and no full-body attack or death animation; the death is
  a rigid fall.
* **No ragdolls or dismemberment.** Hit reactions are pose-based. Knockback is a short slide.
* The enemy roster is a single ronin type with one moveset. Enemies do not parry or dodge.
* The camera's SpringArm only collides with world geometry, so enemies very close behind the
  player can clip into the camera.
* The **ImportedHumanoidVisual** path was only tested against a synthetic skeleton. Real Hunyuan
  rigs will need the import and retarget step described in `ASSET_INTEGRATION.md`, and a
  `weapon_offset` tuned to the hand bone.
* There is no options or rebinding menu (bindings are centralised in `autoload/game_input.gd`)
  and no fullscreen toggle (the window is resizable).
* The blockout courtyard is intentionally simple. Gates are closed doors, and enemies "enter"
  from just inside them.
* An exit-time warning ("ObjectDB instances leaked … AudioStreamWAV") appears when the game is
  force-quit while sounds are playing. This is a benign Godot 4.3 shutdown message.

## 6. Definition of Done

| Requirement | Status |
|---|---|
| Opens without critical errors | ✅ Clean import and run (Godot 4.3, headless and GL) |
| Free third-person movement; working camera | ✅ Tested |
| Light and heavy attacks; 3-hit combo | ✅ Tested |
| Blocking and timed parry; dodging | ✅ Tested |
| Counterattack and combo finisher | ✅ Kaeshi-waza counter, Crescent Wheel, Kesa-giri, Todome (tested) |
| Enemy AI approaches and attacks; takes damage and dies | ✅ Tested |
| 1v1 and multi-enemy combat; group coordination | ✅ Tested (limit, fairness, spread, spacing) |
| Exact enemy count; sequential spawns | ✅ Tested |
| Health and stamina; encounter reset; restart after death | ✅ Tested |
| Placeholder combat animations visible | ✅ Screenshots; blade-motion test |
| Basic effects and audio hooks | ✅ Trail, sparks, impacts, flash, hit-stop, shake; 17 SFX categories and music |
| Accepts replacement Hunyuan assets | ✅ Architecture in place; pipeline tested with a synthetic rig; not yet tested with real assets |
| Windows build | ⚠️ Exported, not launched on Windows |
