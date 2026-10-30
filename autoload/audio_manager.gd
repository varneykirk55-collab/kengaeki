extends Node
## Centralised audio playback.
##
## Sounds are discovered by folder: every file inside res://audio/sfx/<category>/
## becomes a random variation of <category>. Dropping new .wav/.ogg/.mp3 files into
## a folder (or deleting the placeholders) is all that is needed to replace audio.
## Music: the tracks listed in res://audio/music_config.tres, or else every file in
## res://audio/music/ (see MusicConfig). One track loops seamlessly; several play in order.
## The music ducks briefly while combat sounds play (MusicConfig ducking settings).

const SFX_ROOT := "res://audio/sfx"
const MUSIC_ROOT := "res://audio/music"
const MUSIC_CONFIG_PATH := "res://audio/music_config.tres"
const MusicConfigScript := preload("res://scripts/audio/music_config.gd")
const AUDIO_EXTENSIONS := ["wav", "ogg", "mp3"]
const POOL_SIZE_3D := 24
const POOL_SIZE_2D := 6

## Every category the game requests. Missing ones are reported once at startup.
const CATEGORIES := [
	"swing_light", "swing_heavy", "impact", "clash", "block", "parry", "guard_break",
	"dodge", "footstep", "enemy_hurt", "player_hurt", "death", "heavy_warn",
	"counter", "finisher", "ui_click", "ui_open",
]

## Per-category default volume offsets (dB) so placeholder and final assets can be balanced here.
const CATEGORY_VOLUME := {
	"footstep": -14.0,
	"swing_light": -4.0,
	"dodge": -6.0,
	"ui_click": -6.0,
	"ui_open": -8.0,
}

var library: Dictionary = {}
var music_tracks: Array[AudioStream] = []
var _music_index := 0
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_2d: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var music_config: MusicConfigScript
var _duck_db := 0.0
var _duck_until_usec := 0
var _last_tick_usec := 0
var _next_3d := 0
var _next_2d := 0
var _missing_reported: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_load_music_config()
	_scan_library()
	for i in POOL_SIZE_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 6.0
		p.max_distance = 60.0
		p.attenuation_filter_cutoff_hz = 12000.0
		add_child(p)
		_pool_3d.append(p)
	for i in POOL_SIZE_2D:
		var p2 := AudioStreamPlayer.new()
		p2.bus = "UI"
		add_child(p2)
		_pool_2d.append(p2)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	_music_player.volume_db = music_config.volume_db
	_music_player.finished.connect(_on_music_finished)
	add_child(_music_player)


