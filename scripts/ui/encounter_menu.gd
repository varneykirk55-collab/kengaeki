class_name EncounterMenu
extends Control
## Sandbox control panel: choose an exact enemy count, spawn interval and attacker limit;
## spawn / clear / reset / heal. Works while the game is paused.

signal spawn_requested(count: int, interval: float)
signal clear_requested
signal reset_requested
signal restore_requested
signal max_attackers_changed(value: int)
signal close_requested

var count_spin: SpinBox
var interval_slider: HSlider
var attackers_spin: SpinBox
var spawn_button: Button
var clear_button: Button
var reset_button: Button
var restore_button: Button
var resume_button: Button
var _interval_label: Label
var _status: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UIStyle.make_theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.position = Vector2(-470, -290)
	panel.custom_minimum_size = Vector2(420, 0)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(UIStyle.label("ENCOUNTER", 28))
	box.add_child(UIStyle.label("Castle courtyard sandbox", 14, UIStyle.MUTED))
	box.add_child(HSeparator.new())

	count_spin = _spin(box, "Enemies to spawn", 1, 10, 3)
	var row := HBoxContainer.new()
	row.add_child(UIStyle.label("Spawn interval"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_interval_label = UIStyle.label("2.0 s", 17, UIStyle.GOLD)
	row.add_child(_interval_label)
	box.add_child(row)
	interval_slider = HSlider.new()
	interval_slider.min_value = 0.5
	interval_slider.max_value = 6.0
	interval_slider.step = 0.25
	interval_slider.value = 2.0
	interval_slider.value_changed.connect(func(v): _interval_label.text = "%.2f s" % v)
	box.add_child(interval_slider)
	attackers_spin = _spin(box, "Max simultaneous attackers", 1, 4, 2)
	attackers_spin.value_changed.connect(func(v): max_attackers_changed.emit(int(v)))
	box.add_child(HSeparator.new())

	spawn_button = _button(box, "Spawn enemies", func(): spawn_requested.emit(int(count_spin.value), interval_slider.value))
	clear_button = _button(box, "Clear enemies", func(): clear_requested.emit())
	restore_button = _button(box, "Restore health & stamina", func(): restore_requested.emit())
	reset_button = _button(box, "Reset encounter", func(): reset_requested.emit())
	box.add_child(HSeparator.new())
	resume_button = _button(box, "Resume  (Esc)", func(): close_requested.emit())
	_status = UIStyle.label("", 14, UIStyle.MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_status)


func _spin(parent: Control, text: String, lo: int, hi: int, value: int) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_child(UIStyle.label(text))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1
	s.value = value
	s.rounded = true
	row.add_child(s)
	parent.add_child(row)
	return s


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func(): AudioManager.play_ui(&"ui_click"))
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func set_status(text: String) -> void:
	if _status:
		_status.text = text


func open() -> void:
	visible = true
	spawn_button.grab_focus()
	AudioManager.play_ui(&"ui_open")


func close() -> void:
	visible = false
