extends SceneTree
const Score=preload("res://scripts/work_target_score.gd")
const F=preload("res://tests/residents_ui_fixture.gd")
const C=preload("res://scripts/world_3d/world_coordinates.gd")
const T=preload("res://scripts/building_type.gd").Type
const P=preload("res://scripts/resident_profession.gd").Type
const R=preload("res://scripts/resource_type.gd").Type
const TreeData=preload("res://scripts/tree_data.gd")
const RockData=preload("res://scripts/rock_data.gd")
const Fields=preload("res://scripts/farm_fields.gd")
class Locations extends "res://scripts/world_3d/natural_source_locations_3d.gd":
	var queried: Array=[]
	var rejected: Array=[]
	func resolve(source: RefCounted, origin: Vector2) -> Variant:
		queried.append(source.id)
		return null if source.id in rejected else super.resolve(source,origin)
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func order(rows: Array, worker: Vector2=Vector2(12,0), building: Vector2=Vector2.ZERO) -> Array:
	return Score.ordered(rows,worker,building,func(row):return row.point,func(row):return row.id).map(func(row):return row.id)
func math() -> void:
	var measured:=Score.measure(Vector2.ZERO,Vector2(6,0),Vector2(3,4))
	check(is_equal_approx(measured.score,10) and is_equal_approx(measured.worker,5),"True Euclidean distances with equal weights, not squared distances")
	var unequal:=Score.measure(Vector2.ZERO,Vector2(6,0),Vector2(0,4))
	check(is_equal_approx(unequal.score,4+sqrt(52)) and unequal.score==Score.measure(Vector2(6,0),Vector2.ZERO,Vector2(0,4)).score,"Unequal distance terms still have exactly the same weight")
	var rows: Array=[{"id":"worker","point":Vector2(11,4)},{"id":"middle","point":Vector2(6,0)},{"id":"building","point":Vector2(0,2)}]
	check(order(rows)[0]=="middle","Minimum sum differs from both worker-only and building-only nearest")
	check(order([{"id":"line","point":Vector2(1,0)},{"id":"squared","point":Vector2(5,1)}],Vector2.ZERO,Vector2(10,0))[0]=="line","Sum of squares would select a different target")
	check(order([{"id":"far","point":Vector2(9,0)},{"id":"near","point":Vector2(1,0)}],Vector2.ZERO,Vector2(10,0))==["near","far"],"Equal sums prefer smaller worker distance")
	var tied: Array=[{"id":"b","point":Vector2(5,0)},{"id":"a","point":Vector2(5,0)}]
	check(order(tied,Vector2.ZERO,Vector2(10,0))==["a","b"],"Final equality uses stable ID")
	tied.reverse();check(order(tied,Vector2.ZERO,Vector2(10,0))==["a","b"],"Input order does not decide equal targets")
	tied[0].point.y=0.0000001
	check(order(tied,Vector2.ZERO,Vector2(10,0))==["a","b"],"Sub-precision roundoff does not flip stable equality")
	var points: Array=[Vector2i(4,5),Vector2i(5,4)]
	check(Score.ordered(points,Vector2.ZERO,Vector2.ZERO,func(v):return Vector2(v),func(v):return v)==[Vector2i(5,4),Vector2i(4,5)],"Coordinate equality resolves by y then x")
