extends PanelContainer
## The card reads the selection's data; it keeps no copy of resident fields.
const ResidentSelection = preload("res://scripts/resident_selection.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const NeedType = preload("res://scripts/need_type.gd")
const StateText = preload("res://scripts/resident_state_text.gd")
@export var show_state_numbers: bool = true
var _selection: ResidentSelection
@onready var name_label: Label = $Margin/Column/Name
@onready var age_label: Label = $Margin/Column/Age
@onready var profession_label: Label = $Margin/Column/Profession
@onready var id_label: Label = $Margin/Column/ID
@onready var traits_label: Label = $Margin/Column/Traits
@onready var hunger_label: Label = $Margin/Column/Hunger
@onready var fatigue_label: Label = $Margin/Column/Fatigue
@onready var social_label: Label = $Margin/Column/Social
@onready var leisure_label: Label = $Margin/Column/Leisure
@onready var mood_label: Label = $Margin/Column/Mood
@onready var activity_label: Label = $Margin/Column/Activity
@onready var close_button: Button = $Margin/Column/Close

func _ready() -> void:
	hide()
	close_button.pressed.connect(_close)

func bind_selection(selection: ResidentSelection) -> void:
	_selection = selection
	_selection.selection_changed.connect(_refresh)
	_refresh()

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
