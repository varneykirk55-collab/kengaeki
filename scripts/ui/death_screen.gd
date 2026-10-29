class_name DeathScreen
extends Control
## Shown when the player falls.

signal restart_requested
signal return_requested

var restart_button: Button
var return_button: Button
var _fade := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UIStyle.make_theme()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.0, 0.0, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var kanji := UIStyle.label("敗北", 72, UIStyle.VERMILION)
	kanji.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(kanji)
	var title := UIStyle.label("YOU HAVE FALLEN", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := UIStyle.label("The courtyard falls silent.", 16, UIStyle.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	restart_button = Button.new()
	restart_button.text = "Restart encounter (same enemy count)"
	restart_button.pressed.connect(func(): AudioManager.play_ui(&"ui_click"))
	restart_button.pressed.connect(func(): restart_requested.emit())
	box.add_child(restart_button)
	return_button = Button.new()
	return_button.text = "Return to arena (open encounter menu)"
	return_button.pressed.connect(func(): AudioManager.play_ui(&"ui_click"))
	return_button.pressed.connect(func(): return_requested.emit())
	box.add_child(return_button)


func open() -> void:
	visible = true
	modulate.a = 0.0
	_fade = 0.0
	restart_button.grab_focus()


func _process(delta: float) -> void:
	if visible and modulate.a < 1.0:
		_fade += delta
		modulate.a = clampf(_fade / 0.8, 0.0, 1.0)
