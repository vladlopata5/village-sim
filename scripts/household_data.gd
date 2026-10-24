extends RefCounted
## A residential unit owned by one BuildingInstance; membership lives on ResidentData.
const Balance = preload("res://scripts/balance_config.gd")
var _id: StringName
var _local_index: int
var id: StringName:
	get: return _id
var local_index: int:
	get: return _local_index
var capacity: int:
	get: return Balance.HOUSEHOLD_RESIDENT_CAPACITY
static func id_for(building_id: StringName, index: int = 1) -> StringName:
	return StringName("%s/household/%d" % [building_id,index]) if not building_id.is_empty() and index>0 else &""
func _init(building_id: StringName, index: int) -> void:
	_id=id_for(building_id,index)
	_local_index=index
	assert(not _id.is_empty(),"Household needs a building ID and positive local index")
