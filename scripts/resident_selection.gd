extends Node
## Selection is a reference to simulation data, not to a visual node.
const ResidentData = preload("res://scripts/resident_data.gd")
signal selection_changed
var selected_resident: ResidentData

func select(data: ResidentData) -> void:
	if selected_resident == data:
		return
	selected_resident = data
	selection_changed.emit()

func clear() -> void:
	select(null)
