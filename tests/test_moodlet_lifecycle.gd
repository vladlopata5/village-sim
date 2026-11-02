extends "res://tests/test_social_game_events.gd"
const F = preload("res://tests/residents_ui_fixture.gd")
class ObservedStore extends Moodlets:
	var index_passes := 0
	var expiry_passes := 0
	var expiry_visits := 0
	func _update_next_expiry() -> void:
		index_passes += 1
		super._update_next_expiry()
	func expire(minute: int) -> int:
		var before := index_passes
		var entries := size()
		var result := super.expire(minute)
		if index_passes != before: expiry_passes += 1; expiry_visits += entries
		return result
func timed_record(id: String, created: int, expiry: Variant = null) -> Dictionary:
	return {"id":id,"type":id,"source_occurrence_id":"source/"+id+"/"+str(created),"created_minute":created,"expires_at_minute":expiry,"context":{"display_name":"Вкусно поел"},"modifiers":[]}
func _run() -> void:
	deadline_cases()
	await runtime_order_and_time()
	await event_cycle()
	await card_lifecycle()
	await hundred_residents()
	print("Moodlet lifecycle: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
func deadline_cases() -> void:
	var store:=ObservedStore.new("owner");var notices: Array=[]
	var observer:=func(id):notices.append([id,store.next_expiry_minute()])
	store.changed.connect(observer)
	check(store.next_expiry_minute()==-1 and store.expire(100)==0 and store.index_passes==0,"Empty store performs no scan")
	check(store.add(timed_record("a",10,30)) and store.add(timed_record("b",10,50)) and store.add(timed_record("indefinite",10)),"Timed and indefinite additions accepted")
	check(store.next_expiry_minute()==30 and notices[0]==["a",30],"Add updates deadline before notification")
	var passes: int=store.index_passes
	for minute in 30:check(store.expire(minute)==0 and store.index_passes==passes,"No entries traversed before earliest expiry")
	check(not store.add(timed_record("a",10,40)) and store.next_expiry_minute()==30 and store.index_passes==passes,"Rejected same-source duplicate neither refreshes nor changes index")
	check(store.add_or_refresh(timed_record("a",20,70)) and store.next_expiry_minute()==50,"Refreshing the nearest record selects the next deadline")
	check(store.remove("b") and store.next_expiry_minute()==70,"Removing the earliest record updates deadline")
	check(store.add_or_refresh(timed_record("a",25)) and store.next_expiry_minute()==-1,"Refresh to indefinite removes last timed deadline")
	check(store.add_or_refresh(timed_record("a",26,80)) and store.next_expiry_minute()==80,"Refresh from indefinite restores timed deadline")
	check(store.expire(1000)==1 and store.next_expiry_minute()==-1 and store.size()==1,"Large jump purges overdue state, preserves indefinite")
	var reentrant:=Moodlets.new("nested");reentrant.add(timed_record("a",1,10));reentrant.add(timed_record("b",1,10))
	var callback:=func(id):
		if id=="a":
			check(reentrant.size()==0 and reentrant.next_expiry_minute()==-1,"All removals and deadline committed before callbacks")
			reentrant.add(timed_record("b",10,50))
	reentrant.changed.connect(callback)
	check(reentrant.expire(10)==2 and reentrant.next_expiry_minute()==50 and reentrant.is_active("b",49),"Nested replacement and its deadline survive expiration pass")
	reentrant.changed.disconnect(callback)
	check(reentrant.expire(50)==1 and reentrant.next_expiry_minute()==-1,"Replacement later expires normally")
	store.changed.disconnect(observer)
func runtime_order_and_time() -> void:
	var world=F.create(self);var actor: Node=world.resident_runtimes[0];var clock: Node=world.game_time
	var store:=ObservedStore.new(actor.data.id);actor.data.moodlets=store
	var now: int=clock.total_minutes
	store.add(timed_record("boundary",now,now+1))
	actor.data.hunger=10;actor.need_dynamics._fractions[0]=56
	var observed: Array=[]
	var on_need:=func():observed.append([store.size(),store.next_expiry_minute()])
	actor.data.get_need(0).changed.connect(on_need)
	clock.advance(1)
	check(observed==[[0,-1]],"Expiry occurs before this resident's NeedDynamics callbacks on exact minute")
	actor.data.get_need(0).changed.disconnect(on_need)
	var connections: Array=clock.get_signal_connection_list("minute_changed");var cleanup_index: int=-1;var need_index: int=-1;var schedule_index: int=-1
	for index in connections.size():
		var listener: Callable=connections[index].callable
		if listener.get_object()==actor:cleanup_index=index
		if listener.get_object()==actor.need_dynamics:need_index=index
		if listener.get_object()==actor.schedule:schedule_index=index
	check(cleanup_index>=0 and cleanup_index<need_index and cleanup_index<schedule_index,"Runtime owns local earliest subscription, before schedule and needs")
	now=clock.total_minutes;store.add(timed_record("fast",now,now+10));clock.set_speed(20)
	clock.advance(0.45);check(clock.total_minutes==now+9 and store.size()==1,"Speed20 advances nine real game minutes without early expiry")
	paused=true;clock.advance(100);check(clock.total_minutes==now+9 and store.size()==1,"Pause freezes deadline and physical record")
	paused=false;clock.advance(0.05);check(clock.total_minutes==now+10 and store.size()==0,"Tenth accelerated minute expires exactly")
	store.add(timed_record("jump1",now+10,now+20));store.add(timed_record("jump2",now+10,now+30))
	clock.total_minutes=now+100;actor._on_minute(clock.total_minutes)
	check(store.size()==0 and store.next_expiry_minute()==-1,"One late resident tick crosses several deadlines safely")
	store.add(timed_record("instant",clock.total_minutes,clock.total_minutes))
	check(not store.is_active("instant",clock.total_minutes),"Zero duration never becomes active")
	clock.debug_skip_minutes(1);check(store.size()==0,"Zero-duration record added after a tick is purged by next local tick")
	world.free();await process_frame
func event_cycle() -> void:
	var world=F.create(self);configure_world(world)
	var service: Node=world.game_events
	var definitions: Array=[]
	for trigger in ["skill.raised","social.resolved"]:definitions.append_array(service.catalog.definitions_for(trigger).filter(func(d):return d.id in ["personal.skill_progress","social.success_envy"]))
	check(service.catalog.load_data({"definitions":definitions},service.facts),"Existing JSON catalog supplies both stages of lifecycle")
	service.selector.rng=CountingRng.new();service.executor.rng=SequenceRng.new()
	var first: RefCounted=world.resident_runtimes[0].data;var other: RefCounted=world.resident_runtimes[1].data
	other.add_skill_xp(Skill.Type.GATHERING,400)
	var original: Dictionary=other.moodlets.find()[0];var occurrence: String=service.last_occurrence().occurrence_id
	check(original.type=="pride" and other.moodlets.next_expiry_minute()==755,"Real skill event commits moodlet and its deadline atomically")
	var before: int=other.moodlets.size();service.replay(occurrence)
	check(other.moodlets.size()==before,"Replaying the same occurrence never duplicates or refreshes moodlet")
	other.add_skill_xp(Skill.Type.GATHERING,600)
	check(other.moodlets.size()==1 and other.moodlets.find()[0].context.skill=="gathering","A distinct ordinary event replaces one pride record with its current context")
	world.social_events.resolve(first,other,SocialResult.Context.WORK)
	var count:=func():return service.completed_events().values().filter(func(row):return row.definition_id=="social.success_envy").size()
	check(count.call()==1 and first.moodlets.size()==1,"Another real JSON event reads active pride and awards envy")
	world.game_time.debug_skip_minutes(119)
	check(other.moodlets.active(754).size()==1,"Refreshed event moodlet remains active to final preceding minute")
	# Resident0 callbacks can precede resident1 cleanup; fact filtering must still reject expiry.
	first.hunger=10;world.resident_runtimes[0].need_dynamics._fractions[0]=56
	var boundary: Array=[]
	var callback:=func():
		boundary.append(PairFacts.snapshot(first,other,world.game_time.total_minutes).read({"kind":"resident","id":other.id},"moodlets.active").value.size())
		world.social_events.resolve(first,other,SocialResult.Context.WORK)
	first.get_need(0).changed.connect(callback)
	world.game_time.debug_skip_minutes(1);first.get_need(0).changed.disconnect(callback)
	check(boundary==[0] and other.moodlets.size()==0 and first.moodlets.size()==0 and count.call()==1,"Exact boundary cannot select stale JSON facts, even before another resident's purge")
	check(world.resident_selection.selected_resident==null,"Automatic purge required no open card")
	world.free();await process_frame
func card_lifecycle() -> void:
	var world=F.create(self);var first: RefCounted=world.resident_runtimes[0].data;var second: RefCounted=world.resident_runtimes[1].data
	var panel: Node=world.game_ui.info_panel;var card: Node=world.resident_card_view();var now: int=world.game_time.total_minutes
	first.moodlets.add_or_refresh(timed_record("well_fed",now,now+120));second.moodlets.add(timed_record("other",now))
	world.resident_selection.select(first);panel.set_expanded(true);panel.select_tab(&"bio")
	check(card.moodlets_label.text.contains("Вкусно поел — 120 мин.") and first.moodlets.changed.is_connected(card._refresh_moodlets),"Bio renders actual title/time and binds local store")
	world.game_time.debug_skip_minutes(1);check(card.moodlets_label.text.contains("119 мин."),"Existing UI minute updates countdown")
	first.moodlets.add_or_refresh(timed_record("well_fed",now+1,now+121));check(card.moodlets_label.text.contains("120 мин.") and first.moodlets.size()==1,"Singleton refresh updates visible deadline without duplicate")
	world.resident_selection.select(second)
	check(not first.moodlets.changed.is_connected(card._refresh_moodlets) and second.moodlets.changed.is_connected(card._refresh_moodlets) and card.moodlets_label.text.contains("без срока"),"Changing selection disconnects old store and shows indefinite state")
	panel.select_tab(&"work");check(not second.moodlets.changed.is_connected(card._refresh_moodlets),"Hidden moodlet section unsubscribes")
	world.game_time.debug_skip_minutes(120);check(first.moodlets.size()==0,"Closed section does not prevent automatic expiration")
	world.resident_selection.select(first);panel.select_tab(&"bio");check(card.moodlets_label.text=="Мудлеты: нет","Expired record never shown on reopen")
	var tabs: int=panel.tab_rebuild_count;first.moodlets.add(timed_record("future",now+125,now+130))
	check(card.moodlets_label.text=="Мудлеты: нет","Future record remains hidden before activation")
	world.game_time.debug_skip_minutes(4);check(card.moodlets_label.text.contains("5 мин.") and panel.tab_rebuild_count==tabs,"Projection handles creation boundary without rebuilding tabs")
	world.free();await process_frame
	check(first.moodlets.get_signal_connection_list("changed").size()==1 and first.moodlets.get_signal_connection_list("changed")[0].callable.get_method()==&"_on_store_changed" and first.moodlets.modifiers_changed.get_connections().is_empty(),"Freed card leaves only the internal cache subscription")
func hundred_residents() -> void:
	var world=F.create(self)
	for amount in [50,46]:check(world.debug_spawn.spawn_residents(Vector3(-10,0,24),amount,Profession.Type.NONE).created==amount,"100 actual residents created with existing debug fixture")
	for actor in world.resident_runtimes:
		actor.data.set_traits([]);actor.decision._deciding=true;actor.view.set_physics_process(false);actor.intents.abort_current(actor.intents.current_intent)
		world.player_control.assign_profession(actor.data.id,Profession.Type.NONE)
		for need in actor.data.needs.values():need.value=0;need.base_weight=0
	var results: Array=[]
	for scenario in ["empty","synchronous","staggered"]:
		world.game_time.total_minutes=420;var stores: Array=[]
		for index in 100:
			var actor: Node=world.resident_runtimes[index];var store:=ObservedStore.new(actor.data.id);actor.data.moodlets=store;stores.append(store)
			for need in actor.data.needs.values():need.value=0
			if scenario!="empty":
				for entry in 8:
					var expiry: Variant=null
					if entry<5:expiry=420+(entry+1)*20+(index%10 if scenario=="staggered" else 0)
					store.add(timed_record(str(entry),420,expiry))
			store.index_passes=0;store.expiry_passes=0;store.expiry_visits=0
		var times: Array[float]=[];var due_times: Array[float]=[]
		for minute in 200:
			var due: bool=stores.any(func(store):return store.next_expiry_minute()>=0 and store.next_expiry_minute()<=world.game_time.total_minutes+1)
			var started:=Time.get_ticks_usec();world.game_time.advance(1);var elapsed: float=(Time.get_ticks_usec()-started)/1000.0;times.append(elapsed)
			if due:due_times.append(elapsed)
			if minute==18:check(stores.all(func(store):return store.index_passes==0 and store.expiry_passes==0),"All100 residents avoid scanning entries until earliest deadline")
		check(stores.all(func(store):return store.size()==(0 if scenario=="empty" else 3) and store.next_expiry_minute()==-1 and store.expiry_passes==(0 if scenario=="empty" else 5)),"Each store cleans five deadlines, retains three indefinite records")
		times.sort();due_times.sort()
		results.append({"scenario":scenario,"residents":100,"initial_records":0 if scenario=="empty" else 800,"ticks":200,"p50_ms":times[100],"p95_ms":times[190],"p99_ms":times[198],"max_ms":times[-1],"max_due_ms":due_times[-1] if not due_times.is_empty() else 0.0,"index_passes":stores.reduce(func(sum,store):return sum+store.index_passes,0),"expiry_entry_visits":stores.reduce(func(sum,store):return sum+store.expiry_visits,0)})
	print("MOODLET_100 ",JSON.stringify(results))
	world.free();await process_frame
