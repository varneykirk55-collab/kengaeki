class_name CharacterVisual
extends Node3D
## Interface between gameplay and a character's look.
##
## Gameplay never touches meshes, bones or animation clips directly; it only calls the
## methods below. Implementations:
##   * PlaceholderHumanoid  - procedural primitive body with pose-based animation (current).
##   * ImportedHumanoidVisual - wraps an imported rigged model (Hunyuan) + AnimationPlayer.
##
## Attack animation timing is read from the owner's AttackRunner every frame, so the
## visual always matches the real hit window. Imported clips can instead drive timing by
## calling emit_animation_event("hit_start" / "hit_end" / "attack_end") from method tracks.

signal animation_event(event_name: StringName)
signal footstep

var combatant: Combatant


func setup(owner_combatant: Combatant) -> void:
	combatant = owner_combatant


## Returns the katana attached to this visual (may be null).
func get_katana() -> Katana:
	return null


## Locomotion input: velocity in the character's local space and max speed for blending.
func set_locomotion(_local_velocity: Vector3, _max_speed: float) -> void:
	pass


func set_guard(_blocking: bool) -> void:
	pass


func play_dodge(_local_direction: Vector3, _duration: float) -> void:
	pass


## power: 1 flinch, 2 stagger, 3 knockdown.
func play_hit(_power: int, _local_direction: Vector3) -> void:
	pass


func play_block_impact() -> void:
	pass


func play_parried(_duration: float) -> void:
	pass


func play_death() -> void:
	pass


func reset_pose() -> void:
	pass


## Method-track target for imported animations.
func emit_animation_event(event_name: StringName) -> void:
	if event_name == &"footstep":
		footstep.emit()
	else:
		animation_event.emit(event_name)
