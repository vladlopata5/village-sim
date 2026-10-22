extends RefCounted
## Job urgency only. These values never compete directly with Need priorities.
const Balance = preload("res://scripts/balance_config.gd")
static func import_priority(container: RefCounted, resource: int, weight: float = Balance.DEFAULT_BUILDING_LOGISTICS_WEIGHT) -> float:
	return (100.0-clampf(container.import_fill(resource)*100.0,0.0,100.0))*weight*Balance.IMPORT_MULTIPLIER
static func export_priority(container: RefCounted, resource: int, weight: float = Balance.DEFAULT_BUILDING_LOGISTICS_WEIGHT) -> float:
	var category: int = container.get_resource_category(resource)
	var capacity: int = container.get_category_quota(category) if container.is_warehouse() else container.get_capacity(resource)
	if capacity <= 0: return 0.0
	var projected: int = container.get_amount(resource) - container.get_reserved_out(resource)
	if container.is_warehouse(): projected = container.get_category_amount(category) - container.get_category_reserved_out(category)
	var fill := clampf(float(projected) / capacity * 100.0, 0.0, 100.0)
	return fill * weight * Balance.EXPORT_MULTIPLIER
