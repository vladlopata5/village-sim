extends RefCounted
## Optional physical venue for SocialWorld's existing ConversationGroup, not a social selector.
const Types=preload("res://scripts/building_type.gd").Type
const Purpose=preload("res://scripts/world_3d/building_slot_3d.gd").Purpose
const C=preload("res://scripts/world_3d/world_coordinates.gd")
const Balance=preload("res://scripts/balance_config.gd")
const Need=preload("res://scripts/need_type.gd").Type
const Activity=preload("res://scripts/resident_activity.gd").Type
var _world: Node
var _buildings: Dictionary={}
var _closing: Dictionary={}
var _planning: Dictionary={} # Fence synchronous slot callbacks while the initial pair is claimed.
func setup(world: Node) -> void:
	_world=world
	world.social_world.venues=self
	world.game_time.minute_changed.connect(_on_minute)
	world.building_uses.removed.connect(_removed)
	world.tree_exiting.connect(_shutdown)
func register(building: RefCounted) -> void:
	if building.type!=Types.GAZEBO or _buildings.has(building.id):return
	_buildings[building.id]=building
	building.construction_changed.connect(_building_changed.bind(building.id))
func _building_changed(id: StringName) -> void:
	var building: RefCounted=_buildings.get(id)
	if building==null or not building.is_built():_cancel_building(id)
func _removed(id: StringName) -> void:
	_cancel_building(id)
	_buildings.erase(id)
func _cancel_building(id: StringName) -> void:
	for group in _world.social_world.groups.values():
		if group.venue_id==id:_dissolve(group)
func _shutdown() -> void:
	for group in _world.social_world.groups.values():
		if not group.venue_id.is_empty():_dissolve(group)
func _valid(group: RefCounted) -> bool:
	var building: RefCounted=_buildings.get(group.venue_id)
	return not _closing.has(group.id) and _world.social_world.groups.get(group.id)==group and building!=null and building.is_built() and _world.building_uses.view(building.id)!=null
func _for(id: String):
	for group in _world.social_world.groups.values():
		if group.venue_claims.has(id):return group
	return null
func can_join(group: RefCounted,id: String) -> bool:
	if group.venue_id.is_empty():return true
	if not _valid(group) or not group.venue_started or group.venue_claims.has(id):return false
	return not _world.building_uses.choices(group.venue_id,Purpose.VISITOR,C.to_world(_world.social_world.position_of(id))).is_empty()
func _claim(building_id: StringName,id: String) -> Marker3D:
	var origin: Vector3=C.to_world(_world.social_world.position_of(id))
	for marker in _world.building_uses.choices(building_id,Purpose.VISITOR,origin):
		if not _world.navigation.has_walkable_path(origin,marker.global_position):continue
		var claimed: Marker3D=_world.building_uses.acquire(building_id,Purpose.VISITOR,id,origin,marker)
		var building: RefCounted=_buildings.get(building_id)
		if not is_instance_valid(claimed):return null
		if building==null or not building.is_built() or _world.social_world.get_runtime(id)==null or claimed.occupant!=id:
			_world.building_uses.release(building_id,claimed,id)
			return null
		return claimed
	return null
func _option(group: RefCounted,id: String,original: Dictionary = {}) -> Dictionary:
	var option:=original.duplicate()
	option.merge({"target_id":original.get("target_id",id),"group_id":group.id,"venue_group":group.id,"venue_resident":id,"venue_point":C.to_sim(group.venue_claims[id].global_position)},true)
	return option
func _reserve(group: RefCounted,id: String) -> bool:
	var marker:=_claim(group.venue_id,id)
	if marker==null:return false
	if not _valid(group):
		_world.building_uses.release(group.venue_id,marker,id)
		return false
	group.venue_claims[id]=marker
	group.pending[id]={"arrived":false,"deadline":_world.game_time.total_minutes+Balance.GAZEBO_MEETING_TIMEOUT_MINUTES}
	return true
