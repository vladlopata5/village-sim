extends RefCounted
const ResidentActivity = preload("res://scripts/resident_activity.gd")
var activity: ResidentActivity.Type = ResidentActivity.Type.IDLE
const TraitData = preload("res://scripts/trait_data.gd")
## The resident exists as data, independently of any scene or renderer.
## The creator assigns an ID unique within the settlement.
var home_location_id: StringName = &""
var id: String
var resident_name: String
var age: int
var profession: String
var traits: Array[TraitData] = []
## Higher hunger/fatigue means more hungry/tired; higher mood means happier.
var hunger: int = 0:
	set(value):
		hunger = clampi(value, 0, 100)
var fatigue: int = 0:
	set(value):
		fatigue = clampi(value, 0, 100)
var mood: int = 50:
	set(value):
		mood = clampi(value, 0, 100)

func _init(unique_id: String, initial_name: String, initial_age: int, initial_profession: String) -> void:
	id = unique_id
	resident_name = initial_name
	age = initial_age
	profession = initial_profession
