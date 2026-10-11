extends RefCounted
## Settlement resource categories, independent of building categories.
enum Type { FOOD, LOG, PLANK, STONE }

static func display_name(resource: Type) -> String:
	match resource:
		Type.FOOD: return "FOOD"
		Type.LOG: return "Бревно"
		Type.PLANK: return "Доски"
		Type.STONE: return "Камень"
		_: return "Ресурс"
