extends SceneTree
const F=preload("res://tests/residents_ui_fixture.gd")
const Fields=preload("res://scripts/farm_fields.gd")
const Definition=preload("res://scripts/building_definition.gd")
const Types=preload("res://scripts/building_type.gd").Type
const P=preload("res://scripts/resident_profession.gd").Type
const R=preload("res://scripts/resource_type.gd").Type
const C=preload("res://scripts/world_3d/world_coordinates.gd")
const Intent=preload("res://scripts/resident_intent.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func fixture() -> Dictionary:
	var world=F.create(self);world.farm_fields._last_day=world.game_time.get_day()
	var farm=F.building(world,Types.FARM,Vector3(-10,0,16))
	var actor=world.resident_runtimes[0]
	check(world.player_control.assign_workplace(actor.data.id,farm.id,P.FARMER),"Assign real farmer")
	farm.set_stock_target(R.WHEAT,0)
	return {"world":world,"farm":farm,"actor":actor}
func arrive(actor: Node) -> bool:
	for step in 20000:
		if actor.farmer.phase==actor.farmer.Phase.WORKING:return true
		if actor.farmer.phase==actor.farmer.Phase.NONE:return false
		actor.view._physics_process(0.05)
	return false
func one_field(world: Node, actor: Node) -> bool:
	if not actor.farmer.request_work() or not arrive(actor):return false
	world.game_time.advance(10)
	return true
func soil_and_sowing() -> void:
	var env:=fixture();var world=env.world;var farm=env.farm;var actor=env.actor
	farm.resources.add(R.WHEAT,1)
	check(actor.farmer.task().kind==&"PLOW","Farmer starts plowing despite available seed, until five prepared")
	check(actor.farmer.request_work(),"Claim first plow target")
	var cell: Vector2i=actor.farmer._target
	var stale=actor.farmer._intent
	actor.farmer._arrived(stale)
	check(actor.farmer.phase==actor.farmer.Phase.NONE and world.farm_fields.state(cell)==Fields.State.BARE,"Distant fake arrival cannot plow")
	check(actor.farmer.request_work() and arrive(actor),"Farmer physically reaches first cell")
	cell=actor.farmer._target
	world.game_time.advance(9)
	check(world.farm_fields.state(cell)==Fields.State.BARE,"Nine work minutes cannot finish plowing")
	world.game_time.advance(1)
	check(world.farm_fields.state(cell)==Fields.State.PLOWED and actor.farmer.phase==actor.farmer.Phase.NONE,"Exactly10 work minutes, independent dirt base")
	for index in 4:check(actor.farmer.task().kind==&"PLOW" and one_field(world,actor),"Continue preparation to five cells")
	check(world.farm_fields.plot_cells().size()==5 and actor.farmer.task().kind==&"SOW","Five cells prioritize sowing over further plowing")
	check(actor.farmer.request_work() and world.farm_fields.owned_cells(actor.farmer._owner).size()==5 and farm.resources.get_reserved_out(R.WHEAT)==1,"Sow claims five plus one concrete wheat before motion")
	check(farm.resources.get_amount(R.WHEAT)==1 and actor.farmer.phase==actor.farmer.Phase.TO_BUILDING,"Seed remains until first actual sow, physical building preparation required")
	check(arrive(actor),"Actual worker-slot preparation and approach to first seed cell")
	var old_intent=actor.farmer._intent
	world.game_time.advance(10)
	check(farm.resources.get_amount(R.WHEAT)==0 and farm.resources.get_reserved_out(R.WHEAT)==0,"First sow spends one wheat once")
	for index in 2:
		check(arrive(actor),"Approach next separately claimed cell")
		world.game_time.advance(10)
	var fields: Array=world.farm_fields.plot_cells()
	check(fields.filter(func(point):return world.farm_fields.state(point)==Fields.State.SOWN).size()==3,"Three completed sows persist")
	actor.intents.force_set_intent(Intent.new(Intent.Type.MOVE_TO,&"player",Vector2.ZERO,100,false),100)
	actor.farmer.cancel();actor.farmer._arrived(old_intent)
	check(actor.farmer.phase==actor.farmer.Phase.NONE and fields.filter(func(point):return world.farm_fields.state(point)==Fields.State.PLOWED).size()==2 and world.farm_fields._claims.is_empty(),"Forced partial cancellation frees remaining two cells without undoing three crops")
	check(farm.resources.get_amount(R.WHEAT)==0 and farm.resources.get_reserved_out(R.WHEAT)==0,"Unused seed allowance is lost, never refunded or charged twice")
	world.free()
func three_cells() -> void:
	var env:=fixture();var world=env.world;var farm=env.farm;var actor=env.actor
	var center: Vector2i=world.build_grid.world_to_cell(Vector3(-10,0,22))
	var area=world.work_areas.create(C.to_sim(world.build_grid.cell_to_world(center)),C.length_to_sim(0.51))
	check(world.player_control.assign_building_work_area(farm.id,area.id),"Use existing configurable building area")
	world.ground_resources.try_place(R.LOG,1,center+Vector2i.LEFT);world.ground_resources.try_place(R.LOG,1,center+Vector2i.RIGHT)
	farm.resources.add(R.WHEAT,1)
	for index in 3:check(one_field(world,actor),"Only three unblocked cells can be prepared")
	var task: Dictionary=actor.farmer.task()
	check(task.get("kind")==&"SOW" and task.cells.size()==3,"No more legal plowing permits partial three-cell cycle")
	check(actor.farmer.request_work(),"Start partial seed cycle")
	for index in 3:
		check(arrive(actor),"Physical partial-cycle approach")
		world.game_time.advance(10)
	check(world.farm_fields.plot_cells().size()==3 and world.farm_fields.plot_cells().all(func(cell):return world.farm_fields.state(cell)==Fields.State.SOWN) and farm.resources.get_amount(R.WHEAT)==0,"One wheat covers exactly three real sows when no more land exists")
	world.free()
func no_seed_and_cancellations() -> void:
	var env:=fixture();var world=env.world;var farm=env.farm;var actor=env.actor
	world.warehouse_data.resources.try_take(R.WHEAT,10);farm.set_stock_target(R.WHEAT,5)
	check(actor.farmer.task().get("kind")==&"PLOW","Unavailable import does not block field preparation")
	for index in 6:check(one_field(world,actor),"Absent grain does not cap plowing at five")
	check(world.farm_fields.plot_cells().size()==6,"Preparation is not a five-cell total field limit")
	farm.resources.add(R.WHEAT,2)
	check(actor.farmer.task().kind==&"SOW","Newly available grain restores sow priority")
	world.free()
	for cause in ["forced","hunger","fatigue","area","assignment","demolition","reserve","winter","unregistered"]:
		env=fixture();world=env.world;farm=env.farm;actor=env.actor
		for index in 5:check(one_field(world,actor),"Prepare cancellation fixture")
		farm.resources.add(R.WHEAT,1);check(actor.farmer.request_work(),"Sow claim before cancellation: "+cause)
		var stale=actor.farmer._intent
		match cause:
			"forced":actor.intents.force_set_intent(Intent.new(Intent.Type.NONE,&"forced",Vector2.ZERO,100,false),100)
			"hunger":check(actor.needs.try_eat(10000,100),"Critical hunger interrupts field preparation")
			"fatigue":check(actor.needs.try_rest(10000,100),"Critical fatigue interrupts field preparation")
			"area":
				var area=world.work_areas.create(Vector2(600,600),50);world.player_control.assign_building_work_area(farm.id,area.id)
			"assignment":world.player_control.assign_profession(actor.data.id,P.NONE)
			"demolition":world.change_construction_direction(farm.id,true)
			"reserve":farm.resources.release_out(R.WHEAT,1);world.game_time.advance(1)
			"winter":world.game_time.debug_skip_minutes(9*1440-world.game_time.total_minutes)
			"unregistered":world.player_control.unregister_resident(actor.data.id)
		actor.farmer.cancel();actor.farmer._arrived(stale)
		check(actor.farmer.phase==actor.farmer.Phase.NONE and world.farm_fields._claims.is_empty() and farm.resources.get_reserved_out(R.WHEAT)==0 and farm.resources.get_amount(R.WHEAT)==1,"Cancel/stale arrival retain unspent seed and release all owned cells: "+cause)
		world.free()
func reentrant_seed() -> void:
	var env:=fixture();var world=env.world;var farm=env.farm;var actor=env.actor
	for index in 5:check(one_field(world,actor),"Prepare callback-cancellation cycle")
	farm.resources.add(R.WHEAT,1)
	check(actor.farmer.request_work() and arrive(actor),"Reach first sow cell before source callback")
	var callback: Callable=func(resource,_amount):
		if resource==R.WHEAT:
			actor.farmer.cancel()
			actor.intents.force_set_intent(Intent.new(Intent.Type.MOVE_TO,&"player",Vector2.ZERO,100,false),100)
	farm.resources.changed.connect(callback)
	world.game_time.advance(10)
	farm.resources.changed.disconnect(callback)
	check(farm.resources.get_amount(R.WHEAT)==0 and farm.resources.get_reserved_out(R.WHEAT)==0 and world.farm_fields._claims.is_empty(),"Nested seed-take cancellation consumes once and frees remaining claims")
	check(world.farm_fields.plot_cells().filter(func(cell):return world.farm_fields.state(cell)==Fields.State.SOWN).size()==1 and actor.intents.current_intent.reason_id==&"player","Completed first crop and new forced intent survive deferred cleanup")
	world.free()
func terrain_effects() -> void:
	var env:=fixture();var world=env.world
	var footprint: Vector2i=world.build_grid.occupied_cells(env.farm.id)[0]
	check(not world._farm_cell_allowed(footprint),"Actual occupied building footprint cannot be plowed")
	var road_cell: Vector2i=world.build_grid.world_to_cell(Vector3(-10,0,24))
	world.roads.add_road(road_cell)
	var road_revision: int=world.navigation.revision
	check(world.farm_fields.reserve([road_cell],&"road_plow",Fields.State.BARE) and world.farm_fields.plow(road_cell,&"road_plow") and not world.roads.contains(road_cell) and world.navigation.revision>road_revision,"Plowing removes manual road through its existing navigation revision mechanism")
	var cell: Vector2i=world.mycelium.cells()[0]
	world.mycelium.add_mushrooms(cell,2)
	var id: StringName=world.mycelium.source_id(cell);world.mycelium.reserve(id,&"other_gatherer")
	world.roads.add_road(cell);world.roads.set_trample_level(cell,12)
	# A manual road normally clears mushrooms, so create a fresh stock for this test.
	world.roads.remove_road(cell);world.mycelium.add_mushrooms(cell,2)
	check(world.farm_fields.reserve([cell],&"plow",Fields.State.BARE) and world.farm_fields.plow(cell,&"plow"),"Plow real mycelium land")
	check(world.mycelium.has_mycelium(cell) and world.mycelium.amount(cell)==0 and not world.mycelium.can_grow(cell) and world.roads.trample_level(cell)==0,"Plowing clears stock/claims/wear but preserves persistent mycelium")
	world.roads.chance=1;world.roads.visit(cell)
	check(world.roads.trample_level(cell)==0,"Plowed cells cannot be trampled")
	world.farm_fields.reserve([cell],&"sow",Fields.State.PLOWED);world.farm_fields.sow(cell,&"sow",world.game_time.get_day(),func():return true)
	world.roads.visit(cell);check(world.roads.trample_level(cell)==0 and not world.mycelium.can_grow(cell),"Sown cells retain crops and reject trampling/mushrooms")
	var before: int=world.navigation.revision
	world.game_time.total_minutes=9*1440-1;world.game_time.advance(1)
	check(world.farm_fields.terrain(cell)==Fields.Terrain.DIRT and world.farm_fields.state(cell)==Fields.State.BARE and world.mycelium.has_mycelium(cell) and world.mycelium.can_grow(cell) and world.navigation.revision==before,"Winter leaves independent dirt and restores fungal eligibility without nav rebuild")
	world.farm_layer.flush()
	check(world.farm_layer.batches[&"soil"].cells.has(cell) and not world.farm_layer.batches[&"crop"].cells.has(cell),"Batch rendering retains dirt and removes dead crop")
	world.free()
func run() -> void:
	soil_and_sowing();three_cells();no_seed_and_cancellations();reentrant_seed();terrain_effects()
	print("Farming: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
