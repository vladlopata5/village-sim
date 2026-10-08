extends Node3D
## Isolated wiring and debug presentation; the existing 2D Main is not instantiated.
const Data = preload("res://scripts/resident_data.gd")
const Building = preload("res://scripts/building_instance.gd")
const Definition = preload("res://scripts/building_definition.gd")
const BuildingType = preload("res://scripts/building_type.gd")
const Coordinates = preload("res://scripts/prototypes/plane_coordinates.gd")
var resident = Data.new("prototype_resident", "Тестовый житель", 30)
# Local dimensions in prototype units; this does not replace the main HOME definition.
var building = Building.new(&"prototype_building", Definition.new(&"prototype_home", BuildingType.Type.HOME, "Тестовый дом", Vector2(4, 3)), Vector2(3, 1))
@onready var selection = $Selection
@onready var control = $Control
@onready var movement = $Movement
@onready var input_controller = $Input
@onready var resident_view = $Resident
@onready var building_view = $Building
func _ready() -> void:
	resident_view.bind(resident)
	building_view.bind(building)
	building_view.position = Coordinates.to_world(building.position)
	movement.body = resident_view
	control.resident = resident
	control.selection = selection
	control.movement_requested.connect(_move_requested)
	control.stop_requested.connect(movement.stop)
	movement.arrived.connect(control.arrived)
	input_controller.camera = $Camera3D
	input_controller.ground = $Ground
	input_controller.selection = selection
	input_controller.control = control
	selection.selection_changed.connect(_selection_changed)
	_selection_changed()
func _move_requested(destination: Vector2) -> void:
	movement.set_target(Coordinates.to_world(destination))
func _selection_changed() -> void:
	resident_view.show_selection(selection.selected_resident == resident)
	building_view.show_selection(selection.selected_building == building)
	_refresh_debug()
func _process(_delta: float) -> void:
	_refresh_debug()
func _refresh_debug() -> void:
	var description := "Ничего не выбрано"
	if selection.selected_resident != null:
		description = "Resident: %s\nWorld: %s\n%s" % [resident.resident_name, resident_view.global_position, "Moving" if movement.is_moving() else "Idle"]
		if movement.is_moving(): description += "\nTarget: %s" % movement.target_position()
	elif selection.selected_building != null:
		description = "Building: %s\nWorld: %s" % [building.display_name, building_view.global_position]
	$HUD/Panel/Column/Selected.text = description
