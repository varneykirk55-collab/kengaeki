#!/usr/bin/env python3
"""Generates the initial AttackData .tres files. After generation the .tres files are the
source of truth and can be tuned in the Godot inspector; re-running overwrites them."""
import os

ROOT = os.path.join(os.path.dirname(__file__), "..", "resources", "attacks")
F = dict(  # defaults
    startup=0.16, active=0.12, recovery=0.32, cancel_point=0.06, dodge_cancel_startup=0.12,
    damage=14.0, guard_damage=15.0, stamina_cost=10.0, stagger_power=1, knockback=0.6,
    unblockable=False, unparryable=False, hyper_armor=False, invulnerable=False,
    reach=2.3, sweep_from=70.0, sweep_to=-70.0, max_targets=0, lunge_distance=0.8,
    hitstop=0.05, camera_shake=0.15, swing_sound="swing_light", is_finisher=False, is_counter=False,
)

PLAYER = {
    "light_1": dict(display_name="Light Cut I", animation="slash_rl", startup=0.14, active=0.10, recovery=0.30,
                    cancel_point=0.04, damage=14, guard_damage=15, stamina_cost=9, reach=2.4,
                    sweep_from=75, sweep_to=-75, lunge_distance=0.9, hitstop=0.045, camera_shake=0.12),
    "light_2": dict(display_name="Light Cut II", animation="slash_lr", startup=0.13, active=0.10, recovery=0.30,
                    cancel_point=0.04, damage=14, guard_damage=15, stamina_cost=9, reach=2.4,
                    sweep_from=-75, sweep_to=75, lunge_distance=0.9, hitstop=0.045, camera_shake=0.12),
    "light_3": dict(display_name="Crescent Wheel (combo finisher)", animation="spin", startup=0.2, active=0.24,
                    recovery=0.5, cancel_point=0.25, dodge_cancel_startup=0.08, damage=26, guard_damage=30,
                    stamina_cost=14, stagger_power=2, knockback=1.2, reach=2.7, sweep_from=180, sweep_to=-180,
                    lunge_distance=0.6, hyper_armor=True, hitstop=0.08, camera_shake=0.3,
                    swing_sound="swing_heavy", is_finisher=True),
    "heavy_1": dict(display_name="Overhead Cut", animation="overhead", startup=0.34, active=0.12, recovery=0.42,
                    cancel_point=0.12, dodge_cancel_startup=0.18, damage=28, guard_damage=38, stamina_cost=18,
                    stagger_power=2, knockback=1.0, reach=2.6, sweep_from=20, sweep_to=-20, lunge_distance=1.0,
                    hyper_armor=True, hitstop=0.07, camera_shake=0.25, swing_sound="swing_heavy"),
    "light_heavy": dict(display_name="Rising Cut (light > heavy)", animation="rising", startup=0.22, active=0.12,
                        recovery=0.4, cancel_point=0.1, dodge_cancel_startup=0.1, damage=24, guard_damage=34,
                        stamina_cost=16, stagger_power=2, knockback=0.8, reach=2.5, sweep_from=-50, sweep_to=50,
                        lunge_distance=0.9, hyper_armor=True, hitstop=0.07, camera_shake=0.22,
                        swing_sound="swing_heavy"),
    "heavy_light": dict(display_name="Piercing Thrust (heavy > light)", animation="thrust", startup=0.12,
                        active=0.09, recovery=0.32, cancel_point=0.05, damage=18, guard_damage=18,
                        stamina_cost=9, knockback=0.9, reach=2.9, sweep_from=12, sweep_to=-12,
                        lunge_distance=1.4, hitstop=0.05, camera_shake=0.14),
    "finisher_kesa": dict(display_name="Kesa-giri (light, light, heavy finisher)", animation="kesa",
                          startup=0.26, active=0.12, recovery=0.5, cancel_point=0.2, dodge_cancel_startup=0.1,
                          damage=42, guard_damage=60, stamina_cost=18, stagger_power=3, knockback=1.6,
                          reach=2.6, sweep_from=50, sweep_to=-50, lunge_distance=1.1, hyper_armor=True,
                          hitstop=0.1, camera_shake=0.4, swing_sound="swing_heavy", is_finisher=True),
    "counter_riposte": dict(display_name="Kaeshi-waza (parry counter)", animation="kesa", startup=0.12,
                            active=0.1, recovery=0.4, cancel_point=0.15, dodge_cancel_startup=-1, damage=60,
                            guard_damage=0, stamina_cost=0, stagger_power=3, knockback=1.4, unblockable=True,
                            unparryable=True, hyper_armor=True, invulnerable=True, reach=3.0, sweep_from=40,
                            sweep_to=-40, lunge_distance=2.2, hitstop=0.14, camera_shake=0.5,
                            swing_sound="swing_heavy", is_counter=True),
    "finishing_strike": dict(display_name="Todome (finishing strike)", animation="overhead", startup=0.18,
                             active=0.1, recovery=0.55, cancel_point=0.25, dodge_cancel_startup=-1, damage=90,
                             guard_damage=0, stamina_cost=0, stagger_power=3, knockback=1.0, unblockable=True,
                             unparryable=True, hyper_armor=True, invulnerable=True, reach=2.8, sweep_from=25,
                             sweep_to=-25, max_targets=1, lunge_distance=1.8, hitstop=0.16, camera_shake=0.55,
                             swing_sound="swing_heavy", is_finisher=True),
}

