extends Node3D
## Wires the sandbox together: arena, player, camera, encounter manager and UI.

@export var open_menu_on_start: bool = true

var last_interval := 2.0
var menu_open := false

@onready var arena: Arena = $Arena
@onready var player: Player = $Player
@onready var camera_rig: CameraController = $CameraRig
@onready var enemies_root: Node3D = $Enemies
@onready var encounter: EncounterManager = $EncounterManager
@onready var hud: HUD = $UI/HUD
@onready var menu: EncounterMenu = $UI/EncounterMenu
@onready var death_screen: DeathScreen = $UI/DeathScreen


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for world_node in [arena, player, camera_rig, enemies_root, encounter]:
		world_node.process_mode = Node.PROCESS_MODE_PAUSABLE

	player.global_transform = arena.player_start.global_transform
	player.spawn_transform = player.global_transform
	camera_rig.set_target(player)

	encounter.player = player
	encounter.spawner.player = player
	encounter.spawner.spawn_points = arena.get_spawn_points()
	encounter.spawner.container = enemies_root
	encounter.enemy_count_changed.connect(_on_enemy_count_changed)

	hud.bind(player, encounter)
	menu.spawn_requested.connect(_on_spawn_requested)
	menu.clear_requested.connect(_on_clear_requested)
	menu.reset_requested.connect(_on_reset_requested)
	menu.restore_requested.connect(_on_restore_requested)
	menu.max_attackers_changed.connect(_on_max_attackers_changed)
	menu.close_requested.connect(func(): set_menu_open(false))
	death_screen.restart_requested.connect(restart_encounter)
	death_screen.return_requested.connect(return_to_arena)
	player.player_died.connect(_on_player_died)

	death_screen.visible = false
	menu.visible = false
	AudioManager.play_music()
	if "--kengeki-smoke" in OS.get_cmdline_user_args():
		_run_smoke_test()
		return
	if open_menu_on_start:
		set_menu_open(true)
		menu.set_status("Choose how many enemies to face, then Spawn.")
	else:
		_capture_mouse(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_menu") and not death_screen.visible:
		set_menu_open(not menu_open)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not menu_open and not death_screen.visible \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_capture_mouse(true)


func set_menu_open(open: bool) -> void:
	menu_open = open
	if open:
		menu.open()
	else:
		menu.close()
	get_tree().paused = open
	player.input_enabled = not open
	camera_rig.input_enabled = not open
	_capture_mouse(not open)


func _capture_mouse(capture: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE


func _on_spawn_requested(count: int, interval: float) -> void:
	last_interval = interval
	if player.is_dead():
		encounter.reset_encounter()
	encounter.spawn_enemies(count, interval)
	menu.set_status("Spawning %d enemies, one every %.2f s." % [count, interval])
	set_menu_open(false)


func _on_reset_requested() -> void:
	encounter.reset_encounter()
	camera_rig.snap_behind_target()
	menu.set_status("Encounter reset.")


func _on_enemy_count_changed(alive: int, pending: int) -> void:
	hud._on_enemy_count(alive, pending)


func _on_player_died() -> void:
	await get_tree().create_timer(1.6).timeout
	if player.is_dead():
		death_screen.open()
		player.input_enabled = false
		_capture_mouse(false)


func restart_encounter() -> void:
	death_screen.visible = false
	encounter.reset_encounter()
	camera_rig.snap_behind_target()
	encounter.spawn_enemies(encounter.last_requested_count, last_interval)
	set_menu_open(false)


func return_to_arena() -> void:
	death_screen.visible = false
	encounter.reset_encounter()
	camera_rig.snap_behind_target()
	set_menu_open(true)
	menu.set_status("Back in the courtyard. Choose your next encounter.")


func _on_clear_requested() -> void:
	encounter.clear_enemies()
	menu.set_status("Enemies cleared.")


func _on_restore_requested() -> void:
	encounter.restore_player_health()
	menu.set_status("Health and stamina restored.")


func _on_max_attackers_changed(value: int) -> void:
	encounter.max_active_attackers = value
	_on_enemy_count_changed(encounter.alive_count(), encounter.spawner.pending_count())


## Exported-build self check: `KENGEKI.exe -- --kengeki-smoke` (add --headless to skip
## rendering). Spawns 3 enemies, lets a simple bot fight them and exits with code 0 when
## every enemy was defeated and both sides landed blows.
func _run_smoke_test() -> void:
	CombatManager.player_god_mode = true
	CombatFX.time_effects_enabled = false
	var stats := {"player_hits": 0, "enemy_hits": 0, "kills": 0}
	CombatManager.hit_resolved.connect(func(info):
		if info.attacker == player:
			stats.player_hits += 1
		else:
			stats.enemy_hits += 1)
	CombatManager.combatant_died.connect(func(c):
		if c is Enemy:
			stats.kills += 1)
	encounter.spawn_enemies(3, 0.5)
	var t := 0.0
	while t < 90.0 and stats.kills < 3:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var target := player._nearest_enemy(40.0)
		if target:
			var to := target.global_position - player.global_position
			camera_rig.yaw = atan2(-to.x, -to.z)
			if to.length() > 2.2:
				Input.action_press(&"move_forward")
			else:
				Input.action_release(&"move_forward")
				if not player.combat.has_buffered_attack():
					player.combat.buffer_attack(PlayerCombat.LIGHT if randf() < 0.75 else PlayerCombat.HEAVY)
	Input.action_release(&"move_forward")
	var ok: bool = stats.kills >= 3 and stats.player_hits > 0 and stats.enemy_hits > 0
	print("[SMOKE] %s - kills %d, player hits %d, enemy hits %d, attacks loaded %d, %.1f s" % ["PASS" if ok else "FAIL", stats.kills, stats.player_hits, stats.enemy_hits, player.combat.attacks.size(), t])
	get_tree().quit(0 if ok else 1)
