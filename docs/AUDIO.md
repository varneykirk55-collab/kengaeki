# Audio

`autoload/audio_manager.gd` finds sounds **by folder**. Every `.wav`, `.ogg` or `.mp3` in
`audio/sfx/<category>/` is one random variation of that category. To replace a placeholder,
delete it and drop your files into the same folder; no code changes are needed. Volume offsets
per category are in `AudioManager.CATEGORY_VOLUME`. The buses are Master, Music, SFX and UI.

## Music

**Copy your music files into `audio/music/`** in the project folder (`res://audio/music/`).
`.ogg`, `.mp3` and `.wav` all work; `.ogg` is the best choice for long tracks. No names are
required and no code changes are needed.

1. Copy the files from `Desktop/kengeki music` into `<project>/audio/music/`.
2. Open the project in Godot once so it imports them.
3. Press F5. The output log prints `Loaded … music tracks`.

Which tracks play:
* **By default, every file in `audio/music/`**, in filename order (rename with a `01_`, `02_`
  prefix to set the order). `courtyard_theme_placeholder.wav` is skipped automatically as soon as
  any other track is in the folder, and used only when the folder holds nothing else.
* **To choose tracks yourself,** open `audio/music_config.tres` in the inspector and drag files
  into **Tracks**. When that list is not empty it replaces the folder scan. **Shuffle** and
  **Volume Db** (default −10 dB) are set there too.

Looping:
* **One track loops seamlessly,** using the stream's own loop, with no gap at the seam. A `.wav`
  loops the whole file unless loop points are set in its Import dock, which are kept.
* **Several tracks** play one after another and wrap around to the first. Each plays once per
  pass; any loop flag on the individual files is turned off at runtime.

Ducking: when a combat sound plays (`impact`, `clash`, `block`, `parry`, `guard_break`,
`counter`, `finisher`, `enemy_hurt`, `player_hurt`, `death`), the music drops by 6 dB within
0.05 s, holds for 0.35 s after the last such sound, then returns over 0.8 s. Swings, footsteps and
UI sounds do not duck. All of this is in the **Ducking** group of `audio/music_config.tres`; set
**Duck Db** to 0 to turn it off. Ducking runs in real time, so hitstop does not stall it. Other
code can call `AudioManager.duck_music()`.

Buses: `default_bus_layout.tres` defines Music, SFX and UI, all sent to Master, so they show in
the editor's Audio panel for mixing. Music always plays on the Music bus. `AudioManager` also
creates any missing bus at startup.

## Placeholders

SFX Engine and Google Flow Music were **not available** in the build environment. All current
audio is **original placeholder sound synthesised from scratch** by
`tools/gen_placeholder_audio.py` (filtered noise, inharmonic metal partials, Karplus-Strong
plucks). It contains no downloaded or third-party audio. Every file below is a placeholder.

| Category | Placeholder files | Plays when | Suggested final sound |
|---|---|---|---|
| `music/` | `courtyard_theme_placeholder.wav` (≈53 s loop: in-scale plucks, taiko, drone) | always, loops; skipped once other tracks are present | your own tracks (see [Music](#music)) |
| `swing_light` | 3 | light attack startup | fast katana whoosh |
| `swing_heavy` | 2 | heavy, finisher and counter startup | heavier whoosh |
| `impact` | 3 | clean hit | cut into cloth or flesh |
| `clash` | 3 | layered on parries | blade-on-blade ring |
| `block` | 2 | blocked hit | blade-on-blade, duller |
| `parry` | 2 | successful parry | bright ringing clash |
| `guard_break` | 1 | guard broken | heavy clash plus stagger |
| `dodge` | 2 | dodge | cloth swish and gravel scuff |
| `footstep` | 4 | walking or running (gravel) | footsteps on gravel |
| `enemy_hurt` | 3 | enemy takes a hit | male grunts |
| `player_hurt` | 2 | player takes a hit | grunts |
| `death` | 2 | any death | death cry and body fall |
| `heavy_warn` | 1 | enemy starts an unblockable-feel overhead | wooden clack or kiai cue |
| `counter` | 1 | parry counter (stinger) | taiko hit |
| `finisher` | 1 | finishing strike (stinger) | deep taiko |
| `ui_click` | 1 | menu buttons | soft click |
| `ui_open` | 1 | menu opened | soft pluck |

To regenerate the placeholders, run `python3 tools/gen_placeholder_audio.py` (requires numpy).
