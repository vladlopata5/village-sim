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
			building(Types.SHEPHERD_HUT,"home","Содержание 8 животных. Пастух: 1; носильщик: 1 (необязателен)." ),
			building(Types.WEAVER_WORKSHOP,"loom","1 шерсть → 1 шерстяная ткань за 60 рабочих минут."),
			building(Types.TAILOR_WORKSHOP,"needle","3 шерстяные ткани → 1 шерстяная одежда за 120 рабочих минут."),
			building(Types.WINDMILL,"windmill","2 пшеницы → 1 мука за 60 рабочих минут. Мельник: 1; носильщик необязателен."),
			building(Types.FARM,"wheat","Полевые работы и обмолот: сноп → пшеница и солома. Фермер: 1; носильщик необязателен."),
			building(Types.CLAY_HUT,"clay","Добыча и сбор глины в рабочей области хижины."),
			building(Types.POTTERY_WORKSHOP,"pottery","1 глина + 1 топливо → 1 кирпич за 30 рабочих минут.")]},
		{"id":&"logistics", "title":"Логистика", "entries":[building(Types.STORAGE,"storage","Хранение ресурсов и работа носильщиков."),building(Types.WELL,"well","Общедоступный бесконечный источник воды. Набор — 10 минут.")]},
		{"id":&"settlement", "title":"Поселение", "entries":[building(Types.HOME,"home","Жильё и отдых жителей."),building(Types.FOOD,"kitchen","Грибы + топливо или мука + топливо + вода → 2 порции за 30 минут. Повар: 1; носильщик: 1.")]},
	]
static func building(type: int, icon: String, description: String) -> Dictionary:
	var definition = Definition.for_type(type)
	return {"id":StringName("building_%d" % type),"action":&"building","definition":definition,"name":definition.display_name,"icon":icon,"description":description}
