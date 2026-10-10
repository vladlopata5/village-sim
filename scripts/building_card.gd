extends PanelContainer
## Reads the selected instance. Only presentation is updated; there are no management rules.
const Selection = preload("res://scripts/resident_selection.gd")
const Instance = preload("res://scripts/building_instance.gd")
const Types = preload("res://scripts/building_type.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
const Balance = preload("res://scripts/balance_config.gd")
const FOOD = ResourceType.Type.FOOD
var _control: RefCounted
@onready var housing_section: VBoxContainer = $Margin/Column/Scroll/Content/Housing
@onready var housing_count: Label = $Margin/Column/Scroll/Content/Housing/Count
@onready var housing_residents: Label = $Margin/Column/Scroll/Content/Housing/Residents
var _selection: Selection
var _building: Instance
var _last_snapshot: Array = []
signal settlement_management_requested
var management_button: Button
@onready var name_label: Label = $Margin/Column/Scroll/Content/Name
@onready var id_label: Label = $Margin/Column/Scroll/Content/ID
@onready var state_label: Label = $Margin/Column/Scroll/Content/State
@onready var type_label: Label = $Margin/Column/Scroll/Content/Type
@onready var resources_label: Label = $Margin/Column/Scroll/Content/Resources
@onready var production_section: VBoxContainer = $Margin/Column/Scroll/Content/Production
@onready var production_label: Label = $Margin/Column/Scroll/Content/Production/Progress
@onready var construction_section: VBoxContainer = $Margin/Column/Scroll/Content/Construction
@onready var construction_materials: Label = $Margin/Column/Scroll/Content/Construction/Materials
@onready var construction_work: Label = $Margin/Column/Scroll/Content/Construction/Work
@onready var construction_builders: Label = $Margin/Column/Scroll/Content/Construction/Builders
@onready var close_button: Button = $Margin/Column/Close
func _ready() -> void:
	hide()
	management_button = Button.new()
	management_button.text = "Управление поселением"
	$Margin/Column/Scroll/Content.add_child(management_button)
	$Margin/Column/Scroll/Content.move_child(management_button,4)
	management_button.pressed.connect(func(): settlement_management_requested.emit())
	close_button.pressed.connect(_close)
func bind_selection(selection: Selection) -> void:
	_selection = selection
	_selection.selection_changed.connect(_on_selection_changed)
	_on_selection_changed()
func _on_selection_changed() -> void:
	if _building != null:
		_building.construction_changed.disconnect(_refresh)
	if _building != null and _building.resources != null:
		_building.resources.changed.disconnect(_on_resources_changed)
	_building = _selection.selected_building
	_last_snapshot = []
	if _building != null: _building.construction_changed.connect(_refresh)
	if _building != null and _building.resources != null:
		_building.resources.changed.connect(_on_resources_changed)
	$Margin/Column/Scroll.scroll_vertical = 0
	_refresh()
func _on_resources_changed(_resource: ResourceType.Type, _amount: int) -> void: _refresh()
func _process(_delta: float) -> void:
	# Same live-data pattern as ResidentCard; no node/list rebuilding per frame.
	if visible: _refresh()
func _refresh() -> void:
	if management_button != null: management_button.visible = _building != null and _building.is_built() and _building.type == Types.Type.TOWN_CENTER
	if _building == null:
		hide()
		return
	var amount: int = _building.resources.get_amount(FOOD) if _building.resources != null else 0
	var capacity: int = _building.resources.get_capacity(FOOD) if _building.resources != null else 0
	var resource_lines := PackedStringArray()
	if _building.resources != null:
		for resource in ResourceType.Type.values():
			var limit: int = _building.resources.get_capacity(resource)
			if limit > 0: resource_lines.append("%s: %d / %d" % [ResourceType.display_name(resource), _building.resources.get_amount(resource), limit])
	var workers_snapshot: Array = _control.get_workplace_workers(_building.id).map(func(worker): return worker.id) if _control != null else []
	var snapshot: Array = [workers_snapshot,_building.display_name, _building.id, _building.state, _building.type, amount, capacity, _building.production_progress, _building.construction_delivered, _building.construction_progress, _building.active_builder_ids, _building.definition.construction_requirements.duplicate(), _building.definition.construction_work_required, _building.definition.max_builders, resource_lines]
	if snapshot == _last_snapshot: return
	_last_snapshot = snapshot
	name_label.text = _building.display_name
	id_label.text = "ID: %s" % _building.id
	state_label.text = "Состояние: " + ("Построено" if _building.is_built() else "Строится")
	type_label.text = "Тип: " + _type_text(_building.type)
	if _control != null and _building.is_built() and _building.type in [Types.Type.LUMBERJACK_HUT,Types.Type.SAWMILL]:
		var workers: Array = _control.get_workplace_workers(_building.id)
		resource_lines.append("Работники: %d / %d" % [workers.size(),_building.definition.worker_capacity])
		for worker in workers: resource_lines.append(worker.resident_name + " — " + preload("res://scripts/resident_profession.gd").display_name(worker.profession))
	resources_label.text = "\n".join(resource_lines) if not resource_lines.is_empty() else "Ресурсов нет"
	production_section.visible = _building.is_built() and (_building.type == Types.Type.GATHERER_HUT or _building.definition.production_recipe != null)
	production_label.text = "FOOD • прогресс: %d / %d рабочих минут" % [_building.production_progress, Balance.GATHERER_WORK_MINUTES_PER_FOOD]
	if _building.definition.production_recipe != null:
		production_label.text = "Производство: %d / %d рабочих минут" % [_building.production_progress,_building.definition.production_recipe.work_required]
	construction_section.visible = not _building.is_built()
	_refresh_housing()
	var materials := PackedStringArray()
	for resource in _building.definition.construction_requirements:
		materials.append("%s: %d / %d" % [ResourceType.display_name(resource), _building.get_delivered_amount(resource), _building.get_required_amount(resource)])
	construction_materials.text = "Материалы:\n" + ("\n".join(materials) if not materials.is_empty() else "Не требуются")
	construction_work.text = "Прогресс: %d / %d мин\n%.0f%%" % [_building.construction_progress, _building.definition.construction_work_required, _building.get_construction_progress_ratio() * 100.0]
	construction_builders.text = "Строители: %d / %d" % [_building.active_builder_ids.size(), _building.definition.max_builders]
	show()
func _type_text(category: int) -> String:
	match category:
		Types.Type.FOOD: return "Кухня"
		Types.Type.STORAGE: return "Склад"
		Types.Type.GATHERER_HUT: return "Хижина собирателя"
		Types.Type.LUMBERJACK_HUT: return "Хижина лесоруба"
		Types.Type.SAWMILL: return "Лесопилка"
		Types.Type.HOME: return "Дом"
		Types.Type.TOWN_CENTER: return "Городской центр"
		_: return "Здание"
func _close() -> void:
	if _selection != null and _selection.selected_building != null: _selection.clear()


func bind_control(control: RefCounted) -> void:
	if _control != null and _control.home_changed.is_connected(_on_home_changed): _control.home_changed.disconnect(_on_home_changed)
	_control = control
	_control.home_changed.connect(_on_home_changed)
	_refresh_housing()

func _on_home_changed(_resident_id: String, previous: StringName, current: StringName) -> void:
	if _building != null and _building.id in [previous, current]: _refresh_housing()

func _refresh_housing() -> void:
	housing_section.visible = _control != null and _control.is_housing_target(_building)
	if not housing_section.visible: return
	var occupants: Array = _control.get_home_occupants(_building.id)
	housing_count.text = "Жильцы: %d / %d" % [occupants.size(), _building.definition.housing_capacity]
	var names := PackedStringArray()
	for resident in occupants: names.append("• " + resident.resident_name)
	housing_residents.text = "\n".join(names) if not names.is_empty() else "Нет жильцов"
