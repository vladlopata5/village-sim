extends RefCounted
## The resident exists as data, independently of any scene or renderer.
## The creator assigns an ID unique within the settlement.
var id: String
var resident_name: String
var age: int
var profession: String

func _init(unique_id: String, initial_name: String, initial_age: int, initial_profession: String) -> void:
	id = unique_id
	resident_name = initial_name
	age = initial_age
	profession = initial_profession
