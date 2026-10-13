extends VBoxContainer
## A catalogue chooses existing tools. It neither places nor purchases buildings.
signal definition_selected(definition: RefCounted)
signal road_selected
const Data = preload("res://scripts/ui/construction_catalog_data.gd")
var categories: Array = Data.categories()
var category_id: StringName = &"production"
var category_buttons: Dictionary = {}
var tiles: Dictionary = {}
var entries: Dictionary = {}
var _categories: HBoxContainer
var _scroll: ScrollContainer
var _grid: GridContainer
func _ready() -> void:
	_categories = HBoxContainer.new()
	add_child(_categories)
	for category in categories:
		var button := Button.new()
		button.text = category.title
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(select_category.bind(category.id))
		_categories.add_child(button)
		category_buttons[category.id] = button
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_force_pass_scroll_events = false
	add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid)
	for category in categories:
		for entry in category.entries:
			entries[entry.id] = entry
			var tile := Button.new()
			tile.custom_minimum_size = Vector2(160,96)
			tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tile.focus_mode = Control.FOCUS_NONE
			tile.toggle_mode = true
			tile.pressed.connect(_activate.bind(entry.id))
			tile.set_meta("category",category.id)
			_grid.add_child(tile)
			var column := VBoxContainer.new()
			column.name="Content"
			tile.add_child(column)
			column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			column.offset_left=6; column.offset_right=-6
			column.offset_top=6; column.offset_bottom=-6
			column.mouse_filter=Control.MOUSE_FILTER_IGNORE
			var icon := TextureRect.new()
			icon.name="Icon"
			icon.texture=load("res://assets/ui/catalog/%s.svg" % entry.icon)
			icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size=Vector2(32,32)
			icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
			column.add_child(icon)
			var title := Label.new()
			title.name="Title"
			title.text=entry.name
			title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			title.size_flags_vertical=Control.SIZE_EXPAND_FILL
			title.add_theme_font_size_override("font_size",14)
			title.mouse_filter=Control.MOUSE_FILTER_IGNORE
			column.add_child(title)
			tiles[entry.id]=tile
	select_category(category_id)
func select_category(id: StringName) -> void:
	if not category_buttons.has(id): return
	category_id=id
	for key in category_buttons: category_buttons[key].set_pressed_no_signal(key==id)
	for tile in tiles.values(): tile.visible=tile.get_meta("category")==id
	_scroll.scroll_vertical=0
func _activate(id: StringName) -> void:
	var entry: Dictionary=entries[id]
	if entry.action==&"building": definition_selected.emit(entry.definition)
	else: road_selected.emit()
func sync_tool(definition: RefCounted, road_active: bool) -> void:
	for id in entries:
		var entry: Dictionary=entries[id]
		tiles[id].set_pressed_no_signal(entry.get("definition")==definition if entry.action==&"building" else road_active)
func description(definition: RefCounted) -> String:
	for entry in entries.values():
		if entry.action==&"building" and entry.definition.type==definition.type: return entry.description
	return ""
func tile_for_type(type: int) -> Button:
	return tiles.get(StringName("building_%d" % type))
