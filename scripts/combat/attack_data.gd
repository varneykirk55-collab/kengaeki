class_name AttackData
extends Resource
## Data describing one sword technique. Shared by player and enemy combat.
##
## Timing: startup -> active (hit window) -> recovery. With timing_source = ANIMATION_EVENTS
## the hit window is opened/closed by animation method-track events instead
## ("hit_start" / "hit_end" / "attack_end" emitted by the character visual), with
## the data timings kept as a safety fallback.

enum TimingSource { DATA, ANIMATION_EVENTS }

@export var id: StringName = &"attack"
@export var display_name: String = "Attack"
## Animation key requested from the character visual (placeholder pose set or imported clip name).
@export var animation: StringName = &"slash_rl"
@export var timing_source: TimingSource = TimingSource.DATA

@export_group("Timing")
@export var startup: float = 0.16
@export var active: float = 0.12
@export var recovery: float = 0.32
## Seconds into recovery after which a buffered follow-up may begin.
@export var cancel_point: float = 0.06
## Seconds into startup during which a dodge may still cancel the attack (-1 = never).
@export var dodge_cancel_startup: float = 0.12

@export_group("Damage")
@export var damage: float = 14.0
## Damage dealt to the defender's guard (stamina) when blocked.
@export var guard_damage: float = 15.0
@export var stamina_cost: float = 10.0
## 0 = none, 1 = flinch, 2 = stagger, 3 = knockdown.
@export_range(0, 3) var stagger_power: int = 1
@export var knockback: float = 0.6
@export var unblockable: bool = false
@export var unparryable: bool = false
## While true the attacker is not interrupted by incoming hits (damage still applies).
@export var hyper_armor: bool = false
## Attacker cannot be damaged at all (used for cinematic counters / finishers).
@export var invulnerable: bool = false

@export_group("Hit Shape")
## Arc sweep detection: the blade sweeps from sweep_from to sweep_to (degrees, 0 = forward,
## positive = attacker's right) over the active window. Targets inside the newly swept slice
## and within reach are hit, exactly once per attack.
@export var reach: float = 2.3
@export var sweep_from: float = 70.0
@export var sweep_to: float = -70.0
@export var height_min: float = -0.2
@export var height_max: float = 2.2
## Max number of targets damaged by this swing (0 = unlimited).
@export var max_targets: int = 0

@export_group("Movement")
@export var lunge_distance: float = 0.8
## Turn toward the target during startup.
@export var track_target_during_startup: bool = true

@export_group("Feedback")
@export var hitstop: float = 0.05
@export var camera_shake: float = 0.15
@export var swing_sound: StringName = &"swing_light"
@export var is_finisher: bool = false
@export var is_counter: bool = false


func total_time() -> float:
	return startup + active + recovery
