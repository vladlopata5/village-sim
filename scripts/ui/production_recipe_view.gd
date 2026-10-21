extends VBoxContainer
## One persistent recipe section. Reads never select work or issue an order.
const Instance = preload("res://scripts/building_instance.gd")
const Batch = preload("res://scripts/production_batch.gd")
const Goods = preload("res://scripts/resource_type.gd")
const Mode = Instance.ProductionMode
const MODE_NAMES = ["Выключено", "Без ограничений", "Поддерживать запас", "Произвести заказ"]
const STATE_NAMES = {Batch.State.PREPARING:"Подготовка", Batch.State.READY:"Ожидает рабочего места", Batch.State.RUNNING:"Производится", Batch.State.PAUSED:"Приостановлено"}
var _building: Instance
var _control: RefCounted
var recipe: RefCounted
var _mode_dirty := false
var _amount_dirty := false
var title: Label
var composition: Label
var mode: OptionButton
var amount_row: HBoxContainer
var amount_label: Label
var amount: LineEdit
var apply_button: Button
var status: Label
var batches: Label
var feedback: Label

func _label() -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(label)
	return label
func setup(building: Instance, definition: RefCounted, control: RefCounted) -> void:
	_building = building
	recipe = definition
	_control = control
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 5)
	add_child(HSeparator.new())
	for resource in recipe.outputs:
		var icon_path: String = preload("res://scripts/resource_catalog.gd").get_definition(resource).get("icon", "")
		if not icon_path.is_empty():
			var icon := TextureRect.new()
			icon.texture = load(icon_path)
			icon.custom_minimum_size = Vector2(32,32)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			add_child(icon)
	title = _label()
	title.text = " / ".join(recipe.outputs.keys().map(func(resource): return Goods.display_name(resource)))
	title.tooltip_text = str(recipe.id)
	title.add_theme_font_size_override("font_size",16)
	composition = _label()
	composition.text = "%s → %s\n%d рабочих минут" % [_goods(recipe.inputs),_goods(recipe.outputs),recipe.work_required]
	if not recipe.optional_outputs.is_empty():composition.text+="\nДополнительно при завершении, если есть место: "+_goods(recipe.optional_outputs)
	batches = _label()
	mode = OptionButton.new()
	mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for caption in MODE_NAMES: mode.add_item(caption)
	add_child(mode)
	mode.item_selected.connect(_mode_edited)
	amount_row = HBoxContainer.new()
	add_child(amount_row)
	amount_label = Label.new()
	amount_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amount_row.add_child(amount_label)
	amount = LineEdit.new()
	amount.custom_minimum_size.x = 64
	amount.max_length = 20
	amount.keep_editing_on_text_submit = true
	amount_row.add_child(amount)
	amount.text_changed.connect(_amount_edited)
	amount.text_submitted.connect(_submit)
	apply_button = Button.new()
	apply_button.text = "Применить"
	amount_row.add_child(apply_button)
	apply_button.pressed.connect(_apply)
	status = _label()
	feedback = _label()
	feedback.hide()
	refresh()
func _goods(values: Dictionary) -> String:
	var parts := PackedStringArray()
	for resource in values: parts.append("%s ×%d" % [Goods.display_name(resource),values[resource]])
	return " + ".join(parts)
func deactivate() -> void:
	# Queued events from an old section cannot become commands for another selection.
	_control = null
	_building = null
func _mode_edited(_index: int) -> void:
	_mode_dirty = true
	feedback.hide()
	_quantity_visibility()
func _amount_edited(_text: String) -> void:
	_amount_dirty = true
	feedback.hide()
func _quantity_visibility() -> void:
	amount.visible = mode.selected in [Mode.MAINTAIN,Mode.ORDER]
	amount_label.visible = amount.visible
	amount_label.text = "Цель:" if mode.selected==Mode.MAINTAIN else "Заказ:"
	amount.tooltip_text = "Запас результата в этом здании" if mode.selected==Mode.MAINTAIN else "Новый заказ заменяет прежний остаток"
func _submit(_text: String) -> void: _apply()
func _apply() -> void:
	if _building==null or _control==null: return
	var value: Variant = 0
	if mode.selected in [Mode.MAINTAIN,Mode.ORDER]:
		value = amount.text
		if amount.text.is_valid_int() and amount.text.length()<=18: value = amount.text.to_int()
	var result: Dictionary
	if _control.get_building(_building.id)!=_building:
		result = {"ok":false,"error":"Здание больше недоступно."}
	else:
		result = _control.set_production_recipe(_building.id,recipe.id,mode.selected,value)
	feedback.text = "Применено" if result.ok else result.error
	feedback.add_theme_color_override("font_color",Color(0.7,0.9,0.75) if result.ok else Color(1,0.65,0.55))
	feedback.show()
	if result.ok:
		_mode_dirty = false
		_amount_dirty = false
		amount.release_focus()
		refresh()
func refresh() -> void:
	if _building==null: return
	var settings := _building.get_recipe_settings(recipe.id)
	if settings.is_empty(): return
	if not _mode_dirty and not _amount_dirty: mode.select(settings.mode)
	if not _amount_dirty and not amount.has_focus(): amount.text = str(settings.target)
	_quantity_visibility()
	var lines := PackedStringArray(["Режим: " + MODE_NAMES[settings.mode]])
	if settings.mode==Mode.MAINTAIN: lines.append("Поддерживать: %d (в этом здании)" % settings.target)
	if settings.order:
		lines.append("Заказ: %d • Произведено: %d\nОсталось: %d" % [settings.target,settings.produced,settings.remaining])
		if settings.excess>0: lines.append("Превышение: %d" % settings.excess)
	var output := PackedStringArray()
	for resource in recipe.outputs: output.append("%s: %d" % [Goods.display_name(resource),_building.resources.get_amount(resource)])
	lines.append("Готово — " + "; ".join(output))
	var work := PackedStringArray()
	for batch in _building.production_batches:
		if batch.recipe_id==recipe.id and not batch.is_terminal():
			work.append("%s — %s: %d / %d мин" % [_goods(batch.outputs),STATE_NAMES[batch.state],batch.progress,batch.work_required])
	var kits: int = _building.supply.needs.filter(func(need): return need.recipe_id==recipe.id).size()
	lines.append("Партии: %d • Комплекты снабжения: %d" % [work.size(),kits])
	status.text = "\n".join(lines)
	batches.text = "\n".join(work)
	batches.visible = not work.is_empty()