func natural(type: int, profession: int) -> void:
	var world=F.create(self);var place=F.building(world,type,Vector3(-24,0,-16));var actor=world.resident_runtimes[0]
	world.player_control.assign_workplace(actor.data.id,place.id,profession)
	var area=world.work_areas.create(C.to_sim(Vector3(-10,0,-5)),C.length_to_sim(25))
	world.player_control.assign_building_work_area(place.id,area.id)
	actor.view.global_position=Vector3(-12,0,-16)
	var worker=actor.get_node("Lumberjack") if profession==P.LUMBERJACK else actor.get_node("Miner")
	var a: RefCounted
	var b: RefCounted
	if profession==P.LUMBERJACK:
		a=TreeData.new(&"near_worker",C.to_sim(Vector3(-13,0,-12)));b=TreeData.new(&"balanced",C.to_sim(Vector3(-18,0,-16)))
	else:
		a=RockData.new(&"near_worker",C.to_sim(Vector3(-13,0,-12)));b=RockData.new(&"balanced",C.to_sim(Vector3(-18,0,-16)))
	if profession==P.LUMBERJACK:worker.trees=[a,b]
	else:worker.rocks=[a,b]
	var locations=Locations.new();locations.navigation=world.navigation;worker.locations=locations
	var key: String="tree" if profession==P.LUMBERJACK else "rock"
	check(worker.best_target()[key]==b and locations.queried==[b.id],"Building center, not offset WorkArea center or worker-only distance; one resolve: %d"%profession)
	b.claim(&"other");locations.queried.clear()
	check(worker.best_target()[key]==a and locations.queried==[a.id],"Foreign claimed target excluded before route query: %d"%profession)
	b.release(&"other");locations.queried.clear();locations.rejected=[b.id]
	check(worker.best_target()[key]==a and locations.queried==[b.id,a.id],"Unreachable preferred target falls back in ranked order: %d"%profession)
	locations.rejected=[];locations.queried.clear()
	check(worker.has_work() and worker.request_work() and locations.queried==[b.id],"Same-state offer keeps one optimized resolve through claim: %d"%profession)
	actor.view.global_position=Vector3(-13,0,-12)
	check((worker.tree if profession==P.LUMBERJACK else worker.rock)==b and b.reservation_owner_id==StringName(actor.data.id),"Changed position cannot retarget an accepted action: %d"%profession)
	worker.abort(false)
	check(b.reservation_owner_id.is_empty(),"Interruption releases owned natural target")
	world.free()
func farm() -> void:
	var world=F.create(self);var place=F.building(world,T.FARM,Vector3(-10,0,16));var actor=world.resident_runtimes[0]
	world.player_control.assign_workplace(actor.data.id,place.id,P.FARMER);place.set_stock_target(R.WHEAT,0)
	actor.view.global_position=Vector3(-20,0,22)
	var center: Vector2i=world.build_grid.world_to_cell(C.to_world(place.position))
	var worker_cell: Vector2i=world.build_grid.world_to_cell(actor.view.global_position)
	var cells: Array=[worker_cell+Vector2i(0,3),center+Vector2i(-10,10),center+Vector2i(-8,10),center+Vector2i(-6,10),center+Vector2i(-4,10),center+Vector2i(-2,10)]
	var expected: Array=Score.ordered(cells,actor.view.get_sim_position(),place.position,actor.farmer._point,func(cell):return cell)
	var area=world.work_areas.create(C.to_sim(Vector3(-16,0,22)),C.length_to_sim(15));world.player_control.assign_building_work_area(place.id,area.id)
	var first: Vector2i=actor.farmer.task().cells[0]
	world.farm_fields.reserve([first],&"other",Fields.State.BARE)
	check(actor.farmer.task().cells[0]!=first,"Plow selection skips a foreign claim")
	world.farm_fields.release(&"other")
	var route: Callable=world.logistics.sources.route_available
	world.logistics.sources.route_available=func(_start,end):return end!=actor.farmer._point(first)
	world.logistics.sources.revision+=1
	check(actor.farmer.task().cells[0]!=first,"Unreachable preferred plow cell does not mean no work")
	world.logistics.sources.route_available=route;world.logistics.sources.revision+=1
	var ranked: Array=cells.duplicate();actor.farmer._rank(ranked)
	check(ranked==expected,"Farmer ranks from physical worker and building, not custom-area center")
	for cell in cells:
		world.farm_fields.reserve([cell],&"setup",Fields.State.BARE);world.farm_fields.plow(cell,&"setup")
	farm_rank_sow(world,place,actor,expected)
	world.free()
