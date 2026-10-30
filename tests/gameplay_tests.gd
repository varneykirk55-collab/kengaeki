extends Node
## Automated gameplay verification. Runs the real main scene headless with simulated
## input and checks combat, AI, spawning and UI flows.
##   godot --headless --path . --fixed-fps 60 res://tests/gameplay_tests.tscn
## Exit code = number of failed checks.

const MAIN := preload("res://scenes/main.tscn")

var main: Node
var player: Player
var encounter: EncounterManager
var cam: CameraController
var failures := 0
var passes := 0
var results: Array[String] = []
var hit_log: Array[HitInfo] = []
var attack_log: Array[StringName] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	CombatFX.time_effects_enabled = false
	main = MAIN.instantiate()
	main.open_menu_on_start = false
	add_child(main)
	player = main.player
	encounter = main.encounter
	cam = main.camera_rig
	cam.require_mouse_capture = false
	CombatManager.hit_resolved.connect(func(info): hit_log.append(info))
	player.combat.attack_performed.connect(func(a): attack_log.append(a.id))
	await frames(10)
	await run_all()
	print("\n==== KENGEKI gameplay tests: %d passed, %d failed ====" % [passes, failures])
	for r in results:
		print(r)
	get_tree().quit(failures)


func run_all() -> void:
	var tests := [
		test_audio_library, test_movement, test_sprint_and_stamina, test_camera,
		test_light_attack_single_hit, test_three_hit_combo, test_buffered_input,
		test_light_heavy_and_heavy_light, test_combo_finisher_kesa, test_multi_target_swing,
		test_wheel_hits_behind, test_block, test_parry_and_counter, test_parry_anti_mash,
		test_guard_break_and_finishing_strike, test_dodge_iframes, test_dodge_stamina_gate,
		test_player_hit_reaction, test_enemy_block_reduces_damage, test_enemy_death_and_cleanup,
		test_lock_on, test_placeholder_animation_moves, test_hit_feedback,
		test_ai_duel, test_sequential_spawning, test_group_coordination, test_attacker_limit_configurable,
		test_player_defeats_group, test_clear_cancels_queue, test_repeated_spawn_clear,
		test_menu_buttons, test_death_and_restart, test_imported_visual_pipeline,
		test_character_asset, test_character_root_motion_in_place, test_character_locomotion_states,
		test_character_attack_sync, test_character_attack_sync_segments, test_jump, test_sword_draw_and_sheathe, test_sheathed_attack_draws,
		test_character_reset_after_death,
	]
	var only := OS.get_environment("KENGEKI_TEST")
	for t in tests:
		if only != "" and not t.get_method().contains(only):
			continue
		await reset_world()
		print("--- ", t.get_method())
		await t.call()


# --- Helpers ---------------------------------------------------------------------

func check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
		results.append("  PASS  " + label)
	else:
		failures += 1
		results.append("  FAIL  " + label)
		print("  FAIL: ", label)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func seconds(t: float) -> void:
	await frames(int(round(t * 60.0)))


## Held state goes through Input.action_press; the press *event* is pushed through the
## viewport so _unhandled_input handlers run exactly as for real key presses.
## (Input.parse_input_event with several InputEventActions only keeps the last one held.)
func press(action: StringName) -> void:
	Input.action_press(action)
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	get_viewport().push_input(ev)


func release(action: StringName) -> void:
	Input.action_release(action)
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = false
	get_viewport().push_input(ev)


func tap(action: StringName) -> void:
	press(action)
	await frames(2)
	release(action)


