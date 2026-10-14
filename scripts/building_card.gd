extends PanelContainer
# Presentation counters for focused UI diagnostics; never used by simulation.
var refresh_count := 0
@export var embedded := false
@export var embedded_close_path: NodePath
var clock: Node
var _refresh_elapsed := 0.0
func _widget(id: String, legacy_path: String) -> Node:
	if not embedded: return get_node(legacy_path)
	if id in ["ID","State","Type","HousingResidents"]: return null
	return get_node(embedded_close_path) if id == "Close" else get_node("%" + id)

## Reads the selected instance. Only presentation is updated; there are no management rules.
const Selection = preload("res://scripts/resident_selection.gd")
const Instance = preload("res://scripts/building_instance.gd")
const Types = preload("res://scripts/building_type.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
const Balance = preload("res://scripts/balance_config.gd")
const FOOD = ResourceType.Type.FOOD
var _control: RefCounted
@onready var housing_section: VBoxContainer = _widget("Housing", "Margin/Column/Scroll/Content/Housing")
@onready var housing_count: Label = _widget("HousingCount", "Margin/Column/Scroll/Content/Housing/Count")
@onready var housing_residents: Label = _widget("HousingResidents", "Margin/Column/Scroll/Content/Housing/Residents")
var _selection: Selection
var _building: Instance
var _last_snapshot: Array = []
signal settlement_management_requested
signal staffing_requested(profession: int)
var staffing_buttons: Dictionary = {}
var management_button: Button
@onready var name_label: Label = _widget("Name", "Margin/Column/Scroll/Content/Name")
@onready var id_label: Label = _widget("ID", "Margin/Column/Scroll/Content/ID")
@onready var state_label: Label = _widget("State", "Margin/Column/Scroll/Content/State")
@onready var type_label: Label = _widget("Type", "Margin/Column/Scroll/Content/Type")
@onready var resources_label: Label = _widget("Resources", "Margin/Column/Scroll/Content/Resources")
@onready var production_section: VBoxContainer = _widget("Production", "Margin/Column/Scroll/Content/Production")
@onready var production_label: Label = _widget("Progress", "Margin/Column/Scroll/Content/Production/Progress")
@onready var construction_section: VBoxContainer = _widget("Construction", "Margin/Column/Scroll/Content/Construction")
@onready var construction_materials: Label = _widget("Materials", "Margin/Column/Scroll/Content/Construction/Materials")
@onready var construction_work: Label = _widget("Work", "Margin/Column/Scroll/Content/Construction/Work")
@onready var construction_builders: Label = _widget("Builders", "Margin/Column/Scroll/Content/Construction/Builders")
@onready var close_button: Button = _widget("Close", "Margin/Column/Close")
func _ready() -> void:
	hide()
	management_button = Button.new()
	management_button.text = "Управление поселением"
	_info_body().add_child(management_button)
	if not embedded: $Margin/Column/Scroll/Content.move_child(management_button,4)
	else: _info_body().move_child(management_button,get_node("%Demolish").get_index())
	management_button.pressed.connect(func(): settlement_management_requested.emit())
	if not embedded: close_button.pressed.connect(_close)
func bind_selection(selection: Selection) -> void:
	if _selection != null and _selection.selection_changed.is_connected(_on_selection_changed): _selection.selection_changed.disconnect(_on_selection_changed)
	_selection = selection
	_selection.selection_changed.connect(_on_selection_changed)
	_on_selection_changed()
func _on_selection_changed() -> void:
	if _building != null:
		_building.construction_changed.disconnect(_refresh)
	if _building != null and _building.resources != null:
		_building.resources.changed.disconnect(_on_resources_changed)
	_building = _selection.selected_building
	_presented_tabs.clear()
	_last_snapshot = []
	if _building != null: _building.construction_changed.connect(_refresh)
	if _building != null and _building.resources != null:
		_building.resources.changed.connect(_on_resources_changed)
	_widget("Scroll", "Margin/Column/Scroll").scroll_vertical = 0
	_refresh()
func _on_resources_changed(_resource: ResourceType.Type, _amount: int) -> void: _refresh()
func _process(delta: float) -> void:
	# Same live-data pattern as ResidentCard; no node/list rebuilding per frame.
	if not is_visible_in_tree(): return
	if embedded:
		_refresh_elapsed += delta
		if _refresh_elapsed < 0.25: return
		_refresh_elapsed = 0.0
	_refresh()
func _refresh() -> void:
	refresh_count += 1
	if management_button != null: management_button.visible = _building != null and _building.is_built() and _building.type == Types.Type.TOWN_CENTER
	if _building == null:
		if not embedded: hide()
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
	var snapshot: Array = [workers_snapshot,porter_snapshot,_building.definition.porter_capacity,_building.definition.worker_capacity,_building.definition.housing_capacity,_building.display_name, _building.id, _building.state, _building.type, amount, capacity, _building.production_progress, _building.construction_delivered, _building.construction_progress, _building.active_builder_ids, _building.definition.construction_requirements.duplicate(), _building.definition.construction_work_required, _building.definition.max_builders, resource_lines]
	if embedded: _refresh_embedded(resource_lines)
	if snapshot == _last_snapshot: return
	_last_snapshot = snapshot
	name_label.text = _building.display_name
	if not embedded:
		id_label.text = "ID: %s" % _building.id
		state_label.text = "Состояние: " + ("Построено" if _building.is_built() else "Строится")
		type_label.text = "Тип: " + _type_text(_building.type)
	if _control != null and _building.is_built() and _building.definition.worker_profession != preload("res://scripts/resident_profession.gd").Type.NONE:
		var workers: Array = _control.get_workplace_workers(_building.id)
		resource_lines.append("Работники производства: %d / %d" % [workers.size(),_building.definition.worker_capacity])
		if not embedded:
			for worker in workers: resource_lines.append(worker.resident_name + " — " + preload("res://scripts/resident_profession.gd").display_name(worker.profession))
	if _control != null and _building.is_built() and _building.definition.porter_capacity > 0:
		resource_lines.append("Носильщики: %d / %d" % [porter_snapshot.size(),_building.definition.porter_capacity])
	if not embedded: resources_label.text = "\n".join(resource_lines) if not resource_lines.is_empty() else "Ресурсов нет"
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
	if embedded:
		var tabs := available_tabs()
		if tabs != _presented_tabs:
			_presented_tabs = tabs
			presentation_changed.emit()
	else: show()
func _type_text(category: int) -> String:
	match category:
		Types.Type.FOOD: return "Кухня"
		Types.Type.STORAGE: return "Склад"
		Types.Type.GATHERER_HUT: return "Хижина собирателя"
		Types.Type.QUARRY: return "Каменоломня"
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
	if _building != null and _building.id in [previous, current]:
		_refresh_housing()
		if embedded: _refresh()

func _refresh_housing() -> void:
	housing_section.visible = _control != null and _control.is_housing_target(_building)
	if not housing_section.visible: return
	var occupants: Array = _control.get_home_occupants(_building.id)
	housing_count.text = "Жильцы: %d / %d" % [occupants.size(), _building.definition.housing_capacity]
	var names := PackedStringArray()
	for resident in occupants: names.append("• " + resident.resident_name)
	if not embedded: housing_residents.text = "\n".join(names) if not names.is_empty() else "Нет жильцов"

signal presentation_changed
var _presented_tabs: Array[StringName] = []
var visitors_provider: Callable
var natural_progress_provider: Callable
var _people_snapshot: Array = []
var people_rebuild_count := 0
var _presentation_expanded := false
var _image_type := -1
func _info_body() -> VBoxContainer:
	return get_node("%Info") if embedded else $Margin/Column/Scroll/Content
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
func _refresh_embedded(resource_lines: PackedStringArray) -> void:
	var profession = preload("res://scripts/resident_profession.gd")
	var producers: Array = _control.get_production_workers(_building.id) if _control != null else []
	var porters: Array = _control.get_porters(_building.id) if _control != null else []
	var counts := PackedStringArray()
	if _building.is_built() and _building.definition.worker_profession != profession.Type.NONE:
		counts.append("Работники: %d / %s" % [producers.size(), str(_building.definition.worker_capacity) if _building.definition.worker_capacity > 0 else "без лимита"])
	if _building.is_built() and _building.definition.porter_capacity > 0: counts.append("Носильщики: %d / %d" % [porters.size(),_building.definition.porter_capacity])
	get_node("%StaffSummary").text = "\n".join(counts)
	get_node("%StaffSummary").visible = not _presentation_expanded and not counts.is_empty()
	get_node("%Summary").text = "Строится" if not _building.is_built() else ""
	get_node("%Summary").visible=not _building.is_built()
	if _image_type!=_building.type:
		_image_type=_building.type
		get_node("%Image").texture=null
		for category in preload("res://scripts/ui/construction_catalog_data.gd").categories():
			for entry in category.entries:
				if entry.action==&"building" and entry.definition.type==_image_type: get_node("%Image").texture=load("res://assets/ui/catalog/%s.svg" % entry.icon)
	var def = _building.definition
	var buffer_lines := PackedStringArray()
	for resource in ResourceType.Type.values():
		var capacity: int = _building.resources.get_capacity(resource)
		if capacity <= 0: continue
		var role := "Запас"
		if def.production_recipe != null:
			if def.production_recipe.inputs.has(resource): role = "Вход"
			elif def.production_recipe.outputs.has(resource): role = "Выход"
		elif resource in def.internal_resources or _building.type == Types.Type.GATHERER_HUT: role = "Выход"
		buffer_lines.append("%s • %s: %d / %d" % [role,ResourceType.display_name(resource),_building.resources.get_amount(resource),capacity])
	resources_label.text = "\n".join(buffer_lines)
	resources_label.visible = not buffer_lines.is_empty()
	get_node("%StorageAmounts").text = "\n".join(resource_lines)
	get_node("%OtherStocks").text = "\n".join(resource_lines)
	get_node("%OtherStocks").visible = _building.is_built() and available_tabs().size() == 1 and not resource_lines.is_empty()
	var recipe_lines := PackedStringArray()
	if def.production_recipe != null:
		for resource in def.production_recipe.inputs: recipe_lines.append("Нужно: %s ×%d" % [ResourceType.display_name(resource),def.production_recipe.inputs[resource]])
		for resource in def.production_recipe.outputs: recipe_lines.append("Результат: %s ×%d" % [ResourceType.display_name(resource),def.production_recipe.outputs[resource]])
	elif _building.type == Types.Type.GATHERER_HUT: recipe_lines.append("Производит FOOD")
	else:
		for resource in def.internal_resources: recipe_lines.append("Добывает " + ResourceType.display_name(resource))
	get_node("%Recipe").text = "\n".join(recipe_lines)
	production_section.visible = _building.is_built() and (_building.type == Types.Type.GATHERER_HUT or def.production_recipe != null)
	var natural: PackedStringArray = natural_progress_provider.call(_building.id) if def.worker_profession in [profession.Type.LUMBERJACK,profession.Type.MINER] and natural_progress_provider.is_valid() else PackedStringArray()
	get_node("%NaturalProgress").text = "\n".join(natural)
	get_node("%NaturalProgress").visible = not natural.is_empty()
	_refresh_people(producers, porters)
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
	vacancy.text="Свободно: %s" % (str(maxi(capacity-people.size(),0)) if capacity>0 else "без лимита") if _building.is_built() else "Здание строится"
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
func _exit_tree() -> void:
	if _building != null:
		if _building.construction_changed.is_connected(_refresh): _building.construction_changed.disconnect(_refresh)
		if _building.resources.changed.is_connected(_on_resources_changed): _building.resources.changed.disconnect(_on_resources_changed)
	if _control != null and _control.home_changed.is_connected(_on_home_changed): _control.home_changed.disconnect(_on_home_changed)
	if _selection != null and _selection.selection_changed.is_connected(_on_selection_changed): _selection.selection_changed.disconnect(_on_selection_changed)