func farm_rank_sow(world: Node, place: RefCounted, actor: Node, expected: Array) -> void:
	place.resources.add(R.WHEAT,1)
	var candidate: Dictionary=actor.farmer.task()
	check(candidate.get("kind")==&"SOW" and candidate.cells==expected.slice(0,5),"Sow group contains five minimal sums in selected order")
	check(actor.farmer.request_work() and world.farm_fields.owned_cells(actor.farmer._owner)==expected.slice(0,5) and place.resources.get_reserved_out(R.WHEAT)==1,"Entire ranked group and one seed reserved before motion")
	actor.farmer.cancel()
	check(world.farm_fields._claims.is_empty() and place.resources.get_amount(R.WHEAT)==1 and place.resources.get_reserved_out(R.WHEAT)==0,"Cancelling selected group has no extra seed cost")
	world.game_time.debug_skip_minutes(6*1440+420-world.game_time.total_minutes)
	for index in expected.size():world.farm_fields._plots[expected[index]]={"state":Fields.State.SOWN,"maturity":5,"grown_day":7}
	world.farm_fields.revision+=1
	check(actor.farmer.task().cells==[expected[0]],"Equal-maturity harvest uses spatial sum")
	world.farm_fields._plots[expected.back()].maturity=6;world.farm_fields.revision+=1
	check(actor.farmer.task().cells==[expected.back()],"Maturity remains higher priority than spatial sum")
func gatherer() -> void:
	var world=F.create(self);var hut=F.building(world,T.GATHERER_HUT,Vector3(-10,0,16));var actor=world.resident_runtimes[0]
	world.player_control.assign_workplace(actor.data.id,hut.id,P.GATHERER)
	var area=world.work_areas.create(C.to_sim(Vector3(-16,0,22)),C.length_to_sim(15));world.player_control.assign_building_work_area(hut.id,area.id)
	actor.view.global_position=Vector3(-22,0,16)
	world.mycelium.clear_cells(world.mycelium.mushroom_cells())
	var a: Vector2i=world.build_grid.world_to_cell(Vector3(-21.25,0,20.25))
	var b: Vector2i=world.build_grid.world_to_cell(Vector3(-16.25,0,16.25))
	for cell in [a,b]:world.mycelium.add_mycelium(cell);world.mycelium.add_mushrooms(cell,1)
	var id: StringName=world.mycelium.source_id(b)
	check(world.production.find_source(actor.data).id==id,"Gatherer chooses actual stationary mushroom by both distances")
	world.mycelium.reserve(id,&"other")
	check(world.production.find_source(actor.data).id==world.mycelium.source_id(a),"Fully reserved mushroom excluded before ranking")
	world.mycelium.release(id,&"other")
	var route: Callable=world.logistics.sources.route_available;var calls: Array=[0]
	var blocked: Vector2=world.mycelium.position(id)
	world.logistics.sources.route_available=func(start,end):calls[0]+=1;return start!=blocked and end!=blocked
	world.production._offers.clear()
	var chosen=world.production.find_source(actor.data)
	check(chosen.id==world.mycelium.source_id(a),"Gatherer skips unreachable preferred source")
	var before: int=calls[0]
	check(world.production.find_source(actor.data).id==chosen.id and calls[0]==before,"Unchanged gathered proposal retains cached routes")
	world.logistics.sources.route_available=route;world.production._offers.clear()
	check(actor.self_logistics.request_work() and world.logistics.get_job(actor.data.id).source_ref.id==id,"Existing natural haul claims the newly ranked source")
	actor.view.global_position=Vector3(-21.25,0,20.25)
	check(world.logistics.get_job(actor.data.id).source_ref.id==id,"Accepted gathering trip is not retargeted on movement")
	world.logistics._executors[actor.data.id].cancel("fixture")
	check(world.production.find_source(actor.data).id==world.mycelium.source_id(a),"Next gathering choice uses current physical position")
	world.free()
func run() -> void:
	math();natural(T.LUMBERJACK_HUT,P.LUMBERJACK);natural(T.QUARRY,P.MINER);farm();gatherer()
	print("Work target score: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
