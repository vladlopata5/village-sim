extends "res://scripts/resource_container.gd"
## Import endpoint: reservations are physical items, storage is converted units.
var stock: RefCounted
func _init(owner: StringName, target: RefCounted) -> void:
	super(owner);stock=target
	stock.changed.connect(_on_stock_changed)
func _on_stock_changed() -> void:
	for resource in stock.conversions: reservations_changed.emit(resource)
func allows_resource(resource: ResourceType.Type) -> bool:return stock.yield_for(resource)>0
func get_capacity(resource: ResourceType.Type) -> int:return floori(float(stock.capacity)/stock.yield_for(resource)) if allows_resource(resource) else 0
func get_amount(_resource: ResourceType.Type) -> int:return 0 # No physical inventory survives conversion.
func get_available_amount(_resource: ResourceType.Type) -> int:return 0 # Never an export source.
func get_reserved_in(resource: ResourceType.Type) -> int:return stock.incoming(resource)
func get_available_free_capacity(resource: ResourceType.Type) -> int:return stock.room_for(resource)
func reserve_in(resource: ResourceType.Type, quantity: int) -> bool:return stock.reserve_in(resource,quantity)
func release_in(resource: ResourceType.Type, quantity: int) -> bool:return stock.release_in(resource,quantity)
func add_reserved(resource: ResourceType.Type, quantity: int) -> bool:return stock.deliver(resource,quantity)

func import_fill(resource: int) -> float:
	return float(stock.amount+stock.incoming_units())/stock.capacity if allows_resource(resource) and stock.capacity>0 else 1.0

func add(_resource: ResourceType.Type, _quantity: int) -> bool:return false # Only reserved unloads may convert.
func get_total_reserved_in() -> int:
	var total:=0
	for resource in stock.conversions:total+=stock.incoming(resource)
	return total
