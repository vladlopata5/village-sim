extends PanelContainer
# Presentation counters for focused UI diagnostics; never used by simulation.
var refresh_count := 0
@export var close_path: NodePath
var clock: Node
var _refresh_elapsed := 0.0
func _widget(id: String) -> Node:
	return get_node(close_path) if id == "Close" else get_node("%" + id)

## Presents the selected instance; quota commands use PlayerControl and container rules.
const Selection = preload("res://scripts/resident_selection.gd")
const Instance = preload("res://scripts/building_instance.gd")
const Types = preload("res://scripts/building_type.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
const Categories = preload("res://scripts/resource_category.gd")
const Balance = preload("res://scripts/balance_config.gd")
const RecipeView = preload("res://scripts/ui/production_recipe_view.gd")
var farm_stock_section: VBoxContainer
var farm_stock_editor: LineEdit
var farm_stock_feedback: Label
var _stock_dirty:=false
var _stock_id: StringName
var consumable_rows: Dictionary = {}
var consumable_section: VBoxContainer
var recipe_views: Dictionary = {}
var _recipe_ids: Array = []
const FOOD = ResourceType.Type.FOOD
var _control: RefCounted
@onready var housing_section: VBoxContainer = _widget("Housing")
@onready var housing_count: Label = _widget("HousingCount")
var _selection: Selection
var _building: Instance
var _last_snapshot: Array = []
signal settlement_management_requested
signal staffing_requested(profession: int)
signal household_requested(household_id: StringName)
var household_views: Dictionary = {} # Stable household ID -> local presentation only.
var housing_summary: Label
var _active_tab: StringName = &"info"
signal work_area_requested(building_id: StringName)
const BuildingArea = preload("res://scripts/building_work_area.gd")
var work_area_section: VBoxContainer
var work_area_label: Label
var assign_area_button: Button
var reset_area_button: Button
var staffing_buttons: Dictionary = {}
var structural_progress: ProgressBar
var management_button: Button
var animal_summary: Label
var storage_rows: Dictionary = {}
var _quota_dirty: Dictionary = {}
@onready var name_label: Label = _widget("Name")
@onready var resources_label: Label = _widget("Resources")
@onready var production_section: VBoxContainer = _widget("Production")
@onready var production_label: Label = _widget("Progress")
@onready var construction_section: VBoxContainer = _widget("Construction")
@onready var construction_materials: Label = _widget("Materials")
@onready var construction_work: Label = _widget("Work")
@onready var construction_builders: Label = _widget("Builders")
@onready var close_button: Button = _widget("Close")
func _ready() -> void:
	hide()
	structural_progress = ProgressBar.new()
	construction_section.add_child(structural_progress)
	get_node("%Demolish").pressed.connect(_change_construction_direction)
	housing_summary = Label.new()
	housing_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	housing_section.add_child(housing_summary)
	_setup_storage_rows()
	_setup_stock_target()
	consumable_section=VBoxContainer.new()
	_info_body().add_child(consumable_section)
	_setup_work_area()
	animal_summary=Label.new()
	animal_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_info_body().add_child(animal_summary)
	_info_body().move_child(animal_summary,1)
	animal_summary.hide()
	_info_body().move_child(get_node("%Demolish"),0)
	management_button = Button.new()
	management_button.text = "Управление поселением"
	_info_body().add_child(management_button)
	_info_body().move_child(management_button,get_node("%Demolish").get_index())
	management_button.pressed.connect(func(): settlement_management_requested.emit())
func bind_selection(selection: Selection) -> void:
	if _selection != null and _selection.selection_changed.is_connected(_on_selection_changed): _selection.selection_changed.disconnect(_on_selection_changed)
	_selection = selection
	_selection.selection_changed.connect(_on_selection_changed)
	_on_selection_changed()
func _on_selection_changed() -> void:
	_confirm_upgrade_id=&""
	_disconnect_building()
	_clear_recipe_views()
	_quota_dirty.clear()
	for row in storage_rows.values():
		row.editor.release_focus()
		row.expand.set_pressed_no_signal(false)
		row.contents.hide()
		row.expand.text = "▸ " + Categories.display_name(storage_rows.find_key(row))
	get_node("%StorageError").text = ""
	for row in consumable_rows.values():row.box.free()
	consumable_rows.clear()
	_building = _selection.selected_building
	_clear_household_views()
	_presented_tabs.clear()
	_last_snapshot = []
	if _building != null:
		_building.construction_changed.connect(_refresh)
		_building.production_changed.connect(_refresh_recipes)
	if _building != null and _building.resources != null:
		_building.resources.changed.connect(_on_resources_changed)
		_building.resources.reservations_changed.connect(_on_reservations_changed)
		_building.resources.quotas_changed.connect(_refresh)
	_widget("Scroll").scroll_vertical = 0
	_refresh()
func _on_resources_changed(_resource: ResourceType.Type, _amount: int) -> void: _refresh()
func _on_reservations_changed(_resource: ResourceType.Type) -> void: _refresh()
func _process(delta: float) -> void:
	# Same live-data pattern as ResidentCard; no node/list rebuilding per frame.
	if not is_visible_in_tree(): return
	_refresh_elapsed += delta
	if _refresh_elapsed < 0.25: return
	_refresh_elapsed = 0.0
	_refresh()
func _refresh() -> void:
	refresh_count += 1
	_refresh_recipes()
	_refresh_consumables()
	_refresh_work_area()
	_refresh_construction_command()
	_refresh_upgrade()
	if management_button != null: management_button.visible = _building != null and _building.is_built() and _building.type == Types.Type.TOWN_CENTER
	if _building == null:
		return
	var amount: int = _building.resources.get_amount(FOOD) if _building.resources != null else 0
	var capacity: int = _building.resources.get_capacity(FOOD) if _building.resources != null else 0
	var resource_lines := PackedStringArray()
	if _building.resources != null:
		for resource in ResourceType.Type.values():
			var limit: int = _building.resources.get_capacity(resource)
			if limit > 0: resource_lines.append("%s: %d / %d" % [ResourceType.display_name(resource), _building.resources.get_amount(resource), limit])
	if _building.type==Types.Type.WELL:resource_lines.append("Источник воды • запас неограничен • набор 10 минут")
	var workers_snapshot: Array = _control.get_workplace_workers(_building.id).map(func(worker): return worker.id) if _control != null else []
	var porter_snapshot: Array = _control.get_porters(_building.id).map(func(worker): return worker.id) if _control != null else []
	var snapshot: Array = [workers_snapshot,porter_snapshot,_building.definition.porter_capacity,_building.definition.worker_capacity,_building.definition.housing_capacity,_building.level,_building.display_name, _building.id, _building.state, _building.work_direction, _building.work_paused, _building.type, amount, capacity, _building.production_progress, _building.construction_delivered, _building.construction_progress, _building.active_builder_ids, _building.construction_definition().construction_requirements.duplicate(), _building.construction_definition().construction_work_required, _building.construction_definition().max_builders, resource_lines]
	_refresh_details(resource_lines)
	var tabs := available_tabs()
	if tabs != _presented_tabs:
		_presented_tabs = tabs
		presentation_changed.emit()
	if snapshot == _last_snapshot: return
	_last_snapshot = snapshot
	name_label.text = _building.display_name + (" II" if _building.level==2 else " I" if not _building.definition.upgrades.is_empty() else "")
	if _control != null and _building.is_built() and _building.definition.worker_profession != preload("res://scripts/resident_profession.gd").Type.NONE:
		var workers: Array = _control.get_workplace_workers(_building.id)
		resource_lines.append("Работники производства: %d / %d" % [workers.size(),_building.definition.worker_capacity])
	if _control != null and _building.is_built() and _building.definition.porter_capacity > 0:
		resource_lines.append("Носильщики: %d / %d" % [porter_snapshot.size(),_building.definition.porter_capacity])
	production_section.visible = _building.is_built() and _building.type == Types.Type.GATHERER_HUT
	production_label.text = "По 1 грибу за рейс • сбор %d мин • разгрузка %d мин" % [Balance.RESOURCE_LOADING_MINUTES,Balance.RESOURCE_UNLOADING_MINUTES]
	construction_section.visible = not _building.is_built()
	var materials := PackedStringArray()
	var stage: RefCounted=_building.current_construction_stage()
	var requirements: Dictionary=stage.materials if stage!=null else {}
	for resource in requirements:
		materials.append("%s: %d / %d" % [ResourceType.display_name(resource), _building.stage_delivered_amount(resource), requirements[resource]])
	construction_materials.text = "Материалы:\n" + ("\n".join(materials) if not materials.is_empty() else "Не требуются")
	if _building.previously_built and not _building.is_upgrading(): construction_materials.text = "Материалы остаются в конструкции.\nДля восстановления новые материалы не нужны."
	construction_work.text = _building.work_status() + ": %d / %d мин\n%.0f%%" % [_building.construction_progress, _building.construction_definition().construction_work_required, _building.get_construction_progress_ratio() * 100.0]
	if (_building.is_upgrading() or not _building.previously_built) and stage!=null:
		construction_work.text="%s: этап %d/%d — %s\nРаботы этапа: %d / %d мин\nВсего: %d / %d мин (%.0f%%)" % [_building.work_status(),_building.construction_stage_index()+1,_building.construction_definition().construction_stages.size(),stage.display_name,_building.stage_work_progress(),stage.work_minutes,_building.construction_progress,_building.construction_definition().construction_work_required,_building.get_construction_progress_ratio()*100.0]
	structural_progress.value = _building.get_construction_progress_ratio()*100.0
	construction_work.text += "\nОсталось работы: %d мин" % _building.work_remaining()
	if _building.work_paused: construction_work.text += "\nОжидание завершения действий внутри"
	construction_builders.text = "Строители: %d / %d" % [_building.active_builder_ids.size(), _building.construction_definition().max_builders]
func bind_control(control: RefCounted) -> void:
	if _control != null and _control.household_changed.is_connected(_on_household_changed): _control.household_changed.disconnect(_on_household_changed)
	_disconnect_work_area()
	_control = control
	_control.household_changed.connect(_on_household_changed)
	_control.building_work_area_changed.connect(_building_area_changed)
	if _control.work_areas != null:
		_control.work_areas.changed.connect(_refresh_work_area)
		_control.work_areas.presentation_changed.connect(_refresh_work_area)
	_refresh_work_area()
	_refresh_housing()
	_clear_recipe_views()
	_refresh_recipes()

func _setup_work_area() -> void:
	work_area_section = VBoxContainer.new()
	_info_body().add_child(work_area_section)
	_info_body().move_child(work_area_section,0)
	work_area_label = Label.new()
	work_area_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	work_area_section.add_child(work_area_label)
	assign_area_button = Button.new()
	assign_area_button.text = "Назначить область"
	assign_area_button.pressed.connect(func():
		if _building != null: work_area_requested.emit(_building.id))
	work_area_section.add_child(assign_area_button)
	reset_area_button = Button.new()
	reset_area_button.text = "Вернуть стандартную"
	reset_area_button.pressed.connect(func():
		if _building != null and _control != null and _control.get_building(_building.id)==_building: _control.reset_building_work_area(_building.id))
	work_area_section.add_child(reset_area_button)
	work_area_section.hide()
func _building_area_changed(id: StringName) -> void:
	if _building != null and _building.id==id: _refresh_work_area()
func _refresh_work_area() -> void:
	if work_area_section == null: return
	work_area_section.visible = _control != null and BuildingArea.supports(_building) and _control.get_building(_building.id)==_building
	if not work_area_section.visible: return
	var area: RefCounted = _control.work_areas.get_area(_building.work_area_override_id) if _control.work_areas != null else null
	reset_area_button.visible = area != null
	work_area_label.text = "Рабочая область: Пользовательская\n%s\nID: %s" % [area.display_name,area.id] if area != null else "Рабочая область: Стандартная\nРадиус: %.1f мировых единиц" % _building.definition.work_radius
func _disconnect_work_area() -> void:
	if _control == null: return
	if _control.building_work_area_changed.is_connected(_building_area_changed): _control.building_work_area_changed.disconnect(_building_area_changed)
	if _control.work_areas != null:
		for source in [_control.work_areas.changed,_control.work_areas.presentation_changed]:
			if source.is_connected(_refresh_work_area): source.disconnect(_refresh_work_area)

func _on_household_changed(_resident_id: String, previous: StringName, current: StringName) -> void:
	if _building != null and (_building.get_household(previous)!=null or _building.get_household(current)!=null):
		_refresh_housing()

func _clear_household_views() -> void:
	for view in household_views.values():
		view.body.get_parent().remove_child(view.body)
		view.body.queue_free()
	household_views.clear()
	staffing_buttons.erase(&"home")
func _refresh_housing() -> void:
	housing_section.visible = _control != null and _control.is_housing_target(_building)
	var units: Array = _building.households if housing_section.visible else []
	var ids: Array = units.map(func(unit):return unit.id)
	for id in household_views.keys():
		if id in ids and household_views[id].unit==_building.get_household(id): continue
		var body: VBoxContainer=household_views[id].body
		body.get_parent().remove_child(body);body.queue_free();household_views.erase(id)
	staffing_buttons.erase(&"home")
	if not housing_section.visible: return
	var occupants: Array = _control.get_home_occupants(_building.id)
	housing_count.text = "Жильцы: %d / %d" % [occupants.size(), _building.definition.housing_capacity]
	housing_summary.text = "Уровень: %s\nХозяйств: %d\nОбщая вместимость: %d" % ["II" if _building.level==2 else "I",units.size(),units.reduce(func(total,unit):return total+unit.capacity,0)]
	for unit in units:
		if not household_views.has(unit.id):
			var body:=VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			get_node("%Content").add_child(body)
			var title:=Label.new();title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(title)
			var places:=VBoxContainer.new();body.add_child(places)
			var button:=Button.new();button.text="Поселить жителя";button.focus_mode=Control.FOCUS_NONE;body.add_child(button)
			button.pressed.connect(_request_household.bind(unit.id,weakref(unit),weakref(body)))
			household_views[unit.id]={"body":body,"title":title,"places":places,"button":button,"unit":unit,"snapshot":[]}
		var view: Dictionary=household_views[unit.id]
		view.body.visible=_active_tab==unit.id
		var residents: Array=occupants.filter(func(person):return person.household_id==unit.id)
		view.title.text="Хозяйство №%d — %d/%d" % [unit.local_index,residents.size(),unit.capacity]
		view.button.disabled=_building.removal_started
		if units.size()==1:staffing_buttons[&"home"]=view.button # Compatibility handle; actual widget is on the household tab.
		var snapshot: Array=residents.map(func(person):return [person.id,person.resident_name])
		if snapshot==view.snapshot and view.places.get_child_count()==unit.capacity:continue
		view.snapshot=snapshot
		for child in view.places.get_children():view.places.remove_child(child);child.queue_free()
		for index in unit.capacity:
			var row:=HBoxContainer.new();view.places.add_child(row)
			if index>=residents.size():
				var empty:=Label.new();empty.text="%d. Свободно" % [index+1];row.add_child(empty);continue
			var person: RefCounted=residents[index]
			var name_button:=Button.new();name_button.text=person.resident_name;name_button.tooltip_text=person.resident_name
			name_button.clip_text=true;name_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;name_button.focus_mode=Control.FOCUS_NONE
			name_button.pressed.connect(_select_person.bind(person.id));row.add_child(name_button)
			var clear:=Button.new();clear.text="Выселить";clear.focus_mode=Control.FOCUS_NONE;row.add_child(clear)
			clear.pressed.connect(_clear_household_person.bind(person.id,unit.id,weakref(person),weakref(row)))
func _request_household(id: StringName, identity: WeakRef, body: WeakRef) -> void:
	if _building==null or not household_views.has(id):return
	if _control.get_household(id)!=identity.get_ref() or household_views[id].body!=body.get_ref():return
	if _control.get_household_home(id)!=_building or not _control.is_housing_target(_building) or _building.removal_started:return
	household_requested.emit(id)
func _clear_household_person(id: String, household_id: StringName, identity: WeakRef, row: WeakRef) -> void:
	var person: RefCounted=_control.get_resident(id)
	var widget: Node=row.get_ref()
	if person==null or person!=identity.get_ref() or person.household_id!=household_id:return
	if not household_views.has(household_id) or widget==null or widget.get_parent()!=household_views[household_id].places:return
	if _control.get_household_home(household_id)!=_building:return
	_control.clear_household(id)
func tab_title(id: StringName) -> String:
	var unit: RefCounted=_building.get_household(id) if _building!=null else null
	return "Хозяйство %d" % unit.local_index if unit!=null else ""

signal presentation_changed
var _presented_tabs: Array[StringName] = []
var visitors_provider: Callable
var natural_progress_provider: Callable
var _people_snapshot: Array = []
var people_rebuild_count := 0
var _presentation_expanded := false
var _image_type := -1
func _info_body() -> VBoxContainer:
	return get_node("%Info")
func available_tabs() -> Array[StringName]:
	var result: Array[StringName] = [&"info"]
	if _building != null and _building.is_built():
		if _building.type==Types.Type.HOME:
			for unit in _building.households:result.append(unit.id)
		elif _building.definition.is_storage: result.append(&"storage")
		elif _building.definition.worker_profession != preload("res://scripts/resident_profession.gd").Type.NONE: result.append(&"production")
	return result
func apply_presentation(expanded: bool, tab: StringName) -> void:
	_active_tab=tab
	for id in household_views:household_views[id].body.visible=id==tab
	_presentation_expanded=expanded
	get_node("%StaffSummary").visible=not expanded and not get_node("%StaffSummary").text.is_empty()
	get_node("%Scroll").visible = expanded
	get_node("%Info").visible = tab == &"info"
	get_node("%ProductionTab").visible = tab == &"production"
	get_node("%Storage").visible = tab == &"storage"
func _refresh_details(resource_lines: PackedStringArray) -> void:
	animal_summary.visible=_building.animal_housing!=null
	if animal_summary.visible:
		animal_summary.text="Животные: %d / %d\nШерсть: %d / %d\nНосильщик необязателен" % [_building.animal_housing.count(),_building.definition.animal_capacity,_building.resources.get_amount(ResourceType.Type.WOOL),_building.resources.get_capacity(ResourceType.Type.WOOL)]
	var profession = preload("res://scripts/resident_profession.gd")
	var producers: Array = _control.get_production_workers(_building.id) if _control != null else []
	var porters: Array = _control.get_porters(_building.id) if _control != null else []
	var counts := PackedStringArray()
	if _building.is_built() and _building.definition.worker_profession != profession.Type.NONE:
		counts.append("Работники: %d / %s" % [producers.size(), str(_building.definition.worker_capacity) if _building.definition.worker_capacity > 0 else "без лимита"])
	if _building.is_built() and _building.definition.porter_capacity > 0: counts.append("Носильщики: %d / %d" % [porters.size(),_building.definition.porter_capacity])
	if _building.animal_housing!=null:
		if counts.is_empty(): counts.append("Пастух: здание не работает")
		else: counts[0]="Пастух: %d / 1" % producers.size()
		counts.append("Животные: %d / %d" % [_building.animal_housing.count(),_building.definition.animal_capacity])
	get_node("%StaffSummary").text = "\n".join(counts)
	get_node("%StaffSummary").visible = not _presentation_expanded and not counts.is_empty()
	get_node("%Summary").text = _building.work_status() if not _building.is_built() else ""
	get_node("%Summary").visible=not _building.is_built()
	if _building.type in [Types.Type.GAZEBO,Types.Type.FLOWERBED]:
		var visitors: Array=visitors_provider.call(_building.id) if visitors_provider.is_valid() else []
		get_node("%Summary").text=("Беседка • места заняты или зарезервированы: %d / 4\nПостоянных работников нет"%visitors.size() if _building.type==Types.Type.GAZEBO else "Декоративная постройка\nРаботников и производства нет") if _building.is_built() else _building.work_status()
		get_node("%Summary").visible=true
	if _image_type!=_building.type:
		_image_type=_building.type
		get_node("%Image").texture=null
		for category in preload("res://scripts/ui/construction_catalog_data.gd").categories():
			for entry in category.entries:
				if entry.action==&"building" and entry.definition.type==_image_type: get_node("%Image").texture=load("res://assets/ui/catalog/%s.svg" % entry.icon)
	var def = _building.definition
	var buffer_lines := PackedStringArray()
	if _building.animal_housing!=null:
		buffer_lines.append("Домашние животные: %d / %d" % [_building.animal_housing.count(),_building.definition.animal_capacity])
		buffer_lines.append("Шерсть: %d / %d" % [_building.resources.get_amount(ResourceType.Type.WOOL),_building.resources.get_capacity(ResourceType.Type.WOOL)])
		buffer_lines.append("Носильщик необязателен")
	for resource in ResourceType.Type.values():
		var capacity: int = _building.resources.get_capacity(resource)
		if capacity <= 0: continue
		var role := "Запас"
		if not def.production_recipes.is_empty():
			var input: bool = def.production_recipes.any(func(recipe): return recipe.inputs.has(resource))
			var output: bool = def.production_recipes.any(func(recipe): return recipe.outputs.has(resource) or recipe.optional_outputs.has(resource))
			if input and output: role = "Вход и выход"
			elif input: role = "Вход"
			elif output: role = "Выход"
		elif resource in def.internal_resources or _building.type == Types.Type.GATHERER_HUT: role = "Выход"
		buffer_lines.append("%s • %s: %d / %d" % [role,ResourceType.display_name(resource),_building.resources.get_amount(resource),capacity])
	resources_label.text = "\n".join(buffer_lines)
	resources_label.visible = not buffer_lines.is_empty()
	_refresh_storage()
	get_node("%OtherStocks").text = "\n".join(resource_lines)
	get_node("%OtherStocks").visible = _building.is_built() and available_tabs().size() == 1 and not resource_lines.is_empty()
	var recipe_lines := PackedStringArray()
	if _building.type == Types.Type.GATHERER_HUT: recipe_lines.append("Добывает " + ResourceType.display_name(ResourceType.Type.MUSHROOM))
	else:
		for resource in def.internal_resources: recipe_lines.append("Добывает " + ResourceType.display_name(resource))
	get_node("%Recipe").text = "\n".join(recipe_lines)
	get_node("%Recipe").visible = not recipe_lines.is_empty()
	production_section.visible = _building.is_built() and _building.type == Types.Type.GATHERER_HUT
	var natural: PackedStringArray = natural_progress_provider.call(_building.id) if def.worker_profession in [profession.Type.LUMBERJACK,profession.Type.MINER,profession.Type.CLAY_DIGGER] and natural_progress_provider.is_valid() else PackedStringArray()
	get_node("%NaturalProgress").text = "\n".join(natural)
	get_node("%NaturalProgress").visible = not natural.is_empty()
	_refresh_people(producers, porters)

func _setup_storage_rows() -> void:
	for category in [Categories.Type.LOG,Categories.Type.STONE,Categories.Type.PLANK,Categories.Type.SIMPLE_FOOD,Categories.Type.MUSHROOM,Categories.Type.WOOL,Categories.Type.WOOL_CLOTH,Categories.Type.SIMPLE_CLOTHING,Categories.Type.WHEAT,Categories.Type.SHEAF,Categories.Type.STRAW,Categories.Type.FLOUR,Categories.Type.CLAY,Categories.Type.BRICK,Categories.Type.STONE_BRICK]:
		var section := VBoxContainer.new()
		get_node("%StorageAmounts").add_child(section)
		var row := HBoxContainer.new()
		section.add_child(row)
		var label := Button.new()
		label.text = "▸ " + Categories.display_name(category)
		if category==Categories.Type.FLOUR:
			label.icon=preload("res://assets/ui/catalog/flour.svg")
			label.expand_icon=true
			label.add_theme_constant_override("icon_max_width",24)
		label.toggle_mode = true
		label.flat = true
		label.alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.tooltip_text = "Показать конкретные товары"
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var amount := Label.new()
		amount.custom_minimum_size.x = 44
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(amount)
		var editor := LineEdit.new()
		editor.custom_minimum_size.x = 56
		editor.max_length = 20
		editor.keep_editing_on_text_submit = true
		editor.tooltip_text = "Квота категории. Enter или ✓ — применить."
		row.add_child(editor)
		editor.text_changed.connect(_on_quota_edited.bind(category))
		editor.text_submitted.connect(_submit_quota.bind(category))
		var apply := Button.new()
		apply.text = "✓"
		apply.tooltip_text = "Применить максимум"
		row.add_child(apply)
		apply.pressed.connect(_apply_quota.bind(category))
		var contents := Label.new()
		contents.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		contents.hide()
		section.add_child(contents)
		label.toggled.connect(_toggle_category.bind(category))
		storage_rows[category] = {"row":section,"amount":amount,"editor":editor,"apply":apply,"expand":label,"contents":contents}

func _toggle_category(expanded: bool, category: int) -> void:
	var row: Dictionary = storage_rows[category]
	row.contents.visible = expanded
	row.expand.text = ("▾ " if expanded else "▸ ") + Categories.display_name(category)

func _on_quota_edited(_text: String, category: int) -> void:
	_quota_dirty[category] = true

func _apply_quota(category: int) -> void:
	_submit_quota(storage_rows[category].editor.text,category)

func _submit_quota(text: String, category: int) -> void:
	if _building == null or _control == null: return
	var value: Variant = text
	# Bound parsing before conversion; very large input must not overflow an int.
	if text.is_valid_int() and text.length() <= 18: value = text.to_int()
	var result: Dictionary = _control.set_warehouse_category_quota(_building.id,category,value)
	get_node("%StorageError").text = result.error
	if result.ok:
		_quota_dirty.erase(category)
		storage_rows[category].editor.release_focus()
		_refresh_storage()

func _refresh_storage() -> void:
	if _building == null: return
	var container = _building.resources
	if not container.is_warehouse(): return
	get_node("%StorageSummary").text = "Занято: %d / %d\nВ пути: %d\nРаспределено: %d / %d" % [container.get_total_amount(),container.shared_capacity,container.get_total_reserved_in(),container.get_allocated_capacity(),container.shared_capacity]
	for category in storage_rows:
		var row: Dictionary = storage_rows[category]
		row.row.visible = container.supports_category(category)
		row.amount.text = "%d /" % container.get_category_amount(category)
		var lines := PackedStringArray()
		var contents: Dictionary = container.get_category_contents(category)
		for concrete_type in contents: lines.append("  %s: %d" % [ResourceType.display_name(concrete_type),contents[concrete_type]])
		row.contents.text = "\n".join(lines) if not lines.is_empty() else "  Нет запасов"
		row.editor.editable = _control != null and _building.is_built()
		row.apply.disabled = not row.editor.editable
		if not row.editor.has_focus() and not _quota_dirty.has(category):
			row.editor.text = str(container.get_category_quota(category))
func _refresh_people(producers: Array, porters: Array) -> void:
	if _control == null: return
	_refresh_housing()
	var visitors: Array = visitors_provider.call(_building.id) if visitors_provider.is_valid() else []
	var snapshot: Array = [producers.map(func(r): return [r.id,r.resident_name]),porters.map(func(r): return [r.id,r.resident_name]),visitors,_building.active_builder_ids,_building.id,_building.state,_building.definition.worker_capacity,_building.definition.porter_capacity,_building.definition.housing_capacity]
	if snapshot == _people_snapshot: return
	people_rebuild_count += 1
	_people_snapshot = snapshot
	var body: VBoxContainer = get_node("%People")
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var home_button: Button=staffing_buttons.get(&"home")
	staffing_buttons.clear()
	if home_button!=null:staffing_buttons[&"home"]=home_button
	var profession=preload("res://scripts/resident_profession.gd")
	for role in _control.get_workplace_roles(_building.id):
		var people: Array=porters if role==profession.Type.PORTER else producers
		var capacity: int=_building.definition.porter_capacity if role==profession.Type.PORTER else _building.definition.worker_capacity
		_add_staff_group(body,role,people,capacity)
	if not _building.is_built() and not _building.active_builder_ids.is_empty():
		var title := Label.new()
		title.text = "Работающие строители (временное назначение)"
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(title)
		for id in _building.active_builder_ids:
			var person = _control.get_resident(id)
			if person != null: _add_person(body,person,false,false)
	if not visitors.is_empty():
		var title := Label.new()
		title.text = "Посетители"
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(title)
		for entry in visitors:
			var person = _control.get_resident(entry.id)
			if person != null:
				var purpose := Label.new()
				purpose.text = ["Работа","Курьерское посещение","Посещение","Сон"][entry.purpose]
				body.add_child(purpose)
				_add_person(body,person,false,false)
func _add_staff_group(body: VBoxContainer, role: int, people: Array, capacity: int) -> void:
	var label := Label.new()
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.text="%s: %d / %s" % [preload("res://scripts/resident_profession.gd").display_name(role),people.size(),str(capacity) if capacity>0 else "без лимита"]
	body.add_child(label)
	for person in people: _add_person(body,person,false,true,role)
	var row := HBoxContainer.new()
	body.add_child(row)
	var vacancy := Label.new()
	vacancy.text="Свободно: %s" % (str(maxi(capacity-people.size(),0)) if capacity>0 else "без лимита") if _building.is_built() else _building.work_status()
	vacancy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	vacancy.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	row.add_child(vacancy)
	var button := Button.new()
	button.text="Назначить"
	button.focus_mode=Control.FOCUS_NONE
	button.disabled=not _building.is_built() or (capacity>0 and people.size()>=capacity)
	button.pressed.connect(staffing_requested.emit.bind(role))
	row.add_child(button)
	staffing_buttons[role]=button
func _add_person(body: VBoxContainer, person: RefCounted, housing: bool, removable: bool, role: int = -1) -> void:
	var row := HBoxContainer.new()
	body.add_child(row)
	var button := Button.new()
	button.text = person.resident_name
	button.clip_text = true
	if person.resident_name.length()>24:
		var full_name := Label.new()
		full_name.text = person.resident_name
		full_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(full_name)
		body.move_child(full_name,row.get_index())
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_select_person.bind(person.id))
	row.add_child(button)
	if removable:
		var clear := Button.new()
		clear.text = "Выселить" if housing else "Уволить"
		clear.focus_mode = Control.FOCUS_NONE
		clear.pressed.connect(_clear_person.bind(person.id,_building.id,housing,role,weakref(person),weakref(_building)))
		row.add_child(clear)
