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
	_setup_storage_rows()
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
	_disconnect_building()
	_clear_recipe_views()
	_quota_dirty.clear()
	for row in storage_rows.values():
		row.editor.release_focus()
		row.expand.set_pressed_no_signal(false)
		row.contents.hide()
		row.expand.text = "▸ " + Categories.display_name(storage_rows.find_key(row))
	get_node("%StorageError").text = ""
	_building = _selection.selected_building
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
	_refresh_work_area()
	_refresh_construction_command()
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
	var workers_snapshot: Array = _control.get_workplace_workers(_building.id).map(func(worker): return worker.id) if _control != null else []
	var porter_snapshot: Array = _control.get_porters(_building.id).map(func(worker): return worker.id) if _control != null else []
	var snapshot: Array = [workers_snapshot,porter_snapshot,_building.definition.porter_capacity,_building.definition.worker_capacity,_building.definition.housing_capacity,_building.display_name, _building.id, _building.state, _building.work_direction, _building.work_paused, _building.type, amount, capacity, _building.production_progress, _building.construction_delivered, _building.construction_progress, _building.active_builder_ids, _building.definition.construction_requirements.duplicate(), _building.definition.construction_work_required, _building.definition.max_builders, resource_lines]
	_refresh_details(resource_lines)
	if snapshot == _last_snapshot: return
	_last_snapshot = snapshot
	name_label.text = _building.display_name
	if _control != null and _building.is_built() and _building.definition.worker_profession != preload("res://scripts/resident_profession.gd").Type.NONE:
		var workers: Array = _control.get_workplace_workers(_building.id)
		resource_lines.append("Работники производства: %d / %d" % [workers.size(),_building.definition.worker_capacity])
	if _control != null and _building.is_built() and _building.definition.porter_capacity > 0:
		resource_lines.append("Носильщики: %d / %d" % [porter_snapshot.size(),_building.definition.porter_capacity])
	production_section.visible = _building.is_built() and _building.type == Types.Type.GATHERER_HUT
	production_label.text = "По 1 грибу за рейс • сбор %d мин • разгрузка %d мин" % [Balance.RESOURCE_LOADING_MINUTES,Balance.RESOURCE_UNLOADING_MINUTES]
	construction_section.visible = not _building.is_built()
	_refresh_housing()
	var materials := PackedStringArray()
	for resource in _building.definition.construction_requirements:
		materials.append("%s: %d / %d" % [ResourceType.display_name(resource), _building.get_delivered_amount(resource), _building.get_required_amount(resource)])
	construction_materials.text = "Материалы:\n" + ("\n".join(materials) if not materials.is_empty() else "Не требуются")
	if _building.previously_built: construction_materials.text = "Материалы остаются в конструкции.\nДля восстановления новые материалы не нужны."
	construction_work.text = _building.work_status() + ": %d / %d мин\n%.0f%%" % [_building.construction_progress, _building.definition.construction_work_required, _building.get_construction_progress_ratio() * 100.0]
	structural_progress.value = _building.get_construction_progress_ratio()*100.0
	construction_work.text += "\nОсталось работы: %d мин" % _building.work_remaining()
	if _building.work_paused: construction_work.text += "\nОжидание завершения действий внутри"
	construction_builders.text = "Строители: %d / %d" % [_building.active_builder_ids.size(), _building.definition.max_builders]
	var tabs := available_tabs()
	if tabs != _presented_tabs:
		_presented_tabs = tabs
		presentation_changed.emit()
func bind_control(control: RefCounted) -> void:
	if _control != null and _control.home_changed.is_connected(_on_home_changed): _control.home_changed.disconnect(_on_home_changed)
	_disconnect_work_area()
	_control = control
	_control.home_changed.connect(_on_home_changed)
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

func _on_home_changed(_resident_id: String, previous: StringName, current: StringName) -> void:
	if _building != null and _building.id in [previous, current]:
		_refresh_housing()
		_refresh()

func _refresh_housing() -> void:
	housing_section.visible = _control != null and _control.is_housing_target(_building)
	if not housing_section.visible: return
	var occupants: Array = _control.get_home_occupants(_building.id)
	housing_count.text = "Жильцы: %d / %d" % [occupants.size(), _building.definition.housing_capacity]

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
		if _building.definition.is_storage: result.append(&"storage")
		elif _building.definition.worker_profession != preload("res://scripts/resident_profession.gd").Type.NONE: result.append(&"production")
	return result
