extends RefCounted
## Explicit creation; each call owns its mutable resident state.
const Data = preload("res://scripts/resident_data.gd")
const Profession = preload("res://scripts/resident_profession.gd")

static func create(resident_id: String, display_name: String, age: int, profession: Profession.Type, traits: Array, hunger: int, fatigue: int, mood: int, home_location_id: StringName, work_location_id: StringName) -> Data:
	var data = Data.new(resident_id, display_name, age, profession)
	data.traits.assign(traits)
	data.hunger = hunger
	data.fatigue = fatigue
	data.mood = mood
	data.home_location_id = home_location_id
	data.work_location_id = work_location_id
	return data