func _select_person(id: String) -> void:
	var current = _control.get_resident(id) if _control != null else null
	if current != null: _selection.select(current)
func _clear_person(id: String, building_id: StringName, housing: bool, role: int = -1, resident_identity: WeakRef = null, building_identity: WeakRef = null) -> void:
	var current = _control.get_resident(id) if _control != null else null
	var building = _control.get_building(building_id)
	if current == null or building == null: return
	if resident_identity!=null and resident_identity.get_ref()!=current: return
	if building_identity!=null and building_identity.get_ref()!=building: return
	if housing:
		if _control.get_household_home(current.household_id) == building: _control.clear_home(id)
	elif current.work_location_id == building_id and current.profession==role: _control.clear_work_assignment(id)
	_refresh()
func _refresh_consumables() -> void:
	if _building==null:return
	# Construction may configure these stocks after this instance was selected.
	for key in _building.consumable_stocks:
		if consumable_rows.has(key):continue
		var stock: RefCounted=_building.consumable_stocks[key]
		var box:=VBoxContainer.new()
		var label:=Label.new()
		var bar:=ProgressBar.new()
		box.add_child(label);box.add_child(bar);consumable_section.add_child(box)
		consumable_rows[key]={"box":box,"label":label,"bar":bar}
		stock.changed.connect(_refresh_consumables)
	for key in consumable_rows:
		var stock: RefCounted=_building.consumable_stocks[key]
		var row: Dictionary=consumable_rows[key]
		row.label.text="%s: %d / %d" % [stock.display_name,stock.amount,stock.capacity]
		row.bar.max_value=stock.capacity;row.bar.value=stock.amount
