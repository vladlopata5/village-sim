extends RefCounted
## Job urgency only. These values never compete directly with Need priorities.
const Balance = preload("res://scripts/balance_config.gd")
static func import_priority(container: RefCounted, resource: int, weight: float = Balance.DEFAULT_BUILDING_LOGISTICS_WEIGHT) -> float:
	var capacity: int = container.get_capacity(resource)
	if capacity <= 0: return 0.0
	var projected: int = container.get_amount(resource) + container.get_reserved_in(resource)
	var fill := clampf(float(projected) / capacity * 100.0, 0.0, 100.0)
	return (100.0 - fill) * weight * Balance.IMPORT_MULTIPLIER
static func export_priority(container: RefCounted, resource: int, weight: float = Balance.DEFAULT_BUILDING_LOGISTICS_WEIGHT) -> float:
	var capacity: int = container.get_capacity(resource)
	if capacity <= 0: return 0.0
	var projected: int = container.get_amount(resource) - container.get_reserved_out(resource)
	var fill := clampf(float(projected) / capacity * 100.0, 0.0, 100.0)
	return fill * weight * Balance.EXPORT_MULTIPLIER
