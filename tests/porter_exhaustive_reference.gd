extends "res://scripts/logistics_controller.gd"
## Frozen pre-optimization exhaustive selector; intentionally independent of lazy helpers.
func collect_candidates(resident_id: String) -> Array:
	# Call at WORK selection (or explicit read-only debug/tests), not world updates.
	var resident: ResidentData = _residents.get(resident_id)
	if not _can_claim(resident) or not position_provider.is_valid(): return []
	var position: Variant = position_provider.call(resident_id)
	if not position is Vector2: return []
	var candidates: Array = []
	for pair in _pairs():
		if not _porter_pair(resident,pair.source,pair.destination) or not _valid_pair(pair): continue
		var candidate := Candidate.new()
		candidate.source = pair.source
		candidate.source_ref = Source.new(Source.Kind.CONTAINER,pair.source.id)
		candidate.destination = pair.destination
		candidate.resource_type = pair.get("resource",FOOD)
		candidate.world_urgency = Priority.export_priority(pair.source.resources, candidate.resource_type, pair.source.logistics_weight) if pair.export else Priority.import_priority(pair.destination.resources, candidate.resource_type, pair.destination.logistics_weight)
		if not sources.reachable(position,_point(pair.source)) or not sources.reachable(_point(pair.source),_point(pair.destination)): continue
		candidate.route_distance = position.distance_to(_point(pair.source)) + _point(pair.source).distance_to(_point(pair.destination))
		candidate.distance_penalty = distance_penalty(candidate.route_distance)
		candidate.personal_modifier = _get_personal_delivery_modifier(resident, candidate)
		candidate.porter_score = candidate.world_urgency - candidate.distance_penalty + candidate.personal_modifier
		candidates.append(candidate)
	var base: BuildingInstance = _buildings.get(resident.work_location_id)
	if is_instance_valid(sources.ground) and base != null and _point(base) is Vector2:
		for drop in sources.ground.drops:
			var source_ref := Source.new(Source.Kind.GROUND,drop.id)
			if not sources.available(source_ref,drop.resource_type) or not base.definition.allows_external_import(drop.resource_type) or base.resources.get_available_free_capacity(drop.resource_type)<1: continue
			if not sources.reachable(position,drop.world_position) or not sources.reachable(drop.world_position,_point(base)): continue
			var candidate := Candidate.new()
			candidate.source_ref = source_ref
			candidate.destination = base
			candidate.resource_type = drop.resource_type
			candidate.world_urgency = Priority.import_priority(base.resources,drop.resource_type,base.logistics_weight)
			candidate.route_distance = position.distance_to(drop.world_position)+drop.world_position.distance_to(_point(base))
			candidate.distance_penalty = distance_penalty(candidate.route_distance)
			candidate.personal_modifier = _get_personal_delivery_modifier(resident,candidate)
			candidate.porter_score = candidate.world_urgency-candidate.distance_penalty+candidate.personal_modifier+Balance.PORTER_GROUND_CLEANUP_BONUS
			candidates.append(candidate)
	return candidates
