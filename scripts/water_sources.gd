extends RefCounted
## Infinite natural supply, finite access claims. No transport jobs or resource stock.
const Coordinates=preload("res://scripts/world_3d/world_coordinates.gd")
const Source=preload("res://scripts/resource_source_ref.gd")
const Geometry=preload("res://scripts/world_3d/world_geometry.gd")
const RESOURCE_TYPE=preload("res://scripts/resource_type.gd").Type.WATER
signal changed
var fields: RefCounted
var navigation: RefCounted
var locations: RefCounted
var banks: Dictionary={} # Land cell -> source ID; changed cells and four neighbours only.
var _bank_cells: Dictionary={}
var _bank_points: Dictionary={}
var _wells: Dictionary={}
var _claims: Dictionary={} # Haul ID -> source ID/instance snapshot, never water quantity.
const SIDES=[Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]
func setup(model: RefCounted, nav: RefCounted, registry: RefCounted) -> void:
	fields=model;navigation=nav;locations=registry
	fields.changed.connect(_cells_changed)
	navigation.changed.connect(_navigation_changed)
	_cells_changed(fields.surface_cells())
func register_well(building: RefCounted) -> void:
	if _wells.has(building.id):return
	_wells[building.id]=building
	building.construction_changed.connect(_well_changed)
	changed.emit()
func remove_well(id: StringName) -> void:
	var building: RefCounted=_wells.get(id)
	if building==null:return
	_wells.erase(id)
	_invalidate_claims()
	if building.construction_changed.is_connected(_well_changed):building.construction_changed.disconnect(_well_changed)
	changed.emit()
func _well_changed() -> void:
	_invalidate_claims()
	changed.emit()
func _navigation_changed(_revision: int) -> void:
	_invalidate_claims()
	changed.emit()
func _bank_geometry(cell: Vector2i) -> bool:
	return fields.in_bounds(cell) and fields.terrain(cell)!=fields.Terrain.WATER and SIDES.any(func(side):return fields.in_bounds(cell+side) and fields.terrain(cell+side)==fields.Terrain.WATER)
func _cells_changed(cells: Array) -> void:
	var affected: Dictionary={}
	for cell in cells:
		affected[cell]=true
		for side in SIDES:affected[cell+side]=true
	var modified:=false
	for cell in affected:
		var id:=StringName("bank:%d:%d"%[cell.x,cell.y])
		var eligible:=_bank_geometry(cell)
		if eligible==banks.has(cell):continue
		modified=true
		if eligible:
			banks[cell]=id;_bank_cells[id]=cell
			_bank_points[id]=Coordinates.to_sim(fields.geometry.cell_to_world(cell))
		else:banks.erase(cell);_bank_cells.erase(id);_bank_points.erase(id)
	if modified:
		_invalidate_claims()
		changed.emit()
func building_id(id: StringName) -> StringName:
	return StringName(String(id).trim_prefix("well:")) if String(id).begins_with("well:") else &""
func point(id: StringName) -> Variant:
	if _bank_cells.has(id):
		var cell: Vector2i=_bank_cells[id]
		if fields.terrain(cell)!=fields.Terrain.WATER and navigation.is_cell_walkable(cell):return _bank_points[id]
		return null
	var building: RefCounted=_wells.get(building_id(id))
	return locations.get_resource_position(building.id) if building!=null and building.is_built() else null
func exists(id: StringName) -> bool:return point(id) is Vector2
func _bank_free(id: StringName, owner: StringName = &"") -> bool:
	var target: Variant=point(id)
	if not target is Vector2:return false
	for other in _claims:
		if other==owner or not _bank_cells.has(_claims[other].id):continue
		var occupied: Variant=point(_claims[other].id)
		if occupied is Vector2 and Coordinates.length_to_world(occupied.distance_to(target))<2.0*Geometry.RESIDENT_RADIUS:return false
	return true
func available(id: StringName) -> bool:
	return exists(id) and (not _bank_cells.has(id) or _bank_free(id))
func candidates() -> Array:
	var result: Array=[]
	for id in _bank_cells:
		if available(id):result.append(Source.new(Source.Kind.WATER,id))
	for id in _wells:
		var key:=StringName("well:"+String(id))
		if available(key):result.append(Source.new(Source.Kind.WATER,key))
	return result
func reserve(id: StringName, owner: StringName) -> bool:
	if owner.is_empty() or _claims.has(owner) or not available(id) or (_bank_cells.has(id) and not _bank_geometry(_bank_cells[id])):return false
	_claims[owner]={"id":id,"well":_wells.get(building_id(id))}
	changed.emit();return true
func reserved(id: StringName, owner: StringName) -> bool:
	var claim: Dictionary=_claims.get(owner,{})
	return not claim.is_empty() and claim.id==id and exists(id) and (not _bank_cells.has(id) or _bank_geometry(_bank_cells[id])) and (claim.well==null or _wells.get(building_id(id))==claim.well) and (not _bank_cells.has(id) or _bank_free(id,owner))
func pickup(id: StringName, owner: StringName) -> bool:
	if not reserved(id,owner):return false
	_claims.erase(owner) # Release access before inventory's guarded receive publishes one cargo.
	changed.emit();return true
func release(id: StringName, owner: StringName) -> void:
	if _claims.get(owner,{}).get("id",&"")==id:_claims.erase(owner);changed.emit()
func uses_cell(cell: Vector2i) -> bool:
	return _claims.values().any(func(claim):return _bank_cells.get(claim.id)==cell)

func _invalidate_claims() -> void:
	for owner in _claims.keys():
		var claim: Dictionary=_claims[owner]
		if not exists(claim.id) or (claim.well!=null and _wells.get(building_id(claim.id))!=claim.well):_claims.erase(owner)
