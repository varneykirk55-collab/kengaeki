# Locomotion refinement

Integrated on `test/codex-locomotion`, based on main `7dd75f3f6b9c45c4114de2d5bbb854299a502fb9`.

The animation resources and bake/preview tools come from the user-supplied
`Kengeki_Locomotion_Update.zip`. Its production script targeted older main `b1e1f55`;
only its locomotion changes were ported. Current KinemIQ attack mappings, contact
windows, guard playback, ready stance, katana attachment and clearance remain intact.
The archive's historical logs and performance measurements are not fresh validation
of this integration and are not included as test results.

## Animation and playback changes

- Separate `locomotion/walk`, `locomotion/run`, and `locomotion/jump` resources leave
  imported originals available. The supplied bake lengthens walk stride by 10%, widens
  steps and adjusts hip/leg keys with two-bone IK to compensate for uneven root travel.
- The supplied run bake raises the hip 2.5 cm in model space and reduces the deep forward
  torso bend by 30 degrees. Sprint and dodge playback use this refined run resource.
  Dodge distance, duration, invulnerability, stamina and cancel rules are unchanged.
- The supplied jump bake reduces landing squat depth while preserving foot targets.
  Playback adds 50 ms or less of launch compression without delaying the physics impulse.
  Moving landings retain compression before blending out; stationary recovery is shorter.
- Walk/run are sought from a shared contact phase, with a run contact offset. Cadence
  follows measured velocity and each refined clip's duration, including acceleration
  and deceleration. Idle/walk/run thresholds have hysteresis to prevent flickering.
- Dominant backward movement eases into reversed gait playback without resetting phase.
  Sideways lock-on travel still uses the forward cycle; there are no dedicated strafe clips.
- `refined_locomotion = false` on the player's Visual before startup restores original
  movement clips and playback. If a refined resource is absent or invalid, the whole
  locomotion library falls back to original playback instead of installing a partial set.

Only the production visual script changes. Player physics, keyboard/gamepad bindings,
combat mechanics, attack resources, hit detection, blocking mechanics, model, skeleton,
materials, skin weights, and environment systems are unchanged. Existing unarmed idle
and combat ready poses are retained; this update changes their movement transitions.

## Fresh validation in this cloud environment

Godot **4.3 stable**, official binary verified against the release SHA-512 manifest.

- Animation-graph tests: **34 passed, 0 failed**, covering library coexistence, current
  combat mappings, gait thresholds, forward/reverse phase progression, stopping, jump
  recovery, dodge clip selection, attack priority, guard clip selection and legacy mode.
  These use a graph fixture with empty original clips, not a replacement game model.
- Resource validation: all three resources load (walk 62 tracks, run 63, jump 62).
  Bone names match the current combat library; track targets/types, durations, loop modes,
  key times, finite values, normalized quaternions and edited leg-loop seams pass checks.
- Courtyard combat smoke test: **PASS**, 3 kills, 11 player hits, 1 enemy hit.
- Music suite: **27 passed, 0 failed**.
- Full gameplay suite: **112 passed, 25 failed**, exit 25, with missing-model script errors.
  Before integration the same environment reported **113 passed, 24 failed**. The extra
  failure was the group-fight timeout (2/3 kills); its isolated rerun passed (3/3 kills).
  The other failure labels match the baseline. This is not a passing full-game result.
- Full-model validation, bake and preview correctly exit nonzero with a clear missing-GLB
  message; they do not produce false successful previews or overwrite baked resources.

The existing gameplay/smoke runs also emit dummy-renderer null-mesh diagnostics and
exit-time resource leak warnings. The resource and graph checks emit no script errors.
Missing-model failures cannot establish visual combat compatibility.

**Blocking prerequisite:** the original private
`assets/models/kengeki/kengeki_character_animated.glb` is still absent. The uploaded ZIP
explicitly excludes it. Full skeleton validation, rebaking, before/after rendered review,
foot-slide measurement, and complete playable-character testing cannot run here yet.
Do not substitute another model. The supplied report identifies its source GLB SHA-256 as
`d31447fb2cbfae237b827e09f0c9e6e709fa0028e001ddabbff86ae977d76c80`;
that hash has not been independently verified here.

Residual foot slide and armour deformation may remain. Backpedal is a reversed forward
cycle; dodge is a timed run-cycle approximation. Physical keyboard/controller play,
rendered animation quality, and target-hardware performance remain unverified.

## Reproduce

From the project root, with `GODOT` pointing to a Godot 4.3 standard executable:

```sh
"$GODOT" --headless --path . res://tests/locomotion_tests.tscn
"$GODOT" --headless --path . --script tools/locomotion/validate.gd
GODOT="$GODOT" bash tools/run_tests.sh
"$GODOT" --headless --path . --fixed-fps 60 -- --kengeki-smoke
```

After restoring the original private GLB and importing it in Godot 4.3:

```sh
"$GODOT" --headless --path . --script tools/locomotion/validate.gd -- --require-model
"$GODOT" --headless --path . --script tools/locomotion/bake.gd
"$GODOT" --path . --rendering-method gl_compatibility --fixed-fps 60 res://tools/locomotion/preview.tscn -- --out=before
"$GODOT" --path . --rendering-method gl_compatibility --fixed-fps 60 res://tools/locomotion/preview.tscn -- --out=after
"$GODOT" --path . --rendering-method gl_compatibility --fixed-fps 60 res://tools/locomotion/directional.tscn -- --out=directional
```

Baking reads the GLB and rewrites only the three animation resources. Review their diff
before committing a rebake. Preview images and measurement logs go to ignored
`build/locomotion/`; they exercise the actual player controller on a diagnostic floor,
not the castle courtyard. `measure.py` optionally summarizes these logs using NumPy.
The gameplay suite and smoke test exercise the real courtyard scene. Launch the main
scene with `"$GODOT" --path .` for manual movement and combat review.
