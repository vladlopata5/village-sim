extends PanelContainer
## Fixed outer geometry; content minimum sizes stop at the plain Control boundary.
## GameUI still owns exclusivity, close/Esc and pointer blocking.
const ORIGIN := Vector2(12,12)
const RESERVED_SPACE := Vector2(356,244) # Right card + gaps; bottom construction panel.
const MINIMUM_SIZE := Vector2(420,260)
const ROW_MINIMUM_HEIGHT := 30
var header: VBoxContainer
var title_label: Label
var table: Tree
var footer: HBoxContainer
var close_button: Button
var _root: TreeItem
var _surface: Control
var _surface_size := Vector2(-1,-1)

static func geometry_for(surface_size: Vector2) -> Rect2:
	var available := (surface_size-ORIGIN*2).max(Vector2.ZERO)
	var extent := (surface_size-RESERVED_SPACE).max(MINIMUM_SIZE).min(available)
	return Rect2(ORIGIN.min(surface_size*0.5),extent)

func _ready() -> void:
	if has_theme_stylebox("panel","WindowPanel"): theme_type_variation=&"WindowPanel"
	else:
		var style := StyleBoxFlat.new()
		style.bg_color=Color(0.12,0.15,0.13,1)
		for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]: style.set_content_margin(side,12)
		add_theme_stylebox_override("panel",style)
	# A VBox directly under PanelContainer propagates transient wrapped-text minima
	# into the window. This fixed content viewport deliberately has no such minimum.
	var content := Control.new()
	content.name="ListViewport"
	content.clip_contents=true
	add_child(content)
	var column := VBoxContainer.new()
	column.name="Column"
	content.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation",4)
	header=VBoxContainer.new()
	header.add_theme_constant_override("separation",4)
	column.add_child(header)
	title_label=Label.new()
	title_label.clip_text=true
	title_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(title_label)
	table=Tree.new()
	table.hide_root=true
	table.select_mode=Tree.SELECT_ROW
	table.column_titles_visible=true
	table.set_h_scroll_enabled(false)
	table.set_v_scroll_enabled(true)
	table.size_flags_vertical=Control.SIZE_EXPAND_FILL
	table.mouse_force_pass_scroll_events=false
	column.add_child(table)
	_root=table.create_item()
	footer=HBoxContainer.new()
	column.add_child(footer)
	var spacer := Control.new()
	spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	close_button=Button.new()
	close_button.text="Закрыть"
	close_button.focus_mode=Control.FOCUS_NONE
	close_button.pressed.connect(hide)
	footer.add_child(close_button)
	hide()
	if get_parent() is Control: mount_list_window(get_parent())

func configure_table(caption: String, table_name: String, headings: Array, ratios: Array) -> void:
	title_label.text=caption
	table.name=table_name
	table.columns=headings.size()
	for index in headings.size():
		table.set_column_title(index,headings[index])
		table.set_column_expand_ratio(index,ratios[index])

func add_footer_action(action: Control) -> void:
	footer.add_child(action)
	footer.move_child(action,footer.get_child_count()-3)

func create_list_row(id: Variant) -> TreeItem:
	var item := table.create_item(_root)
	item.set_metadata(0,id)
	item.custom_minimum_height=ROW_MINIMUM_HEIGHT
	for index in table.columns:
		item.set_autowrap_mode(index,TextServer.AUTOWRAP_OFF)
		item.set_text_overrun_behavior(index,TextServer.OVERRUN_TRIM_ELLIPSIS)
	return item

func mount_list_window(surface: Control) -> void:
	if _surface!=surface:
		if is_instance_valid(_surface): _surface.resized.disconnect(_apply_list_geometry)
		_surface=surface
		_surface.resized.connect(_apply_list_geometry)
	_apply_list_geometry()

func prepare_open() -> void:
	if is_instance_valid(_surface) and _surface.size!=_surface_size: _apply_list_geometry()

func _apply_list_geometry() -> void:
	_surface_size=_surface.size
	var rect := geometry_for(_surface_size)
	position=rect.position
	size=rect.size

func _exit_tree() -> void:
	if is_instance_valid(_surface) and _surface.resized.is_connected(_apply_list_geometry): _surface.resized.disconnect(_apply_list_geometry)
