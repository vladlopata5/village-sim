extends RefCounted
## Settlement resource categories, independent of building categories.
enum Type { FOOD, WOOD, LOG, PLANK }

static func display_name(resource: Type) -> String:
	match resource:
		Type.FOOD: return "FOOD"
		Type.WOOD: return "Древесина"
		Type.LOG: return "Бревно"
		Type.PLANK: return "Доски"
		_: return "Ресурс"
