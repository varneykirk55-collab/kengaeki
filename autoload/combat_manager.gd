extends Node
## Central combat rules. Every sword contact flows through resolve_hit(), which decides
## between dodge / parry / block / guard break / clean hit, applies damage, notifies both
## combatants and triggers presentation (audio, sparks, hit-stop, camera shake).

signal attack_started(attacker: Combatant, attack: AttackData)
signal hit_resolved(info: HitInfo)
signal combatant_died(combatant: Combatant)

## Defender must face the attacker within this angle to block or parry.
const GUARD_ANGLE := 80.0
## Damage multiplier against a vulnerable (parried / guard-broken) target.
const VULNERABLE_MULTIPLIER := 1.5

## Debug/test hook: when true, the player takes no damage.
var player_god_mode := false


## Controllers call this when an attack's startup begins.
func announce_attack(attacker: Combatant, attack: AttackData) -> void:
	AudioManager.play_sfx(attack.swing_sound, attacker.get_hit_point(), -2.0)
	if attacker.faction == Combatant.Faction.ENEMY and attack.hyper_armor:
		AudioManager.play_sfx(&"heavy_warn", attacker.get_hit_point(), -3.0, 0.02)
	attack_started.emit(attacker, attack)


func resolve_hit(attacker: Combatant, defender: Combatant, attack: AttackData) -> int:
	var info := HitInfo.new()
	info.attacker = attacker
	info.defender = defender
	info.attack = attack
	var dir := defender.global_position - attacker.global_position
	dir.y = 0.0
	info.direction = dir.normalized() if dir.length_squared() > 0.0001 else attacker.get_forward()
	info.point = defender.get_hit_point() - info.direction * defender.body_radius * 0.8
	var contact := attacker.get_hit_point().lerp(defender.get_hit_point(), 0.55) + Vector3.UP * 0.1

	if defender.is_dead():
		info.result = HitInfo.Result.IGNORED
	elif defender.is_invulnerable():
		info.result = HitInfo.Result.DODGED
	else:
		var facing := defender.is_facing_point(attacker.global_position, GUARD_ANGLE)
		if facing and defender.is_parrying() and not attack.unparryable and not attack.unblockable:
			info.result = HitInfo.Result.PARRIED
		elif facing and defender.is_blocking() and not attack.unblockable:
			if defender.stamina.current >= attack.guard_damage:
				info.result = HitInfo.Result.BLOCKED
			else:
				info.result = HitInfo.Result.GUARD_BROKEN
		else:
			info.result = HitInfo.Result.HIT

	var player_involved := attacker.faction == Combatant.Faction.PLAYER or defender.faction == Combatant.Faction.PLAYER
	match info.result:
		HitInfo.Result.PARRIED:
			attacker.on_parried(defender)
			defender.on_parry_success(attacker, attack)
			CombatFX.spawn_sparks(contact, -info.direction + Vector3.UP * 0.5, 40, 8.0)
			AudioManager.play_sfx(&"parry", contact, 2.0, 0.04)
			AudioManager.play_sfx(&"clash", contact, -2.0)
			if player_involved:
				CombatFX.hitstop(0.11)
				CombatFX.shake(0.35)
		HitInfo.Result.BLOCKED:
			defender.stamina.consume(attack.guard_damage)
			info.damage = defender.health.take_damage(attack.damage * defender.get_block_damage_ratio()) if _can_damage(defender) else 0.0
			defender.on_blocked_hit(info)
			attacker.on_attack_blocked(defender)
			CombatFX.spawn_sparks(contact, -info.direction + Vector3.UP * 0.4, 18, 5.0)
			AudioManager.play_sfx(&"block", contact)
			if player_involved:
				CombatFX.hitstop(0.045)
				CombatFX.shake(0.12)
		HitInfo.Result.GUARD_BROKEN:
			defender.stamina.consume(defender.stamina.current)
			info.damage = defender.health.take_damage(attack.damage * 0.5) if _can_damage(defender) else 0.0
			defender.on_guard_broken(info)
			CombatFX.spawn_sparks(contact, -info.direction + Vector3.UP, 30, 7.0)
			AudioManager.play_sfx(&"guard_break", contact)
			if player_involved:
				CombatFX.hitstop(0.09)
				CombatFX.shake(0.4)
		HitInfo.Result.HIT:
			var dmg := attack.damage
			if defender.is_vulnerable():
				dmg *= VULNERABLE_MULTIPLIER
			info.damage = defender.health.take_damage(dmg) if _can_damage(defender) else 0.0
			info.killed = defender.is_dead()
			if attack.knockback > 0.0 and not info.killed:
				defender.apply_knockback(info.direction, attack.knockback)
			defender.on_hit(info)
			CombatFX.spawn_impact(info.point, info.direction + Vector3.UP * 0.6)
			AudioManager.play_sfx(&"impact", info.point)
			if defender.faction == Combatant.Faction.PLAYER:
				AudioManager.play_sfx(&"player_hurt", info.point, -2.0)
				CombatFX.shake(0.35 + attack.camera_shake)
				CombatFX.hitstop(0.06)
			else:
				AudioManager.play_sfx(&"enemy_hurt", info.point, -3.0)
				if attacker.faction == Combatant.Faction.PLAYER:
					CombatFX.hitstop(attack.hitstop * (1.6 if info.killed else 1.0))
					CombatFX.shake(attack.camera_shake * (1.5 if info.killed else 1.0))
			if info.killed and (attack.is_finisher or attack.is_counter):
				CombatFX.slow_motion(0.3, 0.45)
		HitInfo.Result.DODGED:
			pass

	if info.result != HitInfo.Result.IGNORED:
		defender.hit_received.emit(info)
		hit_resolved.emit(info)
	return info.result


func _can_damage(defender: Combatant) -> bool:
	return not (player_god_mode and defender.faction == Combatant.Faction.PLAYER)


func notify_death(combatant: Combatant) -> void:
	AudioManager.play_sfx(&"death", combatant.get_hit_point())
	combatant_died.emit(combatant)
