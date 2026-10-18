extends RefCounted
## Concrete, interchangeable goods. Warehouse grouping lives in ResourceCategory.
enum Type { FOOD = 0, LOG = 1, PLANK = 2, STONE = 3 }

static func display_name(resource: Type) -> String:
	# Runtime load avoids a preload cycle: the catalog itself uses this enum.
	# Godot reuses the loaded script; its static definitions are built only once.
	var label: String = load("res://scripts/resource_catalog.gd").get_display_name(resource)
	return label if not label.is_empty() else "Ресурс"