func _disconnect_building() -> void:
	if _building!=null:
		for stock in _building.consumable_stocks.values():
			if stock.changed.is_connected(_refresh_consumables):stock.changed.disconnect(_refresh_consumables)
	if _building==null: return
	for pair in [
		[_building.construction_changed,_refresh],
		[_building.production_changed,_refresh_recipes],
		[_building.resources.changed,_on_resources_changed],
		[_building.resources.reservations_changed,_on_reservations_changed],
		[_building.resources.quotas_changed,_refresh],
	]:
		if pair[0].is_connected(pair[1]): pair[0].disconnect(pair[1])
func _clear_recipe_views() -> void:
	for view in recipe_views.values():
		view.deactivate()
		view.get_parent().remove_child(view)
		view.queue_free()
	recipe_views.clear()
	_recipe_ids.clear()
func _refresh_recipes() -> void:
	_refresh_stock_target()
	var ids: Array = []
	if _building!=null and (_building.is_built() or _building.is_upgrading()) and not _building.production_removed:
		ids = _building.definition.production_recipes.map(func(recipe): return recipe.id)
	if ids!=_recipe_ids:
		_clear_recipe_views()
		_recipe_ids = ids
		for id in ids:
			var view := RecipeView.new()
			get_node("%RecipeControls").add_child(view)
			view.setup(_building,_building.definition.get_production_recipe(id),_control)
			recipe_views[id] = view
	for view in recipe_views.values(): view.refresh()
