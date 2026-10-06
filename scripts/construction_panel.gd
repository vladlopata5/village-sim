extends PanelContainer
## UI state and buttons only; placement validation/creation belong to the model.
const Definition = preload("res://scripts/building_definition.gd")
signal definition_selected(definition: Definition)
var collapsed := false
var building_buttons: HBoxContainer
var collapse_button: Button
func setup(definitions: Array) -> void:
	name = "ConstructionPanel"
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 16
	offset_top = -110
	offset_bottom = -16
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	collapse_button = Button.new()
	collapse_button.focus_mode = Control.FOCUS_NONE
	collapse_button.pressed.connect(func(): set_collapsed(not collapsed))
	column.add_child(collapse_button)
	building_buttons = HBoxContainer.new()
	column.add_child(building_buttons)
	for definition in definitions:
		var button := Button.new()
		button.text = definition.display_name
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func(): definition_selected.emit(definition))
		building_buttons.add_child(button)
	set_collapsed(false)
func set_collapsed(value: bool) -> void:
	collapsed = value
	building_buttons.visible = not collapsed
	collapse_button.text = "Строительство — Развернуть" if collapsed else "Строительство — Свернуть"
	offset_top = -58 if collapsed else -110
	call_deferred("reset_size")
