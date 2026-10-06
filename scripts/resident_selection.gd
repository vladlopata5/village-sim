extends Node
## Unified single selection. The historical name/API keeps resident callers compatible.
## Only simulation data is stored; visual nodes are never selected entities.
const ResidentData = preload("res://scripts/resident_data.gd")
const BuildingInstance = preload("res://scripts/building_instance.gd")
signal selection_changed
var _selected_entity: RefCounted
var selected_entity: RefCounted:
	get: return _selected_entity
var selected_resident: ResidentData:
	get: return _selected_entity as ResidentData
var selected_building: BuildingInstance:
	get: return _selected_entity as BuildingInstance
func select(data: ResidentData) -> void: _select_entity(data)
func select_building(data: BuildingInstance) -> void: _select_entity(data)
func clear() -> void: _select_entity(null)
func _select_entity(data: RefCounted) -> void:
	if _selected_entity == data: return
	_selected_entity = data
	selection_changed.emit()
