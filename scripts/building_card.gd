extends PanelContainer
## Reads the selected instance. Only presentation is updated; there are no management rules.
const Selection = preload("res://scripts/resident_selection.gd")
const Instance = preload("res://scripts/building_instance.gd")
const Types = preload("res://scripts/building_type.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
const Balance = preload("res://scripts/balance_config.gd")
const FOOD = ResourceType.Type.FOOD
var _selection: Selection
var _building: Instance
var _last_snapshot: Array = []
@onready var name_label: Label = $Margin/Column/Scroll/Content/Name
@onready var id_label: Label = $Margin/Column/Scroll/Content/ID
@onready var state_label: Label = $Margin/Column/Scroll/Content/State
@onready var type_label: Label = $Margin/Column/Scroll/Content/Type
@onready var resources_label: Label = $Margin/Column/Scroll/Content/Resources
@onready var production_section: VBoxContainer = $Margin/Column/Scroll/Content/Production
@onready var production_label: Label = $Margin/Column/Scroll/Content/Production/Progress
@onready var construction_section: VBoxContainer = $Margin/Column/Scroll/Content/Construction
@onready var close_button: Button = $Margin/Column/Close
func _ready() -> void:
	hide()
	close_button.pressed.connect(_close)
func bind_selection(selection: Selection) -> void:
	_selection = selection
	_selection.selection_changed.connect(_on_selection_changed)
	_on_selection_changed()
func _on_selection_changed() -> void:
	if _building != null and _building.resources != null:
		_building.resources.changed.disconnect(_on_resources_changed)
	_building = _selection.selected_building
	_last_snapshot = []
	if _building != null and _building.resources != null:
		_building.resources.changed.connect(_on_resources_changed)
	$Margin/Column/Scroll.scroll_vertical = 0
	_refresh()
func _on_resources_changed(_resource: ResourceType.Type, _amount: int) -> void: _refresh()
func _process(_delta: float) -> void:
	# Same live-data pattern as ResidentCard; no node/list rebuilding per frame.
	if visible: _refresh()
func _refresh() -> void:
	if _building == null:
		hide()
		return
	var amount: int = _building.resources.get_amount(FOOD) if _building.resources != null else 0
	var capacity: int = _building.resources.get_capacity(FOOD) if _building.resources != null else 0
	var snapshot: Array = [_building.display_name, _building.id, _building.state, _building.type, amount, capacity, _building.production_progress]
	if snapshot == _last_snapshot: return
	_last_snapshot = snapshot
	name_label.text = _building.display_name
	id_label.text = "ID: %s" % _building.id
	state_label.text = "Состояние: " + ("Построено" if _building.is_built() else "Строится")
	type_label.text = "Тип: " + _type_text(_building.type)
	resources_label.text = "FOOD: %d / %d" % [amount, capacity] if capacity > 0 else "Ресурсов нет"
	production_section.visible = _building.is_built() and _building.type == Types.Type.GATHERER_HUT
	production_label.text = "FOOD • прогресс: %d / %d рабочих минут" % [_building.production_progress, Balance.GATHERER_WORK_MINUTES_PER_FOOD]
	construction_section.visible = not _building.is_built()
	show()
func _type_text(category: int) -> String:
	match category:
		Types.Type.FOOD: return "Кухня"
		Types.Type.STORAGE: return "Склад"
		Types.Type.GATHERER_HUT: return "Хижина собирателя"
		Types.Type.HOME: return "Дом"
		_: return "Здание"
func _close() -> void:
	if _selection != null and _selection.selected_building != null: _selection.clear()
