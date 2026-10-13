extends SceneTree
const PlayerAPI = preload("res://scripts/player_control.gd")
const Data = preload("res://scripts/resident_data.gd")
const Building = preload("res://scripts/building_instance.gd")
const Definition = preload("res://scripts/building_definition.gd")
const P = preload("res://scripts/resident_profession.gd").Type
const BT = preload("res://scripts/building_type.gd").Type
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func resident(id: String) -> RefCounted: return Data.new(id,id,30,P.NONE)
func run() -> void:
	for category in BT.values():
		var building := Building.new(&"work",Definition.for_type(category))
		var expected := 0 if category == BT.HOME else (2 if category in [BT.STORAGE,BT.TOWN_CENTER] else 1)
		check(building.definition.porter_capacity == expected,"Separate type capacity")
		check(Definition.new(&"custom",category,"Custom",Vector2.ONE).porter_capacity==expected,"Constructor shares type capacity defaults")
		var type_population: Array = [resident("a"),resident("b"),resident("c")]
		var type_player := PlayerAPI.new()
		type_player.setup(type_population,[building])
		for index in 3:
			check(type_player.assign_workplace(type_population[index].id,building.id,P.PORTER) == (index < expected),"Domain capacity for type %d worker %d" % [category,index])
		check(type_player.get_porters(building.id).size() == expected,"Derived Porter count")
		if expected == 0: continue
		check(type_player.assign_workplace("a",building.id,P.PORTER) and type_player.get_porters(building.id).size()==expected,"Repeat assignment is idempotent")
		check(type_player.get_free_staff_places(building.id,P.PORTER)==0,"No free staffed places")
		check(type_player.workplace_assignment_error("c",building.id,P.PORTER).contains("Места носильщиков заняты"),"Clear category-specific refusal")
		check(type_player.clear_work_assignment("a") and type_population[0].profession==P.PORTER,"Unassignment preserves profession")
		check(type_player.assign_workplace("c",building.id,P.PORTER),"Released position reusable")
		type_player.unregister_resident("c")
		check(type_player.get_porters(building.id).size()==expected-1,"Unregister frees derived place")
		type_player.unregister_building(building.id)
		check(type_player.get_building(building.id)==null and type_population.all(func(actor): return actor.work_location_id.is_empty()),"Building removal invalidates relationships")
	# Production categories and legacy inference remain independent.
	var hut := Building.new(&"hut",Definition.for_type(BT.GATHERER_HUT))
	var storage := Building.new(&"storage",Definition.for_type(BT.STORAGE))
	var population: Array = []
	for index in 7: population.append(resident("worker%d"%index))
	var player := PlayerAPI.new()
	player.setup(population,[hut,storage])
	for index in 4: check(player.assign_workplace(population[index].id,hut.id),"Legacy Hut assigns Gatherer")
	check(player.assign_workplace("worker4",hut.id,P.PORTER),"Explicit Porter on production workplace")
	check(player.get_production_workers(hut.id).size()==4 and player.get_porters(hut.id).size()==1 and player.get_workplace_workers(hut.id).size()==4,"Four production plus one logistics; wrapper never mixes")
	check(hut.definition.worker_capacity==4,"Production capacity unchanged")
	check(not player.assign_workplace("worker4",hut.id,P.GATHERER) and population[4].profession==P.PORTER,"Failed role switch preserves assignment")
	check(player.assign_workplace("worker5",storage.id) and player.assign_workplace("worker6",storage.id),"Legacy Storage assigns Porter")
	var before_revision: int = population[4].work_assignment_revision
	check(not player.assign_workplace("worker4",storage.id,P.PORTER) and population[4].work_location_id==hut.id and population[4].work_assignment_revision==before_revision,"Failed reassign preserves old role/location/revision")
	check(player.assign_profession("worker0",P.PORTER) and population[0].work_location_id.is_empty() and population[0].profession==P.PORTER,"Accepted profession, no fake full workplace")
	check(player.get_production_workers(hut.id).size()==3 and player.get_porters(hut.id).size()==1,"Profession change frees only prior category")
	check(not player.assign_workplace("worker0",&"missing",P.PORTER),"Unknown workplace rejected")
	var site := Building.new(&"site",Definition.for_type(BT.SAWMILL),Vector2.ZERO,Building.State.UNDER_CONSTRUCTION)
	player.register_building(site)
	check(not player.assign_workplace("worker0",site.id,P.PORTER) and player.workplace_assignment_error("worker0",site.id,P.PORTER).contains("строится"),"Unbuilt workplace rejected")
	# Stable-ID admission, not eviction by ordinary assignment.
	var historic: Array = []
	for id in ["z","d","c","b","a"]:
		var actor := resident(id)
		actor.profession=P.PORTER
		actor.work_location_id=storage.id
		historic.append(actor)
	var producer := resident("production")
	producer.profession=P.GATHERER
	producer.work_location_id=hut.id
	historic.append(producer)
	var normalized := PlayerAPI.new()
	normalized.work_assignment_changed.connect(func(_id): check(normalized.get_porters(storage.id).size()==2,"Normalization callbacks see fully corrected group"))
	normalized.setup(historic,[storage,hut])
	check(normalized.get_porters(storage.id).map(func(actor): return actor.id).has("a") and normalized.get_porters(storage.id).size()==2,"First two stable IDs admitted")
	check(historic[0].profession==P.PORTER and historic[0].work_location_id.is_empty() and producer.work_location_id==hut.id,"Overflow unassigned, production preserved")
	check(normalized.normalize_porter_assignments().is_empty(),"Normalization idempotent")
	# Synchronous reentrant assignment sees the already-committed first worker.
	var small := Building.new(&"small",Definition.for_type(BT.SAWMILL))
	var a := resident("first")
	var b := resident("second")
	var reentrant := PlayerAPI.new()
	reentrant.setup([a,b],[small])
	var nested: Array = []
	reentrant.profession_changed.connect(func(_id): nested.append(reentrant.assign_workplace(b.id,small.id,P.PORTER)),CONNECT_ONE_SHOT)
	check(reentrant.assign_workplace(a.id,small.id,P.PORTER) and nested==[false],"Reentrant last-place attempt rejected")
	check(reentrant.get_porters(small.id).size()==1 and b.profession==P.NONE,"No ghost staff relationship")
	# Revision captures ABA even if legacy tooling writes fields directly.
	var revision: int = a.work_assignment_revision
	a.work_location_id=&"other"
	a.work_location_id=small.id
	check(a.work_assignment_revision==revision+2,"Assignment ABA invalidates transaction context")
	print("Porter staffing: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
