extends "res://tests/test_event_catalog_content.gd"
const Renderer = preload("res://scripts/event_text_renderer.gd")
const Memory = preload("res://scripts/memory_store.gd")

func sympathy_fixture(people: Array = []) -> Dictionary:
	if people.is_empty(): people = [Data.new("a", "Анна", 25), Data.new("b", "Степан", 30)]
	people[0].grammatical_gender = Traits.GrammaticalGender.FEMININE
	var f := fixture(people)
	prepare_story(f, "social.warm_sympathy"); only(f, "social.warm_sympathy")
	return f

func _run() -> void:
	outcomes(); symmetric_cooldown(); formulations(); probability_sample()
	await ui_company()
	print("Warm sympathy: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)

func outcomes() -> void:
	for bits in 16:
		for sender in [0.0,1.0]:
			var f:=sympathy_fixture();var messages: Array=[]
			f.service.resident_message.connect(func(id,_name,text):messages.append([id,text]))
			var values: Array=[0.0 if bits&1 else 1.0,0.0 if bits&2 else 1.0,0.0 if bits&4 else 1.0]
			if bits&4:values.append(sender)
			values.append(0.0 if bits&8 else 1.0);f.service.executor.rng.values=values
			check(fire(f).status=="completed" and f.service.chronicle.size()==1,"Every new outcome has exactly one chronicle")
			for side in 2:
				var person: RefCounted=f.a if side==0 else f.b;var partner: RefCounted=f.b if side==0 else f.a
				var records: Array=person.memories.find()
				check(records.size()==int(bool(bits&(1<<side))),"Independent 50-percent canonical record per participant")
				if not records.is_empty():check(records[0].strength==30 and records[0].target.id==partner.id and records[0].type=="pleasant_interaction" and not records[0].permanent,"One structured personal record replaces the old two rolls")
				check(person.mood==(60 if bits&8 else 50) and person.moodlets.size()==int(bool(bits&8)),"Shared company effect remains unchanged")
			check(messages.size()==int(bool(bits&4)),"One optional chat message")
			if bits&4:check(messages[0]==["a" if sender==0 else "b","Со Степаном приятно проводить время!" if sender==0 else "С Анной приятно проводить время!"],"Correct sender/partner orientation")
			var token: String=f.service.last_occurrence().occurrence_id;var draws: int=f.service.executor.rng.draws
			var memories: Array=f.a.memories.find();f.clock.total_minutes+=10
			f.service.replay(token);f.service.executor.execute({},f.service.last_occurrence(),645,f.a);f.service.executor.publish(token)
			check(f.service.executor.rng.draws==draws and f.a.memories.find()==memories and messages.size()==int(bool(bits&4)),"Replay cannot change entries or repeat consequences")
			cleanup(f)
	var exact:=sympathy_fixture();exact.service.executor.rng.values=[.5,.5,.25,.5]
	check(fire(exact).status=="completed" and exact.a.memories.size()==0 and exact.b.memories.size()==0 and exact.a.mood==50,"Exact 50/25-percent boundaries fail")
	cleanup(exact)

func formulations() -> void:
	for gender in [false,true]:
		for index in 12:
			var f:=sympathy_fixture()
			if gender:
				f.a.resident_name="Иван";f.a.grammatical_gender=Traits.GrammaticalGender.MASCULINE;f.b.resident_name="Анна";f.b.grammatical_gender=Traits.GrammaticalGender.FEMININE
			var definition:=definition_for(f,"social.warm_sympathy");var draw: float=(index+.2)/12.0
			f.service.executor.rng.values=[0,0,0,0,0,draw,draw,draw,0]
			var messages: Array=[];f.service.resident_message.connect(func(_id,_name,text):messages.append(text))
			check(fire(f).status=="completed","Variant event commits")
			for pair in [[f.a,f.b],[f.b,f.a]]:
				var values: Dictionary={"speaker":pair[0].event_text_projection(),"partner":pair[1].event_text_projection()}
				check(pair[0].memories.find()[0].text==Renderer.render(definition.params.diary_text[index],values).text,"All twelve first-person variants use actual owner's gender and partner case")
			check(messages==[Renderer.render(definition.params.chat_text[index],{"speaker":f.a.event_text_projection(),"partner":f.b.event_text_projection()}).text],"All twelve chat formulations unchanged")
			cleanup(f)

func probability_sample() -> void:
	var f:=sympathy_fixture();var definition:=definition_for(f,"social.warm_sympathy")
	var rng:=RandomNumberGenerator.new();rng.seed=725463;f.service.executor.rng=rng
	var counts: Array=[0,0,0,0];var joint: Array=[0,0,0,0]
	for index in 12000:
		var result: Dictionary=f.service.executor._choose(definition)
		var a: bool=result.items.any(func(item):return item.description.op=="memory.add" and item.description.owner.role=="actor")
		var b: bool=result.items.any(func(item):return item.description.op=="memory.add" and item.description.owner.role=="other")
		counts[0]+=int(a);counts[1]+=int(b);counts[2]+=int(result.items.any(func(item):return item.description.op=="chat.say"));counts[3]+=int(result.items.any(func(item):return item.description.op=="moodlet.add"))
		joint[int(a)+2*int(b)]+=1
	for i in 4:check(absf(float(counts[i])/12000-[.5,.5,.25,.5][i])<.025,"Seeded marginal probabilities unchanged except approved personal records")
	for value in joint:check(absf(float(value)/12000-.25)<.025,"Four independent personal-record combinations near 25 percent")
	print("Unified sympathy N=12000 counts=",counts," joint=",joint);cleanup(f)

func symmetric_cooldown() -> void:
	var f := sympathy_fixture(); var observations: Array = []
	f.a.memories.changed.connect(func(_entry_id): observations.append({"history":f.service.cooldown_history(), "moods":[f.a.mood,f.b.mood], "diaries":[f.a.memories.find().size(),f.b.memories.find().size()], "memories":[f.a.memories.size(),f.b.memories.size()]}))
	check(fire(f).status == "completed", "First pair event succeeds")
	var history: Dictionary = f.service.cooldown_history()
	check(history.size() == 2 and history.values() == [635, 635], "Both directed records committed with the same minute")
	check(observations.size() == 1 and observations[0].history == history and observations[0].moods == [60.0,60.0] and observations[0].diaries == [1,1] and observations[0].memories == [1,1], "Both cooldowns and all consequences exist before any publication")
	check(f.a.mood == 60 and f.b.mood == 60 and f.a.memories.size() == 1 and f.b.memories.size() == 1, "Both residents receive the committed transaction")
	var result: RefCounted = f.social.resolve(f.b, f.a, SocialResult.Context.WORK)
	check(f.service.replay(result.confirmed_context().occurrence_id).status == "no_match", "Swapping roles cannot bypass cooldown")
	f.clock.total_minutes = 874; check(fire(f).status == "no_match", "239 minutes remains blocked")
	f.clock.total_minutes = 875; result = f.social.resolve(f.b, f.a, SocialResult.Context.MEAL)
	check(f.service.replay(result.confirmed_context().occurrence_id).status == "completed" and f.service.cooldown_history().values() == [875, 875], "Reversed pair succeeds at 240 and refreshes both directions")
	cleanup(f)
	for keep_reverse in [false, true]:
		var old := sympathy_fixture(); fire(old)
		var keys: Array = old.service._history.keys(); old.service._history.erase(keys[0 if keep_reverse else 1])
		check(fire(old).status == "no_match", "Either stored direction alone blocks the pair")
		cleanup(old)

func ui_company() -> void:
	var scene = load("res://scenes/main_3d.tscn").instantiate(); root.add_child(scene)
	configure_world(scene); scene.social_events.rng.rolls = [100,100]
	var actor: Node = scene.resident_runtimes[1]; var partner: Node = scene.resident_runtimes[3]
	var result: RefCounted = scene.social_events.resolve(actor.data, partner.data, SocialResult.Context.CONVERSATION)
	check(scene.game_events.replay(result.confirmed_context().occurrence_id).definition_id == "social.warm_sympathy", "Canonical world executes actual event")
	scene.resident_selection.select(actor.data)
	scene.game_ui.info_panel.set_expanded(true); scene.game_ui.info_panel.select_tab(&"bio")
	await process_frame
	var card: Control = scene.resident_card_view()
	check(card.moodlets_label.text.contains("Приятная компания"), "Card displays data-driven company title")
	scene.free(); await process_frame
