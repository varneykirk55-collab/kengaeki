extends Node
## Centralised audio playback.
##
## Sounds are discovered by folder: every file inside res://audio/sfx/<category>/
## becomes a random variation of <category>. Dropping new .wav/.ogg/.mp3 files into
## a folder (or deleting the placeholders) is all that is needed to replace audio.
## Music is any file in res://audio/music/ (played in order, looping).

const SFX_ROOT := "res://audio/sfx"
const MUSIC_ROOT := "res://audio/music"
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
var _next_3d := 0
var _next_2d := 0
var _missing_reported: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
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
	_music_player.volume_db = -10.0
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
	music_tracks.assign(_load_streams_in(MUSIC_ROOT))
	var missing: Array[String] = []
	for c in CATEGORIES:
		if not library.has(c):
			missing.append(c)
	if not missing.is_empty():
		print("[AudioManager] No audio supplied for: ", ", ".join(missing))
	print("[AudioManager] Loaded %d SFX categories, %d music tracks." % [library.size(), music_tracks.size()])


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
	_music_player.stream = music_tracks[_music_index % music_tracks.size()]
	_music_player.play()


func stop_music() -> void:
	_music_player.stop()


func _on_music_finished() -> void:
	_music_index += 1
	_music_player.stream = music_tracks[_music_index % music_tracks.size()]
	_music_player.play()


func _exit_tree() -> void:
	# Stop playback so streams are released cleanly at shutdown.
	for p in [_music_player] + _pool_3d + _pool_2d:
		p.stop()
		p.stream = null
	library.clear()
	music_tracks.clear()
