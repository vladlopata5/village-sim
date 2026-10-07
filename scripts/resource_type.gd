extends RefCounted
## Settlement resource categories, independent of building categories.
enum Type { FOOD, WOOD }

static func display_name(resource: Type) -> String:
	match resource:
		Type.FOOD: return "FOOD"
		Type.WOOD: return "Древесина"
		_: return "Ресурс"
