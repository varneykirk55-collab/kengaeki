class_name HUD
extends Control
## In-game HUD: health / stamina, enemy count, lock-on reticle, combat callouts.

var player: Player
var encounter: EncounterManager

var _health_bar: ProgressBar
var _health_trail: ProgressBar
var _stamina_bar: ProgressBar
var _enemy_label: Label
var _callout: Label
var _technique: Label
var _reticle: LockReticle
var _callout_time := 0.0
var _technique_time := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UIStyle.make_theme()

	var bars := VBoxContainer.new()
	bars.position = Vector2(32, 28)
	bars.add_theme_constant_override("separation", 6)
	add_child(bars)
	bars.add_child(UIStyle.label("KENGEKI", 14, UIStyle.MUTED))
	_health_trail = _make_bar(Color(0.95, 0.85, 0.75, 0.6), Vector2(380, 18))
	_health_bar = _make_bar(UIStyle.VERMILION, Vector2(380, 18))
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(380, 18)
	bars.add_child(stack)
	stack.add_child(_health_trail)
	var clear_bg := StyleBoxEmpty.new()
	_health_bar.add_theme_stylebox_override("background", clear_bg)
	stack.add_child(_health_bar)
	_stamina_bar = _make_bar(UIStyle.GOLD, Vector2(300, 10))
	bars.add_child(_stamina_bar)

	_enemy_label = UIStyle.label("", 18)
	_enemy_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_enemy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_enemy_label.position = Vector2(-360, 28)
	_enemy_label.size = Vector2(330, 60)
	add_child(_enemy_label)

	_callout = UIStyle.label("", 34, UIStyle.PAPER)
	_callout.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_callout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_callout.position = Vector2(-300, 150)
	_callout.size = Vector2(600, 50)
	_callout.add_theme_color_override("font_outline_color", Color.BLACK)
	_callout.add_theme_constant_override("outline_size", 6)
	add_child(_callout)

	_technique = UIStyle.label("", 16, UIStyle.MUTED)
	_technique.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_technique.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_technique.position = Vector2(-300, -90)
	_technique.size = Vector2(600, 30)
	add_child(_technique)

	var hint := UIStyle.label("WASD move · Shift sprint · LMB light · RMB/R heavy · F/Ctrl block (tap = parry) · Space dodge · C jump · E draw/sheathe · Q lock-on · Tab switch · Esc encounter menu", 13, UIStyle.MUTED)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(32, -40)
	add_child(hint)

	_reticle = LockReticle.new()
	_reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_reticle)


func _make_bar(color: Color, size: Vector2) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = size
	b.size = size
	b.show_percentage = false
	b.max_value = 100.0
	b.value = 100.0
	b.add_theme_stylebox_override("fill", UIStyle.bar_fill(color))
	return b


func bind(p: Player, e: EncounterManager) -> void:
	player = p
	encounter = e
	_reticle.player = p
	p.health.changed.connect(_on_health_changed)
	p.stamina.changed.connect(_on_stamina_changed)
	p.combat.attack_performed.connect(_on_attack_performed)
	p.combat.parry_succeeded.connect(func(_a): show_callout("PARRY — COUNTER!", UIStyle.GOLD))
	e.enemy_count_changed.connect(_on_enemy_count)
	CombatManager.hit_resolved.connect(_on_hit_resolved)
	_on_enemy_count(0, 0)


func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_trail.max_value = maximum
	_health_bar.value = current


func _on_stamina_changed(current: float, maximum: float) -> void:
	_stamina_bar.max_value = maximum
	_stamina_bar.value = current


func _on_enemy_count(alive: int, pending: int) -> void:
	var text := "Enemies: %d" % alive
	if pending > 0:
		text += "   (incoming %d)" % pending
	text += "\nMax attackers: %d" % encounter.max_active_attackers
	_enemy_label.text = text


func _on_attack_performed(attack: AttackData) -> void:
	if attack.is_finisher or attack.is_counter or attack.id != &"light_1":
		_technique.text = attack.display_name
		_technique_time = 1.2


func _on_hit_resolved(info: HitInfo) -> void:
	if info.attacker == player:
		if info.result == HitInfo.Result.GUARD_BROKEN:
			show_callout("GUARD BROKEN", UIStyle.VERMILION)
		elif info.killed and (info.attack.is_finisher or info.attack.is_counter):
			show_callout(info.attack.display_name.get_slice(" (", 0).to_upper(), UIStyle.PAPER)
	elif info.defender == player:
		if info.result == HitInfo.Result.DODGED:
			show_callout("evaded", UIStyle.MUTED, 0.5)
		elif info.result == HitInfo.Result.GUARD_BROKEN:
			show_callout("GUARD BROKEN", UIStyle.VERMILION)


func show_callout(text: String, color: Color, duration: float = 0.9) -> void:
	_callout.text = text
	_callout.add_theme_color_override("font_color", color)
	_callout_time = duration


func _process(delta: float) -> void:
	_callout_time -= delta
	_callout.modulate.a = clampf(_callout_time * 3.0, 0.0, 1.0)
	_technique_time -= delta
	_technique.modulate.a = clampf(_technique_time * 2.0, 0.0, 1.0)
	if player:
		# Damage trail lags behind the real health bar.
		_health_trail.value = move_toward(_health_trail.value, _health_bar.value, delta * 40.0) if _health_trail.value > _health_bar.value else _health_bar.value
	_reticle.queue_redraw()


class LockReticle:
	extends Control
	var player: Player

	func _draw() -> void:
		if player == null or player.lock_target == null or not is_instance_valid(player.lock_target):
			return
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var world := player.lock_target.get_hit_point() + Vector3.UP * 0.1
		if cam.is_position_behind(world):
			return
		var p := cam.unproject_position(world)
		var c := UIStyle.VERMILION
		draw_arc(p, 14.0, 0.0, TAU, 32, Color(c, 0.9), 2.0, true)
		draw_circle(p, 3.0, UIStyle.PAPER)
		for i in 4:
			var a := i * PI * 0.5 + PI * 0.25
			var d := Vector2(cos(a), sin(a))
			draw_line(p + d * 18.0, p + d * 26.0, Color(c, 0.9), 2.0)
