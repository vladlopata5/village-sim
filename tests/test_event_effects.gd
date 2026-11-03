extends "res://tests/test_live_skill_events.gd"
const Moodlets = preload("res://scripts/moodlet_store.gd")
class SequenceRng extends RefCounted:
	var values: Array = []
	var draws := 0
	var on_draw: Callable
	func randf() -> float:
		draws += 1
		if on_draw.is_valid(): on_draw.call(draws)
		return values[draws - 1] if draws <= values.size() else 0.0
class RejectingStore extends Moodlets:
	var validations := 0
	var reject_after := 0
	func prepare_add(record: Dictionary) -> Dictionary:
		validations += 1
		return {} if validations > reject_after else super.prepare_add(record)

func fixture(people: Array = []) -> Dictionary:
	var f := super.fixture(people)
	f.service.executor.rng = SequenceRng.new()
	return f

func cleanup(f: Dictionary) -> void:
	if f.service.executor.rng is SequenceRng: f.service.executor.rng.on_draw = Callable()
	for person in [f.a, f.b]:
		for store in [person.memories, person.moodlets]:
			for connection in store.get_signal_connection_list("changed"): store.disconnect("changed", connection.callable)
	super.cleanup(f)

func load_content(f: Dictionary, data: Dictionary) -> void:
	check(f.service.catalog.load_data(data, f.service.facts), "Catalog accepts test definition: " + str(f.service.catalog.errors))

func raise_rank(f: Dictionary) -> Dictionary:
	var rank: int = f.a.get_skill_rank(Skill.Type.GATHERING)
	var target: int = preload("res://scripts/balance_config.gd").SKILL_RANK_XP[rank + 1]
	f.a.add_skill_xp(Skill.Type.GATHERING, target - f.a.get_skill_xp(Skill.Type.GATHERING))
	return f.service.replay(f.service.last_occurrence().occurrence_id)

