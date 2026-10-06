extends RefCounted
const ResidentActivity = preload("res://scripts/resident_activity.gd")
signal activity_changed
var activity: ResidentActivity.Type = ResidentActivity.Type.IDLE:
	set(value):
		if activity == value: return
		activity = value
		activity_changed.emit()
const TraitData = preload("res://scripts/trait_data.gd")
## The resident exists as data, independently of any scene or renderer.
## The creator assigns an ID unique within the settlement.
var work_location_id: StringName = &""
var home_location_id: StringName = &""
var id: String
var resident_name: String
var age: int
const Profession = preload("res://scripts/resident_profession.gd")
var profession: Profession.Type
const Inventory = preload("res://scripts/resident_inventory.gd")
const Assignment = preload("res://scripts/resident_assignment.gd")
var assignments: Array[Assignment] = []
var inventory = Inventory.new()
var traits: Array[TraitData] = []
## Higher hunger/fatigue means more hungry/tired; higher mood means happier.
const NeedType = preload("res://scripts/need_type.gd")
const Need = preload("res://scripts/need.gd")
const Balance = preload("res://scripts/balance_config.gd")
var needs: Dictionary = {
	NeedType.Type.HUNGER: Need.new(0, Balance.HUNGER_BASE_WEIGHT),
	NeedType.Type.FATIGUE: Need.new(0, Balance.FATIGUE_BASE_WEIGHT),
	NeedType.Type.SOCIAL: Need.new(0, Balance.SOCIAL_BASE_WEIGHT),
	NeedType.Type.LEISURE: Need.new(0, Balance.LEISURE_BASE_WEIGHT),
}
signal hunger_changed
signal fatigue_changed
# Compatibility accessors: one source of truth, not a second set of values.
var hunger: int:
	get: return needs[NeedType.Type.HUNGER].value
	set(next): needs[NeedType.Type.HUNGER].value = next
var fatigue: int:
	get: return needs[NeedType.Type.FATIGUE].value
	set(next): needs[NeedType.Type.FATIGUE].value = next
var mood: int = 50:
	set(value):
		mood = clampi(value, 0, 100)

func _init(unique_id: String, initial_name: String, initial_age: int, initial_profession: Profession.Type = Profession.Type.NONE) -> void:
	needs[NeedType.Type.HUNGER].changed.connect(hunger_changed.emit)
	needs[NeedType.Type.FATIGUE].changed.connect(fatigue_changed.emit)
	id = unique_id
	resident_name = initial_name
	age = initial_age
	profession = initial_profession

func get_need(type: NeedType.Type) -> Need:
	return needs[type]
