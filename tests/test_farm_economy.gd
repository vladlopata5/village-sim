extends SceneTree
const F=preload("res://tests/residents_ui_fixture.gd")
const D=preload("res://scripts/building_definition.gd")
const B=preload("res://scripts/building_instance.gd")
const Batch=preload("res://scripts/production_batch.gd")
const Types=preload("res://scripts/building_type.gd").Type
const P=preload("res://scripts/resident_profession.gd").Type
const R=preload("res://scripts/resource_type.gd").Type
const S=preload("res://scripts/resource_source_ref.gd")
const Fields=preload("res://scripts/farm_fields.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func farm(id: StringName=&"farm") -> RefCounted:return B.new(id,D.for_type(Types.FARM))
func batches() -> void:
	for scenario in ["room","full","freed","foreign","pause","cancel","nested"]:
		var place=farm();var stock=place.resources
		stock.add(R.SHEAF,1)
		if scenario in ["full","freed"]:stock.add(R.STRAW,50)
		var batch=place.prepare_production_batch("farmer")
		check(batch!=null and stock.get_reserved_out(R.SHEAF)==1 and stock.get_reserved_in(R.WHEAT)==1 and stock.get_reserved_in(R.STRAW)==0,"Preparation reserves mandatory space only: "+scenario)
		check(batch.begin("farmer") and stock.get_amount(R.SHEAF)==0,"Begin spends exactly one sheaf: "+scenario)
		if scenario=="freed":stock.try_take(R.STRAW,1)
		if scenario=="foreign":stock.add(R.STRAW,49);stock.reserve_in(R.STRAW,1)
		if scenario=="cancel":
			batch.cancel();batch.cancel()
			check(stock.get_reserved_in(R.WHEAT)==0 and stock.get_amount(R.WHEAT)==0 and stock.get_amount(R.SHEAF)==0,"Cancelling paid work releases space without restoring spent input")
			continue
		if scenario=="pause":
			batch.advance("farmer",12);batch.release_worker("farmer")
			check(batch.state==Batch.State.PAUSED and batch.progress==12 and stock.get_reserved_in(R.WHEAT)==1,"Paused process retains progress and mandatory promise")
			check(batch.claim("second") and batch.begin("second"),"Another farmer resumes the original paid process")
			batch.advance("second",17)
			check(not batch.finish("second"),"Twenty-nine work minutes do not finish threshing")
			batch.advance("second",1)
		else:batch.advance("farmer",30)
		var nested: Callable=func(_resource):batch.finish("farmer");batch.cancel()
		if scenario=="nested":stock.reservations_changed.connect(nested)
		var worker: String=batch.worker_id
		check(batch.finish(worker) and stock.get_amount(R.WHEAT)==1,"Mandatory grain completes regardless of straw space: "+scenario)
		var expected:=50 if scenario in ["full","freed"] else (49 if scenario=="foreign" else 1)
		check(stock.get_amount(R.STRAW)==expected,"Straw checked at completion, including foreign reserves: "+scenario)
		check(not batch.finish(worker) and stock.get_amount(R.WHEAT)==1 and stock.get_reserved_in(R.WHEAT)==0,"Duplicate completion cannot create more grain: "+scenario)
		if scenario=="foreign":check(stock.get_reserved_in(R.STRAW)==1,"Foreign straw promise survives skipped optional output")
		if scenario=="nested":stock.reservations_changed.disconnect(nested)
	var full=farm();full.resources.add(R.WHEAT,50);full.resources.add(R.SHEAF,1)
	check(full.prepare_production_batch("farmer")==null and full.resources.get_reserved_out(R.SHEAF)==0,"Full mandatory buffer blocks preparation without leaked input")
func economy() -> void:
	var world=F.create(self);var place=F.building(world,Types.FARM,Vector3(-10,0,16));var actor=world.resident_runtimes[0]
	check(world.warehouse_data.resources.get_amount(R.PLANK)==0 and world.warehouse_data.resources.get_amount(R.WHEAT)==10 and world.warehouse_data.resources.get_amount(R.FOOD)==20,"Approved starter stock: zero boards, ten wheat, twenty food")
	check(place.resources.get_capacity(R.WHEAT)==50 and place.resources.get_capacity(R.SHEAF)==50 and place.resources.get_capacity(R.STRAW)==50 and not place.resources.is_warehouse(),"Three independent buffers of fifty")
	check(world.player_control.assign_workplace(actor.data.id,place.id,P.FARMER),"Farm employs real farmer")
	check(actor.farmer.task().get("kind")==&"IMPORT" and place.supply.stock_deficits().get(R.WHEAT)==5,"Stock deficit precedes field work")
	place.resources.reserve_in(R.WHEAT,2)
	check(place.supply.stock_deficits().get(R.WHEAT)==3,"Accepted inbound promises reduce deficit")
	place.resources.release_in(R.WHEAT,2);place.resources.add(R.WHEAT,12)
	var source=S.new(S.Kind.CONTAINER,place.id)
	for index in 7:check(world.logistics.sources.reserve(source,R.WHEAT,StringName("external%d"%index)),"Independent external claims fit only surplus")
	check(not world.logistics.sources.reserve(source,R.WHEAT,&"eighth") and place.resources.get_available_amount(R.WHEAT)==5,"All professions obey shared export floor")
	for index in 7:world.logistics.sources.release(source,R.WHEAT,StringName("external%d"%index))
	check(world.player_control.set_production_stock_target(place.id,R.WHEAT,0).ok and place.external_available(R.WHEAT)==12,"Zero floor permits export")
	for invalid in [-1,51,1.5,"bad"]:check(not world.player_control.set_production_stock_target(place.id,R.WHEAT,invalid).ok and place.get_stock_target(R.WHEAT)==0,"Invalid target never changes model")
	check(world.player_control.set_production_stock_target(place.id,R.WHEAT,50).ok and place.external_available(R.WHEAT)==0 and place.import_demand(R.WHEAT)==38,"High floor protects all stock and requests exact deficit")
	place.set_stock_target(R.WHEAT,0)
	var cell: Vector2i=world.build_grid.world_to_cell(Vector3(-10,0,22))
	world.ground_resources.try_place(R.SHEAF,2,cell)
	check(actor.farmer.task().get("kind")==&"COLLECT" and actor.farmer.request_work(),"Ground sheaf collection outranks plowing")
	for step in 20000:
		preload("res://tests/handling_test_step.gd").move_3d(actor,0.05)
		if world.logistics.get_job(actor.data.id)==null:break
	check(place.resources.get_amount(R.SHEAF)==1 and world.ground_resources.get_at(cell).amount==1 and actor.data.inventory.amount==0,"Existing executor physically delivers one of two sheaves")
	world.game_time.debug_skip_minutes(9*1440+420-world.game_time.total_minutes)
	check(actor.farmer.task().get("kind")==&"THRESH" and actor.farmer.request_work(),"Winter leaves threshing available")
	for step in 20000:
		preload("res://tests/handling_test_step.gd").move_3d(actor,0.05)
		if actor.recipe_work.phase==actor.recipe_work.Phase.WORKING:break
	check(actor.recipe_work.phase==actor.recipe_work.Phase.WORKING and place.resources.get_amount(R.SHEAF)==0,"Real worker slot starts paid threshing")
	world.game_time.advance(30)
	check(place.resources.get_amount(R.WHEAT)==13 and place.resources.get_amount(R.STRAW)==1 and actor.recipe_work.phase==actor.recipe_work.Phase.NONE,"Physical threshing completes mandatory wheat and optional straw")
	world.free()
func harvest_and_priorities() -> void:
	var world=F.create(self);var place=F.building(world,Types.FARM,Vector3(-10,0,16));var actor=world.resident_runtimes[0]
	world.player_control.assign_workplace(actor.data.id,place.id,P.FARMER);place.set_stock_target(R.WHEAT,0)
	var cells: Array=[world.build_grid.world_to_cell(Vector3(-10,0,22)),world.build_grid.world_to_cell(Vector3(-9,0,22))]
	for cell in cells:
		world.farm_fields.reserve([cell],&"setup",Fields.State.BARE);world.farm_fields.plow(cell,&"setup")
		world.farm_fields.reserve([cell],&"setup",Fields.State.PLOWED);world.farm_fields.sow(cell,&"setup",1,func():return true)
	world.game_time.debug_skip_minutes(6*1440+420-world.game_time.total_minutes)
	world.farm_fields._plots[cells[0]].maturity=5 # Two legitimately grown crops; explicit tie-break fixture.
	check(actor.farmer.task().get("kind")==&"MOW" and actor.farmer.task().cells==[cells[1]],"Mowing selects higher maturity before proximity")
	check(actor.farmer.request_work(),"Autumn operation claims a mature crop")
	var second=F.building(world,Types.FARM,Vector3(5,0,22));var other=world.resident_runtimes[1]
	world.player_control.assign_workplace(other.data.id,second.id,P.FARMER);second.set_stock_target(R.WHEAT,0)
	var shared=world.work_areas.create(C_to_sim(world.build_grid.cell_to_world(cells[0])),100)
	world.player_control.assign_building_work_area(second.id,shared.id)
	check(not world.farm_fields.reserve([cells[1]],&"other",Fields.State.SOWN),"Overlapping farm cannot claim another operation's crop")
	check(other.farmer.task().get("cells",[])==[cells[0]],"Second farmer selects the remaining crop in overlapping area")
	for step in 20000:
		actor.view._physics_process(.05)
		if actor.farmer.phase==actor.farmer.Phase.WORKING:break
	var stale=actor.farmer._intent
	world.game_time.advance(10)
	var drop=world.ground_resources.get_at(cells[1])
	check(world.farm_fields.state(cells[1])==Fields.State.BARE and drop!=null and drop.resource_type==R.SHEAF and drop.amount in [1,2],"Actual ten-minute mow publishes one or two physical sheaves and bare dirt")
	var harvested: int=drop.amount
	actor.farmer._arrived(stale);actor.farmer._minute(world.game_time.total_minutes)
	check(drop.amount==harvested and actor.farmer.task().kind==&"COLLECT","Stale completion cannot reroll harvest; collect outranks remaining mature crop")
	world.free()
func C_to_sim(point: Vector3) -> Vector2:return preload("res://scripts/world_3d/world_coordinates.gd").to_sim(point)
func stock_transport() -> void:
	var world=F.create(self);var place=F.building(world,Types.FARM,Vector3(-10,0,16))
	var farmer=world.resident_runtimes[0];var porter=world.resident_runtimes[1]
	world.player_control.assign_workplace(farmer.data.id,place.id,P.FARMER)
	world.player_control.assign_workplace(porter.data.id,place.id,P.PORTER)
	check(farmer.farmer.request_work() and world._request_work(porter),"Farmer and optional porter independently claim shared stock supply")
	check(place.resources.get_reserved_in(R.WHEAT)==2 and place.import_demand(R.WHEAT)==3,"Parallel imports account for both inbound units")
	for actor in [farmer,porter]:
		for step in 20000:
			preload("res://tests/handling_test_step.gd").move_3d(actor,.05)
			if world.logistics.get_job(actor.data.id)==null:break
	check(place.resources.get_amount(R.WHEAT)==2 and place.resources.get_reserved_in(R.WHEAT)==0 and world.warehouse_data.resources.get_amount(R.WHEAT)==8,"Both physical seed trips deliver distinct units without leaks")
	check(world._request_work(porter),"Next deficit is discoverable at ordinary work decision")
	world.logistics._executors[porter.data.id].cancel("fixture cancellation")
	check(place.resources.get_reserved_in(R.WHEAT)==0 and world.warehouse_data.resources.get_reserved_out(R.WHEAT)==0,"Cancelled import releases only its outbound/inbound")
	place.set_stock_target(R.WHEAT,0);place.resources.add(R.WHEAT,48)
	world.game_time.debug_skip_minutes(9*1440+420-world.game_time.total_minutes)
	check(farmer.farmer.task().get("kind")==&"EXPORT" and farmer.farmer.request_work(),"Full grain buffer enables farmer export when ordinary field work is unavailable")
	for step in 20000:
		preload("res://tests/handling_test_step.gd").move_3d(farmer,.05)
		if world.logistics.get_job(farmer.data.id)==null:break
	check(place.resources.get_amount(R.WHEAT)==49 and world.warehouse_data.resources.get_amount(R.WHEAT)==9 and place.resources.get_reserved_out(R.WHEAT)==0,"Farmer physically exports one available grain")
	check(farmer.farmer.task().is_empty(),"Farmer does not repeat export before buffer is full")
	check(world._request_work(porter),"Optional porter can export below full buffer independently of field priorities")
	place.set_stock_target(R.WHEAT,50)
	check(world.logistics.get_job(porter.data.id)==null and place.resources.get_reserved_out(R.WHEAT)==0 and world.warehouse_data.resources.get_reserved_in(R.WHEAT)==0,"Raising protected stock promptly invalidates unpicked external claim")
	world.free()
func ui() -> void:
	var world=F.create(self);var place=F.building(world,Types.FARM,Vector3(-10,0,16))
	world.resident_selection.select_building(place)
	var card=world.building_card_view()
	check(card.farm_stock_section.visible and card.farm_stock_editor.text=="5","Selected farm exposes local stock target")
	card.farm_stock_editor.text="17";card.farm_stock_editor.text_changed.emit("17")
	place.resources.add(R.WHEAT,1)
	check(card.farm_stock_editor.text=="17" and place.get_stock_target(R.WHEAT)==5,"Resource notification preserves unfinished draft")
	card._apply_stock_target()
	check(place.get_stock_target(R.WHEAT)==17 and card.farm_stock_feedback.text=="Сохранено","Inline editor changes only selected farm")
	card.farm_stock_editor.text="51";card._apply_stock_target()
	check(place.get_stock_target(R.WHEAT)==17 and not card.farm_stock_feedback.text.is_empty(),"Invalid UI target explains refusal")
	world.resident_selection.select_building(world.warehouse_data)
	check(not card.farm_stock_section.visible and not place.production_changed.is_connected(card._refresh_recipes),"Selection disconnects old farm and hides setting")
	world.free()
func run() -> void:
	batches();economy();harvest_and_priorities();stock_transport();ui()
	print("Farm economy: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
