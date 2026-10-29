class_name Combatant
extends CharacterBody3D
## Shared base for every katana wielder (player and enemies).
##
## Gameplay logic lives here and in the controller subclasses; everything visual is
## delegated to the CharacterVisual child, which can be the placeholder humanoid or an
## imported (Hunyuan) model without any change to combat code.

signal died(combatant: Combatant)
signal hit_received(info: HitInfo)

enum Faction { PLAYER, ENEMY }

@export var faction: Faction = Faction.ENEMY
@export var display_name: String = "Combatant"
## Horizontal radius used for hit detection and spacing.
@export var body_radius: float = 0.4
@export var body_height: float = 1.8
## Multiplier on knockback received (lower = holds ground better).
@export var knockback_resistance: float = 1.0
## Fraction of an attack's damage that still lands through a successful block.
@export var block_damage_ratio: float = 0.1

@onready var health: HealthComponent = $Health
@onready var stamina: StaminaComponent = $Stamina
@onready var weapon: WeaponComponent = $Weapon
@onready var attack_runner: AttackRunner = $AttackRunner
@onready var visual: CharacterVisual = $Visual

var hurtbox: Area3D
var knockback_velocity := Vector3.ZERO


func _ready() -> void:
	add_to_group(&"combatants")
	_build_hurtbox()
	if visual:
		visual.setup(self)
		weapon.katana = visual.get_katana()
		visual.animation_event.connect(attack_runner.on_animation_event)
	health.died.connect(_on_health_depleted)


func _build_hurtbox() -> void:
	hurtbox = Area3D.new()
	hurtbox.name = "Hurtbox"
	hurtbox.collision_layer = 1 << 3
	hurtbox.collision_mask = 0
	hurtbox.monitoring = false
	hurtbox.set_meta(&"combatant", self)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = body_radius
	capsule.height = body_height
	shape.shape = capsule
	shape.position.y = body_height * 0.5
	hurtbox.add_child(shape)
	add_child(hurtbox)


# --- State queries used by CombatManager -------------------------------------------

func is_dead() -> bool:
	return health == null or health.is_dead()


func is_invulnerable() -> bool:
	return attack_runner.is_running() and attack_runner.attack.invulnerable


func is_parrying() -> bool:
	return false


func is_blocking() -> bool:
	return false


## True while the combatant can be finished off (parried / guard broken / knocked down).
func is_vulnerable() -> bool:
	return false


func get_block_damage_ratio() -> float:
	return block_damage_ratio


func has_hyper_armor() -> bool:
	return attack_runner.is_running() and attack_runner.attack.hyper_armor


# --- Helpers ---------------------------------------------------------------------

func get_forward() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD


func get_hit_point() -> Vector3:
	return global_position + Vector3.UP * (body_height * 0.65)


func is_facing_point(point: Vector3, max_angle_deg: float) -> bool:
	var to := point - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return true
	return rad_to_deg(get_forward().angle_to(to.normalized())) <= max_angle_deg


## Rotates toward a world direction. weight = 1 snaps instantly.
func face_direction(direction: Vector3, weight: float = 1.0) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(weight, 0.0, 1.0))


func face_point(point: Vector3, weight: float = 1.0) -> void:
	face_direction(point - global_position, weight)


func apply_knockback(direction: Vector3, strength: float) -> void:
	direction.y = 0.0
	knockback_velocity = direction.normalized() * strength * 4.0 * knockback_resistance


func _decay_knockback(delta: float) -> Vector3:
	var kb := knockback_velocity
	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, 14.0 * delta)
	return kb


# --- Reactions (overridden by controllers) ------------------------------------------

## Called by CombatManager after damage for a clean hit was applied.
func on_hit(_info: HitInfo) -> void:
	pass


func on_blocked_hit(_info: HitInfo) -> void:
	pass


func on_guard_broken(_info: HitInfo) -> void:
	pass


## This combatant's attack was parried by `by`.
func on_parried(_by: Combatant) -> void:
	pass


## This combatant parried `attacker`.
func on_parry_success(_attacker: Combatant, _attack: AttackData) -> void:
	pass


## This combatant's attack was blocked by `by`.
func on_attack_blocked(_by: Combatant) -> void:
	pass


func _on_health_depleted() -> void:
	attack_runner.cancel()
	died.emit(self)
	CombatManager.notify_death(self)