func plan(id: String,option: Dictionary) -> Dictionary:
	if option.has("venue_group"):return option if valid_option(option) and option.venue_resident==id else {}
	if option.group_id!=0:
		var group: RefCounted=_world.social_world.groups.get(option.group_id)
		if group==null:return {}
		if group.venue_id.is_empty():return option
		if not can_join(group,id) or not _reserve(group,id):return {}
		return _option(group,id,option)
	# A chosen idle partner is still the social target; the gazebo only changes their meeting place.
	if _for(id)!=null or _for(option.target_id)!=null:return {}
	var target: Node=_world.social_world.get_runtime(option.target_id)
	if target==null or not _world.social_world._idle_available(target):return {}
	var origin: Vector3=C.to_world(_world.social_world.position_of(id))
	var other: Vector3=C.to_world(_world.social_world.position_of(option.target_id))
	var candidates: Array=_buildings.values().filter(func(building):return building.is_built() and C.to_world(building.position).distance_to(origin)<=Balance.GAZEBO_SEARCH_RADIUS and C.to_world(building.position).distance_to(other)<=Balance.GAZEBO_SEARCH_RADIUS)
	candidates.sort_custom(func(a,b):
		var da: float=C.to_world(a.position).distance_squared_to(origin);var db: float=C.to_world(b.position).distance_squared_to(origin)
		return String(a.id)<String(b.id) if is_equal_approx(da,db) else da<db)
	for building in candidates:
		if _planning.has(building.id):continue
		if _world.social_world.groups.values().any(func(other_group):return other_group.venue_id==building.id):continue
		_planning[building.id]=true
		var first:=_claim(building.id,id)
		if first==null:
			_planning.erase(building.id)
			continue
		var second:=_claim(building.id,option.target_id)
		if second==null:
			_world.building_uses.release(building.id,first,id)
			_planning.erase(building.id)
			continue
		var group=_world.social_world.create_group(building.position)
		group.venue_id=building.id
		group.venue_claims={id:first,option.target_id:second}
		_planning.erase(building.id)
		for member in group.venue_claims:group.pending[member]={"arrived":false,"deadline":_world.game_time.total_minutes+Balance.GAZEBO_MEETING_TIMEOUT_MINUTES}
		if target.intents.current_intent.reason_id==&"wander":target.intents.cancel_current(target.intents.current_intent)
		if not _valid(group) or not target.social._start_social(_option(group,option.target_id,{"target_id":id}),target.data.get_need(Need.SOCIAL).get_priority()):
			_dissolve(group)
			return option
		return _option(group,id,option) if _valid(group) else {}
	return option # No venue: exactly the original street action.
func valid_option(option: Dictionary) -> bool:
	var group: RefCounted=_world.social_world.groups.get(option.get("venue_group",0))
	if group==null or not _valid(group):return false
	if group.venue_started and option.get("exact_target",false):
		var target: Node=_world.social_world.get_runtime(option.target_id)
		if target==null or option.target_id not in group.participants or target.data.activity!=Activity.TALKING:return false
	var id: String=option.get("venue_resident","")
	var marker: Marker3D=group.venue_claims.get(id)
	return is_instance_valid(marker) and marker.occupant==id
func arrive(id: String,option: Dictionary) -> bool:
	if not valid_option(option) or option.venue_resident!=id:return false
	var group: RefCounted=_world.social_world.groups[option.venue_group]
	if not group.pending.has(id):return id in group.participants
	if C.to_world(_world.social_world.position_of(id)).distance_to(group.venue_claims[id].global_position)>.1:return false
	group.pending[id].arrived=true
	if not group.venue_started and group.pending.values().any(func(row):return not row.arrived):
		_world.social_world.get_runtime(id).data.activity=Activity.IDLE
		return true
	_world.social_world.membership_changing.emit()
	if not _valid(group):return false
	var joining: Array=[id] if group.venue_started else group.pending.keys()
	group.venue_started=true
	for member in joining:
		group.pending.erase(member)
		group.add_participant(member,C.to_sim(group.venue_claims[member].global_position))
	for member in joining:
		if not _valid(group):return false
		var actor: Node=_world.social_world.get_runtime(member)
		if actor!=null:actor.social.begin_talking()
	_world.social_world.membership_changed.emit()
	for member in joining:
		if _valid(group) and member in group.participants:_world.social_world.conversation_joined.emit(member)
	return _valid(group)
func leave(id: String) -> bool:
	var group=_for(id)
	if group==null:return false
	if _closing.has(group.id):return true
	if not group.venue_started:
		_dissolve(group)
		return true
	_world.social_world.membership_changing.emit()
	if not _valid(group) or not group.venue_claims.has(id):return true
	var marker: Marker3D=group.venue_claims[id]
	group.venue_claims.erase(id);group.pending.erase(id);group.remove_participant(id)
	_world.building_uses.release(group.venue_id,marker,id)
	if group.participants.size()<2:_dissolve(group)
	else:_world.social_world.membership_changed.emit()
	return true
func _dissolve(group: RefCounted) -> void:
	if _closing.has(group.id) or _world.social_world.groups.get(group.id)!=group:return
	_closing[group.id]=true
	_world.social_world.membership_changing.emit()
	_world.social_world.groups.erase(group.id) # Reentrant cleanup cannot find an active meeting.
	var claims: Dictionary=group.venue_claims.duplicate()
	group.venue_claims.clear();group.pending.clear();group.participants.clear();group.positions.clear()
	for id in claims:_world.building_uses.release(group.venue_id,claims[id],id)
	for id in claims:
		var actor: Node=_world.social_world.get_runtime(id)
		if actor!=null and actor.social._option.get("venue_group",0)==group.id:actor.social.cancel_social()
	_world.social_world.membership_changed.emit()
	_closing.erase(group.id)
func _on_minute(minute: int) -> void:
	for group in _world.social_world.groups.values():
		if group.venue_id.is_empty():continue
		if not _valid(group):
			_dissolve(group)
			continue
		for id in group.pending.keys():
			if group.pending.has(id) and minute>=int(group.pending[id].deadline):
				var actor: Node=_world.social_world.get_runtime(id)
				if actor!=null:actor.social.cancel_social()
				else:leave(id)
