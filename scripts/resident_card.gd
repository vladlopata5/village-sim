extends PanelContainer
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
var _preference_targets: Array[ResidentData] = []
@onready var preferences_label: Label = $Margin/Column/Scroll/Content/Preferences
@onready var relationships_label: Label = $Margin/Column/Scroll/Content/Relationships
@onready var skills_label: Label = $Margin/Column/Scroll/Content/Skills
@onready var assignment_list: VBoxContainer = $Margin/Column/Scroll/Content/Assignments
signal work_area_requested(resident_id: String)
var work_place_label: Label
var area_button: Button
var area_choice: OptionButton
var clear_work_button: Button
var profession_choice: OptionButton
var intent_label: Label
var summary_label: Label
@onready var home_label: Label = $Margin/Column/Scroll/Content/Home
@onready var name_label: Label = $Margin/Column/Scroll/Content/Name
@onready var age_label: Label = $Margin/Column/Scroll/Content/Metadata/Age
@onready var profession_label: Label = $Margin/Column/Scroll/Content/Profession
@onready var id_label: Label = $Margin/Column/Scroll/Content/Metadata/ID
@onready var traits_label: Label = $Margin/Column/Scroll/Content/Traits
@onready var hunger_label: Label = $Margin/Column/Scroll/Content/Hunger
@onready var fatigue_label: Label = $Margin/Column/Scroll/Content/Fatigue
@onready var social_label: Label = $Margin/Column/Scroll/Content/Social
@onready var leisure_label: Label = $Margin/Column/Scroll/Content/Leisure
@onready var mood_label: Label = $Margin/Column/Scroll/Content/Mood
@onready var activity_label: Label = $Margin/Column/Scroll/Content/Activity
@onready var close_button: Button = $Margin/Column/Close

func _ready() -> void:
	hide()
	close_button.pressed.connect(_close)
	summary_label = Label.new()
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	$Margin/Column/Scroll/Content.add_child(summary_label)
	$Margin/Column/Scroll/Content.move_child(summary_label, 1)
	profession_choice = OptionButton.new()
	profession_choice.focus_mode = Control.FOCUS_NONE
	for profession in Profession.Type.values():
		profession_choice.add_item(Profession.display_name(profession), profession)
	$Margin/Column/Scroll/Content.add_child(profession_choice)
	$Margin/Column/Scroll/Content.move_child(profession_choice, 3)
	profession_choice.item_selected.connect(_on_profession_selected)
	work_place_label = Label.new()
	work_place_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	area_button = Button.new()
	area_button.text = "Назначить рабочую область"
	area_button.pressed.connect(func(): work_area_requested.emit(_selection.selected_resident.id))
	area_choice = OptionButton.new()
	area_choice.item_selected.connect(_choose_area)
	clear_work_button = Button.new()
	clear_work_button.text = "Снять место работы"
	clear_work_button.pressed.connect(func(): _control.clear_work_assignment(_selection.selected_resident.id))
	for control in [work_place_label,area_button,area_choice,clear_work_button]:
		$Margin/Column/Scroll/Content.add_child(control)
		$Margin/Column/Scroll/Content.move_child(control,profession_choice.get_index()+1+[work_place_label,area_button,area_choice,clear_work_button].find(control))
	intent_label = Label.new()
	intent_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	$Margin/Column/Scroll/Content.add_child(intent_label)
	$Margin/Column/Scroll/Content.move_child(intent_label, mood_label.get_index() + 1)

func bind_control(control: RefCounted) -> void:
	if _control != null and _control.home_changed.is_connected(_on_home_changed): _control.home_changed.disconnect(_on_home_changed)
	if _control != null and _control.residents_changed.is_connected(_on_roster_changed): _control.residents_changed.disconnect(_on_roster_changed)
	if _control != null and _control.has_signal("work_assignment_changed") and _control.work_assignment_changed.is_connected(_work_changed): _control.work_assignment_changed.disconnect(_work_changed)
	if _control != null and _control.get("work_areas") != null and _control.get("work_areas").changed.is_connected(_areas_changed): _control.get("work_areas").changed.disconnect(_areas_changed)
	_control = control
	if _control.has_signal("work_assignment_changed"): _control.work_assignment_changed.connect(_work_changed)
	if _control.get("work_areas") != null: _control.get("work_areas").changed.connect(_areas_changed)
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
	_selection = selection
	_selection.selection_changed.connect(_on_selection_changed)
	_on_selection_changed()

func _process(_delta: float) -> void:
	if visible:
		_refresh()

func _refresh() -> void:
	if _selection == null or _selection.selected_resident == null:
		hide()
		return
	var data = _selection.selected_resident
	summary_label.text = "%s • %s" % [Profession.display_name(data.profession), _activity_text(data.activity)]
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

	show()