func _exit_tree() -> void:
	_disconnect_work_area()
	_disconnect_building()
	for view in recipe_views.values(): view.deactivate()
	if _control != null and _control.household_changed.is_connected(_on_household_changed): _control.household_changed.disconnect(_on_household_changed)
	if _selection != null and _selection.selection_changed.is_connected(_on_selection_changed): _selection.selection_changed.disconnect(_on_selection_changed)

func _refresh_construction_command() -> void:
	var button: Button = get_node("%Demolish")
	button.disabled = _building == null or _control == null or not _control.construction_command.is_valid() or _building.removal_started or _building.state == Instance.State.REMOVED
	if _building == null: return
	if _building.is_upgrading():button.text="Демонтировать здание"
	elif _building.is_built(): button.text = "Демонтировать"
	elif _building.work_direction == Instance.WorkDirection.DEMOLISH: button.text = "Отменить демонтаж" if _building.previously_built else "Возобновить строительство"
	else: button.text = "Демонтировать" if _building.previously_built else "Отменить строительство"
func _change_construction_direction() -> void:
	if _building == null or _control == null: return
	_control.change_construction_direction(_building.id,_building.is_upgrading() or _building.is_built() or _building.work_direction == Instance.WorkDirection.BUILD)
	_refresh()

func _setup_stock_target() -> void:
	farm_stock_section=VBoxContainer.new();get_node("%RecipeControls").add_child(farm_stock_section)
	var title:=Label.new();title.text="Запас пшеницы";farm_stock_section.add_child(title)
	var row:=HBoxContainer.new();farm_stock_section.add_child(row)
	farm_stock_editor=LineEdit.new();farm_stock_editor.custom_minimum_size.x=72;farm_stock_editor.max_length=3;row.add_child(farm_stock_editor)
	var apply:=Button.new();apply.text="Применить";row.add_child(apply)
	apply.pressed.connect(_apply_stock_target)
	farm_stock_editor.text_submitted.connect(func(_text):_apply_stock_target())
	farm_stock_editor.text_changed.connect(func(_text):_stock_dirty=true;farm_stock_feedback.hide())
	farm_stock_feedback=Label.new();farm_stock_feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;farm_stock_section.add_child(farm_stock_feedback)
	farm_stock_section.hide()
