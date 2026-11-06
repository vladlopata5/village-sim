extends "res://tests/test_event_catalog_content.gd"
const Renderer = preload("res://scripts/event_text_renderer.gd")
const Balance = preload("res://scripts/balance_config.gd")
const ID := "social.misunderstood_conversation"

func misunderstood_fixture(reverse: bool = false) -> Dictionary:
	var f := fixture([Data.new("a", "Анна", 25),Data.new("b", "Степан", 30)])
	f.a.grammatical_gender=Traits.GrammaticalGender.FEMININE
	only(f,ID)
	f.social.rng.rolls=[50,0] if reverse else [0,50]
	f.negative=f.b if reverse else f.a
	f.neutral=f.a if reverse else f.b
	return f

func _run() -> void:
	conditions_and_chance(); competition(); outcomes(); formulations(); symmetric_pair(); refresh_and_expire(); atomic_and_nested(); probability_sample()
	await actual_card()
	print("Misunderstood conversation: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func conditions_and_chance() -> void:
	for context in SocialResult.Context.values():
		for first in [0,50,100]:
			for second in [0,50,100]:
				var f:=misunderstood_fixture();f.social.rng.rolls=[first,second]
				var valid: bool=context!=SocialResult.Context.WORK and ((first==0 and second==50) or (first==50 and second==0))
				var result:=fire(f,context)
				check((result.status=="completed")==valid,"Only negative/neutral reactions in conversation/meal qualify")
				check(f.service.chronicle.size()==int(valid),"Rejected facts create no chronicle")
				cleanup(f)
	for roll in [.299999,.3,1.0]:
		var f:=misunderstood_fixture();f.service.selector.set_chance("social.resolved",Balance.SOCIAL_FOLLOWUP_EVENT_CHANCE);f.rng.value=roll
		check(Balance.SOCIAL_FOLLOWUP_EVENT_CHANCE==.3 and (fire(f).status=="completed")== (roll<.3),"Existing 30 percent followup gate, including exact boundary")
		cleanup(f)
	var service:=Service.new();var raw:=service.catalog.definitions_for("social.resolved").filter(func(d):return d.id==ID)
	check(raw.size()==1 and raw[0].weight==1,"Single definition with one weighted ticket for both orientations")
	service.free()

func competition() -> void:
	for reverse in [false,true]:
		for context in SocialResult.Context.values():
			for roll in [0.0,.333332,.333334,.666665,.666668,1.0]:
				var f:=misunderstood_fixture(reverse);f.service._load_catalogs()
				if reverse:f.a.add_trait(Traits.Type.SOCIABLE);f.b.add_trait(Traits.Type.INTROVERTED)
				else:prime(f,f.b);remember(f)
				f.rng.value=roll;var before: int=f.service.completed_events().size()
				var result:=fire(f,context);var selection: Dictionary=f.service.selector.run(f.service.last_occurrence())
				var expected: Array=[]
				if reverse and context==SocialResult.Context.CONVERSATION:expected.append("social.character_contrast")
				if context!=SocialResult.Context.WORK:expected.append(ID)
				if not reverse:expected.append_array(["social.old_grudge","social.success_envy"])
				check(selection.eligible==expected,"Production candidates keep envy, grudge and contrast conditions; one ticket for new definition")
				if expected.is_empty():check(result.status=="no_match","Reverse WORK has no eligible story")
				else:check(result.definition_id==expected[mini(int(roll*expected.size()),expected.size()-1)] and f.service.completed_events().size()==before+1,"Exactly one weighted event, including competing old stories")
				cleanup(f)

func outcomes() -> void:
	for reverse in [false,true]:
		for context in [SocialResult.Context.CONVERSATION,SocialResult.Context.MEAL]:
			for bits in 16:
				var f:=misunderstood_fixture(reverse);var messages: Array=[]
				f.service.resident_message.connect(func(id,name,text):messages.append([id,name,text]))
				f.service.executor.rng.values=[0.0 if bits&1 else 1.0,0.0 if bits&2 else 1.0,0.0 if bits&4 else 1.0,0.0 if bits&8 else 1.0]
				var result:=fire(f,context)
				check(result.status=="completed" and result.main.id==f.negative.id and f.service.chronicle.size()==1,"One mandatory chronicle; actual negative participant is main")
				check(messages.size()==int(bool(bits&1))+int(bool(bits&2)),"Zero, one or two independent messages")
				var expected_senders: Array=[]
				if bits&1:expected_senders.append(f.negative.id)
				if bits&2:expected_senders.append(f.neutral.id)
				check(messages.map(func(row):return row[0])==expected_senders,"Each reaction's chat comes from the matching resident")
				for side in 2:
					var person: RefCounted=f.negative if side==0 else f.neutral
					var partner: RefCounted=f.neutral if side==0 else f.negative
					var present:=int(bool(bits&(4<<side)));var records: Array=person.memories.find()
					check(records.size()==present and person.moodlets.size()==present,"One roll creates BOTH memory and moodlet, or neither")
					if present:
						var memory: Dictionary=records[0];var moodlet: Dictionary=person.moodlets.find()[0]
						check(memory.strength==[30,15][side] and memory.tags==["social",["negative","neutral"][side]] and memory.target.id==partner.id and memory.provenance.kind=="experienced" and not memory.permanent and memory.topic=="social" and memory.type==["unpleasant_interaction","neutral_interaction"][side] and memory.provenance.kind=="experienced","Approved structured journal fields")
						check(moodlet.type==["irritation","talked_out"][side] and moodlet.expires_at_minute==755 and person.mood==[40.0,50.0][side],"Actual side receives its existing moodlet for120 minutes")
						check(person.moodlets.need_growth_factors(635)==({} if side==0 else {Need.Type.SOCIAL:.5}),"Only neutral side receives social growth factor, never negative-side moodlet")
				check(f.negative.get_opinion(f.neutral.id)==-1 and f.neutral.get_opinion(f.negative.id)==0,"Only original directed reaction deltas; no event opinion mutation")
				var token: String=f.service.last_occurrence().occurrence_id;var draws: int=f.service.executor.rng.draws
				var before: Array=[f.a.memories.find(),f.b.memories.find(),f.a.moodlets.find(),f.b.moodlets.find()];f.clock.total_minutes+=10
				f.service.replay(token);f.service.executor.publish(token)
				check(f.service.executor.rng.draws==draws and [f.a.memories.find(),f.b.memories.find(),f.a.moodlets.find(),f.b.moodlets.find()]==before and messages.size()==expected_senders.size() and f.service.chronicle.size()==1,"Replay neither rerolls nor appends, refreshes or speaks")
				cleanup(f)
	var boundary:=misunderstood_fixture();boundary.service.executor.rng.values=[.5,.5,.3,.3]
	check(fire(boundary).status=="completed" and boundary.a.memories.size()+boundary.b.memories.size()+boundary.a.moodlets.size()+boundary.b.moodlets.size()==0,"Exact 50/30 percent thresholds fail, chronicle still commits")
	cleanup(boundary)

func formulations() -> void:
	for reverse in [false,true]:
		for genders in 4:
			for index in 10:
				var f:=misunderstood_fixture(reverse)
				for side in 2:
					var person: RefCounted=f.negative if side==0 else f.neutral
					person.grammatical_gender=Traits.GrammaticalGender.FEMININE if genders&(1<<side) else Traits.GrammaticalGender.MASCULINE
					person.resident_name="Анна" if genders&(1<<side) else "Степан"
				var choices: Array=[index,(index+1)%10,(index+3)%10,(index+7)%10,(index+9)%10]
				var draws: Array=[0,0,0,0]
				for choice in choices:draws.append((choice+.1)/10.0)
				f.service.executor.rng.values=draws
				var messages: Array=[];f.service.resident_message.connect(func(id,_name,text):messages.append([id,text]))
				var definition:=definition_for(f,ID)
				check(fire(f).status=="completed","All variants prepare and commit")
				for side in 2:
					var person: RefCounted=f.negative if side==0 else f.neutral;var partner: RefCounted=f.neutral if side==0 else f.negative
					var values: Dictionary={"speaker":person.event_text_projection(),"partner":partner.event_text_projection()}
					var prefix: String=["negative","neutral"][side]
					check(messages[side]==[person.id,Renderer.render(definition.params[prefix+"_chat"][choices[side]],values).text],"Independent chat variant and speaker gender")
					var text: String=person.memories.find()[0].text
					check(text==Renderer.render(definition.params[prefix+"_diary"][choices[2+side]],values).text,"Independent journal variant relative to its own partner")
					check(not text.contains(" с с ") and not text.contains(" с со ") and not "{" in text,"No duplicated preposition or unresolved token")
				var chronicle: String=f.service.chronicle.entries()[0].text
				check(chronicle==Renderer.render(definition.text.chronicle[choices[4]],{"negative":f.negative.event_text_projection(),"neutral":f.neutral.event_text_projection()}).text,"Independent chronicle choice uses actual semantic participants")
				cleanup(f)
	var example:=misunderstood_fixture();var d:=definition_for(example,ID)
	var projections: Dictionary={"negative":example.negative.event_text_projection(),"neutral":example.neutral.event_text_projection()}
	check(Renderer.render(d.text.chronicle[2],projections).text=="Анна обнаружила в словах собеседника скрытый смысл. Степан о существовании этого смысла даже не подозревал.","Chronicle independently follows female negative and male neutral gender")
	check(Renderer.render(d.text.chronicle[4],projections).text=="После беседы Анна решила некоторое время избегать собеседника. Степан уже забыл, о чём был разговор.","Both personal past forms use semantic roles")
	check(Renderer.render(d.text.chronicle[7],projections).text.begins_with("Разговор Анны и Степана породил недоразумение"),"Both names have genitive forms")
	var examples: Dictionary={"speaker":example.a.event_text_projection(),"partner":example.b.event_text_projection()}
	check(Renderer.render(d.params.negative_chat[2],examples).text=="Я всё прекрасно поняла. Особенно то, что мне якобы ничего такого не сказали.","Negative first-person feminine chat")
	check(Renderer.render(d.params.negative_diary[5],examples).text=="Весь разговор пыталась понять, шутят надо мной или говорят совершенно серьёзно. Так и не разобралась.","Multiple feminine insertions in one diary")
	check(Renderer.render(d.params.negative_diary[7],examples).text.ends_with("Хотя со Степаном это непросто."),"Expanded with token avoids incorrect s Stepаном and duplicated preposition")
	check(Renderer.render(d.params.neutral_diary[0],examples).text.begins_with("Сегодня поговорили со Степаном."),"Neutral diary uses complete with token")
	check(Renderer.render(d.params.neutral_diary[8],examples).text.begins_with("Я не собиралась никого задевать."),"Neutral first-person feminine diary")
	var swapped: Dictionary={"speaker":example.b.event_text_projection(),"partner":example.a.event_text_projection()}
	check(Renderer.render(d.params.neutral_chat[3],swapped).text=="Хорошая беседа. Правда, под конец собеседница почему-то стала немногословной.","Partner gender remains separate from speaker gender")
	check(Renderer.render(d.params.neutral_diary[0],swapped).text=="Сегодня поговорили с Анной. Обычная беседа, хотя к концу настроение собеседницы почему-то изменилось.","Female partner instrumental and feminine reference")
	cleanup(example)

func symmetric_pair() -> void:
	var f:=misunderstood_fixture();fire(f)
	check(f.service.cooldown_history().size()==2 and f.service.cooldown_history().values()==[635,635],"Both directions committed at the same minute")
	f.clock.total_minutes=874;f.social.rng.rolls=[50,0]
	var source: RefCounted=f.social.resolve(f.b,f.a,SocialResult.Context.MEAL)
	check(f.service.replay(source.confirmed_context().occurrence_id).status=="no_match","Reversing actor and reactions cannot bypass 239 minute cooldown")
	f.clock.total_minutes=875;source=f.social.resolve(f.b,f.a,SocialResult.Context.MEAL)
	check(f.service.replay(source.confirmed_context().occurrence_id).status=="completed" and f.service.chronicle.size()==2,"Exact 240 minute boundary permits a new fact")
	cleanup(f)

func refresh_and_expire() -> void:
	var f:=misunderstood_fixture();var d:=definition_for(f,ID);d.cooldown.minutes=0;load_content(f,{"definitions":[d]})
	check(f.negative.moodlets.add({"id":"before-negative","type":"irritation","created_minute":600,"expires_at_minute":720,"source_occurrence_id":"before/irritation","modifiers":[{"channel":"mood.offset","value":-10}]}),"Earlier existing irritation")
	check(f.neutral.moodlets.add({"id":"before-neutral","type":"talked_out","created_minute":600,"expires_at_minute":720,"source_occurrence_id":"before/talked","modifiers":[{"channel":"need_growth_rate","need":"social","multiplier":.5}]}),"Earlier existing talked-out moodlet")
	fire(f);f.clock.total_minutes=695;f.service.executor.rng=SequenceRng.new();fire(f)
	check(f.negative.moodlets.size()==1 and f.negative.moodlets.get_entry("irritation").expires_at_minute==815 and f.negative.mood==40,"Irritation refresh neither stacks mood nor durations")
	check(f.neutral.moodlets.size()==1 and f.neutral.moodlets.get_entry("talked_out").expires_at_minute==815 and f.neutral.mood==50 and f.neutral.moodlets.need_growth_factors(695)=={Need.Type.SOCIAL:.5},"Talked-out refresh never compounds to0.25")
	f.clock.total_minutes=814
	for person in [f.negative,f.neutral]:person.moodlets.advance(814)
	check(f.negative.mood==40 and f.neutral.mood==50 and f.neutral.moodlets.need_growth_factors(814)=={Need.Type.SOCIAL:.5},"Both existing effects remain active at minute119")
	f.clock.total_minutes=815
	for person in [f.negative,f.neutral]:person.moodlets.advance(815);check(person.moodlets.size()==0 and person.mood==50 and person.moodlets.need_growth_factors(815).is_empty(),"Both expire exactly after120 minutes")
	cleanup(f)
	var flipped:=misunderstood_fixture();var definition:=definition_for(flipped,ID);definition.cooldown.minutes=0;load_content(flipped,{"definitions":[definition]})
	fire(flipped);flipped.clock.total_minutes=695;flipped.social.rng.rolls=[50,0];flipped.service.executor.rng=SequenceRng.new();fire(flipped)
	for person in [flipped.a,flipped.b]:check(person.moodlets.size()==2 and person.mood==40 and person.moodlets.need_growth_factors(695)=={Need.Type.SOCIAL:.5},"Swapping real reactions gives the newly appropriate type without deleting the other type")
	check(flipped.a.moodlets.get_entry("irritation").expires_at_minute==755 and flipped.a.moodlets.get_entry("talked_out").expires_at_minute==815 and flipped.b.moodlets.get_entry("irritation").expires_at_minute==815 and flipped.b.moodlets.get_entry("talked_out").expires_at_minute==755,"Independent type deadlines follow actual reaction owners")
	cleanup(flipped)

func atomic_and_nested() -> void:
	for scenario in ["reject","late_reject","inactive","bad_text"]:
		var f:=misunderstood_fixture();var definition:=definition_for(f,ID)
		if scenario in ["reject","late_reject"]:
			f.neutral.moodlets=RejectingStore.new(f.neutral.id);f.neutral.moodlets.reject_after=0 if scenario=="reject" else 1
		if scenario=="inactive":f.service.executor.rng.on_draw=func(draw):
			if draw==4:f.control.unregister_resident(f.neutral.id)
		if scenario=="bad_text":definition.params.neutral_diary[9]="{partner.name:bad_case}";f.service.catalog._by_trigger["social.resolved"]=[definition]
		var messages: Array=[];f.service.resident_message.connect(func(_id,_name,text):messages.append(text))
		check(fire(f).status!="completed","Whole transaction refused: "+scenario)
		check(f.a.memories.size()+f.b.memories.size()+f.a.moodlets.size()+f.b.moodlets.size()+f.service.chronicle.size()==0 and messages.is_empty() and f.service.cooldown_history().is_empty(),"No partial journal, moodlets, chronicle, chat or cooldown")
		check(f.negative.get_opinion(f.neutral.id)==-1 and f.neutral.get_opinion(f.negative.id)==0,"Failed event does not roll back or duplicate already committed social reactions")
		cleanup(f)
	var nested:=misunderstood_fixture();var observed: Array=[]
	nested.negative.memories.changed.connect(func(_id):
		observed.append([nested.a.memories.size(),nested.b.memories.size(),nested.a.moodlets.size(),nested.b.moodlets.size(),nested.service.chronicle.size(),nested.service.cooldown_history().size()])
		nested.service.executor.publish(nested.service.last_occurrence().occurrence_id)
		nested.social.resolve(nested.b,nested.a,SocialResult.Context.MEAL))
	fire(nested)
	check(observed==[[1,1,1,1,1,2]] and nested.service.completed_events().size()==1,"Store callbacks see fully committed pair; nested fact obeys cooldown")
	cleanup(nested)

func probability_sample() -> void:
	var f:=misunderstood_fixture();var definition:=definition_for(f,ID);var n:=20000
	for seed_value in [139921,149527]:
		var rng:=RandomNumberGenerator.new();rng.seed=seed_value;f.service.executor.rng=rng
		var marginal: Array=[0,0,0,0];var joint: Array=[];joint.resize(16);joint.fill(0);var message_counts: Array=[0,0,0]
		for index in n:
			var chosen: Dictionary=f.service.executor._choose(definition);var bits:=0
			for item in chosen.items:
				var effect: Dictionary=item.description;var side:=0 if effect.owner.binding=="negative" else 1
				if effect.op=="chat.say":bits|=1<<side
				if effect.op=="memory.add":bits|=4<<side
				if effect.op=="moodlet.add":check(chosen.items.any(func(other):return other.description.op=="memory.add" and other.description.owner==effect.owner),"Sampled bundle never splits memory and moodlet")
			for bit in 4:marginal[bit]+=int(bool(bits&(1<<bit)))
			joint[bits]+=1;message_counts[int(bool(bits&1))+int(bool(bits&2))]+=1
		for bit in 4:check(absf(float(marginal[bit])/n-([.5,.5,.3,.3][bit]))<.02,"Seeded independent marginal probability")
		for bits in 16:
			var expected:=.25*(.3 if bits&4 else .7)*(.3 if bits&8 else .7)
			check(absf(float(joint[bits])/n-expected)<.012,"All sixteen joint outcomes match four independent rolls")
		for count in 3:check(absf(float(message_counts[count])/n-[.25,.5,.25][count])<.02,"Zero/one/two chat messages near 25/50/25 percent")
		print("Misunderstood sample seed=",seed_value," N=",n," marginal=",marginal," chats=",message_counts," joint=",joint)
	cleanup(f)

func actual_card() -> void:
	var scene=load("res://scenes/main_3d.tscn").instantiate();root.add_child(scene);scene.game_time.set_process(false);scene.game_logger.console_enabled=false
	var definition: Dictionary=scene.game_events.catalog.definitions_for("social.resolved").filter(func(d):return d.id==ID)[0]
	check(scene.game_events.catalog.load_data({"definitions":[definition]},scene.game_events.facts),"Canonical world loads the production definition")
	scene.game_events.selector.set_chance("social.resolved",1);scene.game_events.selector.rng=CountingRng.new();scene.game_events.executor.rng=SequenceRng.new();scene.social_events.rng=SocialRng.new();scene.social_events.rng.rolls=[0,50]
	var a: RefCounted=scene.residents[0];var b: RefCounted=scene.residents[1]
	scene.social_events.resolve(a,b,SocialResult.Context.MEAL)
	check(scene.game_events.chronicle.size()==1 and a.memories.size()==1 and b.memories.size()==1,"Live canonical social service commits paired experience")
	scene.resident_selection.select(b);scene.game_ui.info_panel.set_expanded(true);scene.game_ui.info_panel.select_tab(&"bio");await process_frame
	var card: Control=scene.resident_card_view()
	check(card.moodlets_label.text.contains("Наговорился") and card.get_node("%Diary").text.contains(b.memories.find()[0].text),"Card shows actual neutral moodlet and unified diary entry")
	var company: Dictionary=a.moodlets.get_entry("irritation")
	var factors: Dictionary=b.moodlets.need_growth_factors(scene.game_time.total_minutes)
	check(company.modifiers.size()==1 and company.modifiers[0].channel=="mood.offset" and company.modifiers[0].value==-10 and factors.get(Need.Type.SOCIAL)==.5,"Live canonical event applies existing per-side numeric descriptors: "+str([company.modifiers,factors]))
	scene.free();await process_frame
