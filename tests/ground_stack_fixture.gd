extends RefCounted
## Test arrangement only: index-valid stack, without world geometry validation.
static func create(ground: Node, resource: int, quantity: int, point: Vector2) -> RefCounted:
	if not ground.is_stack_mode(): return ground.create_drop(resource,quantity,point) # Isolated domain fixture only.
	var result: Dictionary=ground.try_place(resource,quantity,ground.cell_from_position(point))
	assert(result.remaining==0,"Fixture must fit its requested stack")
	return result.stack
static func total(ground: Node, resource: int = -1) -> int:
	var amount:=0
	for drop in ground.drops:
		if resource<0 or drop.resource_type==resource: amount+=drop.amount
	return amount
