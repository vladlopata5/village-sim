extends PanelContainer
## Ordered TAB and QUICK_WINDOW entries; this is presentation state, not tool state.
signal definition_selected(definition: RefCounted)
signal road_selected
signal collapse_changed(collapsed: bool)
signal quick_window_requested(id: StringName)
enum Kind { TAB, QUICK_WINDOW }
var sections: Array[Dictionary] = []
var buttons: Dictionary = {}
var collapsed := true
var active_tab: StringName = &""
var collapse_button: Button
var catalogue: VBoxContainer
const CATALOG_SIZE = Vector2(720,156)
const STRIP_HEIGHT = 64.0
const CATALOG_GAP = 8.0
var strip: PanelContainer
var _column: Control
var _contents: PanelContainer
var _row: HBoxContainer
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	_column=Control.new()
	_column.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(_column)
	_contents=PanelContainer.new()
	_contents.theme_type_variation=&"GreenPanel"
	_column.add_child(_contents)
	strip=PanelContainer.new()
	strip.theme_type_variation=&"GreenStrip"
	_column.add_child(strip)
	resized.connect(_layout_surfaces)
	catalogue=preload("res://scenes/ui/construction_catalog.tscn").instantiate()
	catalogue.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_contents.add_child(catalogue)
	catalogue.definition_selected.connect(definition_selected.emit)
	catalogue.road_selected.connect(road_selected.emit)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	scroll.custom_minimum_size.y=36
	scroll.mouse_force_pass_scroll_events=false
	var menu_margin := MarginContainer.new()
	# The surface extends under Blue; the scrollable buttons retain a safe visible lane.
	menu_margin.add_theme_constant_override("margin_right",336)
	strip.add_child(menu_margin)
	menu_margin.add_child(scroll)
	_row=HBoxContainer.new()
	scroll.add_child(_row)
	register_section(&"construction","Строительство",Kind.TAB,catalogue)
	register_section(&"residents","Жители",Kind.QUICK_WINDOW)
	collapse_button=buttons[&"construction"]
	_apply()
	_layout_surfaces()
func _layout_surfaces() -> void:
	_contents.position=Vector2.ZERO
	_contents.size=CATALOG_SIZE
	strip.position=Vector2(0,0.0 if collapsed else CATALOG_SIZE.y+CATALOG_GAP)
	strip.size=Vector2(size.x,STRIP_HEIGHT)
func input_surfaces() -> Array[Control]:
	return [strip,_contents]
func register_section(id: StringName, title: String, kind: Kind, content: Control=null) -> void:
	assert(not buttons.has(id))
	assert(kind!=Kind.TAB or content!=null)
	sections.append({"id":id,"kind":kind,"content":content})
	if content!=null:
		if content.get_parent()!=_contents: content.reparent(_contents)
		content.visible=active_tab==id
	var button := Button.new()
	button.text=title if kind==Kind.TAB else "↗ "+title
	button.theme_type_variation = &"GreenTab" if kind==Kind.TAB else &"QuickButton"
	button.focus_mode=Control.FOCUS_NONE
	button.toggle_mode=kind==Kind.TAB
	button.pressed.connect(_activate.bind(id))
	_row.add_child(button)
	buttons[id]=button
func _activate(id: StringName) -> void:
	for section in sections:
		if section.id!=id: continue
		if section.kind==Kind.QUICK_WINDOW: quick_window_requested.emit(id)
		else:
			var previous := active_tab
			active_tab=&"" if active_tab==id else id
			collapsed=active_tab==&""
			_apply()
			if previous==&"construction" or active_tab==&"construction": collapse_changed.emit(active_tab!=&"construction")
func set_collapsed(value: bool) -> void:
	if collapsed==value: return
	collapsed=value
	active_tab=&"" if value else &"construction"
	_apply()
	collapse_changed.emit(value)
func _apply() -> void:
	_layout_surfaces()
	_contents.visible=not collapsed
	for section in sections:
		if section.kind==Kind.TAB:
			section.content.visible=section.id==active_tab
			buttons[section.id].set_pressed_no_signal(section.id==active_tab)
