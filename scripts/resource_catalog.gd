extends RefCounted
## Static metadata for concrete goods, not stock, reservations or item instances.
const Resources = preload("res://scripts/resource_type.gd")
const Categories = preload("res://scripts/resource_category.gd")
enum FoodQuality { NONE, SIMPLE }
static var _definitions: Dictionary = _build_definitions()

static func _build_definitions() -> Dictionary:
	var definitions := {
		Resources.Type.FOOD: {"id":Resources.Type.FOOD,"display_name":"FOOD","category":Categories.Type.SIMPLE_FOOD,"ready_food":true,"food_quality":FoodQuality.SIMPLE,"quantity_compatible":true},
		Resources.Type.LOG: {"id":Resources.Type.LOG,"display_name":"Бревно","category":Categories.Type.LOG,"ready_food":false,"food_quality":FoodQuality.NONE,"quantity_compatible":true},
		Resources.Type.PLANK: {"id":Resources.Type.PLANK,"display_name":"Доски","category":Categories.Type.PLANK,"ready_food":false,"food_quality":FoodQuality.NONE,"quantity_compatible":true},
		Resources.Type.STONE: {"id":Resources.Type.STONE,"display_name":"Камень","category":Categories.Type.STONE,"ready_food":false,"food_quality":FoodQuality.NONE,"quantity_compatible":true},
	}
	# Values contain only scalars. Freeze both levels before exposing any definition.
	for definition: Dictionary in definitions.values(): definition.make_read_only()
	definitions.make_read_only()
	return definitions

static func get_definition(resource: Variant) -> Dictionary:
	if typeof(resource) != TYPE_INT: return {}
	return _definitions.get(resource,{})

static func get_category(resource: Variant) -> int:
	return get_definition(resource).get("category",Categories.INVALID)

static func get_display_name(resource: Variant) -> String:
	return get_definition(resource).get("display_name","")

static func is_ready_food(resource: Variant) -> bool:
	return get_definition(resource).get("ready_food",false)

static func get_food_quality(resource: Variant) -> int:
	return get_definition(resource).get("food_quality",FoodQuality.NONE)

static func supports_quantity(resource: Variant) -> bool:
	# False means unsupported by today's quantity-only transfers, not instance support.
	return get_definition(resource).get("quantity_compatible",false)

static func types_in_category(category: Variant) -> Array[int]:
	return _types_in_category(_definitions,category)

static func _types_in_category(definitions: Dictionary, category: Variant) -> Array[int]:
	var result: Array[int] = []
	if typeof(category) != TYPE_INT or category not in Categories.Type.values(): return result
	for resource: int in definitions:
		if definitions[resource].category == category: result.append(resource)
	return result
