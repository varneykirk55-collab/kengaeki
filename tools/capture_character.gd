extends Node
## Renders reference screenshots of the integrated Kengeki character (needs a real renderer):
##   godot --path . res://tools/capture_character.tscn
## Output goes to build/character_shots/ (git-ignored: the character is a private asset).

const MAIN := preload("res://scenes/main.tscn")
const OUT_DIR := "res://build/character_shots"

var main: Node
var player: Player
var cam: Camera3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	CombatFX.time_effects_enabled = false
	main = MAIN.instantiate()
	main.open_menu_on_start = false
	add_child(main)
	player = main.player
	CombatManager.player_god_mode = true
	main.camera_rig.require_mouse_capture = false
	await _wait(0.6)
	cam = Camera3D.new()
	cam.fov = 40.0
	add_child(cam)

	# --- Standing, front / side / back, katana in hand.
	await _wait(1.0)
	await _orbit_shot("idle_front", 0.0, 4.2, 1.0)
	await _orbit_shot("idle_side", 90.0, 4.2, 1.0)
	await _orbit_shot("idle_back", 180.0, 4.2, 1.0)
	await _close_shot("idle_hand_R", "CC_Base_R_Hand", 20.0, 0.9)

	# --- Walk and run, side view following the player.
	Input.action_press(&"move_forward")
	await _wait(0.8)
	await _orbit_shot("walk_side", 90.0, 4.6, 1.0)
	Input.action_press(&"sprint")
	await _wait(0.8)
	await _orbit_shot("run_side", 90.0, 5.0, 1.0)
	await _wait(0.13)
	await _orbit_shot("run_front_armor", 0.0, 3.4, 0.75)
	Input.action_release(&"sprint")
	Input.action_release(&"move_forward")
	await _wait(1.0)

	# --- Attack swings A / B / C at their hit windows (with a target dummy in front).
	var e: Enemy = main.encounter.enemy_scene.instantiate()
	e.position = player.global_position + player.get_forward() * 2.2
	main.enemies_root.add_child(e)
	main.encounter._on_enemy_spawned(e)
	e.ai.enabled = false
	e.health.max_health = 100000.0
	e.health.restore_full()
	e.face_point(player.global_position)
	await _wait(0.3)
	player.combat.buffer_attack(PlayerCombat.LIGHT)
	await _until_phase(AttackRunner.Phase.ACTIVE)
	await _orbit_shot("attack_A_light1_active", 60.0, 4.0, 1.1)
	await _close_shot("attack_A_hand_R", "CC_Base_R_Hand", 60.0, 0.9)
	player.combat.buffer_attack(PlayerCombat.LIGHT)
	await _until_attack(&"light_2")
	await _until_phase(AttackRunner.Phase.ACTIVE)
	await _orbit_shot("attack_B_light2_active", 60.0, 4.0, 1.1)
	await _wait(0.9)
	player.combat.buffer_attack(PlayerCombat.HEAVY)
	await _until_phase(AttackRunner.Phase.STARTUP)
	await _wait(0.2)
	await _orbit_shot("attack_C_heavy_windup", 60.0, 4.0, 1.1)
	await _until_phase(AttackRunner.Phase.ACTIVE)
	await _orbit_shot("attack_C_heavy_active", 60.0, 4.0, 1.1)
	await _wait(1.0)

	# --- Guard pose.
	Input.action_press(&"block")
	await _wait(0.5)
	await _orbit_shot("block_guard", 45.0, 4.0, 1.1)
	Input.action_release(&"block")
	await _wait(0.6)
	main.encounter.clear_enemies()
	await _wait(0.5)

	# --- Sheathe, sheathed idle, draw grab.
	await _tap(&"toggle_sword")
	await _wait(0.45)
	await _orbit_shot("sheathe_mid", 30.0, 3.6, 1.0)
	await _wait(1.0)
	await _orbit_shot("sheathed_front", 0.0, 3.6, 1.0)
	await _orbit_shot("sheathed_left", 90.0, 3.6, 1.0)
	await _close_shot("sheathed_hip", "CC_Base_Hip", -60.0, 1.0)
	await _tap(&"toggle_sword")
	await _wait(DRAW_GRAB_WAIT)
	await _orbit_shot("draw_grab", 30.0, 3.6, 1.0)
	await _wait(0.35)
	await _orbit_shot("draw_out", 30.0, 3.6, 1.0)
	await _wait(1.0)

	# --- Jump apex.
	await _tap(&"jump")
	await _wait(0.27)
	await _orbit_shot("jump_apex", 90.0, 5.0, 1.3)
	await _wait(1.5)

	# --- Normal gameplay camera.
	main.encounter.spawn_enemies(2, 0.2)
	await _wait(3.0)
	cam.current = false
	main.camera_rig.snap_behind_target()
	await _wait(0.6)
	await _shot("gameplay_camera")
	print("capture_character: done")
	get_tree().quit()


const DRAW_GRAB_WAIT := 0.42


func _orbit_shot(shot_name: String, yaw_deg: float, distance: float, height: float) -> void:
	var fwd := player.get_forward()
	var dir := fwd.rotated(Vector3.UP, deg_to_rad(yaw_deg))
	var target := player.global_position + Vector3.UP * height
	cam.current = true
	cam.global_position = target + dir * distance + Vector3.UP * 0.25
	cam.look_at(target)
	await _shot(shot_name)


func _close_shot(shot_name: String, bone: String, yaw_deg: float, distance: float) -> void:
	var vis := player.visual as KengekiCharacterVisual
	var sk := vis.skeleton
	var p := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin
	var dir := player.get_forward().rotated(Vector3.UP, deg_to_rad(yaw_deg))
	cam.current = true
	cam.global_position = p + dir * distance + Vector3.UP * 0.1
	cam.look_at(p)
	await _shot(shot_name)


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, shot_name])
	print("capture_character: ", shot_name)


func _until_phase(phase: int) -> void:
	for i in 120:
		if player.attack_runner.phase == phase:
			return
		await get_tree().physics_frame


func _until_attack(id: StringName) -> void:
	for i in 120:
		if player.attack_runner.is_running() and player.attack_runner.attack.id == id:
			return
		await get_tree().physics_frame


## Pushes a real input event so _unhandled_input handlers run (Input.action_press alone
## only sets the held state).
func _tap(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	get_viewport().push_input(ev)
	await _frames(2)
	ev = InputEventAction.new()
	ev.action = action
	get_viewport().push_input(ev)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait(t: float) -> void:
	await get_tree().create_timer(t, true, true).timeout
