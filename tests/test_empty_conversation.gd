extends "res://tests/test_event_catalog_content.gd"
const Renderer = preload("res://scripts/event_text_renderer.gd")
const Balance = preload("res://scripts/balance_config.gd")
const Dynamics = preload("res://scripts/need_dynamics.gd")
const ID := "social.empty_conversation"

func empty_fixture(reverse: bool = false) -> Dictionary:
	var people: Array=[Data.new("a","Анна",25),Data.new("b","Степан",30)]
	people[0].grammatical_gender=Traits.GrammaticalGender.FEMININE
	if reverse:people.reverse()
	var f:=fixture(people);only(f,ID);f.social.rng.rolls=[50,50]
	return f

func _run() -> void:
	conditions_and_competition(); outcomes(); formulations(); pair_lifecycle(); numeric_rates(); clock_effect(); atomic_notifications(); statistics()
	await actual_card()
	print("Empty conversation: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func conditions_and_competition() -> void:
	for context in SocialResult.Context.values():
		for first in [0,50,100]:
			for second in [0,50,100]:
				var f:=empty_fixture();f.social.rng.rolls=[first,second]
				var valid: bool=context!=SocialResult.Context.WORK and first==50 and second==50
				check((fire(f,context).status=="completed")==valid and f.service.chronicle.size()==int(valid),"Only two neutral reactions in conversation/meal; rejected fact creates nothing")
				cleanup(f)
	for mood in [0,19,20,21,50,100]:
		var f:=empty_fixture();MoodSetup.set_value(f.a,mood)
		check(fire(f).status=="completed","No additional mood threshold");cleanup(f)
	for roll in [.299999,.3,1.0]:
		var f:=empty_fixture();f.service.selector.set_chance("social.resolved",Balance.SOCIAL_FOLLOWUP_EVENT_CHANCE);f.rng.value=roll
		check(Balance.SOCIAL_FOLLOWUP_EVENT_CHANCE==.3 and (fire(f).status=="completed")==(roll<.3),"Existing 30 percent gate and exact boundary preserved");cleanup(f)
	for context in SocialResult.Context.values():
		for roll in [0.0,.499999,.5,1.0]:
			var f:=empty_fixture();f.service._load_catalogs();f.a.add_trait(Traits.Type.SOCIABLE);f.b.add_trait(Traits.Type.INTROVERTED);f.rng.value=roll
			var result:=fire(f,context);var selection: Dictionary=f.service.selector.run(f.service.last_occurrence())
			if context==SocialResult.Context.WORK:check(selection.eligible.is_empty() and result.status=="no_match","Both neutral conversation stories exclude WORK")
			elif context==SocialResult.Context.MEAL:check(selection.eligible==[ID] and result.definition_id==ID,"Existing character contrast remains CONVERSATION-only")
			else:
				check(selection.eligible==["social.character_contrast",ID] and result.definition_id==selection.eligible[0 if roll<.5 else 1],"Equal-weight competition with existing character contrast, including exact0.5")
				check(f.service.completed_events().size()==1,"One event per opportunity even when both qualify")
			cleanup(f)

func outcomes() -> void:
	for reverse in [false,true]:
		for context in [SocialResult.Context.CONVERSATION,SocialResult.Context.MEAL]:
			for bits in 16:
				var f:=empty_fixture(reverse);var messages: Array=[]
				f.service.resident_message.connect(func(id,name,text):messages.append([id,name,text]))
				f.service.executor.rng.values=[0.0 if bits&1 else 1.0,0.0 if bits&2 else 1.0,0.0 if bits&4 else 1.0,0.0 if bits&8 else 1.0]
				var result:=fire(f,context)
				check(result.status=="completed" and result.main.id==f.a.id and f.service.chronicle.size()==1,"One mandatory chronicle, even without private consequences")
				var expected_senders: Array=[]
				if bits&1:expected_senders.append(f.a.id)
				if bits&2:expected_senders.append(f.b.id)
				check(messages.map(func(row):return row[0])==expected_senders,"Zero/one/two messages have independent actual senders")
				for side in 2:
					var person: RefCounted=f.a if side==0 else f.b;var partner: RefCounted=f.b if side==0 else f.a
					var present:=int(bool(bits&(4<<side)));var records: Array=person.memories.find()
					check(records.size()==present and person.moodlets.size()==present,"One shared roll for journal and moodlet per side")
					if present:
						var memory: Dictionary=records[0];var moodlet: Dictionary=person.moodlets.get_entry("talked_out")
						check(memory.type=="neutral_interaction" and memory.strength==15 and memory.tags==["social","neutral"] and memory.target.id==partner.id and memory.provenance.kind=="experienced" and not memory.permanent,"Exact structured personal memory contract")
						check(moodlet.expires_at_minute==755 and moodlet.target.id==partner.id and person.mood==50 and moodlet.modifiers==[{"channel":"need_growth_rate","need":"social","multiplier":.5}] and person.moodlets.need_growth_factors(635)=={Need.Type.SOCIAL:.5},"Talked-out moodlet halves only social growth for120 minutes without mood offset")
				check(f.a.get_opinion(f.b.id)==0 and f.b.get_opinion(f.a.id)==0,"Only original social deltas in both directions")
				var token: String=f.service.last_occurrence().occurrence_id;var draws: int=f.service.executor.rng.draws
				var before: Array=[f.a.memories.find(),f.b.memories.find(),f.a.moodlets.find(),f.b.moodlets.find()];f.clock.total_minutes+=10
				f.service.replay(token);f.service.executor.publish(token)
				check(f.service.executor.rng.draws==draws and [f.a.memories.find(),f.b.memories.find(),f.a.moodlets.find(),f.b.moodlets.find()]==before and messages.size()==expected_senders.size() and f.service.chronicle.size()==1,"Duplicate occurrence never refreshes, rerolls, writes or speaks")
				cleanup(f)
	var boundary:=empty_fixture();boundary.service.executor.rng.values=[.5,.5,.3,.3]
	check(fire(boundary).status=="completed" and boundary.a.memories.size()+boundary.b.memories.size()+boundary.a.moodlets.size()+boundary.b.moodlets.size()==0,"Exact optional chance boundaries fail, mandatory chronicle succeeds");cleanup(boundary)

func formulations() -> void:
	for reverse in [false,true]:
		for genders in 4:
			for index in 10:
				var f:=empty_fixture(reverse)
				for side in 2:
					var person: RefCounted=f.a if side==0 else f.b
					person.grammatical_gender=Traits.GrammaticalGender.FEMININE if genders&(1<<side) else Traits.GrammaticalGender.MASCULINE
					person.resident_name="Анна" if genders&(1<<side) else "Степан"
				var choices: Array=[index,(index+1)%10,(index+3)%10,(index+7)%10,(index+9)%10];var draws: Array=[0,0,0,0]
				for choice in choices:draws.append((choice+.1)/10.0)
				f.service.executor.rng.values=draws;var messages: Array=[]
				f.service.resident_message.connect(func(id,_name,text):messages.append([id,text]))
				var definition:=definition_for(f,ID);check(fire(f).status=="completed","Every variant prepares and commits")
				for side in 2:
					var person: RefCounted=f.a if side==0 else f.b;var partner: RefCounted=f.b if side==0 else f.a
					var values: Dictionary={"speaker":person.event_text_projection(),"partner":partner.event_text_projection()}
					check(messages[side]==[person.id,Renderer.render(definition.params.chat_text[choices[side]],values).text],"Shared chat pool still has separate text draws")
					var text: String=person.memories.find()[0].text
					check(text==Renderer.render(definition.params.diary_text[choices[2+side]],values).text and not "{" in text and not text.contains(" с с ") and not text.contains(" с со "),"Diary uses its own partner and independent variant")
				check(f.service.chronicle.entries()[0].text==Renderer.render(definition.text.chronicle[choices[4]],{"actor":f.a.event_text_projection(),"other":f.b.event_text_projection()}).text,"Independent chronicle variant, names and cases")
				cleanup(f)
	var example:=empty_fixture();var d:=definition_for(example,ID)
	var example_values: Dictionary={"speaker":example.a.event_text_projection(),"partner":example.b.event_text_projection()}
	check(d.params.chat_text.size()==10 and d.params.diary_text.size()==10 and d.text.chronicle.size()==10,"Three shared pools of ten")
	check(Renderer.render(d.params.chat_text[5],example_values).text=="Знаешь, я тут подумала... Впрочем, ничего особенного.","Female chat speaker form")
	check(Renderer.render(d.params.diary_text[1],example_values).text.begins_with("Провела некоторое время"),"Female journal speaker form")
	check(Renderer.render(d.params.diary_text[0],example_values).text.begins_with("Сегодня поговорили со Степаном."),"Actual partner with full preposition")
	check(Renderer.render(d.text.chronicle[9],{"actor":example.a.event_text_projection(),"other":example.b.event_text_projection()}).text.begins_with("Беседа Анны и Степана"),"Genitive names in chronicle")
	cleanup(example)

func pair_lifecycle() -> void:
	var f:=empty_fixture();fire(f)
	check(f.service.cooldown_history().size()==2 and f.service.cooldown_history().values()==[635,635],"Both cooldown directions committed")
	f.clock.total_minutes=874;var source: RefCounted=f.social.resolve(f.b,f.a,SocialResult.Context.MEAL)
	check(f.service.replay(source.confirmed_context().occurrence_id).status=="no_match","Reverse pair blocked at239 across contexts")
	f.clock.total_minutes=875;source=f.social.resolve(f.b,f.a,SocialResult.Context.MEAL)
	check(f.service.replay(source.confirmed_context().occurrence_id).status=="completed" and f.service.chronicle.size()==2,"Reverse pair allowed at exact240");cleanup(f)
	var refresh:=empty_fixture();var d:=definition_for(refresh,ID);d.cooldown.minutes=0;load_content(refresh,{"definitions":[d]})
	fire(refresh);refresh.clock.total_minutes=695;refresh.service.executor.rng=SequenceRng.new();fire(refresh)
	for person in [refresh.a,refresh.b]:check(person.moodlets.size()==1 and person.moodlets.get_entry("talked_out").expires_at_minute==815 and person.mood==50 and person.moodlets.need_growth_factors(695)=={Need.Type.SOCIAL:.5},"New occurrence refreshes one half-rate record, never compounds to0.25")
	refresh.clock.total_minutes=814
	for person in [refresh.a,refresh.b]:person.moodlets.advance(814);check(person.moodlets.need_growth_factors(814)=={Need.Type.SOCIAL:.5},"Half growth active just before expiry")
	refresh.clock.total_minutes=815
	for person in [refresh.a,refresh.b]:person.moodlets.advance(815);check(person.mood==50 and person.moodlets.size()==0 and person.moodlets.need_growth_factors(815).is_empty(),"Exact expiry removes growth factor, mood stays unchanged")
	cleanup(refresh)

func numeric_rates() -> void:
	var source:=empty_fixture();fire(source);var record: Dictionary=source.a.moodlets.get_entry("talked_out")
	for trait_type in [-1]+Traits.Type.values():
		for activity in Dynamics.SOCIAL_RATES:
			var normal:=Data.new("normal","Норма",25);var changed:=Data.new("changed","Эффект",25)
			for person in [normal,changed]:
				if trait_type>=0:person.add_trait(trait_type)
				person.activity=activity
				for need in person.needs.values():need.value=50
			var numeric:=record.duplicate(true);numeric.owner={"kind":"resident","id":changed.id};numeric.created_minute=0;numeric.expires_at_minute=120
			check(changed.moodlets.add(numeric),"Actual event descriptor works in existing numeric store")
			var baseline:=Dynamics.new();var modified:=Dynamics.new();baseline._data=normal;modified._data=changed
			for dynamics in [baseline,modified]:
				dynamics.ordinary_idle_provider=func():return activity==Activity.Type.IDLE
				dynamics.active_work_provider=func():return true
				dynamics.caring_partner_provider=func():return true
			for minute in range(1,21):baseline._on_minute_changed(minute);modified._on_minute_changed(minute)
			var denominator:=60*Balance.SOCIAL_GROWTH_DIVISOR*1000
			var ordinary: float=(normal.get_need(Need.Type.SOCIAL).value-50)*denominator+baseline._fractions[Need.Type.SOCIAL]
			var affected: float=(changed.get_need(Need.Type.SOCIAL).value-50)*denominator+modified._fractions[Need.Type.SOCIAL]
			check(is_equal_approx(affected,ordinary*(.5 if Dynamics.SOCIAL_RATES[activity]>0 else 1.0)),"Social growth exactly half; recovery unchanged, with every trait/activity and sleep fractions")
			for need in [Need.Type.HUNGER,Need.Type.FATIGUE,Need.Type.LEISURE]:check(changed.get_need(need).value==normal.get_need(need).value and modified._fractions[need]==baseline._fractions[need],"Other need values and fractions unchanged")
			check(changed.mood==normal.mood and changed.mood==50,"No mood effect")
			baseline.free();modified.free()
	cleanup(source)

func clock_effect() -> void:
	for speed in [1,20]:
		var f:=empty_fixture();fire(f);f.a.activity=Activity.Type.WORKING;f.a.get_need(Need.Type.SOCIAL).value=20
		f.clock.set_speed(speed);f.clock.minute_changed.connect(f.a.moodlets.advance)
		var dynamics:=Dynamics.new();root.add_child(dynamics);dynamics.setup(f.clock,f.a)
		f.clock.advance(119.0/speed)
		check(f.clock.total_minutes==754 and f.a.moodlets.need_growth_factors(754)=={Need.Type.SOCIAL:.5},"119 active minutes at normal/accelerated speed")
		paused=true;f.clock.advance(100);paused=false
		check(f.clock.total_minutes==754 and f.a.moodlets.size()==1,"Pause cannot age moodlet")
		var denominator:=60*Balance.SOCIAL_GROWTH_DIVISOR*1000
		var before: float=f.a.get_need(Need.Type.SOCIAL).value*denominator+dynamics._fractions[Need.Type.SOCIAL]
		f.clock.advance(1.0/speed)
		var after: float=f.a.get_need(Need.Type.SOCIAL).value*denominator+dynamics._fractions[Need.Type.SOCIAL]
		check(f.clock.total_minutes==755 and f.a.moodlets.size()==0 and after-before==60000,"Exact expiry minute uses ordinary social growth, not stale half rate")
		dynamics.free();cleanup(f)

func atomic_notifications() -> void:
	for scenario in ["reject","late_reject","inactive","bad_text"]:
		var f:=empty_fixture();var definition:=definition_for(f,ID)
		if scenario in ["reject","late_reject"]:f.b.moodlets=RejectingStore.new(f.b.id);f.b.moodlets.reject_after=0 if scenario=="reject" else 1
		if scenario=="inactive":f.service.executor.rng.on_draw=func(draw):
			if draw==4:f.control.unregister_resident(f.b.id)
		if scenario=="bad_text":definition.params.diary_text[9]="{partner.name:bad_case}";f.service.catalog._by_trigger["social.resolved"]=[definition]
		var messages: Array=[];f.service.resident_message.connect(func(_id,_name,text):messages.append(text))
		check(fire(f).status!="completed" and f.a.memories.size()+f.b.memories.size()+f.a.moodlets.size()+f.b.moodlets.size()+f.service.chronicle.size()==0 and messages.is_empty() and f.service.cooldown_history().is_empty(),"Whole package rejected without partial effects: "+scenario)
		cleanup(f)
	var nested:=empty_fixture();var observed: Array=[]
	nested.a.memories.changed.connect(func(_id):
		observed.append([nested.a.memories.size(),nested.b.memories.size(),nested.a.moodlets.size(),nested.b.moodlets.size(),nested.service.chronicle.size(),nested.service.cooldown_history().size()])
		nested.service.executor.publish(nested.service.last_occurrence().occurrence_id);nested.social.resolve(nested.b,nested.a,SocialResult.Context.MEAL))
	fire(nested)
	check(observed==[[1,1,1,1,1,2]] and nested.service.completed_events().size()==1,"Nested callbacks see complete data and cannot bypass cooldown");cleanup(nested)

func statistics() -> void:
	var f:=empty_fixture();var definition:=definition_for(f,ID);var n:=20000
	for seed_value in [93921,101527]:
		var rng:=RandomNumberGenerator.new();rng.seed=seed_value;f.service.executor.rng=rng
		var marginal: Array=[0,0,0,0];var joint: Array=[];joint.resize(16);joint.fill(0);var chats: Array=[0,0,0]
		for index in n:
			var selected: Dictionary=f.service.executor._choose(definition);var bits:=0
			for item in selected.items:
				var effect: Dictionary=item.description;var side:=0 if effect.owner.role=="actor" else 1
				if effect.op=="chat.say":bits|=1<<side
				if effect.op=="memory.add":bits|=4<<side
				if effect.op=="moodlet.add":check(selected.items.any(func(other):return other.description.op=="memory.add" and other.description.owner==effect.owner),"Statistics never split a paired experience")
			for bit in 4:marginal[bit]+=int(bool(bits&(1<<bit)))
			joint[bits]+=1;chats[int(bool(bits&1))+int(bool(bits&2))]+=1
		for bit in 4:check(absf(float(marginal[bit])/n-[.5,.5,.3,.3][bit])<.02,"Independent marginal probability")
		for bits in 16:check(absf(float(joint[bits])/n-.25*(.3 if bits&4 else .7)*(.3 if bits&8 else .7))<.012,"All sixteen combinations have product probabilities")
		for count in 3:check(absf(float(chats[count])/n-[.25,.5,.25][count])<.02,"Zero/one/two messages near25/50/25 percent")
		print("Empty conversation sample seed=",seed_value," N=",n," marginal=",marginal," chats=",chats," joint=",joint)
	cleanup(f)

func actual_card() -> void:
	var scene=load("res://scenes/main_3d.tscn").instantiate();root.add_child(scene);scene.game_time.set_process(false);scene.game_logger.console_enabled=false
	var definition: Dictionary=scene.game_events.catalog.definitions_for("social.resolved").filter(func(d):return d.id==ID)[0]
	check(scene.game_events.catalog.load_data({"definitions":[definition]},scene.game_events.facts),"Canonical service loads production definition")
	scene.game_events.selector.set_chance("social.resolved",1);scene.game_events.selector.rng=CountingRng.new();scene.game_events.executor.rng=SequenceRng.new();scene.social_events.rng=SocialRng.new();scene.social_events.rng.rolls=[50,50]
	var a: RefCounted=scene.residents[0];var b: RefCounted=scene.residents[1];var old_mood: float=b.mood;scene.social_events.resolve(a,b,SocialResult.Context.MEAL)
	check(scene.game_events.chronicle.size()==1 and a.memories.size()==1 and b.memories.size()==1,"Live social service creates both personal experiences")
	scene.resident_selection.select(b);scene.game_ui.info_panel.set_expanded(true);scene.game_ui.info_panel.select_tab(&"bio");await process_frame
	var card: Control=scene.resident_card_view()
	check(card.moodlets_label.text.contains("Наговорился") and card.get_node("%Diary").text.contains(b.memories.find()[0].text),"Actual card shows moodlet and unified diary")
	check(b.mood==old_mood and b.moodlets.need_growth_factors(scene.game_time.total_minutes)=={Need.Type.SOCIAL:.5},"Canonical event has no mood offset and exposes the general social growth factor")
	check(not scene.resident_runtimes[0].moodlet_actions._unlocked("angry") and not scene.resident_runtimes[1].moodlet_actions._unlocked("angry"),"Talked-out moodlet never unlocks angry action")
	scene.free();await process_frame
