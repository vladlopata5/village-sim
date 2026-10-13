extends PanelContainer
## Development UI only; spawn/time commands delegate the normal world entry points.
signal placement_started
signal placement_cancelled
const Profession = preload("res://scripts/resident_profession.gd")
const Resources = preload("res://scripts/resource_type.gd")
var escape_handler: Callable
var ui_input_context: RefCounted
var service: RefCounted
var placement_kind: StringName = &""
var _type: Variant
var _quantity := 1
var status: Label
var profession_choice: OptionButton
var resident_count: SpinBox
var resource_choice: OptionButton
var resource_count: SpinBox
var building_choice: OptionButton
var hour: SpinBox
var minute: SpinBox
func setup(commands: RefCounted) -> void:
	if not OS.is_debug_build():
		hide()
		return
	service=commands
	name="DeveloperPanel"
	process_mode=Node.PROCESS_MODE_ALWAYS
	position=Vector2(16,110)
	custom_minimum_size=Vector2(430,470)
	mouse_filter=Control.MOUSE_FILTER_STOP
	var background := StyleBoxFlat.new()
	background.bg_color=Color(0.08,0.10,0.08,1.0)
	add_theme_stylebox_override("panel",background)
	var margin := MarginContainer.new()
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,10)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var title := Label.new()
	title.text="Панель разработчика • F10"
	column.add_child(title)
	status=Label.new()
	status.custom_minimum_size=Vector2(400,50)
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	status.text="Выберите объект и нажмите «Создать». Затем кликните по земле."
	column.add_child(status)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size=Vector2(400,300)
	column.add_child(tabs)
	var residents := _section(tabs,"Жители")
	profession_choice=OptionButton.new()
	for value in Profession.Type.values(): profession_choice.add_item(Profession.display_name(value),value)
	residents.add_child(profession_choice)
	resident_count=_count(residents,50)
	_button(residents,"Создать жителей",func(): begin_placement(&"resident",profession_choice.get_selected_id(),int(resident_count.value)))
	_note(residents,"Обычный AI, потребности и навыки. Рабочее место назначается по штатным правилам; область не создаётся автоматически.")
	var resources := _section(tabs,"Ресурсы")
	resource_choice=OptionButton.new()
	for value in Resources.Type.values(): resource_choice.add_item(Resources.display_name(value),value)
	resources.add_child(resource_choice)
	resource_count=_count(resources,100)
	_button(resources,"Создать ресурсы",func(): begin_placement(&"resource",resource_choice.get_selected_id(),int(resource_count.value)))
	_note(resources,"Отдельные единицы на земле. Подбор и срок жизни — обычные игровые правила.")
	var buildings := _section(tabs,"Здания")
	building_choice=OptionButton.new()
	for definition in service.building_catalog():
		building_choice.add_item(definition.display_name)
		building_choice.set_item_metadata(building_choice.item_count-1,definition)
	buildings.add_child(building_choice)
	_button(buildings,"Создать готовое здание",func(): begin_placement(&"building",building_choice.get_selected_metadata(),1))
	_note(buildings,"Сразу построено, без расхода материалов. Геометрия, входы и ограничения размещения сохраняются.")
	var time := _section(tabs,"Время")
	_button(time,"Пауза / Продолжить",service.world._toggle_pause)
	var speeds := HBoxContainer.new()
	time.add_child(speeds)
	for speed in service.world.game_time.SUPPORTED_SPEEDS: _button(speeds,"x%d" % speed,service.world.game_time.set_speed.bind(speed))
	var row := HBoxContainer.new()
	time.add_child(row)
	hour=_count(row,23,0)
	minute=_count(row,59,0)
	hour.prefix="Час: "
	minute.prefix="Мин: "
	_button(time,"Перевести время вперёд",func(): _show_result(service.advance_to_time(int(hour.value),int(minute.value))))
	_button(time,"Следующий день (00:00)",func(): _show_result(service.next_day()))
	_note(time,"Только вперёд: раннее время — на следующий день. Пропуск проигрывает все игровые минуты; для физического движения используйте скорости x1–x20.")
	_button(column,"Отменить размещение (Esc / ПКМ)",cancel_placement)
	hide()
func _section(tabs: TabContainer, label: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name=label
	tabs.add_child(column)
	return column
func _count(parent: Node, maximum: int, minimum: int = 1) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value=minimum
	spin.max_value=maximum
	spin.step=1
	spin.value=minimum
	parent.add_child(spin)
	return spin
func _button(parent: Node, label: String, action: Callable) -> void:
	var button := Button.new()
	button.text=label
	button.pressed.connect(action)
	parent.add_child(button)
func _note(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text=text
	label.custom_minimum_size.x=380
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
func _input(event: InputEvent) -> void:
	if not OS.is_debug_build(): return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_F10:
			if visible:
				cancel_placement()
				hide()
			else: show()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and escape_handler.is_valid():
			if escape_handler.call(): get_viewport().set_input_as_handled()
		elif event.keycode==KEY_ESCAPE and active():
			cancel_placement()
			get_viewport().set_input_as_handled()
func active() -> bool: return not placement_kind.is_empty()
func begin_placement(kind: StringName, type: Variant, count: int) -> void:
	if not service.available(): return
	placement_kind=kind
	_type=type
	_quantity=count
	status.text="Размещение: %s ×%d. ЛКМ по земле — создать; Esc / ПКМ — отменить." % [{&"resident":"жители",&"resource":"ресурсы",&"building":"готовое здание"}.get(kind,"?"),count]
	placement_started.emit()
func cancel_placement() -> void:
	_paused_clicks.clear()
	placement_cancelled.emit()
	placement_kind=&""
	status.text="Размещение отменено."
func confirm_world(point: Vector3) -> Dictionary:
	if not active(): return service.rejected("Режим размещения не выбран")
	var result: Dictionary
	match placement_kind:
		&"resident": result=service.spawn_residents(point,_quantity,int(_type))
		&"resource": result=service.spawn_resources(point,_quantity,int(_type))
		&"building": result=service.spawn_building(point,_type)
		_: result=service.rejected("Неизвестный режим")
	if result.ok: placement_kind=&""
	_show_result(result)
	return result
func _show_result(result: Dictionary) -> void: status.text=result.reason

var _paused_clicks: Array[InputEventMouseButton] = []
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse and ui_input_context != null and ui_input_context.pointer_blocked(event.position): return
	# Root world input pauses normally; this developer panel can still place while paused.
	if not get_tree().paused or not active(): return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		_paused_clicks.append(event)
		get_viewport().set_input_as_handled()
func _physics_process(_delta: float) -> void:
	for event in _paused_clicks:
		service.world.handle_world_click(event.button_index,service.world.ground_pick(event.position),event.position)
	_paused_clicks.clear()
