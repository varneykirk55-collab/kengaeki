# Kengeki locomotion refinement

Baseline: main at b1e1f550203b454d33d7b358162b3fc1418cb784. Temporary integration branch: test/locomotion-refinement. Main remains unchanged.

## What changed

Three separate native Godot 4.3 animation resources override locomotion only:

- `assets/animations/locomotion/walk.res`: 10% longer stride, slightly wider foot placement, restored lateral weight transfer, and correction for uneven root velocity when controller movement replaces root motion. Two-bone IK keeps the foot orientations while adapting the legs.
- `run.res`: root-velocity correction, slightly wider steps, 2.5 cm model-space hip lift, and 30-degree reduction of the original excessive upper-torso forward lean. The source torso's head-to-spine vector leaned about 61–73 degrees forward; the refined pose retains forward momentum without the same deep hunch.
- `jump.res`: a modest reduction of the deep landing squat, with the feet preserved using leg IK.

The visual controller loads them under the separate `locomotion` animation library. Original imported animations remain available: sword attacks, draw, sheathe, guard and the run clip used for dodge are not replaced. Walk/run playback now matches controller travel, shares a foot-contact phase, and uses speed hysteresis to avoid repeated threshold switching. Dominant backward travel plays the walk cycle backward. Sideways travel remains a limitation.

Jump playback includes a brief compressed launch pose with no delay to the physics impulse. Moving landings retain more recovery before blending out; stationary recovery is less prolonged. This is not a full grounded anticipation wind-up: that would require changing launch timing, which was deliberately preserved.

Only the production visual script changes. Player physics/input, combat, enemy AI, sword attachments, courtyard and music files are unchanged. The original 101-bone skeleton, mesh, materials and skin weights are preserved.

## Evidence and limits

`Kengeki_Locomotion_Before_After.mp4` is a 13-second, silent, side-by-side Godot rendering (20 captured frames/sec from a fixed 60 Hz run). It uses the real player scene/controller on a diagnostic marked floor, with identical scripted movement inputs: idle, walk, run, run-to-walk, stop, stationary jump, moving jump, landing. It is not a recording of a human playing in the courtyard. The whole main scene is exercised separately by the existing gameplay suite.

Rendered frame sequences were inspected. The clearest visual change is the run posture. Walking has less drift, and landing recovers sooner without the original prolonged squat. The source motion still has limitations; the result is a refinement, not a replacement motion-capture set.

Deterministic measurement of horizontal ankle motion during the lowest 30% of each foot's heights, excluding acceleration/transition windows:

| Gait | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| Walk | 1.113 m/s | 0.485 m/s | 56% |
| Run | 1.106 m/s | 0.899 m/s | 19% |

This is a sliding proxy, not a perfect contact detector. Toe roll and remaining source drift contribute. It does not establish zero sliding or terrain-aware foot locking. Reproduce using `tools/locomotion/measure.py` and the included sample logs.

Validation: final existing gameplay suite 143 passed / 0 failed; separate resource validation confirms 101 bones, valid track targets, finite values and normalized rotations. Backpedal test observed local velocity (0, 0, 3.9) and gait direction -1. Keyboard/gamepad bindings are unchanged, but no physical controller was used.

Headless tests emit Godot dummy-renderer `mesh_get_surface_count` null-mesh diagnostics and exit-time resource/object leak warnings. Rendered preview logs show the software OpenGL renderer's V-sync warning. These are disclosed; the run is not claimed to be warning-free. No script parse errors were observed.

Original GLB SHA-256, identical before and after:
`d31447fb2cbfae237b827e09f0c9e6e709fa0028e001ddabbff86ae977d76c80`

## Remaining problems

- Residual foot slide remains, especially running and transitions; no runtime terrain IK was added.
- 4.6 m/s is a fast walking speed. Cadence is brisk to preserve the existing controls.
- Sideways lock-on movement still uses forward walking. Reversed walking is a practical backpedal approximation, not a dedicated backward clip.
- Brief launch compression cannot supply a full anticipation phase while retaining instant takeoff.
- Existing armour deformation and hand/skin-weight issues are not repaired.
- Review the supplied playback on the target PC before accepting the feel; human input and target-hardware performance remain unverified.

## Launch the integration branch on Windows

From the existing project, run `powershell -NoProfile -ExecutionPolicy Bypass -File .\Play-Kengeki.ps1`.
The launcher finds an installed Godot 4.3, imports resources, and launches the game. If automatic discovery fails, it opens an executable picker. It requires the existing private GLB and never copies or rewrites it. This launcher was reviewed statically; Windows execution has not been tested in this Linux environment.

## Install / revert

Use a clean working copy based on the baseline commit. Back up local modifications first. Extract the update ZIP into the Godot project root, preserving its folders. Keep the existing private GLB at `assets/models/kengeki/kengeki_character_animated.glb`. The ZIP does not contain or replace it. Open in Godot 4.3 and run.

For an immediate A/B toggle, set `refined_locomotion` false on the player's Visual node before the scene starts, then restart. This restores the original locomotion code and original clips. To fully revert, restore `scripts/visual/kengeki_character_visual.gd` from the baseline and remove the added animation/tool/report files. The original GLB needs no restoration.

## Reproduce

From project root, using a Godot 4.3 executable named `godot`:

```sh
godot --headless --path . --script tools/locomotion/bake.gd
godot --headless --path . --script tools/locomotion/validate.gd
godot --headless --path . --fixed-fps 60 res://tests/gameplay_tests.tscn
godot --path . --rendering-method gl_compatibility --audio-driver Dummy --resolution 960x540 --fixed-fps 60 res://tools/locomotion/preview.tscn -- --out=before
godot --path . --rendering-method gl_compatibility --audio-driver Dummy --resolution 960x540 --fixed-fps 60 res://tools/locomotion/preview.tscn -- --out=after
```

The preview saves PNG frames and measurement JSON under ignored `build/locomotion/`. Use headless mode for measurement-only previews. The `before` argument disables refinement on the preview's player instance. `directional.tscn` additionally exercises backpedal and shows the remaining strafe limitation.