func apply_presentation(expanded: bool, tab: StringName) -> void:
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
			var output: bool = def.production_recipes.any(func(recipe): return recipe.outputs.has(resource))
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
	get_node("%Recipe").visible = def.production_recipes.is_empty()
	production_section.visible = _building.is_built() and _building.type == Types.Type.GATHERER_HUT
	var natural: PackedStringArray = natural_progress_provider.call(_building.id) if def.worker_profession in [profession.Type.LUMBERJACK,profession.Type.MINER] and natural_progress_provider.is_valid() else PackedStringArray()
	get_node("%NaturalProgress").text = "\n".join(natural)
	get_node("%NaturalProgress").visible = not natural.is_empty()
	_refresh_people(producers, porters)

func _setup_storage_rows() -> void:
	for category in [Categories.Type.LOG,Categories.Type.STONE,Categories.Type.PLANK,Categories.Type.SIMPLE_FOOD,Categories.Type.MUSHROOM,Categories.Type.WOOL,Categories.Type.WOOL_CLOTH,Categories.Type.SIMPLE_CLOTHING]:
		var section := VBoxContainer.new()
		get_node("%StorageAmounts").add_child(section)
		var row := HBoxContainer.new()
		section.add_child(row)
		var label := Button.new()
		label.text = "▸ " + Categories.display_name(category)
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
	var residents: Array = _control.get_home_occupants(_building.id) if _control.is_housing_target(_building) else []
	var visitors: Array = visitors_provider.call(_building.id) if visitors_provider.is_valid() else []
	var snapshot: Array = [producers.map(func(r): return [r.id,r.resident_name]),porters.map(func(r): return [r.id,r.resident_name]),residents.map(func(r): return [r.id,r.resident_name]),visitors,_building.active_builder_ids,_building.id,_building.state,_building.definition.worker_capacity,_building.definition.porter_capacity,_building.definition.housing_capacity]
	if snapshot == _people_snapshot: return
	people_rebuild_count += 1
	_people_snapshot = snapshot
	var body: VBoxContainer = get_node("%People")
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	staffing_buttons.clear()
	var profession=preload("res://scripts/resident_profession.gd")
	for role in _control.get_workplace_roles(_building.id):
		var people: Array=porters if role==profession.Type.PORTER else producers
		var capacity: int=_building.definition.porter_capacity if role==profession.Type.PORTER else _building.definition.worker_capacity
		_add_staff_group(body,role,people,capacity)
	if _control.has_housing_role(_building.id):
		var button := Button.new()
		button.text="Поселить жителя"
		button.disabled=not _building.is_built()
		button.focus_mode=Control.FOCUS_NONE
		button.pressed.connect(staffing_requested.emit.bind(-1))
		body.add_child(button)
		staffing_buttons[&"home"]=button
		for person in residents: _add_person(body,person,true,true)
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
		if current.home_location_id == building_id: _control.clear_home(id)
	elif current.work_location_id == building_id and current.profession==role: _control.clear_work_assignment(id)
	_refresh()
func _disconnect_building() -> void:
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
	var ids: Array = []
	if _building!=null and _building.is_built() and not _building.production_removed:
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
	if _control != null and _control.home_changed.is_connected(_on_home_changed): _control.home_changed.disconnect(_on_home_changed)
	if _selection != null and _selection.selection_changed.is_connected(_on_selection_changed): _selection.selection_changed.disconnect(_on_selection_changed)

func _refresh_construction_command() -> void:
	var button: Button = get_node("%Demolish")
	button.disabled = _building == null or _control == null or not _control.construction_command.is_valid() or _building.removal_started or _building.state == Instance.State.REMOVED
	if _building == null: return
	if _building.is_built(): button.text = "Демонтировать"
	elif _building.work_direction == Instance.WorkDirection.DEMOLISH: button.text = "Отменить демонтаж" if _building.previously_built else "Возобновить строительство"
	else: button.text = "Демонтировать" if _building.previously_built else "Отменить строительство"
func _change_construction_direction() -> void:
	if _building == null or _control == null: return
	_control.change_construction_direction(_building.id,_building.is_built() or _building.work_direction == Instance.WorkDirection.BUILD)
	_refresh()
