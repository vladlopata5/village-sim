extends PanelContainer
## The card reads the selection's data; it keeps no copy of resident fields.
const ResidentSelection = preload("res://scripts/resident_selection.gd")
var _selection: ResidentSelection
@onready var name_label: Label = $Margin/Column/Name
@onready var age_label: Label = $Margin/Column/Age
@onready var profession_label: Label = $Margin/Column/Profession
@onready var id_label: Label = $Margin/Column/ID
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
	name_label.text = "Имя: " + data.resident_name
	age_label.text = "Возраст: %d" % data.age
	profession_label.text = "Профессия: " + data.profession
	id_label.text = "ID: " + data.id
	show()

func _close() -> void:
	if _selection != null:
		_selection.clear()
