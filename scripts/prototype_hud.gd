extends PanelContainer
## Presentation state only. Simulation and input bindings do not depend on collapse.
var collapsed := false
var extended_content: Control
var collapse_button: Button
func configure(content: Control, button: Button) -> void:
	extended_content = content
	collapse_button = button
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func(): set_collapsed(not collapsed))
	set_collapsed(false)
func set_collapsed(value: bool) -> void:
	collapsed = value
	extended_content.visible = not collapsed
	collapse_button.text = "Развернуть" if collapsed else "Свернуть"
	# Let the panel shrink after the hidden content's minimum size is recalculated.
	call_deferred("reset_size")
