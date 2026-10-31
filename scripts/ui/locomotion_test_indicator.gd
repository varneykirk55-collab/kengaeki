extends CanvasLayer
## Temporary test-branch badge. Reads the actual playable player's live tree.
var status_label: Label
var visual: KengekiCharacterVisual

func _ready() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -250
	panel.offset_right = 250
	panel.offset_top = 12
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.025, 0.025, 0.04, 0.92)
	background.content_margin_left = 18
	background.content_margin_right = 18
	background.content_margin_top = 8
	background.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", background)
	add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	var title := Label.new()
	title.text = "ASTRA LOCOMOTION TEST"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
	box.add_child(title)
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 16)
	box.add_child(status_label)
	visual = get_parent().get_node("Player/Visual") as KengekiCharacterVisual
	_process(0.0)

func _process(_delta: float) -> void:
	if status_label == null:
		return
	status_label.text = visual.locomotion_test_state() if is_instance_valid(visual) else "NOT ACTIVE — player visual missing"
	status_label.modulate = Color(0.6, 1.0, 0.7) if is_instance_valid(visual) and visual.is_refined_locomotion_active() else Color(1.0, 0.4, 0.35)
