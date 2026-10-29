extends Node
## Renders reference screenshots of the running game (needs a real renderer, e.g.
## xvfb-run godot --rendering-driver opengl3 --path . res://tools/capture_screens.tscn).

const MAIN := preload("res://scenes/main.tscn")
var main: Node
var out_dir := "res://docs/screenshots"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	CombatFX.time_effects_enabled = false
	main = MAIN.instantiate()
	main.open_menu_on_start = false
	add_child(main)
	await _wait(0.5)
	var player: Player = main.player
	var cam: CameraController = main.camera_rig
	CombatManager.player_god_mode = true

	main.set_menu_open(true)
	await _wait(0.3)
	await _shot("01_encounter_menu")
	main.set_menu_open(false)

	cam.yaw = deg_to_rad(20)
	cam.pitch = deg_to_rad(-22)
	cam.distance = 7.0
	await _wait(1.0)
	await _shot("02_courtyard_overview")

	# Duel: one enemy, AI frozen for a clean mid-swing frame.
	var e: Enemy = _enemy(player.global_position + Vector3(0.6, 0, -2.2))
	e.ai.enabled = false
	cam.distance = 3.6
	cam.yaw = deg_to_rad(-25)
	cam.pitch = deg_to_rad(-10)
	await _wait(0.8)
	player.combat.buffer_attack(PlayerCombat.LIGHT)
	await _wait(0.2)
	await _shot("03_light_attack_active")
	await _wait(0.6)
	e.start_attack(e.attacks[&"enemy_heavy"])
	await _wait(0.4)
	await _shot("04_enemy_heavy_windup")
	Input.action_press(&"block")
	await _wait(0.6)
	await _shot("05_block_clash")
	Input.action_release(&"block")
	main.encounter.clear_enemies()

	# Group fight with live AI.
	main.encounter.spawn_enemies(6, 0.3)
	cam.distance = 5.5
	await _wait(6.0)
	await _shot("06_group_encounter")
	player.toggle_lock_on()
	await _wait(1.0)
	player.combat.buffer_attack(PlayerCombat.LIGHT)
	await _wait(0.25)
	player.combat.buffer_attack(PlayerCombat.LIGHT)
	await _wait(0.3)
	player.combat.buffer_attack(PlayerCombat.LIGHT)
	await _wait(0.3)
	await _shot("07_lock_on_crescent_wheel")

	CombatManager.player_god_mode = false
	player.health.take_damage(999)
	await _wait(2.6)
	await _shot("08_death_screen")
	get_tree().quit()


func _enemy(pos: Vector3) -> Enemy:
	var e: Enemy = main.encounter.enemy_scene.instantiate()
	e.position = pos
	main.enemies_root.add_child(e)
	main.encounter._on_enemy_spawned(e)
	e.face_point(main.player.global_position)
	return e


func _wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, false).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(out_dir.path_join(name + ".png")))
	print("saved ", name)
