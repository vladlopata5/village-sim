extends RefCounted
const ResidentActivity = preload("res://scripts/resident_activity.gd")
var activity: ResidentActivity.Type = ResidentActivity.Type.IDLE
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
var inventory = Inventory.new()
var traits: Array[TraitData] = []
## Higher hunger/fatigue means more hungry/tired; higher mood means happier.
signal hunger_changed
var hunger: int = 0:
	set(value):
		var bounded := clampi(value, 0, 100)
		if hunger != bounded:
			hunger = bounded
			hunger_changed.emit()
var fatigue: int = 0:
	set(value):
		fatigue = clampi(value, 0, 100)
var mood: int = 50:
	set(value):
		mood = clampi(value, 0, 100)

func _init(unique_id: String, initial_name: String, initial_age: int, initial_profession: Profession.Type = Profession.Type.NONE) -> void:
	id = unique_id
	resident_name = initial_name
	age = initial_age
	profession = initial_profession
