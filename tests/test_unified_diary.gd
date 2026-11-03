extends "res://tests/test_live_skill_events.gd"
const Store = preload("res://scripts/memory_store.gd")
const Expr = preload("res://scripts/event_expression.gd")
const Facts = preload("res://scripts/event_facts.gd")
const Catalog = preload("res://scripts/event_catalog.gd")
const Runner = preload("res://scripts/event_dry_run.gd")
class Sequence extends RefCounted:
	var values: Array = []
	var draws := 0
	var callback: Callable
	func randf() -> float:
		draws += 1
		if callback.is_valid(): callback.call(draws)
		return values[draws-1] if draws <= values.size() else 0.0

func entry(id: String, minute: int = 1, strength: float = 30) -> Dictionary:
	return {"id":id,"type":"unpleasant_interaction","topic":"social","text":"Воспоминание "+id,"created_minute":minute,"source_occurrence_id":"source/"+id,"tags":["negative","social"],"target":{"kind":"resident","id":"b"},"strength":strength,"permanent":false,"provenance":{"kind":"experienced"},"context":{}}

func _run() -> void:
	merge_rules(); decay_and_limits(); versions_and_transactions(); collections(); boundary(); clock_lifecycle(); content_contract()
	await actual_card()
	print("Unified diary: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

func merge_rules() -> void:
	for count in [2,3,8]:
		var store := Store.new("a")
		for index in count:
			var record := entry(str(index),index+1,30+index)
			record.context = {"skill":"construction","_event":{"id":str(index),"revision":index},"diagnostics":{"roll":index}}
			if index%2: record.tags.reverse()
			check(store.add(record),"Input repetition added")
		var newest := store.get_entry(str(count-1)); store.advance(1380)
		var merged := store.get_entry(newest.id)
		check(store.size()==1 and merged.text==newest.text and merged.created_minute==newest.created_minute and merged.source_occurrence_id==newest.source_occurrence_id,"Newest complete record survives, no replay dates")
		check(merged.strength==minf(100,30+count-1+10*(count-1))-5,"Merge maximum plus ten per absorbed record, then decay")
		var version: int = merged._version; store.advance(1380); store.advance(1440)
		check(store.get_entry(merged.id)._version==version,"One night is not repeated at midnight")
	var separate := Store.new("a")
	for field in ["base","topic","tags","target","context","provenance","permanent","participants"]:
		var record := entry(field)
		match field:
			"topic": record.topic="work"
			"tags": record.tags=["positive"]
			"target": record.target={"kind":"building","id":"hut"}
			"context": record.context={"skill":"mining"}
			"provenance": record.provenance={"kind":"hearsay","reported_by":{"kind":"resident","id":"c"}}
			"permanent": record.permanent=true
			"participants": record["participants"]=[{"kind":"resident","id":"c"}]
		check(separate.add(record),"Semantic variant added")
	separate.advance(1380);check(separate.size()==8,"Meaningful differences and permanence prevent merging")
	var permanent := Store.new("a")
	for id in ["a","b"]:
		var record := entry(id,1,30);record.permanent=true;permanent.add(record)
	permanent.advance(1380)
	check(permanent.size()==1 and permanent.get_entry("b").strength==40,"Permanent repeats merge deterministically, without decay")
	var construction := Store.new("a")
	for id in ["a","b"]:
		var record:=entry(id,1,1);record.type="construction_finished";record.topic="construction";record.target={"kind":"building","id":"hut"};construction.add(record)
	construction.advance(1380)
	check(construction.size()==1 and construction.get_entry("b").strength==6,"Construction merges without a flag, before weak entries could decay to zero")

func decay_and_limits() -> void:
	for day in [1,39,40,80]:
		var store := Store.new("a")
		for index in 60:
			var record := entry("id/%03d"%index,index+1,50); record.context={"meaning":index};store.add(record)
		store._last_night=(day-1)*1440-60
		store.advance((day-1)*1440+1380)
		var expected := mini(10+day,50)
		check(store.size()==expected,"Absolute-day cap: "+str(day))
		check(store.get_entry("id/000").is_empty() and store.get_entry("id/059").strength==45,"Oldest equal-strength ordinary records removed")
	var permanent_store := Store.new("a")
	for index in 60:
		var record := entry(str(index),1,1);record.permanent=true;record.context={"meaning":index};permanent_store.add(record)
	permanent_store.add(entry("ordinary",2,100));permanent_store.advance(1380)
	check(permanent_store.size()==60 and permanent_store.get_entry("ordinary").is_empty() and permanent_store.get_entry("0").strength==1,"Permanent count can exceed cap, never decays or prunes")
	var faded := Store.new("a");faded.add(entry("zero",1,5));faded.advance(1380)
	check(faded.size()==0,"Strength zero removed after five-point decay")
	var jump := Store.new("a");jump.add(entry("alive",1,30));jump.advance(1380+2*1440)
	check(jump.get_entry("alive").strength==15,"Every crossed night applies once")

func selected(f: Dictionary, id: String = "test") -> Dictionary:
	var definition := {"schema_version":1,"id":"reinforce","revision":1,"enabled":true,"trigger":"test","weight":1,"main_role":"actor","roles":{"actor":{"type":"resident","from":"ctx.actor"}},"bind":[{"as":"chosen","select":{"from":{"fact":[{"role":"actor"},"memories"]},"as":"candidate","where":true,"take":1,"order_by":"id"}}],"effects":[{"op":"memory.reinforce","owner":{"role":"actor"},"entry_id":{"field":[{"binding":"chosen"},"id"]},"expected_version":{"field":[{"binding":"chosen"},"_version"]},"amount":10,"chance":1}],"text":{"chronicle":"{actor.name} вспоминает прошлое."}}
	var facts: RefCounted = preload("res://scripts/resident_event_facts.gd").snapshot(f.a,null,f.clock.total_minutes)
	var catalog := Catalog.new();check(catalog.load_data({"definitions":[definition]},facts),"Generic reinforce validates")
	var runner := Runner.new(catalog,facts);runner.set_chance("test",1)
	var context := {"occurrence_id":id,"trigger":"test","minute":635,"actor":{"kind":"resident","id":"a"}}
	f.service.executor.setup(f.control,facts,func(person):return f.control.get_resident(person.id)==person)
	return {"selection":runner.run(context),"context":context}

func versions_and_transactions() -> void:
	for scenario in ["success","changed","deleted","recreated","store_replaced","late_changed","bad_sibling","invalid_participants","duplicate_destination"]:
		var f := fixture();f.a.memories.add(entry("memory",1,95))
		var frozen: Dictionary = f.a.memories.get_entry("memory");var data := selected(f,scenario)
		if scenario=="changed":f.a.memories.reinforce("memory",1,635,"other")
		if scenario in ["deleted","recreated"]:f.a.memories.remove("memory")
		if scenario=="recreated":f.a.memories.add(entry("memory",1,95))
		if scenario=="store_replaced":f.a.memories=Store.new("a");f.a.memories.add(entry("memory",1,95))
		var rng := Sequence.new(); f.service.executor.rng=rng
		if scenario=="late_changed":
			data.selection.selected.effects.append({"op":"chat.say","owner":{"role":"actor"},"text":["Один","Два"]})
			rng.callback=func(draw):
				if draw==3:f.a.memories.reinforce("memory",1,635,"nested")
		if scenario=="bad_sibling":data.selection.selected.effects.append({"op":"moodlet.add","owner":{"role":"actor"},"definition":"invalid","duration_minutes":-1})
		if scenario=="invalid_participants":data.selection.selected.effects.append({"op":"memory.add","owner":{"role":"actor"},"kind":"test","topic":"test","strength":30,"text":"Текст","provenance":{"kind":"experienced"},"participants":123})
		if scenario=="duplicate_destination":data.selection.selected.effects.append(data.selection.selected.effects[0].duplicate(true))
		var result: Dictionary = f.service.executor.execute(data.selection,data.context,635,f.a)
		if scenario=="success":
			check(result.status=="completed" and f.a.memories.get_entry("memory").strength==100,"One exact selected memory reinforced with saturation")
			check(f.a.memories.get_entry("memory").text==frozen.text and f.a.memories.get_entry("memory").created_minute==1,"Identity, creation time and text unchanged")
			var version: int=f.a.memories.get_entry("memory")._version
			f.service.executor.execute(data.selection,data.context,700,f.a);f.service.executor.publish(scenario);f.service.executor.publish(scenario)
			check(f.a.memories.get_entry("memory")._version==version and rng.draws==1,"Repeated occurrence cannot reinforce or draw again")
		else:
			check(result.status!="completed" and f.service.chronicle.size()==0 and f.a.moodlets.size()==0,"Stale/invalid package is fully refused: "+scenario)
			if scenario!="deleted":check(f.a.memories.get_entry("memory").strength==(96 if scenario in ["changed","late_changed"] else 95),"Rejected package never applies even a partial reinforcement: "+scenario)
		rng.callback=Callable();cleanup(f)

func collections() -> void:
	for count in [257,3000]:
		var f := fixture()
		for index in count:
			var record:=entry("record/%05d"%index);record.tags=["positive"] if index<count-1 else ["negative"];record.permanent=true;f.a.memories.add(record)
		var facts: RefCounted=preload("res://scripts/resident_event_facts.gd").snapshot(f.a,f.b,635)
		var source: Dictionary={"fact":[{"role":"actor"},"memories"]}
		var query: Dictionary={"from":source,"as":"candidate","where":{"has_tag":[{"local":"candidate"},"negative"]},"take":1,"order_by":"id"}
		var env: Dictionary={"ctx":{},"role":{"actor":{"kind":"resident","id":"a"}},"binding":{},"param":{},"catalog":{},"local":{}}
		var expression:=Expr.new();var found:=expression.select_one(query,env,facts)
		check(found.known and found.value.id=="record/%05d"%(count-1),"Select reaches beyond old limit: "+str(count))
		check(expression.evaluate({"exists":query},env,facts).value,"Exists reaches full immutable collection")
		f.a.memories.remove(found.value.id)
		check(expression.select_one(query,env,facts).value.id==found.value.id,"Fact source remains an immutable snapshot")
		check(not Facts.plain(range(257)),"Ordinary JSON collection bound remains 256")
		cleanup(f)

func boundary() -> void:
	var f:=fixture();f.clock.total_minutes=1379
	f.a.memories.add(entry("a",1,5));f.b.memories.add(entry("b",1,5))
	var observations: Array=[]
	f.a.memories.changed.connect(func(_id):
		var snapshot: RefCounted=preload("res://scripts/resident_event_facts.gd").snapshot(f.a,f.b,1380)
		observations.append([snapshot.read({"kind":"resident","id":"a"},"memories").value.size(),snapshot.read({"kind":"resident","id":"b"},"memories").value.size()]))
	f.a.memories.advance(1380)
	check(observations==[[0,0]] and f.b.memories.size()==0,"Event-like nested snapshot sees both journals processed at 23:00")
	cleanup(f)

func clock_lifecycle() -> void:
	var f:=fixture();f.clock.total_minutes=1379;f.a.memories.add(entry("clock",1,30))
	f.clock.minute_changed.connect(f.a.memories.advance)
	paused=true;f.clock.advance(10)
	check(f.clock.total_minutes==1379 and f.a.memories.get_entry("clock").strength==30,"Pause prevents night maintenance")
	paused=false;f.clock.set_speed(20);f.clock.advance(.05)
	check(f.clock.total_minutes==1380 and f.a.memories.get_entry("clock").strength==25,"Acceleration crosses 23:00 exactly once")
	f.clock.debug_skip_minutes(1440)
	check(f.a.memories.get_entry("clock").strength==20,"Debug jump crosses the next night, not an extra midnight decay")
	cleanup(f)

func content_contract() -> void:
	var service:=Service.new()
	var rates: Dictionary={"personal.skill_progress":[1,30],"personal.skill_progress_advanced":[1,50],"personal.construction_finished":[1,40],"personal.well_fed":[.35,10],"social.success_envy":[.6,35],"social.success_admiration":[.7,25],"social.warm_sympathy":[.5,30],"social.rough_conversation":[.6,45],"social.character_contrast":[.7,15]}
	var count:=0
	for trigger in ["social.resolved","skill.raised","construction.completed","meal.completed"]:
		for definition in service.catalog.definitions_for(trigger):
			count+=1
			check(not definition.text.has("diary_main") and not definition.has("secondary_diary"),"No parallel Diary policy")
			var records: Array=definition.get("effects",[]).filter(func(e):return e.op=="memory.add")
			if definition.id=="social.old_grudge":
				check(records.is_empty() and definition.effects[0].op=="memory.reinforce" and definition.effects[0].amount==10,"Old grudge reinforces without a new record")
			else:
				check(records.size()==(2 if definition.id=="social.warm_sympathy" else 1),"One creation per participant")
				for record in records:check(record.chance==rates[definition.id][0] and record.strength==rates[definition.id][1] and not record.permanent and record.has("text"),"Approved chance, strength and text: "+definition.id)
	check(count==10,"All ten current events adapted");service.free()

func actual_card() -> void:
	var world=load("res://scenes/main_3d.tscn").instantiate();root.add_child(world);world.game_time.set_process(false);world.game_logger.console_enabled=false
	var person: RefCounted=world.residents[0];person.memories.add(entry("old",360));person.memories.add(entry("new",1500));world.game_time.total_minutes=1600
	world.resident_selection.select(person);world.game_ui.info_panel.set_expanded(true);world.game_ui.info_panel.select_tab(&"bio");await process_frame
	var text: String=world.resident_card_view().get_node("%Diary").text
	check(text.contains("Воспоминание old") and text.contains("Воспоминание new") and text.find("Воспоминание new")<text.find("Воспоминание old"),"Actual card shows all retained days, newest first")
	world.free();await process_frame