func release_all() -> void:
	for a in [&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint", &"block", &"light_attack", &"heavy_attack", &"dodge", &"jump", &"toggle_sword"]:
		Input.action_release(a)


func reset_world() -> void:
	release_all()
	if main.menu_open:
		main.set_menu_open(false)
	main.death_screen.visible = false
	encounter.reset_encounter()
	encounter.max_active_attackers = 2
	CombatManager.player_god_mode = false
	if player.state in [Player.State.EQUIP, Player.State.AIRBORNE] or not player.sword_drawn:
		player.revive(Transform3D(Basis(), Vector3(0, 0.05, 0)))
	player.input_enabled = true
	player.global_position = Vector3(0, 0.05, 0)
	player.rotation = Vector3.ZERO
	cam.snap_behind_target()
	hit_log.clear()
	attack_log.clear()
	await frames(20)


## Spawns an enemy directly (AI optional) at an offset relative to the player.
func make_enemy(offset: Vector3, ai_on: bool = false, max_hp: float = 60.0) -> Enemy:
	var e: Enemy = encounter.enemy_scene.instantiate()
	e.position = player.global_position + offset
	main.enemies_root.add_child(e)
	encounter._on_enemy_spawned(e)
	e.ai.enabled = ai_on
	e.health.max_health = max_hp
	e.health.restore_full()
	e.block_chance = 0.0 if not ai_on else e.block_chance
	e.face_point(player.global_position)
	return e


func results_against(defender: Node) -> Array:
	return hit_log.filter(func(i): return i.defender == defender).map(func(i): return i.result)


# --- Tests ---------------------------------------------------------------------------

func test_audio_library() -> void:
	var missing := []
	for c in AudioManager.CATEGORIES:
		if not AudioManager.has_category(c):
			missing.append(c)
	check(missing.is_empty(), "audio: all %d SFX categories have placeholder sounds (missing: %s)" % [AudioManager.CATEGORIES.size(), missing])
	check(AudioManager.music_tracks.size() >= 1, "audio: background music track loaded")


func test_movement() -> void:
	var start := player.global_position
	press(&"move_forward")
	await seconds(1.0)
	release(&"move_forward")
	var moved := player.global_position - start
	check(moved.z < -3.5 and absf(moved.x) < 0.3, "movement: W moves camera-forward (%.2f m)" % -moved.z)
	await seconds(0.4)
	check(Vector2(player.velocity.x, player.velocity.z).length() < 0.2, "movement: smooth deceleration to a stop")
	# Camera-relative: rotate camera 90 degrees and move forward again.
	cam.yaw = deg_to_rad(90.0)
	start = player.global_position
	press(&"move_forward")
	await seconds(0.6)
	release(&"move_forward")
	moved = player.global_position - start
	check(moved.x < -1.5 and absf(moved.z) < 0.4, "movement: direction follows camera yaw (dx %.2f)" % moved.x)
	check(rad_to_deg(absf(angle_difference(player.rotation.y, deg_to_rad(90.0)))) < 15.0, "movement: character turns to face travel direction")


func test_sprint_and_stamina() -> void:
	var start := player.global_position
	press(&"sprint")
	press(&"move_forward")
	await seconds(1.0)
	release(&"move_forward")
	release(&"sprint")
	check(player.global_position.distance_to(start) > 6.0, "sprint: faster than walking (%.2f m in 1 s)" % player.global_position.distance_to(start))
	check(player.stamina.current < 95.0, "sprint: drains stamina (%.1f)" % player.stamina.current)
	await seconds(3.0)
	check(player.stamina.current >= 99.0, "stamina: regenerates after delay")


func test_camera() -> void:
	var yaw0 := cam.yaw
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(100, 0)
	cam._unhandled_input(ev)
	check(absf(cam.yaw - yaw0 - (-100 * cam.mouse_sensitivity)) < 0.001, "camera: mouse rotates yaw")
	var d0 := cam.distance
	var zoom := InputEventMouseButton.new()
	zoom.button_index = MOUSE_BUTTON_WHEEL_DOWN
	zoom.pressed = true
	cam._unhandled_input(zoom)
	check(cam.distance > d0, "camera: adjustable distance (%.1f -> %.1f)" % [d0, cam.distance])
	# Collision: back the player against the south wall so the camera would be inside it.
	player.global_position = Vector3(0, 0.05, 19.0)
	cam.yaw = 0.0
	cam.pitch = 0.0
	cam.snap_behind_target()
	cam.pitch = 0.0
	await frames(30)
	check(cam.spring_arm.get_hit_length() < cam.spring_arm.spring_length - 0.5, "camera: collision pulls camera in front of wall (hit %.2f of %.2f)" % [cam.spring_arm.get_hit_length(), cam.spring_arm.spring_length])


func test_light_attack_single_hit() -> void:
	var e := make_enemy(Vector3(0, 0, -1.8))
	await frames(5)
	await tap(&"light_attack")
	await seconds(0.7)
	check(attack_log == [&"light_1"], "light attack performed (%s)" % [attack_log])
	check(is_equal_approx(e.health.current, 60.0 - 14.0), "light attack: exactly one hit of 14 damage (hp %.1f)" % e.health.current)
	check(results_against(e).size() == 1, "light attack: no repeated damage from one swing")


func test_three_hit_combo() -> void:
	var e := make_enemy(Vector3(0, 0, -1.8), false, 1000.0)
	await frames(5)
	for i in 3:
		await tap(&"light_attack")
		await seconds(0.22)
	await seconds(1.0)
	check(attack_log == [&"light_1", &"light_2", &"light_3"], "three-hit light combo chains (%s)" % [attack_log])
	check(results_against(e).size() == 3 and is_equal_approx(e.health.current, 1000.0 - 54.0), "three-hit combo: all three hits land (hp %.1f)" % e.health.current)


func test_buffered_input() -> void:
	make_enemy(Vector3(0, 0, -1.8), false, 1000.0)
	await frames(5)
	await tap(&"light_attack")
	await frames(3)  # second press during the first attack's startup
	await tap(&"light_attack")
	await seconds(1.0)
	check(attack_log == [&"light_1", &"light_2"], "input buffer: early press is queued into the next combo hit (%s)" % [attack_log])


func test_light_heavy_and_heavy_light() -> void:
	make_enemy(Vector3(0, 0, -1.8), false, 1000.0)
	await frames(5)
	await tap(&"light_attack")
	await seconds(0.2)
	await tap(&"heavy_attack")
	await seconds(1.5)
	check(attack_log == [&"light_1", &"light_heavy"], "light > heavy combo (%s)" % [attack_log])
	attack_log.clear()
	await tap(&"heavy_attack")
	await seconds(0.4)
	await tap(&"light_attack")
	await seconds(1.2)
	check(attack_log == [&"heavy_1", &"heavy_light"], "heavy > light combo (%s)" % [attack_log])


func test_combo_finisher_kesa() -> void:
	var e := make_enemy(Vector3(0, 0, -1.8), false, 1000.0)
	await frames(5)
	await tap(&"light_attack")
	await seconds(0.22)
	await tap(&"light_attack")
	await seconds(0.22)
	await tap(&"heavy_attack")
	await seconds(1.4)
	check(attack_log == [&"light_1", &"light_2", &"finisher_kesa"], "light-light-heavy finisher (%s)" % [attack_log])
	check(1000.0 - e.health.current >= 14 + 14 + 42 - 0.1, "kesa finisher deals its damage (total %.1f)" % (1000.0 - e.health.current))


func test_multi_target_swing() -> void:
	var a := make_enemy(Vector3(-1.3, 0, -1.4))
	var b := make_enemy(Vector3(0, 0, -1.9))
	var c := make_enemy(Vector3(1.3, 0, -1.4))
	await frames(5)
	await tap(&"light_attack")
	await seconds(0.7)
	var hit_count := 0
	for e in [a, b, c]:
		if e.health.current < 60.0:
			hit_count += 1
	check(hit_count == 3, "one light swing damages multiple enemies (%d/3)" % hit_count)


func test_wheel_hits_behind() -> void:
	var front := make_enemy(Vector3(0, 0, -1.8), false, 1000.0)
	var behind := make_enemy(Vector3(0, 0, 1.8), false, 1000.0)
	await frames(5)
	for i in 3:
		await tap(&"light_attack")
		await seconds(0.22)
	await seconds(1.0)
	check(behind.health.current < 1000.0 and front.health.current < 1000.0, "Crescent Wheel finisher strikes all around (behind hp %.0f)" % behind.health.current)


func test_block() -> void:
	var e := make_enemy(Vector3(0, 0, -1.9))
	await frames(5)
	press(&"block")
	await seconds(0.5)  # past the parry window
	var stamina_before := player.stamina.current
	e.start_attack(e.attacks[&"enemy_slash"])
	await seconds(0.8)
	var r := results_against(player)
	check(r == [HitInfo.Result.BLOCKED], "block: enemy strike is blocked (%s)" % [r])
	check(absf(player.health.current - (100.0 - 12.0 * player.block_damage_ratio)) < 0.01, "block: only chip damage taken (hp %.1f)" % player.health.current)
	check(player.stamina.current < stamina_before - 10.0, "block: costs stamina/guard")
	release(&"block")


func test_parry_and_counter() -> void:
	var e := make_enemy(Vector3(0, 0, -1.9), false, 200.0)
	await frames(5)
	e.start_attack(e.attacks[&"enemy_slash"])  # 0.42 s startup
	await seconds(0.3)
	press(&"block")
	await seconds(0.3)
	release(&"block")
	var r := results_against(player)
	check(r == [HitInfo.Result.PARRIED], "timed parry succeeds (%s)" % [r])
	check(player.health.current == 100.0, "parry: no damage taken")
	check(e.is_vulnerable(), "parry: attacker staggered and vulnerable")
	check(player.combat.has_counter_opportunity(), "parry: counter window opened")
	var hp := e.health.current
	await tap(&"light_attack")
	await seconds(0.9)
	check(attack_log.has(&"counter_riposte"), "counterattack performed after parry (%s)" % [attack_log])
	check(hp - e.health.current >= 60.0, "counterattack deals heavy damage (%.0f)" % (hp - e.health.current))


func test_parry_anti_mash() -> void:
	player.combat.on_block_pressed()
	await frames(20)
	player.combat.on_block_pressed()  # re-press 0.33 s later after a whiff
	check(not player.combat.is_parry_active(), "parry: mashing block does not reopen the window immediately")


func test_guard_break_and_finishing_strike() -> void:
	var e := make_enemy(Vector3(0, 0, -1.9), false, 500.0)
	await frames(5)
	e.ai.transition(&"block", {"duration": 30.0})
	for i in 4:
		await tap(&"heavy_attack")
		await seconds(0.95)
		if e.is_vulnerable():
			break
	var r := results_against(e)
	check(r.has(HitInfo.Result.BLOCKED), "enemy blocks player attacks (%s)" % [r])
	check(r.has(HitInfo.Result.GUARD_BROKEN), "heavy attacks break the enemy guard")
	check(e.is_vulnerable(), "guard-broken enemy is vulnerable")
	attack_log.clear()
	await tap(&"heavy_attack")
	await seconds(1.0)
	check(attack_log == [&"finishing_strike"], "heavy on a vulnerable enemy triggers the finishing strike (%s)" % [attack_log])
	check(e.is_dead() or e.health.current < 500.0 - 100.0, "finishing strike lands (hp %.0f)" % e.health.current)


func test_dodge_iframes() -> void:
	var e := make_enemy(Vector3(0, 0, -1.9))
	await frames(5)
	press(&"move_right")
	await tap(&"dodge")
	await frames(6)
	check(player.state == Player.State.DODGE and player.is_invulnerable(), "dodge: brief invulnerability active")
	var res := CombatManager.resolve_hit(e, player, e.attacks[&"enemy_slash"])
	check(res == HitInfo.Result.DODGED and player.health.current == 100.0, "dodge: strike during i-frames deals no damage")
	await seconds(0.35)
	check(not player.is_invulnerable(), "dodge: invulnerability ends")
	release(&"move_right")
	check(player.global_position.x > 2.5, "dodge: moves in input direction (x %.2f)" % player.global_position.x)


func test_dodge_stamina_gate() -> void:
	var count := 0
	for i in 8:
		await tap(&"dodge")
		await seconds(0.45)
		if player.state == Player.State.DODGE or attack_log.size() > 0:
			pass
	# 100 stamina / 18 per dodge with regen pauses: should be refused at some point.
	player.stamina.current = 5.0
	await tap(&"dodge")
	await frames(3)
	check(player.state != Player.State.DODGE, "dodge: refused without enough stamina")


func test_player_hit_reaction() -> void:
	var e := make_enemy(Vector3(0, 0, -1.9))
	await frames(5)
	e.start_attack(e.attacks[&"enemy_slash"])
	await seconds(0.5)
	check(player.health.current == 88.0, "enemy strike damages unguarded player (hp %.0f)" % player.health.current)
	check(player.state == Player.State.HITSTUN, "player hit reaction (hitstun)")
	await seconds(0.6)
	check(player.state == Player.State.MOVE, "player recovers from hitstun")


func test_enemy_block_reduces_damage() -> void:
	var e := make_enemy(Vector3(0, 0, -1.8), false, 100.0)
	await frames(5)
	e.ai.transition(&"block", {"duration": 5.0})
	await tap(&"light_attack")
	await seconds(0.6)
	check(results_against(e) == [HitInfo.Result.BLOCKED] and e.health.current > 98.0, "enemy block reduces damage (hp %.1f)" % e.health.current)


func test_enemy_death_and_cleanup() -> void:
	var e := make_enemy(Vector3(0, 0, -1.8))
	e.corpse_time = 0.5
	await frames(5)
	var died := [false]
	e.died.connect(func(_c): died[0] = true)
	for i in 6:
		await tap(&"light_attack")
		await seconds(0.25)
		if e.is_dead():
			break
	check(died[0] and e.is_dead(), "enemy dies at zero health")
	check(encounter.alive_count() == 0, "enemy count updates on death")
	await seconds(2.5)
	check(not is_instance_valid(e), "defeated enemy is cleaned up")


func test_lock_on() -> void:
	var a := make_enemy(Vector3(-2.0, 0, -5.0))
	var b := make_enemy(Vector3(2.0, 0, -5.0))
	await frames(5)
	await tap(&"lock_on")
	await frames(2)
	check(player.lock_target != null, "lock-on acquires a target")
	var first := player.lock_target
	await tap(&"switch_target")
	await frames(2)
	check(player.lock_target != null and player.lock_target != first, "lock-on target switching")
	await seconds(1.0)
	var to := player.lock_target.global_position - player.global_position
	check(rad_to_deg(absf(angle_difference(cam.yaw, atan2(-to.x, -to.z)))) < 15.0, "camera turns toward the locked target")
	player.lock_target.health.take_damage(999)
	await frames(3)
	check(player.lock_target != null and not player.lock_target.is_dead(), "lock-on hops to the next enemy when the target dies")
	await tap(&"lock_on")
	await frames(2)
	check(player.lock_target == null, "lock-on toggles off")


func test_placeholder_animation_moves() -> void:
	make_enemy(Vector3(0, 0, -1.8), false, 1000.0)
	await frames(5)
	var tip := player.weapon.katana.blade_tip
	var positions: Array[Vector3] = []
	await tap(&"light_attack")
	for i in 30:
		positions.append(tip.global_position)
		await frames(1)
	var travel := 0.0
	for i in range(1, positions.size()):
		travel += positions[i].distance_to(positions[i - 1])
	check(travel > 1.0, "placeholder attack animation visibly moves the blade (%.2f m tip travel)" % travel)
	check(player.weapon.katana.trail != null, "blade trail present on katana")


func test_hit_feedback() -> void:
	CombatFX.time_effects_enabled = true
	var trauma_before := cam.trauma
	var e := make_enemy(Vector3(0, 0, -1.8), false, 1000.0)
	await frames(5)
	await tap(&"heavy_attack")
	var saw_hitstop := false
	var max_trauma := trauma_before
	for i in 40:
		await frames(1)
		saw_hitstop = saw_hitstop or Engine.time_scale < 0.5
		max_trauma = maxf(max_trauma, cam.trauma)
	CombatFX.clear_time_effects()
	CombatFX.time_effects_enabled = false
	check(e.health.current < 1000.0, "heavy attack lands")
	check(saw_hitstop, "hit-stop applied on impact")
	check(max_trauma > trauma_before + 0.1, "camera shake on significant impact")


func test_ai_duel() -> void:
	encounter.spawn_enemies(1, 2.0)
	await frames(2)
	var e: Enemy = encounter.enemies[0]
	var start_dist := e.distance_to_target()
	var states := {}
	e.ai.state_changed.connect(func(_f, t): states[t] = true)
	var attacked := false
	for i in 60 * 15:
		await frames(1)
		for h in hit_log:
			if h.attacker == e:
				attacked = true
		if attacked:
			break
	check(start_dist > 7.0, "enemy spawns away from the player (%.1f m)" % start_dist)
	check(states.has(&"approach") and states.has(&"engage"), "AI approaches and engages (%s)" % [states.keys()])
	check(attacked, "AI attacks the player in a duel")


func test_sequential_spawning() -> void:
	CombatManager.player_god_mode = true
	encounter.spawner.spawn_log.clear()
	var positions: Array[Vector3] = []
	encounter.spawner.enemy_spawned.connect(func(en): positions.append(en.global_position), CONNECT_ONE_SHOT)
	encounter.spawn_enemies(5, 0.5)
	await frames(2)
	check(encounter.alive_count() == 1 and encounter.spawner.pending_count() == 4, "spawn: first enemy enters immediately, rest queued")
	await seconds(2.4)
	var log := encounter.spawner.spawn_log
	check(log.size() == 5, "spawn: exact count spawned (%d)" % log.size())
	var gaps_ok := true
	for i in range(1, log.size()):
		gaps_ok = gaps_ok and absf(log[i] - log[i - 1] - 0.5) < 0.05
	check(gaps_ok, "spawn: enemies enter sequentially at the chosen interval")
	var far_ok := true
	for en in encounter.enemies:
		pass
	for p in positions:
		far_ok = far_ok and p.distance_to(player.global_position) >= 7.0
	check(far_ok, "spawn: not on top of the player")


func test_group_coordination() -> void:
	CombatManager.player_god_mode = true
	encounter.spawn_enemies(6, 0.3)
	var over_limit := false
	var min_spacing := INF
	var stuck_check := {}
	for i in 60 * 30:
		await frames(1)
		# The test player is a passive dummy; keep it mid-arena (a real player moves) so
		# accumulated knockback does not pin it into a corner and skew the spread check.
		player.global_position = Vector3(player.global_position.x * 0.9, player.global_position.y, player.global_position.z * 0.9) if player.global_position.length() > 3.0 else player.global_position
		if encounter.active_attacker_count() > encounter.max_active_attackers:
			over_limit = true
		if i % 30 == 0 and i > 60 * 6:
			var live := encounter.enemies.filter(func(e): return is_instance_valid(e) and not e.is_dead())
			for x in live.size():
				for y in range(x + 1, live.size()):
					min_spacing = minf(min_spacing, live[x].global_position.distance_to(live[y].global_position))
	var with_tokens := 0
	for e in encounter.enemies:
		if encounter.tokens_granted.get(e.get_instance_id(), 0) > 0:
			with_tokens += 1
	var attackers := {}
	for h in hit_log:
		if h.defender == player:
			attackers[h.attacker] = true
	check(not over_limit and encounter.peak_active_attackers <= 2, "group: never more than 2 simultaneous attackers (peak %d)" % encounter.peak_active_attackers)
	check(encounter.peak_active_attackers == 2, "group: attacker slots are used")
	check(with_tokens == 6, "group: every enemy gets an attack turn within 30 s (%d/6) - no permanent waiting" % with_tokens)
	check(attackers.size() >= 4, "group: several different enemies actually strike (%d)" % attackers.size())
	check(min_spacing > 0.6, "group: enemies avoid stacking on each other (min spacing %.2f m)" % min_spacing)
	# Ring distribution: bearings of waiting enemies should cover several directions.
	var sectors := {}
	for e in encounter.enemies:
		var d: Vector3 = e.global_position - player.global_position
		sectors[int(floor((atan2(d.x, d.z) + PI) / (PI / 2.0)))] = true
	check(sectors.size() >= 3, "group: enemies surround the player from different directions (%d quadrants)" % sectors.size())


func test_attacker_limit_configurable() -> void:
	CombatManager.player_god_mode = true
	encounter.max_active_attackers = 3
	encounter.spawn_enemies(6, 0.2)
	var over := false
	for i in 60 * 15:
		await frames(1)
		over = over or encounter.active_attacker_count() > 3
	check(not over and encounter.peak_active_attackers == 3, "group: attacker limit is configurable (limit 3, peak %d)" % encounter.peak_active_attackers)


## Simple bot: lock on, attack, block when an enemy winds up. Proves multi-enemy fights resolve.
func test_player_defeats_group() -> void:
	CombatManager.player_god_mode = true
	encounter.spawn_enemies(3, 0.5)
	var t := 0
	var kills := [0]
	CombatManager.combatant_died.connect(func(c): if c is Enemy: kills[0] += 1)
	while t < 60 * 60 and (encounter.alive_count() > 0 or encounter.spawner.pending_count() > 0):
		var target := player.combat.find_attack_target()
		if target == null:
			target = player._nearest_enemy(40.0)
		if target:
			var to := target.global_position - player.global_position
			cam.yaw = atan2(-to.x, -to.z)
			if to.length() > 2.2:
				Input.action_press(&"move_forward")
			else:
				Input.action_release(&"move_forward")
				if t % 12 == 0:
					await tap(&"light_attack" if (t / 12) % 4 != 3 else &"heavy_attack")
					t += 2
		await frames(1)
		t += 1
	release_all()
	check(kills[0] >= 3 and encounter.alive_count() == 0, "multi-enemy fight: player defeats all 3 enemies (%d kills in %.1f s)" % [kills[0], t / 60.0])


func test_clear_cancels_queue() -> void:
	encounter.spawn_enemies(5, 1.0)
	await seconds(1.5)
	check(encounter.alive_count() == 2, "spawn: 2 of 5 entered after 1.5 s at 1 s interval (%d)" % encounter.alive_count())
	encounter.clear_enemies()
	await frames(2)
	check(encounter.alive_count() == 0 and encounter.spawner.pending_count() == 0, "clear: removes enemies and cancels queued spawns")
	await seconds(3.0)
	check(get_tree().get_nodes_in_group(&"enemies").size() == 0, "clear: nothing spawns afterwards")


func test_repeated_spawn_clear() -> void:
	var ok := true
	for cycle in 5:
		encounter.spawn_enemies(cycle + 2, 0.1)
		await seconds(0.25 + (cycle + 2) * 0.1)
		ok = ok and encounter.alive_count() == cycle + 2
		encounter.clear_enemies()
		await frames(3)
		ok = ok and get_tree().get_nodes_in_group(&"enemies").size() == 0
	check(ok, "repeated spawn / clear cycles stay consistent")
	encounter.spawn_enemies(10, 0.1)
	await seconds(1.5)
	check(encounter.alive_count() == 10, "spawn: supports 10 enemies (%d)" % encounter.alive_count())
	encounter.spawn_enemies(10, 0.1)
	encounter.spawn_enemies(10, 0.1)
	await seconds(4.0)
	check(encounter.alive_count() <= encounter.spawner.max_alive, "spawn: safety cap respected under spammed requests (%d alive)" % encounter.alive_count())


func test_menu_buttons() -> void:
	var menu: EncounterMenu = main.menu
	main.set_menu_open(true)
	check(get_tree().paused and menu.visible, "menu: opens and pauses")
	menu.count_spin.value = 4
	menu.interval_slider.value = 0.5
	menu.attackers_spin.value = 3
	check(encounter.max_active_attackers == 3, "menu: max attackers control applies")
	menu.spawn_button.pressed.emit()
	check(not get_tree().paused and not menu.visible, "menu: spawn closes the menu and resumes")
	await seconds(2.0)
	check(encounter.alive_count() == 4, "menu: spawns the exact selected count (%d)" % encounter.alive_count())
	player.health.take_damage(40)
	main.set_menu_open(true)
	menu.restore_button.pressed.emit()
	check(player.health.current == player.health.max_health, "menu: restore health")
	menu.clear_button.pressed.emit()
	check(encounter.alive_count() == 0, "menu: clear enemies")
	menu.count_spin.value = 2
	menu.spawn_button.pressed.emit()
	await seconds(0.5)
	main.set_menu_open(true)
	menu.reset_button.pressed.emit()
	check(encounter.alive_count() == 0 and encounter.spawner.pending_count() == 0 and player.health.current == 100.0, "menu: reset encounter")
	menu.resume_button.pressed.emit()
	check(not get_tree().paused, "menu: resume")


func test_death_and_restart() -> void:
	encounter.spawn_enemies(2, 0.5)
	await seconds(0.2)
	player.health.take_damage(1000)
	await frames(2)
	check(player.state == Player.State.DEAD, "player death state")
	await seconds(2.0)
	check(main.death_screen.visible, "death screen shown")
	press(&"move_forward")
	await seconds(0.3)
	release(&"move_forward")
	main.death_screen.restart_button.pressed.emit()
	await seconds(1.0)
	check(not player.is_dead() and player.health.current == 100.0 and player.state != Player.State.DEAD, "restart: player revived at full health")
	check(not main.death_screen.visible and encounter.alive_count() + encounter.spawner.pending_count() == 2, "restart: encounter restarts with the same enemy count")
	player.health.take_damage(1000)
	await seconds(2.0)
	main.death_screen.return_button.pressed.emit()
	check(main.menu_open and not player.is_dead() and encounter.alive_count() == 0, "return to arena: revived, enemies cleared, menu open")
	main.set_menu_open(false)


## Builds a stand-in for an imported Hunyuan character (skeleton + AnimationPlayer whose
## attack clip carries hit_start / hit_end / attack_end method-track events), swaps it in
## as an enemy's visual and checks katana bone attachment + event-driven hit windows.
func test_imported_visual_pipeline() -> void:
	var model := Node3D.new()
	model.name = "FakeHunyuanModel"
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	model.add_child(skel)
	skel.owner = model
	skel.add_bone("Hips")
	skel.add_bone("RightHand")
	skel.set_bone_parent(1, 0)
	skel.set_bone_rest(0, Transform3D(Basis(), Vector3(0, 0.95, 0)))
	skel.set_bone_rest(1, Transform3D(Basis(), Vector3(0.3, 0.3, -0.3)))
	skel.reset_bone_poses()
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	model.add_child(ap)
	ap.owner = model
	var lib := AnimationLibrary.new()
	for clip in ["Idle", "Walk", "Run", "SlashRL"]:
		var anim := Animation.new()
		anim.length = 1.0
		if clip == "SlashRL":
			var track := anim.add_track(Animation.TYPE_METHOD)
			anim.track_set_path(track, NodePath(".."))  # AnimationPlayer root (model) -> its parent = visual
			anim.track_insert_key(track, 0.3, {"method": &"emit_animation_event", "args": [&"hit_start"]})
			anim.track_insert_key(track, 0.42, {"method": &"emit_animation_event", "args": [&"hit_end"]})
			anim.track_insert_key(track, 0.8, {"method": &"emit_animation_event", "args": [&"attack_end"]})
		lib.add_animation(clip, anim)
	ap.add_animation_library("", lib)
	var packed := PackedScene.new()
	check(packed.pack(model) == OK, "import pipeline: synthetic rigged model packs")
	model.free()

	var e: Enemy = encounter.enemy_scene.instantiate()
	var old := e.get_node("Visual")
	e.remove_child(old)
	old.free()
	var vis := ImportedHumanoidVisual.new()
	vis.name = "Visual"
	vis.model_scene = packed
	vis.model_yaw_degrees = 0.0
	e.add_child(vis)
	e.position = player.global_position + Vector3(0, 0, -1.9)
	main.enemies_root.add_child(e)
	encounter._on_enemy_spawned(e)
	e.ai.enabled = false
	e.face_point(player.global_position)
	await frames(5)
	check(e.weapon.katana != null and e.weapon.katana.get_parent() is BoneAttachment3D, "import pipeline: katana attached to the hand bone")
	var attack: AttackData = e.attacks[&"enemy_slash"].duplicate()
	attack.timing_source = AttackData.TimingSource.ANIMATION_EVENTS
	attack.startup = 1.0  # data fallback would open the window only after 2 s
	e.start_attack(attack)
	await seconds(0.38)
	check(vis.anim_player.current_animation == "SlashRL", "import pipeline: attack plays the mapped clip (%s)" % vis.anim_player.current_animation)
	check(e.attack_runner.phase == AttackRunner.Phase.ACTIVE or results_against(player).size() > 0, "import pipeline: hit window opened by the animation event, not data timing")
	await seconds(0.3)
	check(results_against(player).size() == 1, "import pipeline: animation-timed strike resolves through combat")
	await seconds(0.6)
	check(not e.attack_runner.is_running(), "import pipeline: attack_end event finishes the attack")


# --- Kengeki character integration -------------------------------------------------------

func _kvis() -> KengekiCharacterVisual:
	return player.visual as KengekiCharacterVisual


func _bone_world(bone: String) -> Vector3:
	var sk := _kvis().skeleton
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin


func _katana_bone() -> StringName:
	var a := player.weapon.katana.get_parent() as BoneAttachment3D
	return a.bone_name if a else &""


func test_character_asset() -> void:
	var v := _kvis()
	check(v != null and v.model != null and v.skeleton != null, "character: AccuRIG model and skeleton loaded as the player visual")
	if v == null or v.model == null:
		return
	var clips := ["Idle_Unarmed", "Walk", "Run", "Jump", "Sword_Draw", "Sword_Sheathe", "Sword_Combo_OneHand"]
	var missing := clips.filter(func(c): return not v.anim_player.has_animation(c))
	check(missing.is_empty(), "character: all seven clips present (missing %s)" % [missing])
	check(v.anim_tree != null and v.anim_tree.active and str(v.anim_tree.root_motion_track) == "Kengeki_Rig/Skeleton3D:RL_BoneRoot", "character: AnimationTree active, root motion track RL_BoneRoot")
	check(v.model.find_children("*", "Skeleton3D", true, false).size() == 1, "character: exactly one skeleton")
	var katanas := player.find_children("*", "", true, false).filter(func(n): return n is Katana)
	check(katanas.size() == 1 and player.weapon.katana == katanas[0], "character: exactly one katana, wired to the weapon component")
	check(_katana_bone() == &"CC_Base_R_Hand", "character: katana held in the right hand bone")
	var mi := v.model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var mat := mi.mesh.surface_get_material(0) as BaseMaterial3D
	check(mat != null and mat.albedo_texture != null and mat.normal_texture != null, "character: material keeps albedo and normal textures")
	var head := _bone_world("CC_Base_Head").y - player.global_position.y
	check(head > 1.35 and head < 1.65, "character: scaled to the 1.8 m capsule (head bone at %.2f m)" % head)
	var to_toe := _bone_world("CC_Base_R_ToeBase") - _bone_world("CC_Base_R_Foot")
	to_toe.y = 0.0
	check(to_toe.normalized().dot(player.get_forward()) > 0.7, "character: model faces the gameplay forward direction")


func test_character_root_motion_in_place() -> void:
	# Walk, sprint and loop several cycles: the hips must stay over the capsule (root motion
	# extracted, not applied) and never jump between frames (no snap-back on loop).
	var v := _kvis()
	var max_offset := 0.0
	var max_jump := 0.0
	var prev := Vector3.INF
	press(&"move_forward")
	for i in 150:
		if i == 60:
			press(&"sprint")
		await frames(1)
		var hip := _bone_world("CC_Base_Hip") - player.global_position
		hip.y = 0.0
		hip = player.global_transform.basis.inverse() * hip
		max_offset = maxf(max_offset, hip.length())
		if prev != Vector3.INF:
			max_jump = maxf(max_jump, hip.distance_to(prev))
		prev = hip
	release(&"sprint")
	release(&"move_forward")
	var root := v.skeleton.get_bone_pose_position(v.skeleton.find_bone("RL_BoneRoot"))
	check(max_offset < 0.35, "root motion: hips stay over the body while walking/sprinting (max %.2f m)" % max_offset)
	check(max_jump < 0.08, "root motion: no snapping between frames across loops (max %.3f m)" % max_jump)
	check(Vector2(root.x, root.z).length() < 0.01 and absf(root.y) < 0.01, "root motion: RL_BoneRoot travel not applied to the skeleton (%s)" % root)


func test_character_locomotion_states() -> void:
	var v := _kvis()
	await seconds(0.3)
	check(String(v.anim_tree.get("parameters/loco/current_state")) == "idle", "locomotion: idle when standing")
	press(&"move_forward")
	await seconds(0.5)
	check(String(v.anim_tree.get("parameters/loco/current_state")) == "walk", "locomotion: walk when moving")
	press(&"sprint")
	await seconds(0.6)
	check(String(v.anim_tree.get("parameters/loco/current_state")) == "run", "locomotion: run when sprinting")
	# The locomotion clip must keep playing, not restart every frame.
	var hand_a := player.global_transform.basis.inverse() * (_bone_world("CC_Base_L_Hand") - player.global_position)
	await frames(6)
	var hand_b := player.global_transform.basis.inverse() * (_bone_world("CC_Base_L_Hand") - player.global_position)
	check(hand_a.distance_to(hand_b) > 0.03, "locomotion: run cycle advances (arm moved %.2f m)" % hand_a.distance_to(hand_b))
	release(&"sprint")
	release(&"move_forward")
	await seconds(0.8)
	check(String(v.anim_tree.get("parameters/loco/current_state")) == "idle", "locomotion: back to idle after stopping")


func test_character_attack_sync() -> void:
	# The fastest point of the right hand during Light Cut I must fall inside the hit window.
	make_enemy(Vector3(0, 0, -1.8), false, 1000.0)
	await frames(5)
	await tap(&"light_attack")
	var best_speed := 0.0
	var best_phase := -1
	var prev := player.global_transform.basis.inverse() * (_bone_world("CC_Base_R_Hand") - player.global_position)
	var weights: Array[float] = []
	for i in 40:
		await frames(1)
		var cur := player.global_transform.basis.inverse() * (_bone_world("CC_Base_R_Hand") - player.global_position)
		var spd := cur.distance_to(prev) * 60.0
		weights.append(_kvis().anim_tree.get("parameters/full/blend_amount"))
		if spd > best_speed and player.attack_runner.is_running():
			best_speed = spd
			best_phase = player.attack_runner.phase
		prev = cur
	check(weights.max() > 0.95, "attack: combo clip drives the full body during the swing")
	check(best_phase == AttackRunner.Phase.ACTIVE, "attack: fastest hand motion lands in the hit window (phase %d, %.1f m/s)" % [best_phase, best_speed])
	await seconds(0.6)
	check(_kvis().anim_tree.get("parameters/full/blend_amount") < 0.05, "attack: control returns to locomotion afterwards")


func test_jump() -> void:
	var v := _kvis()
	var y0 := player.global_position.y
	var peak := y0
	var max_foot_gap := 0.0
	await tap(&"jump")
	await frames(2)
	check(player.state == Player.State.AIRBORNE, "jump: C / A launches the player")
	for i in 60:
		await frames(1)
		peak = maxf(peak, player.global_position.y)
		if player.state == Player.State.AIRBORNE:
			var foot := minf(_bone_world("CC_Base_L_Foot").y, _bone_world("CC_Base_R_Foot").y) - player.global_position.y
			max_foot_gap = maxf(max_foot_gap, foot)
	check(peak - y0 > 0.6 and peak - y0 < 1.1, "jump: rises %.2f m" % (peak - y0))
	check(max_foot_gap < 0.3, "jump: clip lift compensated, feet stay with the body (max %.2f m above it)" % max_foot_gap)
	check(player.state == Player.State.MOVE and player.is_on_floor(), "jump: lands and returns to normal movement")
	await seconds(1.2)
	check(v.model.position.y == 0.0 and v.anim_tree.get("parameters/full/blend_amount") < 0.05, "jump: landing settles back to locomotion")


func test_sword_draw_and_sheathe() -> void:
	var v := _kvis()
	await tap(&"toggle_sword")
	await frames(2)
	check(player.state == Player.State.EQUIP, "sheathe: E starts sheathing")
	press(&"move_forward")
	await seconds(0.4)
	check(Vector2(player.velocity.x, player.velocity.z).length() > 1.5, "sheathe: player can keep walking while sheathing")
	check(v.anim_tree.get("parameters/upper_blend/blend_amount") > 0.9, "sheathe: upper-body layer plays Sword_Sheathe")
	release(&"move_forward")
	await seconds(0.8)
	check(not player.sword_drawn and player.state == Player.State.MOVE, "sheathe: katana sheathed, control restored")
	check(_katana_bone() == &"CC_Base_Hip", "sheathe: katana moved to the hip")
	await tap(&"toggle_sword")
	await seconds(0.3)
	check(_katana_bone() == &"CC_Base_Hip", "draw: katana still at the hip before the grab")
	await seconds(0.6)
	check(player.sword_drawn and _katana_bone() == &"CC_Base_R_Hand", "draw: katana back in the right hand")
	var katanas := player.find_children("*", "", true, false).filter(func(n): return n is Katana)
	check(katanas.size() == 1, "draw/sheathe: still exactly one katana")


func test_sheathed_attack_draws() -> void:
	var e := make_enemy(Vector3(0, 0, -1.8), false, 1000.0)
	await tap(&"toggle_sword")
	await seconds(1.2)
	check(not player.sword_drawn, "sheathed: precondition (katana sheathed)")
	await tap(&"light_attack")
	await frames(3)
	check(player.state == Player.State.EQUIP and attack_log.is_empty(), "sheathed: attack input draws the katana first")
	await seconds(1.3)
	check(player.sword_drawn and attack_log.has(&"light_1"), "sheathed: the attack fires once the katana is out (%s)" % [attack_log])
	check(results_against(e).size() >= 1, "sheathed: draw-attack still hits through the combat pipeline")


func test_character_reset_after_death() -> void:
	await tap(&"toggle_sword")
	await seconds(0.3)
	player.health.take_damage(1000)
	await seconds(1.5)
	var fallen: float = _kvis()._pose_root.rotation_degrees.x
	check(fallen > 60.0, "death: body falls (%.0f deg)" % fallen)
	player.revive()
	await seconds(0.4)
	check(absf(_kvis()._pose_root.rotation_degrees.x) < 2.0 and player.sword_drawn and _katana_bone() == &"CC_Base_R_Hand", "restart: pose reset and katana back in hand")
	main.death_screen.visible = false


## For each swing segment of the combo clip (A light I, B light II, C overhead), the hand's
## fastest motion during that attack must fall inside its hit window.
func test_character_attack_sync_segments() -> void:
	make_enemy(Vector3(0, 0, -1.8), false, 5000.0)
	await frames(5)
	var best := {}  # attack id -> [speed, phase]
	var prev := Vector3.INF
	await tap(&"light_attack")
	for i in 75:
		if i == 16:
			await tap(&"light_attack")  # buffered into Light Cut II
		await frames(1)
		var cur := player.global_transform.basis.inverse() * (_bone_world("CC_Base_R_Hand") - player.global_position)
		if prev != Vector3.INF and player.attack_runner.is_running():
			var id: StringName = player.attack_runner.attack.id
			var spd := cur.distance_to(prev) * 60.0
			if spd > best.get(id, [0.0, -1])[0]:
				best[id] = [spd, player.attack_runner.phase]
		prev = cur
	await seconds(0.6)
	prev = Vector3.INF
	await tap(&"heavy_attack")
	for i in 60:
		await frames(1)
		var cur := player.global_transform.basis.inverse() * (_bone_world("CC_Base_R_Hand") - player.global_position)
		if prev != Vector3.INF and player.attack_runner.is_running():
			var id: StringName = player.attack_runner.attack.id
			var spd := cur.distance_to(prev) * 60.0
			if spd > best.get(id, [0.0, -1])[0]:
				best[id] = [spd, player.attack_runner.phase]
		prev = cur
	for id in [&"light_1", &"light_2", &"heavy_1"]:
		var b: Array = best.get(id, [0.0, -1])
		check(b[1] == AttackRunner.Phase.ACTIVE, "attack sync %s: fastest hand motion in the hit window (phase %d, %.1f m/s)" % [id, b[1], b[0]])
