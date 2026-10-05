extends Node
## All rates in one place: 60 fractional units = one need point.
const Data = preload("res://scripts/resident_data.gd")
const NeedType = preload("res://scripts/need_type.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const UNITS_PER_POINT := 60
const HUNGER_AWAKE := 4
const HUNGER_SLEEPING := 1
const HUNGER_EATING := -120 # Paid meal: -2 points per game minute.
const FATIGUE_RATES = {
	Activity.Type.IDLE: 1, Activity.Type.MOVING: 2,
	Activity.Type.WORKING: 4, Activity.Type.HAULING: 5,
	Activity.Type.EATING: 1, Activity.Type.SLEEPING: -30,
	Activity.Type.RESTING: -10, Activity.Type.TALKING: 1, Activity.Type.RELAXING: 1,
}
const SOCIAL_RATES = {
	Activity.Type.IDLE: 12, Activity.Type.MOVING: 30, Activity.Type.WORKING: 60,
	Activity.Type.HAULING: 60, Activity.Type.EATING: 12, Activity.Type.SLEEPING: 6,
	Activity.Type.RESTING: 12, Activity.Type.TALKING: -180, Activity.Type.RELAXING: 12,
}
const LEISURE_RATES = {
	Activity.Type.IDLE: 12, Activity.Type.MOVING: 30, Activity.Type.WORKING: 60,
	Activity.Type.HAULING: 60, Activity.Type.EATING: 12, Activity.Type.SLEEPING: 6,
	Activity.Type.RESTING: 12, Activity.Type.TALKING: -30, Activity.Type.RELAXING: -180,
}
var _data: Data
var _fractions: Dictionary = {NeedType.Type.HUNGER: 0, NeedType.Type.FATIGUE: 0, NeedType.Type.SOCIAL: 0, NeedType.Type.LEISURE: 0}
func setup(clock: Node, data: Data) -> void:
	_data = data
	clock.minute_changed.connect(_on_minute_changed)
func _on_minute_changed(_minute: int) -> void:
	var activity = _data.activity
	var hunger_rate := HUNGER_AWAKE
	if activity == Activity.Type.SLEEPING: hunger_rate = HUNGER_SLEEPING
	elif activity == Activity.Type.EATING: hunger_rate = HUNGER_EATING
	_apply(NeedType.Type.HUNGER, hunger_rate)
	_apply(NeedType.Type.FATIGUE, FATIGUE_RATES[activity])
	_apply(NeedType.Type.SOCIAL, SOCIAL_RATES[activity])
	_apply(NeedType.Type.LEISURE, LEISURE_RATES[activity])
func _apply(type: NeedType.Type, rate: int) -> void:
	var need = _data.get_need(type)
	if (need.value == 100 and rate > 0) or (need.value == 0 and rate < 0):
		_fractions[type] = 0
		return
	_fractions[type] += rate
	var points := int(float(_fractions[type]) / UNITS_PER_POINT)
	if points != 0:
		_fractions[type] -= points * UNITS_PER_POINT
		need.value += points
		if need.value in [0, 100]: _fractions[type] = 0