func _refresh_stock_target() -> void:
	if farm_stock_section==null:return
	farm_stock_section.visible=_building!=null and _building.is_built() and _building.stock_targets().has(ResourceType.Type.WHEAT)
	if not farm_stock_section.visible:_stock_id=&"";return
	if _stock_id!=_building.id:_stock_id=_building.id;_stock_dirty=false;farm_stock_feedback.hide()
	if not _stock_dirty:farm_stock_editor.text=str(_building.get_stock_target(ResourceType.Type.WHEAT))
func _apply_stock_target() -> void:
	if _building==null or _control==null or _building.id!=_stock_id:return
	var text:=farm_stock_editor.text.strip_edges()
	var result: Dictionary={"ok":false,"error":"Введите целое число от 0 до 50."}
	if text.is_valid_int():result=_control.set_production_stock_target(_stock_id,ResourceType.Type.WHEAT,text.to_int())
	farm_stock_feedback.text="Сохранено" if result.ok else result.error;farm_stock_feedback.show()
	if result.ok:_stock_dirty=false;_refresh_stock_target()

var upgrade_section: VBoxContainer
var upgrade_button: Button
var upgrade_cancel: Button
var upgrade_summary: Label
var upgrade_confirm: Button
var upgrade_back: Button
var _confirm_upgrade_id: StringName = &""
func _refresh_upgrade() -> void:
	if upgrade_section==null:
		upgrade_section=VBoxContainer.new();get_node("%Demolish").get_parent().add_child(upgrade_section)
		upgrade_button=Button.new();upgrade_button.text="Улучшить";upgrade_section.add_child(upgrade_button);upgrade_button.pressed.connect(_preview_upgrade)
		upgrade_summary=Label.new();upgrade_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;upgrade_section.add_child(upgrade_summary)
		upgrade_confirm=Button.new();upgrade_confirm.text="Подтвердить улучшение";upgrade_section.add_child(upgrade_confirm);upgrade_confirm.pressed.connect(_start_upgrade)
		upgrade_back=Button.new();upgrade_back.text="Назад";upgrade_section.add_child(upgrade_back);upgrade_back.pressed.connect(func():_confirm_upgrade_id=&"";_refresh_upgrade())
		upgrade_cancel=Button.new();upgrade_cancel.text="Отменить улучшение";upgrade_section.add_child(upgrade_cancel);upgrade_cancel.pressed.connect(_cancel_upgrade)
	var plan: RefCounted=_building.next_upgrade() if _building!=null else null
	var active: bool=_building!=null and _building.is_upgrading()
	var preview: bool=_building!=null and _confirm_upgrade_id==_building.id and _building.is_built() and plan!=null
	upgrade_section.visible=active or (_building!=null and _building.is_built() and plan!=null)
	upgrade_button.visible=upgrade_section.visible and not active and not preview
	upgrade_button.disabled=_control==null or not _control.upgrade_command.is_valid()
	upgrade_summary.visible=active or preview
	upgrade_confirm.visible=preview;upgrade_back.visible=preview
	upgrade_cancel.visible=active;upgrade_cancel.disabled=active and _building.work_direction==Instance.WorkDirection.DEMOLISH
	if active:upgrade_summary.text="Улучшение до уровня II" if _building.work_direction==Instance.WorkDirection.BUILD else "Отмена улучшения • разборка проекта"
	elif preview:
		var materials:=PackedStringArray()
		for resource in plan.construction_requirements:materials.append("%s ×%d"%[ResourceType.display_name(resource),plan.construction_requirements[resource]])
		upgrade_summary.text="%s I → II\n%s\n%d рабочих минут\n%s"%[_building.display_name,", ".join(materials),plan.construction_work_required,plan.description]
func _preview_upgrade() -> void:
	if _building==null:return
	_confirm_upgrade_id=_building.id;_refresh_upgrade()
func _start_upgrade() -> void:
	if _building==null or _control==null or _confirm_upgrade_id!=_building.id:return
	var result: Dictionary=_control.start_building_upgrade(_building.id)
	_confirm_upgrade_id=&"";_refresh()
	if not result.ok:upgrade_summary.text=result.error;upgrade_summary.show()
func _cancel_upgrade() -> void:
	if _building!=null and _control!=null:_control.cancel_building_upgrade(_building.id);_refresh()
