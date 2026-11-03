extends "res://tests/test_event_catalog_content.gd"
const Renderer = preload("res://scripts/event_text_renderer.gd")
const Balance = preload("res://scripts/balance_config.gd")
const ID := "social.awkward_conversation"

func awkward_fixture(reverse: bool = false) -> Dictionary:
	var f := fixture([Data.new("a", "Анна", 25),Data.new("b", "Степан", 30)])
	f.a.grammatical_gender=Traits.GrammaticalGender.FEMININE
	only(f,ID)
	f.social.rng.rolls=[-100,100] if reverse else [100,-100]
	f.positive=f.b if reverse else f.a
	f.negative=f.a if reverse else f.b
	return f

func _run() -> void:
	conditions_and_chance(); outcomes(); formulations(); symmetric_pair(); refresh_and_expire(); atomic_and_nested(); probability_sample()
	await actual_card()
	print("Awkward conversation: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func conditions_and_chance() -> void:
	for context in SocialResult.Context.values():
		for first in [-100,0,100]:
			for second in [-100,0,100]:
				var f:=awkward_fixture();f.social.rng.rolls=[first,second]
				var valid: bool=context!=SocialResult.Context.WORK and first*second==-10000
				var result:=fire(f,context)
				check((result.status=="completed")==valid,"Only mixed reactions in conversation/meal qualify")
				check(f.service.chronicle.size()==int(valid),"Rejected facts create no chronicle")
				cleanup(f)
	for roll in [.299999,.3,1.0]:
		var f:=awkward_fixture();f.service.selector.set_chance("social.resolved",Balance.SOCIAL_FOLLOWUP_EVENT_CHANCE);f.rng.value=roll
		check(Balance.SOCIAL_FOLLOWUP_EVENT_CHANCE==.3 and (fire(f).status=="completed")== (roll<.3),"Existing 30 percent followup gate, including exact boundary")
		cleanup(f)
	var service:=Service.new();var raw:=service.catalog.definitions_for("social.resolved").filter(func(d):return d.id==ID)
	check(raw.size()==1 and raw[0].weight==1,"Single definition with one weighted ticket for both orientations")
	service.free()

func outcomes() -> void:
	for reverse in [false,true]:
		for context in [SocialResult.Context.CONVERSATION,SocialResult.Context.MEAL]:
			for bits in 16:
				var f:=awkward_fixture(reverse);var messages: Array=[]
				f.service.resident_message.connect(func(id,name,text):messages.append([id,name,text]))
				f.service.executor.rng.values=[0.0 if bits&1 else 1.0,0.0 if bits&2 else 1.0,0.0 if bits&4 else 1.0,0.0 if bits&8 else 1.0]
				var result:=fire(f,context)
				check(result.status=="completed" and result.main.id==f.positive.id and f.service.chronicle.size()==1,"One mandatory chronicle; actual positive participant is main")
				check(messages.size()==int(bool(bits&1))+int(bool(bits&2)),"Zero, one or two independent messages")
				var expected_senders: Array=[]
				if bits&1:expected_senders.append(f.positive.id)
				if bits&2:expected_senders.append(f.negative.id)
				check(messages.map(func(row):return row[0])==expected_senders,"Each reaction's chat comes from the matching resident")
				for side in 2:
					var person: RefCounted=f.positive if side==0 else f.negative
					var partner: RefCounted=f.negative if side==0 else f.positive
					var present:=int(bool(bits&(4<<side)));var records: Array=person.memories.find()
					check(records.size()==present and person.moodlets.size()==present,"One roll creates BOTH memory and moodlet, or neither")
					if present:
						var memory: Dictionary=records[0];var moodlet: Dictionary=person.moodlets.find()[0]
						check(memory.strength==[20,30][side] and memory.tags==["social",["positive","negative"][side]] and memory.target.id==partner.id and memory.provenance.kind=="experienced" and not memory.permanent,"Approved structured journal fields")
						check(moodlet.type==["pleasant_company","awkwardness"][side] and moodlet.expires_at_minute==755 and person.mood==[60.0,40.0][side],"Existing mood.offset gives signed ten for 120 minutes")
				check(f.positive.get_opinion(f.negative.id)==1 and f.negative.get_opinion(f.positive.id)==-1,"Only original directed reaction deltas; no event opinion mutation")
				var token: String=f.service.last_occurrence().occurrence_id;var draws: int=f.service.executor.rng.draws
				var before: Array=[f.a.memories.find(),f.b.memories.find(),f.a.moodlets.find(),f.b.moodlets.find()];f.clock.total_minutes+=10
				f.service.replay(token);f.service.executor.publish(token)
				check(f.service.executor.rng.draws==draws and [f.a.memories.find(),f.b.memories.find(),f.a.moodlets.find(),f.b.moodlets.find()]==before and messages.size()==expected_senders.size() and f.service.chronicle.size()==1,"Replay neither rerolls nor appends, refreshes or speaks")
				cleanup(f)
	var boundary:=awkward_fixture();boundary.service.executor.rng.values=[.5,.5,.3,.3]
	check(fire(boundary).status=="completed" and boundary.a.memories.size()+boundary.b.memories.size()+boundary.a.moodlets.size()+boundary.b.moodlets.size()==0,"Exact 50/30 percent thresholds fail, chronicle still commits")
	cleanup(boundary)

func formulations() -> void:
	for reverse in [false,true]:
		for genders in 4:
			for index in 10:
				var f:=awkward_fixture(reverse)
				for side in 2:
					var person: RefCounted=f.positive if side==0 else f.negative
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
					var person: RefCounted=f.positive if side==0 else f.negative;var partner: RefCounted=f.negative if side==0 else f.positive
					var values: Dictionary={"speaker":person.event_text_projection(),"partner":partner.event_text_projection()}
					var prefix: String=["positive","negative"][side]
					check(messages[side]==[person.id,Renderer.render(definition.params[prefix+"_chat"][choices[side]],values).text],"Independent chat variant and speaker gender")
					var text: String=person.memories.find()[0].text
					check(text==Renderer.render(definition.params[prefix+"_diary"][choices[2+side]],values).text,"Independent journal variant relative to its own partner")
					check(not text.contains("с с ") and not text.contains("с со ") and not "{" in text,"No duplicated preposition or unresolved token")
				var chronicle: String=f.service.chronicle.entries()[0].text
				check(chronicle==Renderer.render(definition.text.chronicle[choices[4]],{"positive":f.positive.event_text_projection(),"negative":f.negative.event_text_projection()}).text,"Independent chronicle choice uses actual semantic participants")
				cleanup(f)
	var example:=awkward_fixture();var d:=definition_for(example,ID);var example_values: Dictionary={"speaker":example.a.event_text_projection(),"partner":example.b.event_text_projection()}
	check(Renderer.render(d.params.positive_diary[1],example_values).text.begins_with("Со Степаном"),"Full with-preposition is not prefixed again")
	check(Renderer.render(d.params.negative_chat[0],example_values).text.begins_with("Я трижды сказала"),"Female speaker uses actual resident gender")
	check(Renderer.render(d.text.chronicle[1],{"positive":example.a.event_text_projection(),"negative":example.b.event_text_projection()}).text.begins_with("Беседа Анны и Степана"),"Genitive after беседа")
	cleanup(example)

func symmetric_pair() -> void:
	var f:=awkward_fixture();fire(f)
	check(f.service.cooldown_history().size()==2 and f.service.cooldown_history().values()==[635,635],"Both directions committed at the same minute")
	f.clock.total_minutes=874;f.social.rng.rolls=[-100,100]
	var source: RefCounted=f.social.resolve(f.b,f.a,SocialResult.Context.MEAL)
	check(f.service.replay(source.confirmed_context().occurrence_id).status=="no_match","Reversing actor and reactions cannot bypass 239 minute cooldown")
	f.clock.total_minutes=875;source=f.social.resolve(f.b,f.a,SocialResult.Context.MEAL)
	check(f.service.replay(source.confirmed_context().occurrence_id).status=="completed" and f.service.chronicle.size()==2,"Exact 240 minute boundary permits a new fact")
	cleanup(f)

func refresh_and_expire() -> void:
	var f:=awkward_fixture();var d:=definition_for(f,ID);d.cooldown.minutes=0;load_content(f,{"definitions":[d]})
	f.service.executor.rng=SequenceRng.new();fire(f);f.clock.total_minutes=695;f.service.executor.rng=SequenceRng.new();fire(f)
	for person in [f.positive,f.negative]:
		check(person.moodlets.size()==1 and person.moodlets.find()[0].expires_at_minute==815,"Independent new occurrence refreshes singleton to now plus 120")
		person.moodlets.advance(814);check(person.mood!=50,"Mood offset active just before expiry")
		person.moodlets.advance(815);check(person.mood==50 and person.moodlets.size()==0,"Existing expiry removes offset at the exact minute")
	cleanup(f)

func atomic_and_nested() -> void:
	for scenario in ["reject","late_reject","inactive","bad_text"]:
		var f:=awkward_fixture();var definition:=definition_for(f,ID)
		if scenario in ["reject","late_reject"]:
			f.negative.moodlets=RejectingStore.new(f.negative.id);f.negative.moodlets.reject_after=0 if scenario=="reject" else 1
		if scenario=="inactive":f.service.executor.rng.on_draw=func(draw):
			if draw==4:f.control.unregister_resident(f.negative.id)
		if scenario=="bad_text":definition.params.negative_diary[9]="{partner.name:bad_case}";f.service.catalog._by_trigger["social.resolved"]=[definition]
		var messages: Array=[];f.service.resident_message.connect(func(_id,_name,text):messages.append(text))
		check(fire(f).status!="completed","Whole transaction refused: "+scenario)
		check(f.a.memories.size()+f.b.memories.size()+f.a.moodlets.size()+f.b.moodlets.size()+f.service.chronicle.size()==0 and messages.is_empty() and f.service.cooldown_history().is_empty(),"No partial journal, moodlets, chronicle, chat or cooldown")
		cleanup(f)
	var nested:=awkward_fixture();var observed: Array=[]
	nested.positive.memories.changed.connect(func(_id):
		observed.append([nested.a.memories.size(),nested.b.memories.size(),nested.a.moodlets.size(),nested.b.moodlets.size(),nested.service.chronicle.size(),nested.service.cooldown_history().size()])
		nested.service.executor.publish(nested.service.last_occurrence().occurrence_id)
		nested.social.resolve(nested.b,nested.a,SocialResult.Context.MEAL))
	fire(nested)
	check(observed==[[1,1,1,1,1,2]] and nested.service.completed_events().size()==1,"Store callbacks see fully committed pair; nested fact obeys cooldown")
	cleanup(nested)

func probability_sample() -> void:
	var f:=awkward_fixture();var definition:=definition_for(f,ID);var n:=20000
	for seed_value in [73921,81527]:
		var rng:=RandomNumberGenerator.new();rng.seed=seed_value;f.service.executor.rng=rng
		var marginal: Array=[0,0,0,0];var joint: Array=[];joint.resize(16);joint.fill(0);var message_counts: Array=[0,0,0]
		for index in n:
			var chosen: Dictionary=f.service.executor._choose(definition);var bits:=0
			for item in chosen.items:
				var effect: Dictionary=item.description;var side:=0 if effect.owner.binding=="positive" else 1
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
		print("Awkward sample seed=",seed_value," N=",n," marginal=",marginal," chats=",message_counts," joint=",joint)
	cleanup(f)

func actual_card() -> void:
	var scene=load("res://scenes/main_3d.tscn").instantiate();root.add_child(scene);scene.game_time.set_process(false);scene.game_logger.console_enabled=false
	var definition: Dictionary=scene.game_events.catalog.definitions_for("social.resolved").filter(func(d):return d.id==ID)[0]
	check(scene.game_events.catalog.load_data({"definitions":[definition]},scene.game_events.facts),"Canonical world loads the production definition")
	scene.game_events.selector.set_chance("social.resolved",1);scene.game_events.selector.rng=CountingRng.new();scene.game_events.executor.rng=SequenceRng.new();scene.social_events.rng=LegacyRng.new();scene.social_events.rng.rolls=[100,-100]
	var a: RefCounted=scene.residents[0];var b: RefCounted=scene.residents[1]
	scene.social_events.resolve(a,b,SocialResult.Context.MEAL)
	check(scene.game_events.chronicle.size()==1 and a.memories.size()==1 and b.memories.size()==1,"Live canonical social service commits paired experience")
	scene.resident_selection.select(b);scene.game_ui.info_panel.set_expanded(true);scene.game_ui.info_panel.select_tab(&"bio");await process_frame
	var card: Control=scene.resident_card_view()
	check(card.moodlets_label.text.contains("Неловкость") and card.get_node("%Diary").text.contains(b.memories.find()[0].text),"Card shows new moodlet title and actual unified diary entry")
	scene.free();await process_frame
