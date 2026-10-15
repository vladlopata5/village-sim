extends SceneTree
const Areas = preload("res://scripts/ground_search_areas.gd")
const Balance = preload("res://scripts/balance_config.gd")
const WorkArea = preload("res://scripts/work_area.gd")
const Sources = preload("res://scripts/resource_sources.gd")
const Source = preload("res://scripts/resource_source_ref.gd")
const Ground = preload("res://scripts/ground_resources.gd")
const Building = preload("res://scripts/building_instance.gd")
const Definition = preload("res://scripts/building_definition.gd")
const T = preload("res://scripts/building_type.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	var clock = preload("res://scripts/game_time.gd").new(); root.add_child(clock); clock.set_process(false)
	var ground := Ground.new(); root.add_child(ground); ground.setup(clock)
	var sources := Sources.new(); sources.bind_ground(ground)
	var base := Building.new(&"work",Definition.for_type(T.STORAGE),Vector2(1000,0))
	var producer := Building.new(&"producer",Definition.for_type(T.GATHERER_HUT),Vector2(-1200,0))
	sources.buildings = {base.id:base,producer.id:producer}
	base.resources.set_capacity(R.LOG,20); base.resources.add(R.LOG,2)
	producer.resources.set_capacity(R.FOOD,5); producer.resources.add(R.FOOD,1)
	var area := WorkArea.new(&"assigned",Vector2(2000,0),50)
	var nearby = ground.create_drop(R.LOG,1,Vector2(100,0))
	var outside = ground.create_drop(R.LOG,1,Vector2(100.01,0))
	var work_edge = ground.create_drop(R.LOG,1,Vector2(750,0))
	var area_edge = ground.create_drop(R.LOG,1,Vector2(2050,0))
	check(Balance.RESIDENT_GROUND_SEARCH_RADIUS==100 and base.definition.get_ground_search_radius()==250,"Documented defaults and simulation units")
	check(Areas.contains(nearby.world_position,Vector2.ZERO),"Inclusive resident boundary")
	check(not Areas.contains(outside.world_position,Vector2.ZERO),"Just outside resident circle")
	check(Areas.contains(work_edge.world_position,Vector2.ZERO,base),"Inclusive work-object boundary")
	check(not Areas.contains(Vector2(749.99,0),Vector2.ZERO,base),"Outside both circles")
	check(Areas.contains(area_edge.world_position,Vector2.ZERO,base,area),"Actual WorkArea inclusive boundary")
	check(not Areas.contains(Vector2(2050.01,0),Vector2.ZERO,base,area),"Outside all regions")
	check(Areas.contains(nearby.world_position,Vector2.ZERO,null,area),"Nearby resource allowed outside assigned WorkArea")
	check(not Areas.contains(Vector2.ZERO,null,base,area),"Missing resident context fails closed for ground")
	var all: Array = sources.ground_candidates(R.LOG,Vector2.ZERO,base,area)
	check(all.size()==3 and not all.any(func(ref): return ref.id==outside.id),"Union of independent regions")
	var overlapping = ground.create_drop(R.LOG,1,Vector2(1000,0))
	all=sources.ground_candidates(R.LOG,Vector2(1000,0),base)
	check(all.filter(func(ref): return ref.id==overlapping.id).size()==1,"One enumeration despite overlapping circles")
	check(sources.ground_candidates(R.LOG,Vector2.ZERO).size()==1,"No WorkArea/building: resident circle alone")
	base.definition.ground_search_radius=20
	check(not sources.ground_candidates(R.LOG,Vector2.ZERO,base).any(func(ref): return ref.id==work_edge.id),"Shrunk per-type radius is read live")
	base.definition.ground_search_radius=300
	check(sources.ground_candidates(R.LOG,Vector2.ZERO,base).any(func(ref): return ref.id==work_edge.id),"Expanded radius is read live")
	check(producer.definition.get_ground_search_radius()==250,"Override is isolated to its definition")
	base.position=Vector2(3000,0)
	check(not sources.ground_candidates(R.LOG,Vector2.ZERO,base).any(func(ref): return ref.id==work_edge.id),"Moved work object has no stale center")
	sources.buildings.erase(base.id)
	check(not sources.ground_candidates(R.LOG,Vector2.ZERO,base).any(func(ref): return ref.id==overlapping.id),"Removed work object contributes no circle")
	sources.buildings[base.id]=base
	var routes: Array = []
	sources.route_available=func(a,b): routes.append([a,b]); return b!=nearby.world_position
	var matches: Array = sources.find(R.LOG,Vector2.ZERO,Vector2(25,0))
	check(matches.size()==1 and matches[0].kind==Source.Kind.CONTAINER,"Unreachable local ground rejected; far container allowed")
	check(not routes.any(func(pair): return pair[1]==outside.world_position or pair[1]==area_edge.world_position),"Excluded ground never reaches path query")
	sources.route_available=Callable()
	check(sources.find(R.FOOD,Vector2.ZERO,Vector2(25,0))[0].id==producer.id,"Distant production buffer remains global")
	var ground_ref := Source.new(Source.Kind.GROUND,nearby.id)
	check(sources.reserve(ground_ref,R.LOG,&"one") and not sources.reserve(ground_ref,R.LOG,&"two"),"Last-resource reservation competition unchanged")
	check(sources.ground_candidates(R.LOG,Vector2.ZERO).is_empty(),"Reserved ground excluded from new selection")
	check(sources.reserved(ground_ref,R.LOG,&"one") and sources.pickup(ground_ref,R.LOG,&"one"),"Committed pickup has no admission radius check")
	var old_revision: int = sources.revision
	outside.world_position=Vector2(50,0)
	check(sources.revision>old_revision and sources.ground_candidates(R.LOG,Vector2.ZERO).size()==1,"Drop movement signals invalidate and restore selection")
	var registry = preload("res://scripts/work_areas.gd").new()
	var assigned = registry.create(Vector2(4000,0),50)
	var isolated = ground.create_drop(R.LOG,1,Vector2(4000,0))
	check(sources.ground_candidates(R.LOG,Vector2.ZERO,null,registry.get_area(assigned.id)).any(func(ref): return ref.id==isolated.id),"Assigned registry area resolves to real geometry")
	assigned.update(Vector2(5000,0),60)
	check(not sources.ground_candidates(R.LOG,Vector2.ZERO,null,registry.get_area(assigned.id)).any(func(ref): return ref.id==isolated.id),"Changed WorkArea changes new selection")
	registry.remove(assigned.id)
	check(not sources.ground_candidates(R.LOG,Vector2.ZERO,null,registry.get_area(assigned.id)).any(func(ref): return ref.id==isolated.id),"Removed WorkArea is not retained by caller")
	ground.free(); clock.free(); await process_frame
	print("Ground search geometry: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
