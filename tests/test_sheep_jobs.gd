extends SceneTree
const F=preload("res://tests/residents_ui_fixture.gd")
const D=preload("res://scripts/building_definition.gd")
const T=preload("res://scripts/building_type.gd").Type
const P=preload("res://scripts/resident_profession.gd").Type
const R=preload("res://scripts/resource_type.gd").Type
const A=preload("res://scripts/resident_assignment.gd")
const Animal=preload("res://scripts/animal_data.gd")
const Intent=preload("res://scripts/resident_intent.gd")
const Phase=preload("res://scripts/resident_shepherd_controller.gd").Phase
const C=preload("res://scripts/world_3d/world_coordinates.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func fixture() -> Dictionary:
	var world=F.create(self)
	for actor in world.resident_runtimes:actor.data.set_traits([]) # Explicit baseline; trait work is covered separately below.
	var hut=F.building(world,T.SHEPHERD_HUT,Vector3(-10,0,16))
	var runtime=world.resident_runtimes[0]
	world.player_control.assign_workplace(runtime.data.id,hut.id,P.SHEPHERD)
	for actor in world.animal_executors:actor.set_physics_process(false)
	var sheep=world.animal_executors[0]
	sheep.behavior.cancel_behavior()
	return {"world":world,"hut":hut,"runtime":runtime,"sheep":sheep,"job":runtime.shepherd}
func tick(f: Dictionary,delta: float=.05) -> void:
	f.world.game_time.advance(delta)
	f.runtime.view._physics_process(delta)
	for actor in f.world.animal_executors:actor._physics_process(delta)
	if is_instance_valid(f.job.pair):f.job.pair.advance(delta)
	f.job._physics_process(delta)
func reach(f: Dictionary,phase: int,steps: int=20000) -> bool:
	for i in steps:
		if f.runtime.view._resume_after_frame==Engine.get_physics_frames():
			await physics_frame;await process_frame
		if f.job.phase==phase:return true
		if f.job.phase==Phase.NONE:return false
		tick(f)
	return false
func task(f: Dictionary) -> RefCounted:
	var assignment=A.new(&"",f.runtime.data.id,A.CAPTURE_SHEEP,f.sheep.data.id)
	check(f.runtime.assignments.add(assignment),"Normal assignment API accepts explicit capture request")
	return assignment
func dispose(f: Dictionary) -> void:f.world.free()
func selection_and_capture() -> void:
	var f=fixture();var runtime=f.runtime
	var options: Array=f.world.interactions.get_interactions([runtime.data.id],f.sheep.data.id)
	check(options.any(func(o):return o.id==&"capture_sheep" and o.enabled and o.interaction_kind==o.Kind.RESIDENT_ASSIGNMENT),"Selected shepherd sees ordinary capture assignment, not forced command")
	var other=f.world.residents[1]
	check(not f.world.interactions.get_interactions([other.id],f.sheep.data.id).any(func(o):return o.id==&"capture_sheep"),"Other professions cannot capture")
	var busy=Intent.new(Intent.Type.NONE,&"busy_fixture",Vector2.ZERO,50,false);runtime.intents.submit(busy)
	var assignment=task(f)
	check(runtime.intents.current_intent==busy and runtime.intents.forced_priority==0 and f.hut.animal_housing.reserved_count()==0 and f.sheep.data.operation_id.is_empty(),"Enqueue preserves busy action and reserves nothing")
	check(runtime.assignments.collect_actions().any(func(row):return row.id=="ASSIGNMENT:"+String(assignment.id)),"Capture participates in normal utility candidate set")
	runtime.intents.clear_completed(busy)
	check(runtime.assignments.start(assignment.id) and f.hut.animal_housing.reserved_count()==1,"Actual start alone claims sheep and capacity")
	check((await reach(f,Phase.CAPTURING)) and f.sheep.behavior.suspended and f.sheep.data.status==Animal.Status.WILD,"Physical approach stops sheep, still wild")
	var start: int=f.world.game_time.total_minutes
	f.world.game_time.debug_skip_minutes(59)
	check(f.job.phase==Phase.CAPTURING and f.job._progress==59,"Capture requires all60 work minutes")
	f.world.game_time.debug_skip_minutes(1)
	check(f.job.phase==Phase.ESCORT and f.world.game_time.total_minutes==start+60 and f.sheep.data.status==Animal.Status.WILD,"Finished capture starts real H2, no early domestication")
	check(runtime.data.get_skill_xp(preload("res://scripts/skill_type.gd").Type.ANIMAL_HUSBANDRY)==0,"Capture timer without accepted animal earns no XP")
	check((await reach(f,Phase.NONE)) and assignment.state==A.State.COMPLETED and f.sheep.data.status==Animal.Status.DOMESTIC and f.hut.animal_housing.count()==1,"Both physically arrive, original sheep becomes domestic")
	check(f.hut.animal_housing.reserved_count()==0 and f.sheep.data.operation_id.is_empty() and runtime.view.position.distance_to(f.sheep.position)<=.801,"Completed acceptance clears only temporary ownership")
	f.job.cancel()
	check(runtime.data.get_skill_xp(preload("res://scripts/skill_type.gd").Type.ANIMAL_HUSBANDRY)==8,"Accepted capture awards once; repeated cleanup is inert")
	check(not f.world.interactions.get_interactions([runtime.data.id],f.sheep.data.id).any(func(o):return o.id==&"capture_sheep" and o.enabled),"Domestic sheep has no enabled wild capture")
	dispose(f)
	f=fixture();f.world.player_control.clear_work_assignment(f.runtime.data.id)
	var invalid=A.new(&"",f.runtime.data.id,A.CAPTURE_SHEEP,f.sheep.data.id)
	check(not f.runtime.assignments.add(invalid) and f.world.social_feed.messages.size()==1 and "некуда" in f.world.social_feed.messages[0].text,"Missing hut rejects request with character SocialFeed message")
	dispose(f)
func cancellations() -> void:
	for stage in [Phase.APPROACH,Phase.CAPTURING,Phase.ESCORT]:
		var case_fixture=fixture();var assignment=task(case_fixture);case_fixture.runtime.assignments.start(assignment.id)
		check(await reach(case_fixture,stage),"Reach cancellation stage")
		if stage==Phase.CAPTURING:case_fixture.world.game_time.debug_skip_minutes(30)
		var position: Vector3=case_fixture.sheep.position;var wool: int=case_fixture.sheep.data.wool_growth;var old_id: StringName=case_fixture.job.identity
		var forced=Intent.new(Intent.Type.MOVE_TO,&"forced_fixture",Vector2(100,100),100,false)
		case_fixture.runtime.intents.force_set_intent(forced,100)
		case_fixture.job.cancel();case_fixture.job._escorted(1,&"completed",old_id)
		check(case_fixture.job.phase==Phase.NONE and case_fixture.sheep.data.status==Animal.Status.WILD and case_fixture.sheep.position==position and case_fixture.sheep.data.wool_growth==wool,"Forced cancel preserves wild position/wool, stale callback cannot domesticate")
		check(case_fixture.sheep.data.operation_id.is_empty() and case_fixture.hut.animal_housing.reserved_count()==0 and not case_fixture.sheep.behavior.suspended and case_fixture.runtime.intents.current_intent==forced,"Cancellation releases claims and cannot overwrite newer forced intent")
		dispose(case_fixture)
	var f=fixture();var a=task(f);f.runtime.assignments.start(a.id);await reach(f,Phase.ESCORT)
	f.world.change_construction_direction(f.hut.id,true)
	check(f.job.phase==Phase.NONE and f.hut.animal_housing.reserved_count()==0 and f.sheep.data.status==Animal.Status.WILD,"Hut demolition cancels active capture escort immediately")
	dispose(f)
	f=fixture();a=task(f);f.runtime.assignments.start(a.id);await reach(f,Phase.CAPTURING)
	f.world.player_control.assign_profession(f.runtime.data.id,P.NONE)
	check(f.job.phase==Phase.NONE and f.sheep.movement_owner==null and f.sheep.data.operation_id.is_empty(),"Profession loss releases stopped sheep")
	dispose(f)
func conflicts() -> void:
	var f=fixture();var second_hut=F.building(f.world,T.SHEPHERD_HUT,Vector3(16,0,16))
	var other=f.world.resident_runtimes[1];f.world.player_control.assign_workplace(other.data.id,second_hut.id,P.SHEPHERD)
	var first=task(f);var second=A.new(&"",other.data.id,A.CAPTURE_SHEEP,f.sheep.data.id)
	check(other.assignments.add(second),"Several waiting requests may name one sheep")
	var menu: Array=f.world.interactions.get_interactions([other.data.id],f.sheep.data.id)
	var capture=menu.filter(func(option):return option.id==&"capture_sheep")[0]
	f.runtime.assignments.start(first.id)
	var messages: int=f.world.social_feed.messages.size()
	check(not f.world.interactions.execute([other.data.id],capture) and f.world.social_feed.messages.size()==messages+1,"Stale capture menu rejects new claim with a character refusal")
	check(not other.assignments.start(second.id) and f.sheep.data.operation_id==f.job.identity and f.hut.animal_housing.reserved_count()==1 and second_hut.animal_housing.reserved_count()==0,"Losing shepherd cannot steal claim or another hut hold")
	for i in 7:f.hut.animal_housing.reserve(StringName("other_%d"%i),StringName("animal_%d"%i))
	check(f.hut.animal_housing.available()==0 and not f.hut.animal_housing.reserve(&"ninth",&"ninth_animal"),"Last reserved capacity cannot be overbooked")
	f.job.cancel()
	check(f.hut.animal_housing.reserved_count()==7,"Cancellation preserves all foreign reservations")
	dispose(f)
func shearing_and_export() -> void:
	var f=fixture();f.world.game_time.total_minutes=480
	check(f.sheep.assign_home(f.hut,f.world.building_uses,f.world.work_areas),"Controlled domestic state uses S2 assignment")
	f.sheep.behavior.cancel_behavior();f.sheep.data.wool_growth=14
	check(not f.job.has_work(),"Only wool15 is eligible")
	f.sheep.data.wool_growth=15;f.hut.resources.add(R.WOOL,20)
	check(not f.job.has_work(),"Full output buffer prevents new shearing")
	f.hut.resources.try_take(R.WOOL,1)
	check(f.job.request_work() and f.hut.resources.get_reserved_in(R.WOOL)==1,"One available place suffices for the trip and service")
	check((await reach(f,Phase.SHEARING)) and f.sheep.home.owns_service(f.job.identity) and f.runtime.view.is_inside_building(f.hut.id),"Real H2 plus final approach brings both into separate service/worker slots")
	f.world.game_time.debug_skip_minutes(119)
	check(f.job.phase==Phase.SHEARING and f.sheep.data.wool_growth==15 and f.hut.resources.get_amount(R.WOOL)==19,"No output before120 work minutes")
	f.world.game_time.debug_skip_minutes(1)
	check(f.job.phase==Phase.NONE and f.sheep.data.wool_growth==0 and f.hut.resources.get_amount(R.WOOL)==20 and f.job.last_result.saved==1 and f.job.last_result.discarded>=2,"Full shearing resets wool and discards overflow instead of Ground drops")
	check(f.hut.resources.get_reserved_in(R.WOOL)==0 and f.world.building_uses.inside_count(f.hut.id)==0 and f.sheep.data.operation_id.is_empty(),"Service completion releases physical slots/output reserve")
	f.job.cancel()
	check(f.runtime.data.get_skill_xp(preload("res://scripts/skill_type.gd").Type.ANIMAL_HUSBANDRY)==16,"Full shearing awards sixteen once, irrespective of saved/discarded wool")
	check(not f.job.has_work(),"No repeated shear before regrowth")
	check(not f.runtime.self_logistics.has_work(),"No invented destination when warehouse wool quota is zero")
	await physics_frame;await process_frame
	var destination=f.world.warehouse_data
	var categories=preload("res://scripts/resource_category.gd").Type
	destination.resources.set_category_quota(categories.PLANK,40);destination.resources.set_category_quota(categories.WOOL,10)
	f.hut.resources.try_take(R.WOOL,15) # Leave five actual produced/output units in fixture.
	check(f.runtime.self_logistics.request_work(),"Shepherd can export real wool with no porter")
	var job=f.world.logistics.get_job(f.runtime.data.id)
	for i in 16000:
		if f.world.logistics.get_job(f.runtime.data.id)==null:break
		preload("res://tests/handling_test_step.gd").move_3d(f.runtime,.05)
		f.world.game_time.advance(.05)
	check(job!=null and job.state==job.State.COMPLETED and destination.resources.get_amount(R.WOOL)==1 and f.runtime.data.inventory.amount==0,"Shared HaulExecutor physically delivers one wool unit with exact reservations")
	var porter=f.world.resident_runtimes[1]
	check(f.world.player_control.assign_workplace(porter.data.id,f.hut.id,P.PORTER) and f.world._request_work(porter),"Optional hut porter accepts existing wool transport")
	job=f.world.logistics.get_job(porter.data.id)
	for i in 16000:
		if f.world.logistics.get_job(porter.data.id)==null:break
		preload("res://tests/handling_test_step.gd").move_3d(porter,.05);f.world.game_time.advance(.05)
	check(job!=null and job.state==job.State.COMPLETED and job.resource_type==R.WOOL and destination.resources.get_amount(R.WOOL)==2 and f.hut.resources.get_reserved_out(R.WOOL)==0,"Optional porter delivers second unit without stealing the shepherd's reserves")
	dispose(f)
func geometry_endpoint() -> void:
	var nav=preload("res://scripts/navigation_grid.gd").new()
	var from:=Vector3(-1.12,0,12);var to:=Vector3(-1.5,0,12.5)
	check(nav.has_line_of_sight(from,to) and nav.has_line_of_sight(to,from),"H2 cell-edge subsegment is valid in both directions, no DDA step beyond endpoint")
	nav.add_blocker(&"barrier",Rect2(-1.5,11,.5,1))
	check(not nav.has_line_of_sight(Vector3(-2,0,10),Vector3(0,0,13)),"Interior obstacle checks remain mandatory")
func partial_interrupts() -> void:
	for cause in ["forced","critical_hunger","profession","service_slot","output_reserve","demolition","animal_removed","resident_removed"]:
		var case_fixture=fixture();case_fixture.world.game_time.total_minutes=480
		case_fixture.sheep.assign_home(case_fixture.hut,case_fixture.world.building_uses,case_fixture.world.work_areas);case_fixture.sheep.behavior.cancel_behavior();case_fixture.sheep.data.wool_growth=15
		case_fixture.job.request_work()
		check(await reach(case_fixture,Phase.SHEARING),"Reach real service for interruption: "+cause)
		var data: RefCounted=case_fixture.sheep.data
		var potential: int=case_fixture.job.batch.potential
		case_fixture.world.game_time.debug_skip_minutes(60)
		match cause:
			"critical_hunger":
				case_fixture.runtime.decision._deciding=false
				case_fixture.runtime.data.hunger=100
			"forced":case_fixture.runtime.intents.force_set_intent(Intent.new(Intent.Type.NONE,&"emergency_test",Vector2.ZERO,100,false),100)
			"profession":case_fixture.world.player_control.assign_profession(case_fixture.runtime.data.id,P.NONE)
			"service_slot":case_fixture.world.building_uses.release_animal(case_fixture.hut.id,case_fixture.sheep.home._slot,data.id)
			"output_reserve":case_fixture.hut.resources.release_in(R.WOOL,1)
			"demolition":case_fixture.world.change_construction_direction(case_fixture.hut.id,true)
			"animal_removed":case_fixture.sheep.free()
			"resident_removed":case_fixture.runtime.view.free()
		check(case_fixture.job.phase==Phase.NONE and data.wool_growth==7 and case_fixture.job.last_result.minutes==60,"Emergency settles exactly60 actual minutes and eight removed levels: "+cause)
		var expected:=0 if cause=="demolition" else floori(float(potential)/2)
		check(case_fixture.hut.resources.get_amount(R.WOOL)==expected and case_fixture.hut.resources.get_reserved_in(R.WOOL)==0 and data.operation_id.is_empty(),"Partial output and reservations agree after "+cause)
		case_fixture.job.cancel()
		check(data.wool_growth==7 and case_fixture.hut.resources.get_amount(R.WOOL)==expected and case_fixture.world.building_uses.inside_count(case_fixture.hut.id)==0,"Second cleanup does not repeat settlement or retain slots: "+cause)
		check(case_fixture.runtime.data.get_skill_xp(preload("res://scripts/skill_type.gd").Type.ANIMAL_HUSBANDRY)==0,"Interrupted shearing yields no XP despite partial output: "+cause)
		dispose(case_fixture)
	var f=fixture();f.world.game_time.total_minutes=480
	f.sheep.assign_home(f.hut,f.world.building_uses,f.world.work_areas);f.sheep.behavior.cancel_behavior();f.sheep.data.wool_growth=15;f.job.request_work()
	check(await reach(f,Phase.SHEARING),"Reach service before schedule change")
	f.world.game_time.total_minutes=1379
	f.job._last_minute=1379 # Controlled boundary starts with no unearned elapsed work.
	f.world.game_time.debug_skip_minutes(1)
	check(f.job.phase==Phase.SHEARING and f.job.batch.progress==1 and f.runtime.schedule.keeps_production_action(),"Ordinary night phase retains accepted service")
	f.world.game_time.debug_skip_minutes(119)
	check(f.job.phase==Phase.NONE and f.sheep.data.wool_growth==0,"Accepted shearing completes after end of working day")
	dispose(f)
func simulation_speeds() -> void:
	for speed in [1,2,4,10,20]:
		var speed_fixture=fixture();speed_fixture.world.game_time.total_minutes=480;speed_fixture.world.game_time.set_speed(speed)
		var request=task(speed_fixture);speed_fixture.runtime.assignments.start(request.id)
		check((await reach(speed_fixture,Phase.NONE)) and request.state==A.State.COMPLETED,"Physical capture60 and H2 acceptance at x%d" % speed)
		await physics_frame;await process_frame
		speed_fixture.sheep.behavior.cancel_behavior();speed_fixture.sheep.data.wool_growth=15
		check(speed_fixture.job.request_work() and (await reach(speed_fixture,Phase.SHEARING)),"Physical service setup at x%d" % speed)
		var began: int=speed_fixture.world.game_time.total_minutes
		check((await reach(speed_fixture,Phase.NONE)) and speed_fixture.job.last_result.minutes==120 and speed_fixture.world.game_time.total_minutes-began==ceili(120.0/speed_fixture.job._work_rate),"Accepted skill rate, independent of real speed x%d" % speed)
		dispose(speed_fixture)
func reentrant_and_capacity() -> void:
	var f=fixture();var other=f.world.resident_runtimes[1];var second_sheep=f.world.animal_executors[1]
	# Bypass worker admission only in this fixture to stress the independent housing race.
	other.data.profession=P.SHEPHERD;other.data.work_location_id=f.hut.id
	for i in 7:f.hut.animal_housing.reserve(StringName("foreign_%d"%i),StringName("future_%d"%i))
	var first=task(f);var second=A.new(&"",other.data.id,A.CAPTURE_SHEEP,second_sheep.data.id)
	check(other.assignments.add(second),"Two requests queue before the last capacity place is claimed")
	check(f.runtime.assignments.start(first.id) and not other.assignments.start(second.id) and second_sheep.data.operation_id.is_empty(),"Atomic last-place admission rejects the losing operation without stealing its animal")
	check(f.hut.animal_housing.reserved_count()==8,"No ninth reserved place even in a synthetic staffing race")
	dispose(f)
	f=fixture();var request=task(f);f.runtime.assignments.start(request.id)
	var refusal=func():
		if f.sheep.data.status==Animal.Status.DOMESTIC:f.runtime.intents.force_set_intent(Intent.new(Intent.Type.NONE,&"acceptance_interrupt",Vector2.ZERO,100,false),100)
	f.sheep.data.changed.connect(refusal)
	check(await reach(f,Phase.NONE),"Acceptance callback interruption terminates operation")
	check(request.state==A.State.CANCELLED and f.sheep.data.status==Animal.Status.WILD and f.hut.animal_housing.count()==0 and f.hut.animal_housing.reserved_count()==0 and f.sheep.data.operation_id.is_empty(),"Reentrant interruption during membership commit rolls back domestication and all claims")
	f.sheep.data.changed.disconnect(refusal)
	dispose(f)
	f=fixture();f.world.game_time.total_minutes=480
	f.sheep.assign_home(f.hut,f.world.building_uses,f.world.work_areas);f.sheep.behavior.cancel_behavior();f.sheep.data.wool_growth=15
	var service_interrupt=func(_building_id: StringName,purpose: int):
		if purpose==preload("res://scripts/building_slot_purpose.gd").Type.ANIMAL_SERVICE and not f.sheep.data.operation_id.is_empty():
			f.runtime.intents.force_set_intent(Intent.new(Intent.Type.NONE,&"service_admission_interrupt",Vector2.ZERO,100,false),100)
	f.world.building_uses.slots_changed.connect(service_interrupt)
	check(f.job.request_work() and (await reach(f,Phase.NONE)),"Service admission can be interrupted from its slot callback")
	check(not f.sheep.home.is_inside() and f.sheep.data.operation_id.is_empty() and f.sheep.data.wool_growth==15 and f.world.building_uses.inside_count(f.hut.id)==0 and f.hut.resources.get_reserved_in(R.WOOL)==0,"Cancelled service admission cannot portal the animal or retain either slot")
	f.world.building_uses.slots_changed.disconnect(service_interrupt)
	dispose(f)
func run() -> void:
	await hasty_efficiency()
	await skill_efficiency()
	geometry_endpoint();await selection_and_capture();await cancellations();conflicts();await shearing_and_export();await partial_interrupts();await cancelled_completion_boundary();await simulation_speeds();await reentrant_and_capacity()
	print("Sheep jobs: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)

func cancelled_completion_boundary() -> void:
	var f=fixture();f.world.game_time.total_minutes=480
	f.sheep.assign_home(f.hut,f.world.building_uses,f.world.work_areas)
	f.sheep.behavior.cancel_behavior();f.sheep.data.wool_growth=15
	check(f.job.request_work() and (await reach(f,Phase.SHEARING)),"Reach service for cancellation at the final minute")
	f.world.game_time.debug_skip_minutes(119)
	f.world.game_time.total_minutes+=1 # Cancel accrues the final interval before its minute callback.
	f.job.cancel("cancel at boundary")
	check(f.job.last_result.minutes==120 and f.job.last_result.produced>=3,"Cancellation may settle even full wool without declaring success")
	f.job.cancel()
	check(f.runtime.data.get_skill_xp(preload("res://scripts/skill_type.gd").Type.ANIMAL_HUSBANDRY)==0,"Cancelled shearing never awards XP, even with full settle/duplicate cleanup")
	dispose(f)

func hasty_efficiency() -> void:
	var hasty_type=preload("res://scripts/trait_type.gd").Type.HASTY
	var skill=preload("res://scripts/skill_type.gd").Type.ANIMAL_HUSBANDRY
	var f=fixture();f.runtime.data.add_trait(hasty_type)
	var assignment=task(f)
	check(f.runtime.assignments.start(assignment.id) and (await reach(f,Phase.CAPTURING)),"HASTY reaches actual capture")
	check(f.runtime.is_actively_working() and is_equal_approx(f.job._work_rate,1.15),"Capture rate and active-work guard use HASTY")
	f.world.game_time.debug_skip_minutes(52)
	check(f.job.phase==Phase.CAPTURING,"Capture remains incomplete before53 ticks")
	f.world.game_time.debug_skip_minutes(1)
	check(f.job.phase==Phase.ESCORT and not f.runtime.is_actively_working(),"Escort receives neither progress nor fatigue bonus")
	check(await reach(f,Phase.NONE),"HASTY still escorts physically")
	check(f.runtime.data.get_skill_xp(skill)==8,"Capture reward unchanged")
	dispose(f)
	for cancelled in [false,true]:
		f=fixture();f.runtime.data.add_trait(hasty_type)
		f.sheep.assign_home(f.hut,f.world.building_uses,f.world.work_areas)
		f.sheep.behavior.cancel_behavior();f.sheep.data.wool_growth=15
		check(f.job.request_work() and (await reach(f,Phase.SHEARING)),"HASTY starts actual shearing")
		check(f.runtime.is_actively_working(),"Shearing is active work")
		if cancelled:
			f.world.game_time.debug_skip_minutes(10);f.job.cancel()
			check(is_equal_approx(f.job.last_result.minutes,11.5) and f.runtime.data.get_skill_xp(skill)==0,"Partial accelerated wool settles without cancelled XP")
		else:
			f.world.game_time.debug_skip_minutes(104)
			check(f.job.phase==Phase.SHEARING,"120-unit shear requires105 whole ticks at1.15")
			f.world.game_time.debug_skip_minutes(1)
			check(f.runtime.data.get_skill_xp(skill)==16 and f.job.phase==Phase.NONE,"Full shear awards fixed sixteen once")
		f.job.cancel();check(not f.runtime.is_actively_working(),"Repeated cleanup disables active work")
		dispose(f)

func skill_efficiency() -> void:
	var skill=preload("res://scripts/skill_type.gd").Type.ANIMAL_HUSBANDRY
	for xp in [0,2500,10000]:
		var f=fixture();f.runtime.data.add_skill_xp(skill,xp)
		var assignment=task(f)
		check(f.runtime.assignments.start(assignment.id) and (await reach(f,Phase.CAPTURING)),"Reach real capture for skill rate")
		var ticks:=ceili(60.0/f.job._work_rate)
		f.world.game_time.debug_skip_minutes(ticks-1)
		check(f.job.phase==Phase.CAPTURING and f.runtime.data.get_skill_xp(skill)==xp,"Capture has no early success or XP")
		f.world.game_time.debug_skip_minutes(1)
		check(f.job.phase==Phase.ESCORT and f.runtime.data.get_skill_xp(skill)==xp,"Skill accelerates contact, not escort or acceptance")
		check(await reach(f,Phase.NONE),"Accepted sheep completes physical trip")
		check(f.runtime.data.get_skill_xp(skill)==mini(xp+8,10000),"Capture reward remains eight")
		dispose(f)
		for cancelled in [false,true]:
			f=fixture();f.runtime.data.add_skill_xp(skill,xp)
			f.sheep.assign_home(f.hut,f.world.building_uses,f.world.work_areas)
			f.sheep.behavior.cancel_behavior();f.sheep.data.wool_growth=15
			check(f.job.request_work() and (await reach(f,Phase.SHEARING)),"Real service starts at accepted skill rate")
			var potential: int=f.job.batch.potential
			if cancelled:
				f.world.game_time.debug_skip_minutes(7)
				var partial: float=f.job.batch.progress
				f.job.cancel()
				check(is_equal_approx(f.job.last_result.minutes,partial) and f.job.last_result.produced==preload("res://scripts/work_progress.gd").whole_floor(potential*partial/120.0),"Fractional shearing settles exact completed volume")
				check(f.runtime.data.get_skill_xp(skill)==xp,"Partial wool does not grant XP")
			else:
				var duration:=ceili(120.0/f.job._work_rate)
				f.world.game_time.debug_skip_minutes(duration-1)
				check(f.job.phase==Phase.SHEARING and f.hut.resources.get_amount(R.WOOL)==0,"Shearing stays incomplete until final tick")
				f.world.game_time.debug_skip_minutes(1)
				check(f.job.phase==Phase.NONE and f.job.last_result.produced==potential and f.runtime.data.get_skill_xp(skill)==mini(10000,xp+16),"One full output and unchanged skill award")
			var result: Dictionary=f.job.last_result.duplicate();f.job.cancel()
			check(f.job.last_result==result and f.hut.resources.get_reserved_in(R.WOOL)==0,"Repeated settlement leaves no new output or reserves")
			dispose(f)