func _close() -> void:
	if _selection != null:
		_selection.clear()

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
	if _assignment_resident != null:
		_assignment_resident.assignments_changed.disconnect(_refresh_assignments)
		_assignment_resident.skill_changed.disconnect(_on_skill_changed)
		_assignment_resident.traits_changed.disconnect(_refresh_traits)
		_assignment_resident.relationship_changed.disconnect(_on_relationship_changed)
		_assignment_resident.diary_changed.disconnect(_refresh_diary)
		_assignment_resident.trait_preferences_changed.disconnect(_on_preferences_changed)
	_assignment_resident = _selection.selected_resident
	if _assignment_resident != null:
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
	$Margin/Column/Scroll.scroll_vertical = 0
	_refresh_assignments()
	_refresh_home()
	_refresh_work_place()
	_refresh()

func _refresh_assignments() -> void:
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
	var labels := {"chop_tree": "Рубка дерева", "builder_source": "Идёт за строительным материалом", "builder_delivery": "Доставляет материалы на стройку", "builder_site": "Строительная работа", "eat": "Идёт поесть", "social": "Идёт к собеседнику", "leisure": "Отдыхает", "wander": "Прогулка", "day_work": "Работа по расписанию", "night_home": "Возвращается домой", "night_outdoor": "Спит снаружи", "haul_source": "Идёт за грузом", "haul_destination": "Доставляет груз", "player_move": "Идёт по приказу игрока", "critical_sleep": "Восстанавливает силы", "rest": "Отдыхает"}
	return labels.get(reason, reason)


func _on_home_changed(resident_id: String, _previous: StringName, _current: StringName) -> void:
	if _selection != null and _selection.selected_resident != null and _selection.selected_resident.id == resident_id: _refresh_home()

func _refresh_home() -> void:
	var home: RefCounted = _control.get_home(_selection.selected_resident.id) if _control != null and _selection != null and _selection.selected_resident != null else null
	home_label.text = "Дом: %s (%s)" % [home.display_name, home.id] if home != null else "Дом: Нет дома"

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
	var lines := PackedStringArray(["Отношения"])
	if _assignment_resident != null and _control != null:
		for other in _control.get_residents():
			if other.id == _assignment_resident.id: continue
			var opinion: int = _assignment_resident.get_opinion(StringName(other.id))
			var number := "%+d" % opinion if opinion > 0 else "%d" % opinion
			var preference: int = _assignment_resident.get_trait_preference_score(other)
			var preference_number := "%+d" % preference if preference > 0 else "%d" % preference
			lines.append("%s: %s • Предпочтение: %s" % [other.resident_name, number, preference_number])
	if lines.size() == 1: lines.append("Нет других жителей")
	relationships_label.text = "\n".join(lines)

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
	for other in _preference_targets: other.traits_changed.disconnect(_refresh_relationships)
	_preference_targets.clear()
	if _assignment_resident != null and _control != null:
		for other in _control.get_residents():
			if other.id == _assignment_resident.id: continue
			_preference_targets.append(other)
			other.traits_changed.connect(_refresh_relationships)
	_refresh_relationships()


func _refresh_diary() -> void:
	var lines := PackedStringArray(["Дневник"])
	if _assignment_resident != null:
		for entry in _assignment_resident.diary_entries:
			lines.append("• %s%s" % [entry.text, " (ключевая)" if entry.importance == Diary.Importance.KEY else " (временная)"])
	if lines.size() == 1: lines.append("Записей нет")
	$Margin/Column/Scroll/Content/Diary.text = "\n".join(lines)

func _work_changed(_resident_id: String) -> void: _refresh_work_place()
func _areas_changed() -> void:
	if area_choice == null: return
	area_choice.clear()
	area_choice.add_item("Использовать созданную область…")
	if _control != null and _control.get("work_areas") != null:
		for area in _control.get("work_areas").all():
			area_choice.add_item(String(area.id))
			area_choice.set_item_metadata(area_choice.item_count-1,area.id)
	_refresh_work_place()
func _choose_area(index: int) -> void:
	if index > 0 and _selection != null and _selection.selected_resident != null:
		_control.assign_work_area(_selection.selected_resident.id,area_choice.get_item_metadata(index))
	area_choice.select(0)
func _refresh_work_place() -> void:
	if work_place_label == null or _selection == null or _selection.selected_resident == null: return
	var data = _selection.selected_resident
	var label := "Носильщик без рабочего места" if data.profession == Profession.Type.PORTER else "Место работы не назначено"
	if _control != null and not data.work_location_id.is_empty():
		var building = _control.get_building(data.work_location_id)
		if building != null: label = "При здании: %s (%s)" % [building.display_name,building.id]
	elif _control != null and _control.get("work_areas") != null and _control.get("work_areas").get_area(data.work_area_id) != null:
		label = "Свободная область: " + String(data.work_area_id)
	work_place_label.text = label
	var enabled: bool = data.profession in [Profession.Type.LUMBERJACK,Profession.Type.MINER] and _control != null and _control.get("work_areas") != null
	area_button.visible = enabled
	area_choice.visible = enabled
	clear_work_button.visible = enabled or data.profession == Profession.Type.PORTER
