extends PanelContainer
# Presentation counters for focused UI diagnostics; never used by simulation.
var refresh_count := 0
@export var close_path: NodePath
var clock: Node
var _refresh_elapsed := 0.0
func _widget(id: String) -> Node:
	return get_node(close_path) if id == "Close" else get_node("%" + id)

const Diary = preload("res://scripts/diary_entry.gd")
## The card reads the selection's data; it keeps no copy of resident fields.
const Trait = preload("res://scripts/trait_type.gd")
const Skill = preload("res://scripts/skill_type.gd")
const Assignment = preload("res://scripts/resident_assignment.gd")
const ResidentData = preload("res://scripts/resident_data.gd")
const ResidentSelection = preload("res://scripts/resident_selection.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const NeedType = preload("res://scripts/need_type.gd")
const StateText = preload("res://scripts/resident_state_text.gd")
@export var show_state_numbers: bool = true
var _selection: ResidentSelection
var _control: RefCounted
var _assignment_resident: ResidentData
@onready var preferences_label: Label = _widget("Preferences")
@onready var relationships_label: Label = _widget("Relationships")
@onready var skills_label: Label = _widget("Skills")
@onready var assignment_list: VBoxContainer = _widget("Assignments")
signal work_area_requested(resident_id: String)
signal existing_area_requested(resident_id: String, area_id: StringName)
var work_place_label: Label
var area_button: Button
var area_choice: OptionButton
var clear_work_button: Button
signal workplace_requested(resident_id: String)
var workplace_button: Button
var profession_choice: OptionButton
var intent_label: Label
var summary_label: Label
@onready var home_label: Label = _widget("Home")
@onready var name_label: Label = _widget("Name")
@onready var age_label: Label = _widget("Age")
@onready var profession_label: Label = _widget("Profession")
@onready var id_label: Label = _widget("ID")
@onready var traits_label: Label = _widget("Traits")
@onready var hunger_label: Label = _widget("Hunger")
@onready var fatigue_label: Label = _widget("Fatigue")
@onready var social_label: Label = _widget("Social")
@onready var leisure_label: Label = _widget("Leisure")
@onready var mood_label: Label = _widget("Mood")
@onready var activity_label: Label = _widget("Activity")
@onready var close_button: Button = _widget("Close")

func _ready() -> void:
	hide()
	summary_label = _widget("Summary")
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	profession_choice = OptionButton.new()
	profession_choice.fit_to_longest_item=false
	profession_choice.clip_text=true
	profession_choice.focus_mode = Control.FOCUS_NONE
	for profession in Profession.Type.values():
		profession_choice.add_item(Profession.display_name(profession), profession)
	_work_body().add_child(profession_choice)
	profession_choice.item_selected.connect(_on_profession_selected)
	work_place_label = Label.new()
	work_place_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	area_button = Button.new()
	area_button.text = "Назначить область"
	area_button.pressed.connect(func(): work_area_requested.emit(_selection.selected_resident.id))
	workplace_button=Button.new()
	workplace_button.text="Назначить рабочее здание"
	workplace_button.pressed.connect(func(): workplace_requested.emit(_selection.selected_resident.id))
	area_choice = OptionButton.new()
	area_choice.fit_to_longest_item=false
	area_choice.clip_text=true
	area_choice.item_selected.connect(_choose_area)
	clear_work_button = Button.new()
	clear_work_button.text = "Снять место работы"
	clear_work_button.pressed.connect(_clear_work_assignment)
	for control in [work_place_label,workplace_button,area_button,area_choice,clear_work_button]:
		_work_body().add_child(control)
	intent_label = Label.new()
	intent_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_work_body().add_child(intent_label)
	get_node("%SkillsToggle").toggled.connect(skills_label.set_visible)
	get_node("%DiaryToggle").toggled.connect(_widget("Diary").set_visible)
	get_node("%ClearHome").pressed.connect(_clear_home)

func bind_control(control: RefCounted) -> void:
	if _control != null and _control.home_changed.is_connected(_on_home_changed): _control.home_changed.disconnect(_on_home_changed)
	if _control != null and _control.residents_changed.is_connected(_on_roster_changed): _control.residents_changed.disconnect(_on_roster_changed)
	if _control != null and _control.has_signal("work_assignment_changed") and _control.work_assignment_changed.is_connected(_work_changed): _control.work_assignment_changed.disconnect(_work_changed)
	if _control != null and _control.get("work_areas") != null and _control.get("work_areas").changed.is_connected(_areas_changed): _control.get("work_areas").changed.disconnect(_areas_changed)
	if _control != null and _control.get("work_areas") != null and _control.get("work_areas").presentation_changed.is_connected(_areas_changed): _control.get("work_areas").presentation_changed.disconnect(_areas_changed)
	_control = control
	if _control.has_signal("work_assignment_changed"): _control.work_assignment_changed.connect(_work_changed)
	if _control.get("work_areas") != null: _control.get("work_areas").changed.connect(_areas_changed)
	if _control.get("work_areas") != null: _control.get("work_areas").presentation_changed.connect(_areas_changed)
	_areas_changed()
	_control.residents_changed.connect(_on_roster_changed)
	_on_roster_changed()
	_control.home_changed.connect(_on_home_changed)
	_refresh_home()
	_refresh_assignments()

func _on_profession_selected(index: int) -> void:
	if _control != null and _selection != null and _selection.selected_resident != null:
		_control.assign_profession(_selection.selected_resident.id, profession_choice.get_item_id(index))
	_refresh_work_place()
	_refresh()

func bind_selection(selection: ResidentSelection) -> void:
	if _selection != null and _selection.selection_changed.is_connected(_on_selection_changed): _selection.selection_changed.disconnect(_on_selection_changed)
	_selection = selection
	_selection.selection_changed.connect(_on_selection_changed)
	_on_selection_changed()

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	_refresh_elapsed += delta
	if _refresh_elapsed < 0.25: return
	_refresh_elapsed = 0.0
	_refresh()
	_refresh_home()
	_refresh_work_place()
	if get_node("%Relations").is_visible_in_tree(): _refresh_known_relationships()

func _refresh() -> void:
	refresh_count += 1
	if _selection == null or _selection.selected_resident == null:
		return
	var data = _selection.selected_resident
	summary_label.text = Profession.display_name(data.profession)
	activity_label.text = "Занятие: " + _activity_text(data.activity)
	name_label.text = "Имя: " + data.resident_name
	age_label.text = "Возраст: %d" % data.age
	profession_label.text = "Профессия: " + Profession.display_name(data.profession)
	profession_choice.select(profession_choice.get_item_index(data.profession))
	profession_choice.disabled = _control == null
	var intent = _control.current_intent(data.id) if _control != null else null
	var reason: String = String(intent.reason_id) if intent != null else ""
	var handling: StringName = intent.resource_handling if intent != null else &""
	intent_label.text = "Действие: " + (("Погрузка" if handling==&"loading" else "Разгрузка") if not handling.is_empty() else _intent_text(reason))
	intent_label.visible = not reason.is_empty() and not (reason == "social" and data.activity == Activity.Type.TALKING) and not (reason == "eat" and data.activity == Activity.Type.EATING) and not (reason == "leisure" and data.activity == Activity.Type.RELAXING)
	id_label.text = "ID: " + data.id
	hunger_label.text = _state_line("Голод", data.hunger, StateText.hunger_description(data.hunger))
	fatigue_label.text = _state_line("Усталость", data.fatigue, StateText.fatigue_description(data.fatigue))
	social_label.text = _state_line("Общение", data.get_need(NeedType.Type.SOCIAL).value, "Хочет общения" if data.get_need(NeedType.Type.SOCIAL).value >= 25 else "Достаточно общения")
	leisure_label.text = _state_line("Досуг", data.get_need(NeedType.Type.LEISURE).value, "Хочет развлечься" if data.get_need(NeedType.Type.LEISURE).value >= 25 else "Достаточно досуга")
	mood_label.text = "Настроение: %d/100 — %s" % [data.mood, StateText.mood_description(data.mood)] if show_state_numbers else "Настроение: " + StateText.mood_description(data.mood)

	refresh_work_task()

func _state_line(title: String, value: int, description: String) -> String:
	if show_state_numbers:
		return "%s: %d — %s" % [title, value, description]
	return "%s: %s" % [title, description]

func _activity_text(activity: Activity.Type) -> String:
	match activity:
		Activity.Type.TALKING: return "Разговаривает"
		Activity.Type.RELAXING: return "Развлекается"
		Activity.Type.RESTING: return "Отдыхает"
		Activity.Type.MOVING: return "Идёт"
		Activity.Type.SLEEPING: return "Спит"
		Activity.Type.WORKING: return "Работает"
		Activity.Type.EATING: return "Ест"
		Activity.Type.HAULING: return "Несёт груз"
		_: return "Бездельничает"

func _on_selection_changed() -> void:
	_disconnect_need_signals()
	if _assignment_resident != null:
		_assignment_resident.assignments_changed.disconnect(_refresh_assignments)
		_assignment_resident.skill_changed.disconnect(_on_skill_changed)
		_assignment_resident.traits_changed.disconnect(_refresh_traits)
		_assignment_resident.relationship_changed.disconnect(_on_relationship_changed)
		_assignment_resident.diary_changed.disconnect(_refresh_diary)
		_assignment_resident.trait_preferences_changed.disconnect(_on_preferences_changed)
	_assignment_resident = _selection.selected_resident
	_relationship_snapshot = [null]
	if _assignment_resident != null:
		_connect_need_signals()
		_assignment_resident.assignments_changed.connect(_refresh_assignments)
		_assignment_resident.skill_changed.connect(_on_skill_changed)
		_assignment_resident.traits_changed.connect(_refresh_traits)
		_assignment_resident.relationship_changed.connect(_on_relationship_changed)
		_assignment_resident.diary_changed.connect(_refresh_diary)
		_assignment_resident.trait_preferences_changed.connect(_on_preferences_changed)
	_refresh_skills()
	_refresh_traits()
	_refresh_preferences()
	_refresh_diary()
	_on_roster_changed()
	_widget("Scroll").scroll_vertical = 0
	_refresh_assignments()
	_refresh_home()
	_refresh_work_place()
	_refresh()

func _refresh_assignments() -> void:
	assignment_rebuild_count += 1
	# Rebuild on assignment/selection events only, never from the per-frame card refresh.
	for child in assignment_list.get_children():
		assignment_list.remove_child(child)
		child.queue_free()
	if _assignment_resident == null: return
	for assignment in _assignment_resident.assignments:
		if assignment.state not in [Assignment.State.QUEUED, Assignment.State.ACTIVE, Assignment.State.SUSPENDED]: continue
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		row.set_meta("assignment_id", assignment.id)
		assignment_list.add_child(row)
		var description := Label.new()
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.text = _control.describe_assignment(_assignment_resident.id, assignment.id) if _control != null else "Поручение"
		row.add_child(description)
		var state_label := Label.new()
		state_label.text = _assignment_state_text(assignment.state)
		row.add_child(state_label)
		var cancel_button := Button.new()
		cancel_button.text = "Отменить"
		cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_END
		cancel_button.add_theme_font_size_override("font_size", 14)
		cancel_button.focus_mode = Control.FOCUS_NONE
		cancel_button.disabled = _control == null
		cancel_button.pressed.connect(_cancel_assignment.bind(_assignment_resident.id, assignment.id))
		row.add_child(cancel_button)
	if assignment_list.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "Поручений нет"
		assignment_list.add_child(empty)

func _cancel_assignment(resident_id: String, assignment_id: StringName) -> void:
	if _control != null: _control.cancel_assignment(resident_id, assignment_id)

func _assignment_state_text(state: Assignment.State) -> String:
	match state:
		Assignment.State.QUEUED: return "Ожидает"
		Assignment.State.ACTIVE: return "Выполняется"
		Assignment.State.SUSPENDED: return "Приостановлено"
		_: return ""

func _intent_text(reason: String) -> String:
	var labels := {"chop_tree": "Рубка дерева", "plant_tree": "Посадка дерева", "mine_rock": "Добыча камня", "recipe_work": "Производственная работа", "builder_wait_materials": "Ожидает строительные материалы", "builder_source": "Идёт за строительным материалом", "builder_delivery": "Доставляет материалы на стройку", "builder_site": "Строительная работа", "eat": "Идёт поесть", "social": "Идёт к собеседнику", "leisure": "Отдыхает", "wander": "Прогулка", "day_work": "Работа по расписанию", "night_home": "Возвращается домой", "night_outdoor": "Спит снаружи", "haul_source": "Идёт за грузом", "haul_destination": "Доставляет груз", "player_move": "Идёт по приказу игрока", "critical_sleep": "Восстанавливает силы", "rest": "Отдыхает"}
	return labels.get(reason, reason)


func _on_home_changed(resident_id: String, _previous: StringName, _current: StringName) -> void:
	if _selection != null and _selection.selected_resident != null and _selection.selected_resident.id == resident_id: _refresh_home()

func _refresh_home() -> void:
	var home: RefCounted = _control.get_home(_selection.selected_resident.id) if _control != null and _selection != null and _selection.selected_resident != null else null
	home_label.text = "Дом: %s (%s)" % [home.display_name, home.id] if home != null else "Дом: Нет дома"
	get_node("%ClearHome").visible = home != null

func _on_skill_changed(_skill: int, _amount: int, _previous_level: int) -> void:
	_refresh_skills()
func _refresh_skills() -> void:
	if _assignment_resident == null:
		skills_label.text = ""
		return
	var lines := PackedStringArray(["Навыки"])
	for skill in Skill.Type.values():
		lines.append("%s: ур. %d (%d XP)" % [Skill.display_name(skill), _assignment_resident.get_skill_level(skill), _assignment_resident.get_skill_xp(skill)])
	skills_label.text = "\n".join(lines)

func _refresh_traits() -> void:
	var names := PackedStringArray()
	if _assignment_resident != null:
		for trait_type in _assignment_resident.traits: names.append("• " + Trait.display_name(trait_type))
	traits_label.text = "Черты\n" + "\n".join(names) if not names.is_empty() else "Черты: нет"

func _on_relationship_changed(_other_id: StringName) -> void:
	_refresh_relationships()
func _refresh_relationships() -> void:
	_refresh_known_relationships()

func _on_preferences_changed() -> void:
	_refresh_preferences()
	_refresh_relationships()
func _refresh_preferences() -> void:
	var liked := "Нет"
	var disliked := "Нет"
	if _assignment_resident != null:
		liked = _preference_names(_assignment_resident.liked_traits)
		disliked = _preference_names(_assignment_resident.disliked_traits)
	preferences_label.text = "Предпочтения\nНравятся: %s\nНе нравятся: %s" % [liked, disliked]
func _preference_names(list: Array[Trait.Type]) -> String:
	var names := PackedStringArray()
	for trait_type in list: names.append(Trait.display_name(trait_type))
	return ", ".join(names) if not names.is_empty() else "Нет"
func _on_roster_changed() -> void:
	_refresh_relationships()


func _refresh_diary() -> void:
	var lines := PackedStringArray(["Дневник"])
	if _assignment_resident != null:
		for entry in _assignment_resident.diary_entries:
			if (clock == null or floori(float(entry.created_minute)/1440.0) != floori(float(clock.total_minutes)/1440.0)): continue
			lines.append("• %s%s" % [entry.text, " (ключевая)" if entry.importance == Diary.Importance.KEY else " (временная)"])
	if lines.size() == 1: lines.append("За текущий день записей нет")
	_widget("Diary").text = "\n".join(lines)

func _work_changed(_resident_id: String) -> void: _refresh_work_place()
func _areas_changed() -> void:
	if area_choice == null: return
	area_choice.clear()
	area_choice.add_item("Использовать созданную область…")
	if _control != null and _control.get("work_areas") != null:
		for area in _control.get("work_areas").all():
			area_choice.add_item("%s (%s)" % [area.display_name,area.id])
			area_choice.set_item_metadata(area_choice.item_count-1,area.id)
	_refresh_work_place()
func _choose_area(index: int) -> void:
	if index > 0 and _selection != null and _selection.selected_resident != null:
		existing_area_requested.emit(_selection.selected_resident.id,area_choice.get_item_metadata(index))
	area_choice.select(0)
func _clear_work_assignment() -> void:
	var resident = _selection.selected_resident if _selection != null else null
	if resident != null and _control != null and _control.get_resident(resident.id)==resident: _control.clear_work_assignment(resident.id)
func _refresh_work_place() -> void:
	if work_place_label == null or _selection == null or _selection.selected_resident == null: return
	var data = _selection.selected_resident
	var label := "Носильщик без рабочего места" if data.profession == Profession.Type.PORTER else "Место работы не назначено"
	if _control != null and not data.work_location_id.is_empty():
		var building = _control.get_building(data.work_location_id)
		if building != null: label = "При здании: %s (%s)" % [building.display_name,building.id]
	elif _control != null and _control.get("work_areas") != null and _control.get("work_areas").get_area(data.work_area_id) != null:
		var area = _control.work_areas.get_area(data.work_area_id)
		label = "Свободная область: %s (%s)" % [area.display_name,area.id]
	work_place_label.text = label
	var enabled: bool = _control != null and _control.can_assign_work_area(data.id)
	workplace_button.visible = data.profession not in [Profession.Type.NONE,Profession.Type.BUILDER]
	area_button.visible = enabled
	area_choice.visible = enabled
	clear_work_button.visible = enabled or data.profession == Profession.Type.PORTER or ((not data.work_location_id.is_empty() or not data.work_area_id.is_empty()))
	clear_work_button.text = "Снять назначение области" if not data.work_area_id.is_empty() else "Снять место работы"

var job_provider: Callable
var _needs_connected: Array = []
var _relationship_snapshot: Array = [null]
var relationship_rebuild_count := 0
var assignment_rebuild_count := 0
func _work_body() -> VBoxContainer:
	return get_node("%WorkBody")
func apply_presentation(expanded: bool, tab: StringName) -> void:
	get_node("%Scroll").visible = expanded
	get_node("%Bio").visible = tab == &"bio"
	get_node("%Work").visible = tab == &"work"
	get_node("%Relations").visible = tab == &"relations"
func _clear_home() -> void:
	if _control != null and _selection.selected_resident != null:
		_control.clear_home(_selection.selected_resident.id)
func _connect_need_signals() -> void:
	_assignment_resident.activity_changed.connect(_refresh)
	for need in _assignment_resident.needs.values():
		need.changed.connect(_refresh)
		_needs_connected.append(need)
func _disconnect_need_signals() -> void:
	for need in _needs_connected:
		if need.changed.is_connected(_refresh): need.changed.disconnect(_refresh)
	_needs_connected.clear()
	if _assignment_resident != null and _assignment_resident.activity_changed.is_connected(_refresh): _assignment_resident.activity_changed.disconnect(_refresh)
func _refresh_known_relationships() -> void:
	var snapshot: Array = []
	if _assignment_resident != null and _control != null:
		for id in _assignment_resident.relationships:
			var other = _control.get_resident(String(id))
			if other != null: snapshot.append([other.id, other.resident_name, _assignment_resident.get_opinion(id)])
	if snapshot == _relationship_snapshot: return
	relationship_rebuild_count += 1
	_relationship_snapshot = snapshot
	var list: VBoxContainer = get_node("%RelationshipLinks")
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	relationships_label.text = "Пока нет известных отношений" if snapshot.is_empty() else "Направленные отношения"
	for entry in snapshot:
		var button := Button.new()
		button.text = "%s: %+d" % [entry[1], entry[2]]
		button.clip_text = true
		if str(entry[1]).length()>24:
			var full_name := Label.new()
			full_name.text = str(entry[1])
			full_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			list.add_child(full_name)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_select_related.bind(entry[0]))
		list.add_child(button)
