extends Node
## Background music verification: the real tracks in res://audio/music/ load, play on the
## Music bus, keep playing through menu -> gameplay -> combat, duck under combat sounds and
## move on to the next track (wrapping around) when one ends.
##   godot --headless --path . res://tests/music_tests.tscn
## Runs in real time (no --fixed-fps) so audio playback positions advance normally.
## Exit code = number of failed checks.

const MAIN := preload("res://scenes/main.tscn")

## Expected playlist, in play order, with each file's length in seconds (from the source WAVs).
const EXPECTED := [
	["res://audio/music/01_katana_thunder.wav", 180.565],
	["res://audio/music/02_raijins_wrath.wav", 181.312],
	["res://audio/music/03_iron_ronin.wav", 181.493],
]

var main: Node
var failures := 0
var passes := 0
var results: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await test_tracks_loaded()
	await test_menu_gameplay_combat()
	await test_playlist_advances_and_wraps()
	print("\n==== KENGEKI music tests: %d passed, %d failed ====" % [passes, failures])
	for r in results:
		print(r)
	get_tree().paused = false
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(failures)


func check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
		results.append("  PASS  " + label)
	else:
		failures += 1
		results.append("  FAIL  " + label)
		print("  FAIL: ", label)


func wait_real(sec: float) -> void:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


func player() -> AudioStreamPlayer:
	return AudioManager._music_player


func current_path() -> String:
	return player().stream.resource_path if player().stream else ""


func test_tracks_loaded() -> void:
	var tracks: Array[AudioStream] = AudioManager.music_tracks
	check(tracks.size() == EXPECTED.size(), "music: %d tracks loaded (%d)" % [EXPECTED.size(), tracks.size()])
	for i in mini(tracks.size(), EXPECTED.size()):
		var s := tracks[i] as AudioStreamWAV
		var path: String = EXPECTED[i][0]
		var length: float = EXPECTED[i][1]
		check(s != null and s.resource_path == path, "music: track %d is %s" % [i + 1, path.get_file()])
		if s:
			check(absf(s.get_length() - length) < 0.05, "music: %s length %.2f s (expected %.2f)" % [path.get_file(), s.get_length(), length])
			check(s.mix_rate == 48000 and s.stereo and s.data.size() > 30000000, "music: %s is 48 kHz stereo PCM with audio data (%d bytes)" % [path.get_file(), s.data.size()])
	var has_placeholder := tracks.any(func(t): return t.resource_path.contains("placeholder"))
	check(not has_placeholder, "music: placeholder theme skipped now that real tracks are present")
	check(AudioServer.get_bus_index("Music") != -1 and player().bus == &"Music", "music: plays on the Music bus")


func test_menu_gameplay_combat() -> void:
	main = MAIN.instantiate()  # open_menu_on_start = true, as in the real game
	add_child(main)
	await wait_real(0.3)
	check(main.menu_open and get_tree().paused, "menu: game starts with the encounter menu open and paused")
	check(player().playing and current_path() == EXPECTED[0][0], "menu: music playing under the start menu (%s)" % current_path().get_file())
	var p0 := player().get_playback_position()
	await wait_real(1.0)
	var p1 := player().get_playback_position()
	check(p1 - p0 > 0.5, "menu: playback advances while the tree is paused (%.2f -> %.2f s)" % [p0, p1])

	main.set_menu_open(false)
	await wait_real(1.0)
	var p2 := player().get_playback_position()
	check(not get_tree().paused and player().playing and current_path() == EXPECTED[0][0] and p2 > p1,
		"gameplay: same track continues without restarting when the menu closes (%.2f s)" % p2)

	main.encounter.spawn_enemies(2, 0.2)
	await wait_real(0.5)
	check(main.encounter.alive_count() > 0 and player().playing, "combat: music keeps playing with enemies in the courtyard")
	var base_db: float = AudioManager.music_config.volume_db
	AudioManager.play_sfx(&"impact", Vector3.ZERO)
	await wait_real(0.15)
	var ducked := player().volume_db
	check(ducked < base_db - 4.0, "combat: music ducks under a hit (%.1f dB vs %.1f dB)" % [ducked, base_db])
	await wait_real(1.6)
	check(absf(player().volume_db - base_db) < 0.5, "combat: music returns to full volume (%.1f dB)" % player().volume_db)

	main.set_menu_open(true)
	await wait_real(0.5)
	check(get_tree().paused and player().playing, "menu: music still playing when the menu is reopened mid-fight")
	main.set_menu_open(false)
	main.encounter.reset_encounter()


func test_playlist_advances_and_wraps() -> void:
	var order: Array[String] = [current_path()]
	for i in EXPECTED.size():
		var s := player().stream
		var wav := s as AudioStreamWAV
		check(wav != null and wav.loop_mode == AudioStreamWAV.LOOP_DISABLED, "playlist: %s plays once per pass (no per-file loop)" % current_path().get_file())
		player().seek(s.get_length() - 0.4)
		var t0 := Time.get_ticks_msec()
		while current_path() == order[-1] and Time.get_ticks_msec() - t0 < 3000:
			await get_tree().process_frame
		await wait_real(0.3)
		order.append(current_path())
		check(player().playing, "playlist: music still playing after %s ended" % order[-2].get_file())
	var expected_order: Array[String] = []
	for e in EXPECTED:
		expected_order.append(e[0])
	expected_order.append(EXPECTED[0][0])
	check(order == expected_order, "playlist: tracks play in order and wrap to the first (%s)" % ", ".join(order.map(func(p): return p.get_file())))
