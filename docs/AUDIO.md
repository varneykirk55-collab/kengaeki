# Audio

`autoload/audio_manager.gd` finds sounds **by folder**. Every `.wav`, `.ogg` or `.mp3` in
`audio/sfx/<category>/` is one random variation of that category. To replace a placeholder,
delete it and drop your files into the same folder; no code changes are needed. Volume offsets
per category are in `AudioManager.CATEGORY_VOLUME`. The buses are Master, Music, SFX and UI.

SFX Engine and Google Flow Music were **not available** in the build environment. All current
audio is **original placeholder sound synthesised from scratch** by
`tools/gen_placeholder_audio.py` (filtered noise, inharmonic metal partials, Karplus-Strong
plucks). It contains no downloaded or third-party audio. Every file below is a placeholder.

| Category | Placeholder files | Plays when | Suggested final sound |
|---|---|---|---|
| `music/` | `courtyard_theme_placeholder.wav` (≈53 s loop: in-scale plucks, taiko, drone) | always, loops | Google Flow Music track(s); several files play in order |
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
