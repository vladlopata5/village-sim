extends PanelContainer
## The card reads the selection's data; it keeps no copy of resident fields.
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
@onready var assignment_list: VBoxContainer = $Margin/Column/Scroll/Content/Assignments
var profession_choice: OptionButton
var intent_label: Label
@onready var name_label: Label = $Margin/Column/Scroll/Content/Name
@onready var age_label: Label = $Margin/Column/Scroll/Content/Age
@onready var profession_label: Label = $Margin/Column/Scroll/Content/Profession
@onready var id_label: Label = $Margin/Column/Scroll/Content/ID
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
	profession_choice = OptionButton.new()
	profession_choice.focus_mode = Control.FOCUS_NONE
	for profession in Profession.Type.values():
		profession_choice.add_item(Profession.display_name(profession), profession)
	$Margin/Column/Scroll/Content.add_child(profession_choice)
	$Margin/Column/Scroll/Content.move_child(profession_choice, 3)
	profession_choice.item_selected.connect(_on_profession_selected)
	intent_label = Label.new()
	intent_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	$Margin/Column/Scroll/Content.add_child(intent_label)
	$Margin/Column/Scroll/Content.move_child(intent_label, activity_label.get_index() + 1)

func bind_control(control: RefCounted) -> void:
	_control = control
	_refresh_assignments()

func _on_profession_selected(index: int) -> void:
	if _control != null and _selection != null and _selection.selected_resident != null:
		_control.assign_profession(_selection.selected_resident.id, profession_choice.get_item_id(index))
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
	activity_label.text = "Занятие: " + _activity_text(data.activity)
	name_label.text = "Имя: " + data.resident_name
	age_label.text = "Возраст: %d" % data.age
	profession_label.text = "Профессия: " + Profession.display_name(data.profession)
	profession_choice.select(profession_choice.get_item_index(data.profession))
	profession_choice.disabled = _control == null
	var intent = _control.current_intent(data.id) if _control != null else null
	var reason: String = String(intent.reason_id) if intent != null else ""
	intent_label.text = "Действие: " + (reason if not reason.is_empty() else _activity_text(data.activity))
	id_label.text = "ID: " + data.id
	hunger_label.text = _state_line("Голод", data.hunger, StateText.hunger_description(data.hunger))
	fatigue_label.text = _state_line("Усталость", data.fatigue, StateText.fatigue_description(data.fatigue))
	social_label.text = _state_line("Общение", data.get_need(NeedType.Type.SOCIAL).value, "Хочет общения" if data.get_need(NeedType.Type.SOCIAL).value >= 25 else "Достаточно общения")
	leisure_label.text = _state_line("Досуг", data.get_need(NeedType.Type.LEISURE).value, "Хочет развлечься" if data.get_need(NeedType.Type.LEISURE).value >= 25 else "Достаточно досуга")
	mood_label.text = _state_line("Настроение", data.mood, StateText.mood_description(data.mood))
	var trait_names := PackedStringArray()
	for trait_definition in data.traits:
		trait_names.append("• " + trait_definition.display_name)
	traits_label.text = "Известные черты:\n" + "\n".join(trait_names) if not trait_names.is_empty() else "Известные черты: нет"
	show()

func _close() -> void:
	if _selection != null:
		_selection.clear()

func _state_line(title: String, value: int, description: String) -> String:
	if show_state_numbers:
		return "%s: %d/100 — %s" % [title, value, description]
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
	_assignment_resident = _selection.selected_resident
	if _assignment_resident != null:
		_assignment_resident.assignments_changed.connect(_refresh_assignments)
	$Margin/Column/Scroll.scroll_vertical = 0
	_refresh_assignments()
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
