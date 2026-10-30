class_name MusicConfig
extends Resource
## Background music settings, read by AudioManager at startup (res://audio/music_config.tres).
##
## Tracks: drag audio files into `tracks` in the inspector. If the list is empty, every
## .wav/.ogg/.mp3 in res://audio/music/ is used instead (in filename order), and files whose
## name contains "placeholder" are skipped as soon as any other track is present.
##
## Looping: a single track loops seamlessly (the stream's own loop, no gap). Several tracks
## play one after another and wrap around to the first.

@export var tracks: Array[AudioStream] = []
@export var shuffle: bool = false
@export_range(-40.0, 6.0, 0.5) var volume_db: float = -10.0

@export_group("Ducking")
## Music is lowered while these SFX categories play (see AudioManager.CATEGORIES).
@export var duck_categories: PackedStringArray = [
	"impact", "clash", "block", "parry", "guard_break", "counter", "finisher",
	"enemy_hurt", "player_hurt", "death",
]
## How far the music drops (dB, negative). 0 disables ducking.
@export_range(-30.0, 0.0, 0.5) var duck_db: float = -6.0
## Seconds to reach the ducked level.
@export var duck_attack: float = 0.05
## Seconds the music stays ducked after the last triggering sound.
@export var duck_hold: float = 0.35
## Seconds to return to full volume.
@export var duck_release: float = 0.8
