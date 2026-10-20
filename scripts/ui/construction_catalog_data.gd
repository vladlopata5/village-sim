extends RefCounted
## Presentation metadata only; recipes, geometry and capacity belong to Definition.
const Definition = preload("res://scripts/building_definition.gd")
const Types = preload("res://scripts/building_type.gd").Type
static func categories() -> Array:
	return [
		{"id":&"production", "title":"Производство", "entries":[
			building(Types.LUMBERJACK_HUT,"tree","Рубка, сбор древесины и посадка деревьев при хижине."),
			building(Types.QUARRY,"rock","Добыча и сбор камня в рабочей области каменоломни."),
			building(Types.GATHERER_HUT,"basket","Сбор грибов и доставка их в хижину."),
			building(Types.SAWMILL,"saw","Производство досок из брёвен."),
			building(Types.SHEPHERD_HUT,"home","Содержание 8 животных. Пастух: 1; носильщик: 1 (необязателен)." )]},
		{"id":&"logistics", "title":"Логистика", "entries":[building(Types.STORAGE,"storage","Хранение ресурсов и работа носильщиков.")]},
		{"id":&"settlement", "title":"Поселение", "entries":[building(Types.HOME,"home","Жильё и отдых жителей."),building(Types.FOOD,"kitchen","Приготовление жареных грибов и питание жителей.")]},
	]
static func building(type: int, icon: String, description: String) -> Dictionary:
	var definition = Definition.for_type(type)
	return {"id":StringName("building_%d" % type),"action":&"building","definition":definition,"name":definition.display_name,"icon":icon,"description":description}
