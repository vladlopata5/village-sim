extends Node
## First need decision: hunger only. Uses existing buildings, places and intents.
const Data = preload("res://scripts/resident_data.gd")
const BuildingData = preload("res://scripts/building_data.gd")
const BuildingType = preload("res://scripts/building_type.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const IntentController = preload("res://scripts/resident_intent_controller.gd")
const Schedule = preload("res://scripts/resident_schedule_controller.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const EAT_PRIORITY := 75
const HUNGER_THRESHOLD := 70
const MEAL_MINUTES := 30
var _data: Data
var _buildings: Array[BuildingData]
var _locations: RefCounted
var _intents: IntentController
var _schedule: Schedule
var _clock: Node
var _eat_intent: Intent
var _meal_active := false
var _meal_started_at: int = 0
var _minutes_left: int = 0

func setup(clock: Node, data: Data, buildings: Array[BuildingData], locations: RefCounted, intents: IntentController, schedule: Schedule) -> void:
	_clock = clock
	_data = data
	_buildings = buildings
	_locations = locations
	_intents = intents
	_schedule = schedule
	_data.hunger_changed.connect(evaluate)
	_clock.minute_changed.connect(_on_minute_changed)
	_clock.phase_changed.connect(_on_phase_changed)
	_intents.intent_changed.connect(_on_intent_changed)
	_intents.intent_completed.connect(_on_intent_completed)
	evaluate()

func evaluate() -> void:
	if _meal_active:
		return
	if _eat_intent != null:
		if _intents.current_intent == _eat_intent:
			return
		_eat_intent = null
	if _data.hunger < HUNGER_THRESHOLD or _data.activity == Activity.Type.SLEEPING or _schedule.is_night:
		return
	for building in _buildings:
		if building.type != BuildingType.Type.FOOD:
			continue
		var location = _locations.get_location(building.id)
		if location == null:
			continue
		var target: Variant = _locations.get_position(location.id)
		if not target is Vector2:
			continue
		var candidate = Intent.new(Intent.Type.MOVE_TO, &"eat", target, EAT_PRIORITY)
		# Set before submit: a resident already at the kitchen arrives synchronously.
		_eat_intent = candidate
		if not _intents.submit(candidate) and _eat_intent == candidate:
			_eat_intent = null
		return

func _on_intent_changed(intent: Intent) -> void:
	if intent.type != Intent.Type.NONE and intent != _eat_intent:
		_eat_intent = null
		_meal_active = false
		_minutes_left = 0

func _on_intent_completed(intent: Intent) -> void:
	if intent != _eat_intent or _schedule.is_night:
		return
	_eat_intent = null
	_meal_active = true
	_meal_started_at = _clock.total_minutes
	_minutes_left = MEAL_MINUTES
	_data.activity = Activity.Type.EATING

func _on_minute_changed(total_minutes: int) -> void:
	if _meal_active and total_minutes > _meal_started_at:
		_minutes_left -= 1
		if _minutes_left == 0:
			_meal_active = false
			_data.activity = Activity.Type.IDLE
			_data.hunger -= 60
			_schedule.resume_current_phase()
	evaluate()

func _on_phase_changed(_phase: String) -> void:
	# If home is missing, night still interrupts the meal without a false arrival.
	if _schedule.is_night:
		_intents.clear_reason(&"eat")
		_eat_intent = null
		_meal_active = false
		_minutes_left = 0
		if _data.activity == Activity.Type.EATING:
			_data.activity = Activity.Type.IDLE
	else:
		evaluate()