ENEMY = {
    "enemy_slash": dict(display_name="Ronin Cut", animation="slash_rl", startup=0.42, active=0.12, recovery=0.5,
                        cancel_point=0.2, dodge_cancel_startup=-1, damage=12, guard_damage=18, stamina_cost=0,
                        reach=2.3, sweep_from=70, sweep_to=-70, lunge_distance=0.8, hitstop=0.04,
                        camera_shake=0.1),
    "enemy_slash_2": dict(display_name="Ronin Return Cut", animation="slash_lr", startup=0.3, active=0.12,
                          recovery=0.55, cancel_point=0.2, dodge_cancel_startup=-1, damage=12, guard_damage=18,
                          stamina_cost=0, reach=2.3, sweep_from=-70, sweep_to=70, lunge_distance=0.7,
                          hitstop=0.04, camera_shake=0.1),
    "enemy_heavy": dict(display_name="Ronin Overhead (hyper armor)", animation="overhead", startup=0.75,
                        active=0.14, recovery=0.7, cancel_point=0.3, dodge_cancel_startup=-1, damage=24,
                        guard_damage=40, stamina_cost=0, stagger_power=2, knockback=1.0, reach=2.5,
                        sweep_from=20, sweep_to=-20, lunge_distance=1.2, hyper_armor=True, hitstop=0.06,
                        camera_shake=0.2, swing_sound="swing_heavy"),
    "enemy_thrust": dict(display_name="Ronin Thrust", animation="thrust", startup=0.5, active=0.1, recovery=0.6,
                         cancel_point=0.3, dodge_cancel_startup=-1, damage=16, guard_damage=22, stamina_cost=0,
                         knockback=0.8, reach=2.8, sweep_from=10, sweep_to=-10, lunge_distance=1.5,
                         hitstop=0.05, camera_shake=0.12),
}


def fmt(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return repr(float(v))
    return v


def write(folder, attacks):
    os.makedirs(os.path.join(ROOT, folder), exist_ok=True)
    for aid, props in attacks.items():
        d = dict(F)
        d.update(props)
        lines = ['[gd_resource type="Resource" script_class="AttackData" load_steps=2 format=3]', "",
                 '[ext_resource type="Script" path="res://scripts/combat/attack_data.gd" id="1_attack"]', "",
                 "[resource]", 'script = ExtResource("1_attack")', f'id = &"{aid}"',
                 f'display_name = "{d.pop("display_name")}"', f'animation = &"{d.pop("animation")}"']
        sound = d.pop("swing_sound")
        for k, v in d.items():
            if k in ("damage", "guard_damage", "stamina_cost", "knockback", "reach", "sweep_from", "sweep_to",
                     "lunge_distance", "startup", "active", "recovery", "cancel_point", "dodge_cancel_startup",
                     "hitstop", "camera_shake"):
                v = float(v)
            lines.append(f"{k} = {fmt(v)}")
        lines.append(f'swing_sound = &"{sound}"')
        with open(os.path.join(ROOT, folder, aid + ".tres"), "w") as f:
            f.write("\n".join(lines) + "\n")


write("player", PLAYER)
write("enemy", ENEMY)
print("ok")
