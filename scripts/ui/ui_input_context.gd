extends RefCounted
## Presentation-only input queries. No selection or active-tool copy.
var _ui: WeakRef
func setup(ui: Control) -> void:
	_ui = weakref(ui)
func text_editing() -> bool:
	var ui = _ui.get_ref()
	if ui == null: return false
	var focus: Control = ui.get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit
func pointer_blocked(point: Vector2) -> bool:
	var ui = _ui.get_ref()
	return ui != null and ui.pointer_blocked(point)