func _run() -> void:
	probabilities(); groups(); atomic_failures(); notifications_and_reentrancy(); recipients()
	await canonical_effects()
	print("Event effects: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func probabilities() -> void:
	for pair in [[0.1,0.1],[0.1,0.9],[0.9,0.1],[0.9,0.9],[0.6,0.3]]:
		var f:=fixture();var data:=content(f.service);data.definitions[0].effects[0].chance=0.6;load_content(f,data)
		f.service.executor.rng.values=pair
		var result:=raise_rank(f);var memory_count:=int(pair[0]<0.6);var mood_count:=int(pair[1]<0.3)
		check(result.status=="completed" and f.service.chronicle.size()==1,"Chronicle commits even when both optional effects fail")
		check(f.a.memories.size()==memory_count and f.a.moodlets.size()==mood_count,"Independent canonical memory and moodlet probabilities")
		check(f.rng.draws==2 and f.service.executor.rng.draws==2,"Separate selector and consequence streams")
		var token: String=f.service.last_occurrence().occurrence_id
		f.a.skill_raised.emit(1,Skill.Type.GATHERING,0,1);f.service.executor.execute({},f.service.last_occurrence(),635,f.a);f.service.executor.publish(token)
		check(f.service.executor.rng.draws==2 and f.a.memories.size()==memory_count and f.a.moodlets.size()==mood_count,"Coordinator/executor/publication are idempotent")
		if memory_count:
			var memory: Dictionary=f.a.memories.find()[0]
			check(memory.strength==30 and memory.type=="skill_progress" and memory.source_occurrence_id==token and not memory.text.is_empty() and memory._version>0,"One structured personal record, provenance and version")
		check(f.a.mood==50 and f.a.relationships.is_empty() and f.a.get_skill_xp(Skill.Type.GATHERING)==400,"No implicit mood/opinion/XP from memory")
		cleanup(f)
	var empty:=fixture();var definition:=content(empty.service);definition.definitions[0].effects=[];load_content(empty,definition)
	check(raise_rank(empty).status=="completed" and empty.a.memories.size()==0 and empty.service.chronicle.size()==1 and empty.service.executor.rng.draws==0,"Chronicle-only event is valid without a hidden diary append")
	cleanup(empty)

func groups() -> void:
	for draw in [0.0,0.5,1.0]:
		var f:=fixture();var data:=content(f.service);var definition: Dictionary=data.definitions[0]
		var option: Dictionary=definition.effects[0].duplicate(true);option.erase("chance");option.weight=1
		var second:=option.duplicate(true);second.kind="second"
		definition.effects=[];definition.exclusive_groups=[{"id":"choice","chance":1,"options":[option,second,{"op":"none","weight":1}]}]
		load_content(f,data);f.service.executor.rng.values=[0,draw]
		var result:=raise_rank(f);var index:=int(draw*2)
		check(result.status=="completed" and result.exclusive_groups==[{"id":"choice","index":index}],"Weighted group chooses at most one option")
		check(f.a.memories.size()==(0 if index==2 else 1),"None option leaves only the chronicle")
		cleanup(f)

func atomic_failures() -> void:
	for scenario in ["strength","duration","unsupported","rng","reject_store","late_reject","source","recipient"]:
		var f:=fixture();var data:=content(f.service);var definition: Dictionary=data.definitions[0]
		for effect in definition.effects:effect.chance=1
		definition.cooldown={"minutes":60,"scope":[{"role":"actor"}]}
		if scenario=="strength":definition.effects[0].strength=-1
		if scenario=="duration":definition.effects[1].duration_minutes=-1
		if scenario=="unsupported":definition.effects.append({"op":"opinion.add","owner":{"role":"actor"},"target":{"role":"actor"},"amount":1,"chance":0})
		if scenario=="rng":f.service.executor.rng.values=[0,NAN]
		if scenario in ["reject_store","late_reject"]:
			f.a.moodlets=RejectingStore.new("a");f.a.moodlets.reject_after=0 if scenario=="reject_store" else 1
		if scenario=="recipient":
			data.catalogs={"recipient":{"kind":"resident","id":"b"}};definition.bind=[{"as":"recipient","type":"resident_ref","value":{"catalog":"recipient"}}];definition.effects[1].owner={"binding":"recipient"}
		if scenario in ["source","recipient"]:
			f.service.executor.rng.on_draw=func(draw):
				if draw==2:f.control.unregister_resident("a" if scenario=="source" else "b")
		load_content(f,data);var notices: Array=[]
		f.a.memories.changed.connect(func(_id):notices.append("memory"));f.a.moodlets.changed.connect(func(_id):notices.append("moodlet"))
		var result:=raise_rank(f)
		check(result.status!="completed" and result.has("errors"),"Diagnostic refusal: "+scenario)
		check(f.a.memories.size()==0 and f.a.moodlets.size()==0 and f.b.moodlets.size()==0 and notices.is_empty() and f.service.chronicle.size()==0,"No partial records, moodlets, history or notifications: "+scenario)
		check(f.service.completed_events().is_empty() and f.service.cooldown_history().is_empty(),"Failed package does not start cooldown")
		var draws: int=f.service.executor.rng.draws;f.a.skill_raised.emit(1,Skill.Type.GATHERING,0,1)
		check(f.service.executor.rng.draws==draws,"Failed occurrence is not rerolled")
		cleanup(f)

func notifications_and_reentrancy() -> void:
	var f:=fixture();var data:=content(f.service)
	for effect in data.definitions[0].effects:effect.chance=1
	data.definitions[0].cooldown={"minutes":60,"scope":[]};load_content(f,data)
	var observations: Array=[]
	var observe:=func():observations.append([f.a.memories.size(),f.a.moodlets.size(),f.service.completed_events().size(),f.service.cooldown_history().size()])
	f.a.memories.changed.connect(func(_id):
		observe.call();f.service.executor.publish(f.service.last_occurrence().occurrence_id);f.b.add_skill_xp(Skill.Type.GATHERING,400))
	f.a.moodlets.changed.connect(func(_id):observe.call())
	raise_rank(f)
	check(observations==[[1,1,1,1],[1,1,1,1]],"Both callbacks see complete data and metadata; reentrant publish is silent")
	check(f.b.memories.size()==0 and f.service.completed_events().size()==1,"Nested event waits and cannot bypass committed cooldown")
	f.clock.total_minutes+=60;f.b.add_skill_xp(Skill.Type.GATHERING,600)
	check(f.b.memories.size()==1 and f.service.completed_events().size()==2,"Later independent occurrence succeeds at cooldown boundary")
	cleanup(f)

func recipients() -> void:
	for remove in [false,true]:
		var f:=fixture();var data:=content(f.service);var definition: Dictionary=data.definitions[0]
		data.catalogs={"recipient":{"kind":"resident","id":"b"}};definition.bind=[{"as":"recipient","type":"resident_ref","value":{"catalog":"recipient"}}]
		definition.main_role="recipient";definition.effects[0].owner={"binding":"recipient"};definition.effects[0].target={"role":"actor"};definition.effects[0].provenance={"kind":"hearsay","reported_by":{"role":"actor"}}
		definition.effects[0].text="{recipient.name}: мои впечатления"
		load_content(f,data)
		if remove:f.service.executor.rng.on_draw=func(draw):
			if draw==2:f.control.unregister_resident("b")
		var result:=raise_rank(f)
		check((result.status=="completed")==not remove and f.a.memories.size()==0 and f.b.memories.size()==int(not remove),"Explicit owner/main recipient and activity revalidation")
		if not remove:check(f.b.memories.find()[0].provenance.reported_by.id=="a" and f.b.memories.find()[0].target.id=="a","Hearsay and target bindings preserved")
		cleanup(f)

func canonical_effects() -> void:
	var world=load("res://scenes/main_3d.tscn").instantiate();root.add_child(world);world.game_time.set_process(false);world.game_logger.console_enabled=false;world.social_events.enabled=false
	world.game_events.executor.rng=SequenceRng.new();world.game_events.selector.rng=CountingRng.new()
	var resident: RefCounted=world.residents[0];resident.add_skill_xp(Skill.Type.CONSTRUCTION,400)
	check(resident.memories.size()==1 and resident.moodlets.size()==1 and world.game_events.chronicle.size()==1,"Canonical skill event commits one personal record and the unchanged pride effect")
	world.free();await process_frame
