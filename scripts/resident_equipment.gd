extends RefCounted
## Personal equipment only; ResidentInventory remains the one-unit work cargo.
const Item=preload("res://scripts/equipped_item.gd")
const Catalog=preload("res://scripts/resource_catalog.gd")
const Balance=preload("res://scripts/balance_config.gd")
enum Slot { CLOTHING }
signal changed
var _slots: Dictionary={}
var _transferring:=false
func item(slot: Slot=Slot.CLOTHING) -> RefCounted:return _slots.get(slot)
static func allowed(resource: int, slot: Slot=Slot.CLOTHING) -> bool:
	return slot==Slot.CLOTHING and Catalog.get_definition(resource).get("equipment_slot",&"")==&"clothing"
func needs_clothing() -> bool:
	var current=item()
	return current==null or current.remaining_minutes<Balance.CLOTHING_LIFETIME_MINUTES*0.1
func set_item(slot: Slot, value: RefCounted) -> bool:
	if _transferring or slot not in Slot.values() or (value!=null and (not value is Item or not allowed(value.resource_type,slot) or value.remaining_minutes<=0)):return false
	if value==null:_slots.erase(slot)
	else:_slots[slot]=value
	changed.emit();return true
func receive(resource: int, take: Callable) -> bool:
	if _transferring or not needs_clothing() or not allowed(resource) or not take.is_valid():return false
	var next=Item.new(resource)
	_transferring=true
	var taken: Variant=take.call()
	var accepted: bool=typeof(taken)==TYPE_BOOL and taken
	if accepted:
		_slots[Slot.CLOTHING]=next # Replace only after the one-unit source transaction commits.
		changed.emit()
	_transferring=false
	return accepted
func advance(minutes: int) -> void:
	if minutes<=0 or _transferring:return
	var current=item()
	if current==null:return
	current.wear(minutes)
	if current.remaining_minutes<=0:_slots.erase(Slot.CLOTHING)
	changed.emit()