func _setup_buses() -> void:
	for bus_name in ["Music", "SFX", "UI"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func _scan_library() -> void:
	library.clear()
	var dir := DirAccess.open(SFX_ROOT)
	if dir:
		for category in dir.get_directories():
			var streams := _load_streams_in(SFX_ROOT.path_join(category))
			if not streams.is_empty():
				library[category] = streams
	_collect_music_tracks()
	var missing: Array[String] = []
	for c in CATEGORIES:
		if not library.has(c):
			missing.append(c)
	if not missing.is_empty():
		print("[AudioManager] No audio supplied for: ", ", ".join(missing))
	print("[AudioManager] Loaded %d SFX categories, %d music tracks." % [library.size(), music_tracks.size()])


func _load_music_config() -> void:
	if ResourceLoader.exists(MUSIC_CONFIG_PATH):
		music_config = load(MUSIC_CONFIG_PATH) as MusicConfigScript
	if music_config == null:
		music_config = MusicConfigScript.new()


## Tracks from the config if any are assigned, otherwise the music folder. Placeholder files
## are dropped from the folder scan once real tracks are present.
func _collect_music_tracks() -> void:
	var tracks: Array[AudioStream] = []
	for t in music_config.tracks:
		if t:
			tracks.append(t)
	if tracks.is_empty():
		var placeholders: Array[AudioStream] = []
		for t in _load_streams_in(MUSIC_ROOT):
			if t.resource_path.get_file().to_lower().contains("placeholder"):
				placeholders.append(t)
			else:
				tracks.append(t)
		if tracks.is_empty():
			tracks = placeholders
	if music_config.shuffle:
		tracks.shuffle()
	music_tracks.assign(tracks)


func _load_streams_in(path: String) -> Array[AudioStream]:
	var out: Array[AudioStream] = []
	var seen: Dictionary = {}
	for file in DirAccess.get_files_at(path):
		# Exported builds list "name.wav.import"/".remap"; strip to the source path.
		var clean := file.trim_suffix(".import").trim_suffix(".remap")
		if seen.has(clean) or not AUDIO_EXTENSIONS.has(clean.get_extension().to_lower()):
			continue
		seen[clean] = true
		var stream := load(path.path_join(clean)) as AudioStream
		if stream:
			out.append(stream)
	out.sort_custom(func(a, b): return a.resource_path < b.resource_path)
	return out


func has_category(category: StringName) -> bool:
	return library.has(String(category))


func _pick(category: StringName) -> AudioStream:
	var list: Array = library.get(String(category), [])
	if list.is_empty():
		if not _missing_reported.has(category):
			_missing_reported[category] = true
			push_warning("[AudioManager] Missing sound category '%s'" % category)
		return null
	return list[randi() % list.size()]


## Plays a positional sound effect. Returns the player used (or null if the category is empty).
func play_sfx(category: StringName, position: Vector3, volume_db: float = 0.0, pitch_variation: float = 0.08) -> AudioStreamPlayer3D:
	var stream := _pick(category)
	if stream == null:
		return null
	var p := _pool_3d[_next_3d]
	_next_3d = (_next_3d + 1) % _pool_3d.size()
	p.stop()
	p.stream = stream
	p.global_position = position
	p.volume_db = volume_db + CATEGORY_VOLUME.get(String(category), 0.0)
	p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	p.play()
	if music_config.duck_categories.has(String(category)):
		duck_music()
	return p


## Plays a non-positional sound (UI, stingers).
func play_ui(category: StringName, volume_db: float = 0.0) -> void:
	var stream := _pick(category)
	if stream == null:
		return
	var p := _pool_2d[_next_2d]
	_next_2d = (_next_2d + 1) % _pool_2d.size()
	p.stream = stream
	p.volume_db = volume_db + CATEGORY_VOLUME.get(String(category), 0.0)
	p.play()


func play_music() -> void:
	if music_tracks.is_empty() or _music_player.playing:
		return
	_start_music_track()


func stop_music() -> void:
	_music_player.stop()


## A single track uses the stream's own loop, which is seamless; with several tracks each one
## plays once and `finished` moves on to the next.
func _start_music_track() -> void:
	var stream := music_tracks[_music_index % music_tracks.size()]
	_set_stream_loop(stream, music_tracks.size() == 1)
	_music_player.stream = stream
	_music_player.play()


func _set_stream_loop(stream: AudioStream, enabled: bool) -> void:
	var wav := stream as AudioStreamWAV
	if wav:
		if not enabled:
			wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
		elif wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			# Keep loop points set in the import dock; otherwise loop the whole file.
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(wav.get_length() * wav.mix_rate)
	elif "loop" in stream:  # AudioStreamOggVorbis, AudioStreamMP3
		stream.set("loop", enabled)


func _on_music_finished() -> void:
	if music_tracks.is_empty():
		return
	_music_index += 1
	_start_music_track()


## Lowers the music for a moment; called for combat sounds and usable from anywhere.
func duck_music() -> void:
	_duck_until_usec = Time.get_ticks_usec() + int(music_config.duck_hold * 1000000.0)


func _process(_delta: float) -> void:
	# Real time, so hitstop and slow motion (Engine.time_scale) do not stall the ducking.
	var now := Time.get_ticks_usec()
	var dt := 0.0 if _last_tick_usec == 0 else (now - _last_tick_usec) / 1000000.0
	_last_tick_usec = now
	var depth: float = music_config.duck_db
	var target := depth if now < _duck_until_usec else 0.0
	var time: float = music_config.duck_attack if target < _duck_db else music_config.duck_release
	_duck_db = move_toward(_duck_db, target, absf(depth) * dt / maxf(time, 0.001))
	if _music_player:
		_music_player.volume_db = music_config.volume_db + _duck_db


func _exit_tree() -> void:
	# Stop playback so streams are released cleanly at shutdown.
	for p in [_music_player] + _pool_3d + _pool_2d:
		p.stop()
		p.stream = null
	library.clear()
	music_tracks.clear()
