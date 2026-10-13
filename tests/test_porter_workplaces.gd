extends SceneTree
const PlayerAPI = preload("res://scripts/player_control.gd")
const Data = preload("res://scripts/resident_data.gd")
const Building = preload("res://scripts/building_instance.gd")
const Definition = preload("res://scripts/building_definition.gd")
const Drop = preload("res://scripts/ground_resource.gd")
const Ground = preload("res://scripts/ground_resources.gd")
const Ref = preload("res://tests/porter_exhaustive_reference.gd")
const Source = preload("res://scripts/resource_source_ref.gd")
const CandidateValue = preload("res://scripts/delivery_candidate.gd")
const P = preload("res://scripts/resident_profession.gd").Type
const BT = preload("res://scripts/building_type.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
class Counted extends "res://scripts/logistics_controller.gd":
	var global_scans := 0
	var policies := 0
	var routes := 0
	func _pairs() -> Array:
		global_scans += 1
		return super._pairs()
	func allows_external_delivery(a: BuildingInstance,b: BuildingInstance,resource: int) -> bool:
		policies += 1
		return super.allows_external_delivery(a,b,resource)
	func _routes_available(candidate: Candidate,point: Vector2) -> bool:
		routes += 1
		return super._routes_available(candidate,point)
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func fixture(own: int = BT.TOWN_CENTER) -> Dictionary:
	var buildings: Array = []
	for category in BT.values():
		var building := Building.new(StringName("building%d"%category),Definition.for_type(category),Vector2(30+category*15,20))
		for resource in R.values(): building.resources.set_capacity(resource,20)
		buildings.append(building)
	var actors: Array = []
	for index in 3: actors.append(Data.new("p%d"%index,"Porter%d"%index,30,P.NONE))
	var player := PlayerAPI.new()
	player.setup(actors,buildings)
	check(player.assign_workplace(actors[0].id,buildings[own].id,P.PORTER),"Fixture uses authoritative normal assignment")
	var service := Counted.new()
	service.assignment_control=player
	service.setup(buildings[BT.TOWN_CENTER],buildings[BT.FOOD],actors[0])
	for building in buildings: service.register_building(building)
	for actor in actors: service.register_resident(actor)
	player.resident_unregistered.connect(service.unregister_resident)
	service.position_provider=func(_id): return Vector2(-100,25)
	var ground_owner := Ground.new()
	service.sources.ground=ground_owner
	return {"buildings":buildings,"player":player,"actors":actors,"actor":actors[0],"base":buildings[own],"service":service,"ground":ground_owner}
func ground(f: Dictionary, resource: int, index: int = 0) -> RefCounted:
	var drop := Drop.new(resource,3,Vector2(15+index,5),0)
	drop.id=StringName("ground%d"%index)
	check(f.ground.register_drop(drop),"Real owner-managed Ground registration")
	return drop
func has_pair(pool: Array, a: RefCounted, b: RefCounted, resource: int) -> bool:
	return pool.any(func(c): return c.source==a and c.destination==b and c.resource_type==resource)
func reference(f: Dictionary) -> RefCounted:
	var reference_value := Ref.new()
	reference_value.setup(f.base,null,f.actor)
	for building in f.service._buildings.values(): reference_value.register_building(building)
	reference_value.position_provider=f.service.position_provider
	reference_value.sources.ground=f.ground
	reference_value.sources.route_available=f.service.sources.route_available
	return reference_value
func chosen_candidate(f: Dictionary) -> RefCounted:
	var result := CandidateValue.new()
	result.source=f.buildings[BT.TOWN_CENTER]
	result.source_ref=Source.new(Source.Kind.CONTAINER,result.source.id)
	result.destination=f.buildings[BT.SAWMILL]
	result.resource_type=R.LOG
	return result
func run() -> void:
	var positive := [[BT.TOWN_CENTER,BT.LUMBERJACK_HUT,BT.TOWN_CENTER,R.LOG],[BT.SAWMILL,BT.LUMBERJACK_HUT,BT.SAWMILL,R.LOG],[BT.LUMBERJACK_HUT,BT.LUMBERJACK_HUT,BT.SAWMILL,R.LOG],[BT.TOWN_CENTER,BT.QUARRY,BT.TOWN_CENTER,R.STONE],[BT.QUARRY,BT.QUARRY,BT.STORAGE,R.STONE],[BT.FOOD,BT.GATHERER_HUT,BT.FOOD,R.FOOD],[BT.GATHERER_HUT,BT.GATHERER_HUT,BT.FOOD,R.FOOD],[BT.STORAGE,BT.SAWMILL,BT.STORAGE,R.PLANK],[BT.SAWMILL,BT.SAWMILL,BT.TOWN_CENTER,R.PLANK],[BT.TOWN_CENTER,BT.TOWN_CENTER,BT.SAWMILL,R.LOG]]
	for row in positive:
		var positive_case := fixture(row[0])
		var source = positive_case.buildings[row[1]]
		var destination = positive_case.buildings[row[2]]
		source.resources.add(row[3],1)
		check(has_pair(positive_case.service.collect_candidates(positive_case.actor.id),source,destination,row[3]),"Positive own-endpoint flow %s"%str(row))
		var job = positive_case.service.claim_best_job(positive_case.actor.id)
		check(job!=null and job.workplace_location_id==positive_case.base.id,"Claim captures proper workplace before publication")
		if job!=null: check(positive_case.service.cancel_job(job),"Positive case cleanup")
		positive_case.ground.free()
	for row in [[BT.TOWN_CENTER,R.LOG],[BT.STORAGE,R.FOOD],[BT.SAWMILL,R.LOG],[BT.STORAGE,R.PLANK],[BT.TOWN_CENTER,R.STONE]]:
		var ground_case := fixture(row[0])
		var drop := ground(ground_case,row[1])
		var job = ground_case.service.claim_best_job(ground_case.actor.id)
		check(job!=null and job.source_ref.id==drop.id and job.destination_location_id==ground_case.base.id,"Ground import uses actual own destination")
		if job!=null: ground_case.service.cancel_job(job)
		check(drop.amount==3 and drop.reservation_owner_id.is_empty(),"No quantity change on cancelled claim")
		ground_case.ground.free()
	for own in [BT.LUMBERJACK_HUT,BT.QUARRY]:
		var closed_case := fixture(own)
		ground(closed_case,R.LOG if own==BT.LUMBERJACK_HUT else R.STONE)
		check(not closed_case.service.has_available_job(closed_case.actor.id),"Closed external import never becomes Porter INTERNAL")
		check(closed_case.service.claim_internal(closed_case.actor.id,Source.new(Source.Kind.GROUND,&"ground0"),closed_case.base,R.LOG if own==BT.LUMBERJACK_HUT else R.STONE,func(): return true)==null,"Cannot forge producer authorization")
		closed_case.ground.free()
	var f := fixture()
	f.buildings[BT.LUMBERJACK_HUT].resources.add(R.LOG,1)
	f.buildings[BT.SAWMILL].resources.add(R.LOG,1)
	var pool: Array = f.service.collect_candidates(f.actor.id)
	check(not has_pair(pool,f.buildings[BT.LUMBERJACK_HUT],f.buildings[BT.SAWMILL],R.LOG),"Foreign to foreign rejected")
	check(not has_pair(pool,f.buildings[BT.SAWMILL],f.base,R.LOG),"Protected Sawmill LOG never exported")
	check(not has_pair(pool,f.base,f.buildings[BT.STORAGE],R.LOG),"No Storage balancing")
	f.player.clear_work_assignment(f.actor.id)
	check(not f.service.has_available_job(f.actor.id),"Unassigned Porter has no work")
	f.ground.free()
	# Every precommit callback change must roll back exactly the owned attempt.
	for point in ["out","in"]:
		for mutation in ["workplace","profession","unassign","aba","capacity","remove","unregister"]:
			f=fixture()
			f.base.resources.add(R.LOG,1)
			var candidate := chosen_candidate(f)
			var callback := func(_resource):
				match mutation:
					"workplace": f.player.assign_workplace(f.actor.id,f.buildings[BT.STORAGE].id,P.PORTER)
					"profession": f.player.assign_profession(f.actor.id,P.NONE)
					"unassign": f.player.clear_work_assignment(f.actor.id)
					"aba":
						f.player.assign_workplace(f.actor.id,f.buildings[BT.STORAGE].id,P.PORTER)
						f.player.assign_workplace(f.actor.id,f.base.id,P.PORTER)
					"capacity": f.base.definition.porter_capacity=0
					"remove": f.service.remove_building(f.base.id)
					"unregister": f.player.unregister_resident(f.actor.id)
			var signal_container = f.base.resources if point=="out" else candidate.destination.resources
			signal_container.reservations_changed.connect(callback,CONNECT_ONE_SHOT)
			check(f.service._claim_delivery(f.actor,candidate)==null,"Precommit rejects %s at reserve_%s"%[mutation,point])
			check(f.service.jobs.is_empty() and f.service._inbound.is_empty() and f.service.sources._claims.is_empty(),"No published job or orphan ownership")
			check(f.base.resources.get_reserved_out(R.LOG)==0 and candidate.destination.resources.get_reserved_in(R.LOG)==0 and f.actor.inventory.amount==0 and f.base.resources.get_amount(R.LOG)==1,"Rollback preserves actual source quantity and clears both reservations")
			f.ground.free()
	# Notifications after publication may change assignment; old snapshot stays committed.
	f=fixture()
	f.base.resources.add(R.LOG,1)
	var snapshots: Array = []
	f.service.changed.connect(func():
		var published = f.service.get_job(f.actor.id)
		if published!=null:
			snapshots.append(published.workplace_location_id)
			f.player.assign_workplace(f.actor.id,f.buildings[BT.QUARRY].id,P.PORTER),CONNECT_ONE_SHOT)
	var committed = f.service._claim_delivery(f.actor,chosen_candidate(f))
	check(committed!=null and snapshots==[f.base.id] and committed.workplace_location_id==f.base.id and f.actor.work_location_id==f.buildings[BT.QUARRY].id,"Publication sees captured old base; later reassignment does not rewrite it")
	if committed!=null:
		check(committed.validation.call(),"Committed validation ignores new live assignment")
		f.base.definition.porter_capacity=0
		check(committed.validation.call(),"Administrative capacity change does not cancel an already confirmed safe trip")
		f.service.cancel_job(committed)
	f.ground.free()
	# Source and destination endpoint Porter compete without special ownership priority.
	f=fixture(BT.LUMBERJACK_HUT)
	f.buildings[BT.LUMBERJACK_HUT].resources.add(R.LOG,1)
	check(f.player.assign_workplace(f.actors[1].id,f.buildings[BT.SAWMILL].id,P.PORTER),"Second endpoint normal staffing")
	var first = f.service.claim_best_job(f.actor.id)
	var second = f.service.claim_best_job(f.actors[1].id)
	check(first!=null and second==null,"One actual source unit cannot be double-claimed")
	if first!=null: f.service.cancel_job(first)
	second=f.service.claim_best_job(f.actors[1].id)
	check(second!=null and second.destination_location_id==f.buildings[BT.SAWMILL].id,"Loser can import after release")
	if second!=null: f.service.cancel_job(second)
	f.ground.free()
	# Nested competing claim cannot steal reservations from a rejected attempt.
	f=fixture()
	f.base.resources.add(R.LOG,1)
	check(f.player.assign_workplace(f.actors[1].id,f.base.id,P.PORTER),"Second normal Porter for reentrant competition")
	var nested: Array = []
	f.base.resources.reservations_changed.connect(func(_resource):
		f.player.assign_workplace(f.actor.id,f.buildings[BT.QUARRY].id,P.PORTER)
		nested.append(f.service.claim_best_job(f.actors[1].id)),CONNECT_ONE_SHOT)
	check(f.service._claim_delivery(f.actor,chosen_candidate(f))==null and nested==[null],"In-flight rollback excludes nested competing claim")
	var winner = f.service.claim_best_job(f.actors[1].id)
	check(winner!=null and f.base.resources.get_reserved_out(R.LOG)==1,"Fresh contender claims only after owned rollback")
	if winner!=null: f.service.cancel_job(winner)
	f.ground.free()
	# Independent exhaustive enumeration covers all supported assignments and changing worlds.
	var rng := RandomNumberGenerator.new()
	rng.seed=937
	var allowed := [BT.TOWN_CENTER,BT.STORAGE,BT.LUMBERJACK_HUT,BT.QUARRY,BT.GATHERER_HUT,BT.SAWMILL,BT.FOOD]
	for iteration in 200:
		f=fixture(allowed[iteration%allowed.size()])
		for building in f.buildings:
			building.position=Vector2(rng.randi_range(-300,300),rng.randi_range(-200,200))
			for resource in R.values():
				var amount := rng.randi_range(0,10)
				if amount>0: building.resources.add(resource,amount)
				if iteration%3==0: building.resources.reserve_in(resource,2)
		for index in 5: ground(f,R.values()[index%4],index)
		if iteration%2==0: f.service.sources.route_available=func(a,b): return (roundi(a.x)+roundi(b.x))%7!=0
		var exhaustive := reference(f)
		var expected = exhaustive._best(exhaustive.collect_candidates(f.actor.id))
		check(f.service.has_available_job(f.actor.id)==(expected!=null),"Read-only availability equals exhaustive existence")
		check(f.service.jobs.is_empty() and f.service._inbound.is_empty() and f.service.sources._claims.is_empty(),"Probe owns no reservation")
		var actual = f.service.claim_best_job(f.actor.id)
		check((actual==null)==(expected==null),"Exact winner presence")
		if actual!=null and expected!=null:
			check(actual.source_ref.stable_key()==expected.source_ref.stable_key() and actual.destination_location_id==expected.destination.id and actual.priority==expected.porter_score,"Exact score, stable key and source/destination match independent reference")
			f.service.cancel_job(actual)
		check(f.service.global_scans==0,"Production never enumerates global pairs")
		f.ground.free()
	print("Porter workplaces: %d checks, %d failures; 200 seeded fixtures"%[checks,failures])
	quit(1 if failures else 0)
