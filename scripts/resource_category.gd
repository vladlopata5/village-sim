extends RefCounted
## Warehouse grouping only; these IDs never replace a concrete ResourceType.
enum Type { SIMPLE_FOOD, LOG, PLANK, STONE }
const INVALID := -1

static func display_name(category: Variant) -> String:
	if typeof(category) != TYPE_INT: return ""
	match category:
		Type.SIMPLE_FOOD: return "Простая еда"
		Type.LOG: return "Брёвна"
		Type.PLANK: return "Доски"
		Type.STONE: return "Камень"
		_: return ""
