extends "res://tests/test_event_effects.gd"
const F = preload("res://tests/residents_ui_fixture.gd")
const P = preload("res://scripts/resident_profession.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const TreeData = preload("res://scripts/tree_data.gd")
const Intent = preload("res://scripts/resident_intent.gd")
class BlockableLocations extends RefCounted:
	var base: RefCounted
	var blocked := false
	func resolve(tree: RefCounted, origin: Vector2) -> Variant: return null if blocked else base.resolve(tree,origin)
	func is_available(point: Vector2) -> bool: return not blocked and base.is_available(point)
	func in_range(tree: RefCounted, point: Vector2) -> bool: return base.in_range(tree,point)
func anger_world() -> Node:
	var world=F.create(self)
	var definition: Dictionary=world.game_events.catalog.definitions_for("skill.raised").filter(func(d):return d.id=="personal.skill_progress")[0]
	definition.id="test.angry";definition.effects=[{"op":"moodlet.add","owner":{"role":"actor"},"definition":"angry","duration_minutes":120,"modifiers":[]}]
	check(world.game_events.catalog.load_data({"definitions":[definition]},world.game_events.facts),"Test-only JSON effect uses existing event format; no new story in game catalog")
	world.game_events.selector.rng=CountingRng.new();world.game_events.executor.rng=SequenceRng.new()
	for actor in world.resident_runtimes:world.player_control.assign_profession(actor.data.id,P.NONE)
	return world
func grant(world: Node, actor: Node) -> Dictionary:
	var rank: int=actor.data.get_skill_rank(Skill.Type.GATHERING)
	var target: int=preload("res://scripts/balance_config.gd").SKILL_RANK_XP[rank+1]
	actor.data.add_skill_xp(Skill.Type.GATHERING,target-actor.data.get_skill_xp(Skill.Type.GATHERING))
	return world.game_events.replay(world.game_events.last_occurrence().occurrence_id)
func has_vent(actor: Node) -> bool:
	return actor.decision.collect_actions(false).any(func(row):return row.id=="VENT_ANGER")
func walk_to_tree(actor: Node) -> void:
	for step in 12000:
		if actor.get_node("VentAnger")._active==null or actor.get_node("VentAnger")._ends_at>=0:return
		actor.view._physics_process(0.05)
	check(false,"Physical route terminates")
func start_vent(actor: Node) -> bool:
	check(has_vent(actor),"Active moodlet exposes read-only ordinary candidate")
	return actor.moodlet_actions.start("VENT_ANGER",600)
func _run() -> void:
	await event_policy()
	await complete_cycle()
	await cancellations_and_failures()
	await expiry_cases()
	await independent_work()
	await reentrant_completion()
	await priorities_and_time()
	print("Anger action: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func event_policy() -> void:
	var world=anger_world();var actor: Node=world.resident_runtimes[0];var store: RefCounted=actor.data.moodlets
	check(grant(world,actor).status=="completed" and store.size()==1 and store.get_entry("angry").type=="angry" and store.next_expiry_minute()==540,"Real event creates one120-minute angry singleton")
	var original: Dictionary=store.get_entry("angry");var occurrence: String=world.game_events.last_occurrence().occurrence_id
	world.game_time.debug_skip_minutes(10);world.game_events.replay(occurrence)
	check(store.get_entry("angry")==original,"Replay never refreshes or duplicates same occurrence")
	check(grant(world,actor).status=="completed" and store.size()==1 and store.get_entry("angry").expires_at_minute==world.game_time.total_minutes+120 and store.get_entry("angry").source_occurrence_id!=original.source_occurrence_id,"Distinct event refreshes one stable ID to now+120")
	original=store.get_entry("angry");var diary_count: int=actor.data.diary_entries.size()
	var definition: Dictionary=world.game_events.catalog.definitions_for("skill.raised")[0]
	definition.effects.append(definition.effects[0].duplicate(true))
	check(world.game_events.catalog.load_data({"definitions":[definition]},world.game_events.facts),"Duplicate singleton destinations reach normal atomic validation")
	check(grant(world,actor).status=="prepare_failed" and actor.data.diary_entries.size()==diary_count and store.get_entry("angry")==original,"Two singleton writes in one event reject whole bundle without partial diary or refresh")
	definition.effects.resize(1);definition.effects[0].duration_minutes=119
	world.game_events.catalog.load_data({"definitions":[definition]},world.game_events.facts)
	check(grant(world,actor).status=="prepare_failed" and actor.data.diary_entries.size()==diary_count and store.get_entry("angry")==original,"Wrong angry duration rejects whole bundle without changing current record")
	world.free();await process_frame
func complete_cycle() -> void:
	var world=anger_world();var actor: Node=world.resident_runtimes[0]
	check(not has_vent(actor),"No angry means no extra action or tree search")
	grant(world,actor);var xp: Dictionary=actor.data._skill_xp.duplicate(true)
	var trees_before: Array=world.trees.map(func(t):return [t.id,t.state,t.work_done,t.reservation_owner_id])
	var resources: int=world.ground_resources.drops.reduce(func(sum,drop):return sum+drop.amount,0)
	actor.decision._deciding=false;actor.decision.wander=null;actor.decision.rng.seed=0
	check(actor.decision._choose_need(false) and actor.intents.current_intent.reason_id==&"vent_anger","Existing UtilitySelector chooses and starts actual VENT_ANGER")
	actor.decision._deciding=true;walk_to_tree(actor)
	var controller: Node=actor.get_node("VentAnger")
	check(controller._ends_at==world.game_time.total_minutes+10 and actor.intents.current_intent.type==Intent.Type.NONE,"Physical arrival starts ten-minute owned stationary action")
	check(not actor.intents.is_ordinary_idle() and not actor.is_actively_working(),"Placeholder is neither empty idle nor productive work with trait/skill speed")
	world.game_time.debug_skip_minutes(9);check(actor.data.moodlets.is_active("angry",world.game_time.total_minutes) and controller._active!=null,"No early removal before ten complete minutes")
	world.game_time.debug_skip_minutes(1)
	check(controller._active==null and not actor.intents.has_current_action() and actor.data.moodlets.size()==0 and not has_vent(actor),"Completion removes angry and returns to ordinary decision lifecycle")
	controller._on_minute(world.game_time.total_minutes)
	check(actor.data._skill_xp==xp and world.trees.map(func(t):return [t.id,t.state,t.work_done,t.reservation_owner_id])==trees_before and world.ground_resources.drops.reduce(func(sum,drop):return sum+drop.amount,0)==resources,"No XP, tree work, claims, wood or duplicate completion effects")
	world.free();await process_frame
func cancellations_and_failures() -> void:
	for mode in ["no_tree","blocked","cancel_route","cancel_stationary","depleted","late_blocked","claimed","occupied"]:
		var world=anger_world();var actor: Node=world.resident_runtimes[0];grant(world,actor);var controller: Node=actor.get_node("VentAnger")
		if mode=="no_tree":controller.trees=[];check(not has_vent(actor) and not actor.moodlet_actions.start("VENT_ANGER",600),"No available tree excludes candidate")
		elif mode=="blocked":
			var resolver:=BlockableLocations.new();resolver.base=controller.locations;resolver.blocked=true;controller.locations=resolver
			check(not has_vent(actor),"No reachable approach excludes candidate")
		elif mode=="occupied":
			var intent:=Intent.new(Intent.Type.NONE,&"existing_work",Vector2.ZERO,100,true);actor.intents.submit(intent)
			check(not has_vent(actor) and not actor.moodlet_actions.start("VENT_ANGER",600) and actor.intents.current_intent==intent,"New moodlet never replaces existing ordinary work even at higher utility")
		else:
			check(start_vent(actor),"Available action starts")
			if mode not in ["cancel_route","claimed"]:walk_to_tree(actor)
			if mode in ["cancel_route","cancel_stationary"]:
				actor.intents.abort_current(actor.intents.current_intent);actor.intents.abort_current(actor.intents.current_intent)
			elif mode=="depleted":controller._tree.state=TreeData.State.DEPLETED;controller._tree.changed.emit()
			elif mode=="late_blocked":
				var resolver:=BlockableLocations.new();resolver.base=controller.locations;resolver.blocked=true;controller.locations=resolver;world.game_time.debug_skip_minutes(1)
			elif mode=="claimed":
				var tree: RefCounted=controller._tree
				check(tree.claim(&"forester") and controller._active!=null,"Concurrent forester can claim tree; vent never reserves it")
				walk_to_tree(actor);tree.add_work(&"forester",2);world.game_time.debug_skip_minutes(10)
				check(tree.work_done==2 and tree.reservation_owner_id==&"forester" and not actor.data.moodlets.is_active("angry",world.game_time.total_minutes),"Successful vent preserves forester's progress and claim")
			if mode!="claimed":check(controller._active==null and actor.data.moodlets.is_active("angry",world.game_time.total_minutes),"Cancellation/failure preserves angry, clears only owned action")
			if mode=="cancel_stationary":check(start_vent(actor),"Repeat selection after cancellation is allowed without cooldown")
		world.free();await process_frame
func expiry_cases() -> void:
	for when in ["before_start","route","stationary"]:
		var world=anger_world();var actor: Node=world.resident_runtimes[0];grant(world,actor)
		world.game_time.debug_skip_minutes(119 if when!="stationary" else 115)
		check(has_vent(actor),"Active immediately before deadline")
		if when=="before_start":
			world.game_time.debug_skip_minutes(1)
			check(not actor.moodlet_actions.start("VENT_ANGER",600) and not actor.intents.has_current_action(),"Expired between check and start cannot launch")
		else:
			check(start_vent(actor),"Action admitted while angry is active")
			if when=="route":world.game_time.debug_skip_minutes(2)
			walk_to_tree(actor);var controller: Node=actor.get_node("VentAnger")
			world.game_time.debug_skip_minutes(9);check(controller._active!=null,"Expiry after accepted start does not force cancellation or shorten operation")
			world.game_time.debug_skip_minutes(1);check(controller._active==null and actor.data.moodlets.size()==0,"Started action finishes normally after expiry")
		world.free();await process_frame
func independent_work() -> void:
	var world=anger_world();var angry: Node=world.resident_runtimes[0];var worker: Node=world.resident_runtimes[1]
	var place=F.building(world,BuildingType.Type.SAWMILL,Vector3(-10,0,16));place.resources.add(R.LOG,1)
	world.player_control.assign_workplace(worker.data.id,place.id,P.SAWYER)
	check(worker.recipe_work.request_work(),"Unrelated real production starts");F.walk(world,worker)
	grant(world,angry);check(start_vent(angry),"Anger action starts beside ordinary production");walk_to_tree(angry)
	world.game_time.debug_skip_minutes(10)
	check(worker.recipe_work.batch.progress==10 and place.resources.get_amount(R.PLANK)==0,"Ten vent minutes do not alter existing recipe speed or output")
	world.game_time.debug_skip_minutes(20);check(place.resources.get_amount(R.PLANK)==1,"Unrelated paid recipe completes normally")
	world.free();await process_frame
func reentrant_completion() -> void:
	var world=anger_world();var actor: Node=world.resident_runtimes[0];grant(world,actor);check(start_vent(actor),"Reentrant scenario starts");walk_to_tree(actor)
	var observed: Array=[]
	var callback:=func(id):
		if id=="angry" and actor.data.moodlets.get_entry(id).is_empty():
			observed.append(actor.get_node("VentAnger")._active==null)
			grant(world,actor);actor.get_node("VentAnger")._on_minute(world.game_time.total_minutes)
	actor.data.moodlets.changed.connect(callback);world.game_time.debug_skip_minutes(10);actor.data.moodlets.changed.disconnect(callback)
	check(observed==[true] and actor.data.moodlets.size()==1 and actor.data.moodlets.get_entry("angry").created_minute==world.game_time.total_minutes,"Nested new event survives completed action and repeated completion callback")
	check(start_vent(actor),"A distinct later angry permits a new normal action")
	world.free();await process_frame
func priorities_and_time() -> void:
	var world=anger_world();var actor: Node=world.resident_runtimes[0]
	var before: Array=actor.decision.collect_actions(false)
	grant(world,actor)
	var actions: Array=actor.decision.collect_actions(false)
	check(actions.filter(func(row):return row.id!="VENT_ANGER")==before and actions.filter(func(row):return row.id=="VENT_ANGER")[0].priority==600,"Only the extra600 candidate is added; other utilities remain identical")
	actor.data.activity=preload("res://scripts/resident_activity.gd").Type.WORKING
	check(not has_vent(actor) and not actor.moodlet_actions.start("VENT_ANGER",600),"Legacy working cycle without a current route is never empty idle")
	actor.data.activity=preload("res://scripts/resident_activity.gd").Type.IDLE
	actor.decision._deciding=false;actor.data.hunger=100
	check(actor.intents.forced_priority==200 and actor.intents.current_intent.reason_id==&"eat" and not has_vent(actor),"Actual critical hunger keeps forced precedence over unlocked action")
	world.free();await process_frame
	for trait_type in [preload("res://scripts/trait_type.gd").Type.HASTY,preload("res://scripts/trait_type.gd").Type.DELIBERATE]:
		world=anger_world();actor=world.resident_runtimes[0];actor.data.add_trait(trait_type);grant(world,actor)
		check(start_vent(actor),"Work-speed trait does not prohibit optional action");walk_to_tree(actor)
		world.game_time.set_speed(20);world.game_time.advance(0.45)
		check(actor.get_node("VentAnger")._active!=null,"Nine game minutes remain incomplete at speed20, regardless of work rate")
		paused=true;world.game_time.advance(100);paused=false
		check(actor.get_node("VentAnger")._active!=null,"Pause does not advance anger action")
		world.game_time.advance(0.05);check(actor.get_node("VentAnger")._active==null and actor.data.moodlets.size()==0,"Exactly ten game minutes, no work multiplier")
		world.free();await process_frame