func _select_related(id: String) -> void:
	var current = _control.get_resident(id) if _control != null else null
	if current != null: _selection.select(current)
func refresh_work_task() -> void:
	if _assignment_resident == null or _control == null: return
	var intent = _control.current_intent(_assignment_resident.id)
	var reason: String = String(intent.reason_id) if intent != null else ""
	var job = job_provider.call(_assignment_resident.id) if job_provider.is_valid() else null
	if job != null and job.is_active():
		var destination = _control.get_building(job.destination_location_id)
		var title: String = destination.display_name if destination != null else String(job.destination_location_id)
		var stage: String = _intent_text(reason)
		if intent != null and not intent.resource_handling.is_empty(): stage = "Погрузка" if intent.resource_handling == &"loading" else "Разгрузка"
		intent_label.text = "Рабочая задача: %s ×%d → %s\n%s" % [preload("res://scripts/resource_type.gd").display_name(job.resource_type), job.amount, title, stage]
	else:
		var is_work := reason.begins_with("builder_") or reason in ["haul_source","haul_destination","chop_tree","plant_tree","mine_rock","recipe_work","day_work"]
		intent_label.text = "Рабочая задача: " + (_intent_text(reason) if is_work else "нет активной задачи")
	intent_label.show()
func _exit_tree() -> void:
	_disconnect_need_signals()
	if _assignment_resident != null:
		for pair in [["assignments_changed",_refresh_assignments],["skill_changed",_on_skill_changed],["traits_changed",_refresh_traits],["relationship_changed",_on_relationship_changed],["diary_changed",_refresh_diary],["trait_preferences_changed",_on_preferences_changed]]:
			if _assignment_resident.is_connected(pair[0],pair[1]): _assignment_resident.disconnect(pair[0],pair[1])
	if _control != null:
		for pair in [["home_changed",_on_home_changed],["residents_changed",_on_roster_changed],["work_assignment_changed",_work_changed]]:
			if _control.is_connected(pair[0],pair[1]): _control.disconnect(pair[0],pair[1])
		if _control.get("work_areas") != null and _control.get("work_areas").changed.is_connected(_areas_changed): _control.get("work_areas").changed.disconnect(_areas_changed)
		if _control.get("work_areas") != null and _control.get("work_areas").presentation_changed.is_connected(_areas_changed): _control.get("work_areas").presentation_changed.disconnect(_areas_changed)
	if _selection != null and _selection.selection_changed.is_connected(_on_selection_changed): _selection.selection_changed.disconnect(_on_selection_changed)
