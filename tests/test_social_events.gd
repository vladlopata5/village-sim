extends SceneTree
const Service = preload("res://scripts/social_event_service.gd")
const Event = preload("res://scripts/social_event.gd")
const Entry = preload("res://scripts/social_narrative_entry.gd")
const Diary = preload("res://scripts/diary_entry.gd")
const Data = preload("res://scripts/resident_data.gd")
const Trait = preload("res://scripts/trait_type.gd")
const Balance = preload("res://scripts/balance_config.gd")
const Setup = preload("res://tests/behavior_test_setup.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const Need = preload("res://scripts/need_type.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const Definition = preload("res://scripts/building_definition.gd")
const BuildingType = preload("res://scripts/building_type.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
class FixedRng extends RefCounted:
	var probability := 0.0
	var integers: Array = [0]
	var cursor := 0
	var draws := 0
	func randf() -> float:
		draws += 1
		return probability
	func randi_range(low: int, high: int) -> int:
		var value: int = integers[cursor % integers.size()]
		cursor += 1
		return clampi(value, low, high)
var checks := 0
var failures := 0
var feed: Array = []
var debug_lines: Array = []
var event_count := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func pair() -> Array: return [Data.new("a", "Анна", 25), Data.new("b", "Марина", 30)]
func fixed(service: Node, rolls: Array = [0, 0], probability: float = 0.0) -> FixedRng:
	var random := FixedRng.new()
	random.integers = rolls
	random.probability = probability
	service.rng = random
	return random
func result() -> Event:
	var value := Event.new()
	value.context = Event.Context.CONVERSATION
	value.reaction_1 = Event.Reaction.POSITIVE
	value.reaction_2 = Event.Reaction.NEGATIVE
	return value
func _run() -> void:
	check(Balance.SOCIAL_EVENT_DIARY_CHANCE==0.20,"Diary prototype chance")
	var service := Service.new()
	root.add_child(service)
	service.feed_message.connect(func(text): feed.append(text))
	service.logger=preload("res://scripts/game_logger.gd").new()
	service.logger.debug_enabled=true
	service.logger.console_enabled=false
	service.logger.line_logged.connect(func(line,_level): debug_lines.append(line))
	var people := pair()
	var a: RefCounted = people[0]
	var b: RefCounted = people[1]
	b.add_trait(Trait.Type.FOOLISH)
	a.add_liked_trait(Trait.Type.FOOLISH)
	a.set_opinion(b.id, 5)
	b.set_opinion(a.id, -15)
	check(Service.attitude(a,b) == 15 and Service.attitude(b,a) == -15, "Attitude is directed opinion plus preference")
	a.set_opinion(b.id, 100)
	check(Service.attitude(a,b) == 100, "Positive attitude clamped")
	a.remove_liked_trait(Trait.Type.FOOLISH)
	a.add_disliked_trait(Trait.Type.FOOLISH)
	a.set_opinion(b.id, -100)
	check(Service.attitude(a,b) == -100, "Negative attitude clamped")
	a.set_opinion(b.id, 5)
	check(Service.attitude(a,b) == -5, "Opinion change affects derived attitude")
	a.remove_disliked_trait(Trait.Type.FOOLISH)
	a.add_liked_trait(Trait.Type.FOOLISH)
	check(Service.attitude(a,b) == 15, "Preference change affects attitude")
	for score in [-51,-50,0,50,51]:
		var expected := Event.Reaction.NEGATIVE if score < -50 else Event.Reaction.POSITIVE if score > 50 else Event.Reaction.NEUTRAL
		check(Service.reaction(score) == expected, "Inclusive neutral thresholds")
	fixed(service,[43,17])
	var event := service.resolve(a,b,Event.Context.CONVERSATION)
	check(event.attitude_1_to_2 == 15 and event.attitude_2_to_1 == -15, "Both attitudes snapshotted")
	check(event.roll_1 == 43 and event.roll_2 == 17, "Independent reaction rolls")
	check(debug_lines[0].contains("attitude=15 roll=43 score=58 reaction=POSITIVE delta=1"),"Structured DEBUG result logged after mechanics/text")
	print(debug_lines[0])
	check(event.reaction_1 == Event.Reaction.POSITIVE and event.reaction_2 == Event.Reaction.NEUTRAL, "Positive/neutral outcomes independent")
	check(a.get_opinion(b.id) == 6 and b.get_opinion(a.id) == -15, "Only directed positive delta applied")
	fixed(service,[100,-100])
	event = service.resolve(a,b,Event.Context.WORK)
	check(event.reaction_1 == Event.Reaction.POSITIVE and event.reaction_2 == Event.Reaction.NEGATIVE, "Positive/negative outcomes")
	check(event.opinion_delta_1 == 1 and event.opinion_delta_2 == -1, "Delta mapping")
	a.set_opinion(b.id,100)
	b.set_opinion(a.id,-100)
	service.resolve(a,b,Event.Context.MEAL)
	check(a.get_opinion(b.id)==100 and b.get_opinion(a.id)==-100,"Existing opinion clamps preserved")
	people=pair(); a=people[0]; b=people[1]
	fixed(service,[0,0]); service.resolve(a,b,Event.Context.CONVERSATION)
	check(a.relationships.is_empty() and b.relationships.is_empty(),"Neutral preserves sparse lazy records")
	check(service.resolve(a,a,Event.Context.WORK)==null,"Self event rejected")
	check(not "social_attitude" in a,"Attitude is not resident stored state")
	service.entries=[]; fixed(service,[100,-100]); event=service.resolve(a,b,Event.Context.MEAL)
	check(event.selected_entry_id.is_empty() and a.get_opinion(b.id)==1 and b.get_opinion(a.id)==-1,"No text match preserves mechanical result")
	check(not feed.is_empty(),"No-match feed fallback")
	var before: int=a.get_opinion(b.id)
	service.present(event,a,b,[],[])
	check(a.get_opinion(b.id)==before,"Presentation never mutates opinion")
	# Every optional condition independently filters; wildcard entries remain eligible.
	event=result(); b.add_trait(Trait.Type.FOOLISH); a.add_trait(Trait.Type.LAZY)
	var filters: Array=[{"allowed_contexts":["MEAL"]},{"reaction_a":"NEUTRAL"},{"reaction_b":"NEUTRAL"},{"required_traits_a":[Trait.Type.FOOLISH]},{"required_traits_b":[Trait.Type.LAZY]},{"participant_state_tags_a":["EATING"]},{"participant_state_tags_b":["WORKING"]}]
	for condition in filters:
		var entry := Entry.new({"id":"filter","conditions":condition})
		check(not entry.matches(event.context,a,b,event.reaction_1,event.reaction_2,["TALKING"],["TALKING"]),"Mismatching optional condition rejected")
	var wildcard := Entry.new({"id":"general"})
	var specific := Entry.new({"id":"specific","conditions":{"allowed_contexts":["CONVERSATION"],"reaction_a":"POSITIVE","reaction_b":"NEGATIVE","required_traits_a":[Trait.Type.LAZY],"required_traits_b":[Trait.Type.FOOLISH],"participant_state_tags_a":["TALKING"],"participant_state_tags_b":["VISITOR"]}})
	service.entries=[wildcard,specific]
	var matches:=service.matching_entries(event,a,b,["TALKING"],["VISITOR"])
	check(matches.size()==2,"General and specific get one ticket each")
	check(matches[0].orientations.size()==2,"Both orientations do not double entry weight")
	check(specific.matches(event.context,a,b,event.reaction_1,event.reaction_2,["TALKING"],["VISITOR"]),"All filters can match")
	# Reverse orientation applies to text only, not to mechanical directions.
	var reverse := Entry.new({"id":"reverse","conditions":{"reaction_a":"NEGATIVE","required_traits_b":[Trait.Type.LAZY]},"feed_text_a":"%A% -> %B%","feed_text_b":"%B% -> %A%","diary_text_a":"%A% dislikes %B%","diary_text_b":"%B% likes %A%","diary_importance":1})
	service.entries=[reverse]; service.diary_chance=1; feed.clear()
	service.present(event,a,b,["TALKING"],["TALKING"])
	check(event.reversed_orientation and event.selected_entry_id=="reverse","Reverse orientation selected")
	check(feed==["Марина -> Анна","Анна -> Марина"],"A/B feed names reversed correctly")
	check(b.diary_entries.back().text=="Марина dislikes Анна" and a.diary_entries.back().text=="Анна likes Марина","A/B diary ownership follows narrative roles")
	check(event.reaction_1==Event.Reaction.POSITIVE,"Presentation leaves result directions unchanged")
	# Diary rules and morning expiry; every roll independent from mechanical RNG.
	a.diary_entries.clear(); b.diary_entries.clear(); service.diary_chance=0
	service.present(event,a,b,[],[])
	check(a.diary_entries.is_empty() and b.diary_entries.is_empty(),"Diary chance zero prevents history")
	service.diary_chance=1; reverse.diary_importance=Diary.Importance.NONE
	service.present(event,a,b,[],[])
	check(a.diary_entries.is_empty(),"NONE prevents history even at chance one")
	reverse.diary_importance=Diary.Importance.KEY
	service.present(event,a,b,[],[])
	check(a.diary_entries[0].importance==Diary.Importance.KEY,"KEY history stored")
	a.add_diary_entry(Diary.new("temporary",Diary.Importance.TEMPORARY,100))
	a.expire_temporary_diary(360)
	check(a.diary_entries.size()==1 and a.diary_entries[0].importance==Diary.Importance.KEY,"Morning removes temporary and retains key")
	reverse.diary_text_a=""; reverse.diary_text_b=""; reverse.feed_text_a=""; reverse.feed_text_b=""; feed.clear()
	service.present(event,a,b,[],[])
	check(feed.size()==2 and a.diary_entries.size()==1,"Missing output text uses feed fallback without extra diary")
	# Equal-weight sampling and narrative independence from mechanics.
	service.entries=[wildcard,specific]; service.rng=RandomNumberGenerator.new(); service.set_seed(5)
	var counts := {"general":0,"specific":0}
	for i in range(1000):
		service.present(event,a,b,["TALKING"],["VISITOR"])
		counts[event.selected_entry_id]+=1
	check(counts.general>400 and counts.specific>400,"Uniform entries including general/specific")
	var s2:=Service.new(); root.add_child(s2)
	service.set_seed(123); s2.set_seed(123); s2.entries=[]
	var p2:=pair(); people=pair()
	for i in range(25):
		var one:=service.resolve(people[0],people[1],Event.Context.CONVERSATION)
		var two:=s2.resolve(p2[0],p2[1],Event.Context.CONVERSATION)
		check(one.roll_1==two.roll_1 and one.roll_2==two.roll_2,"Narrative choices do not perturb future reaction RNG")
	s2.free(); service.free()
	await _runtime_tests()
	print("Social event checks: %d, failures: %d" % [checks,failures])
	quit(0 if failures==0 else 1)
func _runtime_tests() -> void:
	var scene=Setup.make_scene(self)
	var service: Node=scene.social_events
	check(service.entries.size()==12,"Twelve data-driven entries loaded")
	var sample:=result()
	var people:=pair()
	people[1].add_trait(Trait.Type.FOOLISH)
	var library_matches: Array=service.matching_entries(sample,people[0],people[1],["TALKING"],["TALKING"])
	check(library_matches.any(func(row): return row.entry.id=="foolish_story"),"Real data trait-specific entry matches")
	var reversed_matches: Array=service.matching_entries(sample,people[1],people[0],["TALKING"],["TALKING"])
	check(not reversed_matches.any(func(row): return row.entry.id=="foolish_story"),"Real data requires positive reactor paired with FOOLISH target")

	service.enabled=true
	service.event_resolved.connect(func(_value): event_count+=1)
	var actor=scene.resident_runtimes[1]
	var target=scene.resident_runtimes[3]
	var passer=scene.resident_runtimes[2]
	var random:=fixed(service,[0,0])
	check(service.chance_for(Event.Context.CONVERSATION)==0.30 and service.chance_for(Event.Context.MEAL)==1.00 and service.chance_for(Event.Context.WORK)==0.50,"Configured chances")
	check(service.trigger(actor,Event.Context.CONVERSATION)==null,"No group means no eligible others")
	var starting_draws:=random.draws
	actor.data.get_need(Need.Type.SOCIAL).value=100
	target.data.get_need(Need.Type.SOCIAL).value=100
	check(actor.social.try_social_at(StringName(target.data.id),8000),"Existing conversation starts")
	actor.view._process(100)
	check(random.draws==starting_draws+2,"One roll per participant start; both present before rolls")
	check(event_count==2,"Both initial participants can trigger independently")
	check(service.participant_pool(actor,Event.Context.CONVERSATION)==[target],"Same group pool excludes self")
	var old_events:=event_count
	actor.social._on_minute(scene.game_time.total_minutes+1)
	check(event_count==old_events,"No per-minute duplicate roll")
	# Meaningful group inside kitchen is VISITOR presence; moving passer excluded.
	var group=scene.social_world.group_of(actor.data.id)
	group.center=scene.kitchen_data.position
	check(service.presence(target).building_id==scene.kitchen_data.id,"Conversation visitor has semantic building presence")
	passer.view.position=scene.kitchen_data.position
	passer.data.activity=Activity.Type.MOVING
	check(passer not in service.participant_pool(actor,Event.Context.MEAL,scene.kitchen_data.id),"Physical passer has no semantic membership")
	check(target in service.participant_pool(actor,Event.Context.WORK,scene.kitchen_data.id),"Worker plus visitor eligible regardless of same activity")
	# MEAL emits only after paid eating begins, not reservation/travel.
	scene.free()
	scene=Setup.make_scene(self); service=scene.social_events; service.enabled=true
	actor=scene.resident_runtimes[1]; target=scene.resident_runtimes[3]
	random=fixed(service)
	scene.kitchen_data.resources.add(ResourceType.Type.FOOD,5)
	actor.data.hunger=50
	starting_draws=random.draws
	check(actor.needs.try_eat(8000),"Existing eat starts")
	check(random.draws==starting_draws,"Meal route does not roll")
	actor.view._process(100)
	check(random.draws==starting_draws+1,"Paid eating start rolls once")
	actor.needs._on_arrival(actor.intents.current_intent)
	check(random.draws==starting_draws+1,"Duplicate eating arrival does not roll")
	# Stationary committed worker in same kitchen is eligible to eater.
	target.data.activity=Activity.Type.WORKING
	target.decision._work_cycle_active=true
	target.decision._work_assignment={"location_id":scene.kitchen_data.id,"profession":Profession.Type.GATHERER}
	check(target in service.participant_pool(actor,Event.Context.MEAL,scene.kitchen_data.id),"Eater plus worker eligible")
	check(service.presence(target).tags==["WORKING","WORKER"],"Worker state tags")
	# Partial chances reject equality; a full chance accepts even randf endpoint 1.0.
	for context in Event.Context.values():
		random.probability=service.chance_for(context)
		var boundary_event=service.trigger(actor,context,scene.kitchen_data.id)
		check((boundary_event!=null) if context==Event.Context.MEAL else (boundary_event==null),"100% succeeds at inclusive endpoint; partial chance rejects equality")
		random.probability=service.chance_for(context)-0.001
		if context!=Event.Context.CONVERSATION: check(service.trigger(actor,context,scene.kitchen_data.id)!=null,"Roll just below chance accepted")
	for value in [0.0,0.30,0.50,0.999999,1.0]:
		random.probability=value
		var draws_before:=random.draws
		check(service.trigger(actor,Event.Context.MEAL,scene.kitchen_data.id)!=null,"MEAL always succeeds with eligible participant")
		check(random.draws==draws_before+1,"100% MEAL preserves exactly one chance RNG draw")
	target.decision._work_cycle_active=false
	target.data.activity=Activity.Type.IDLE
	check(service.trigger(actor,Event.Context.MEAL,scene.kitchen_data.id)==null,"100% MEAL without eligible participant still creates no event")
	target.data.activity=Activity.Type.WORKING
	target.decision._work_cycle_active=true
	random.probability=0.50
	check(service.trigger(actor,Event.Context.WORK,scene.kitchen_data.id)==null,"WORK threshold is exactly 0.50")
	random.probability=0.499999
	check(service.trigger(actor,Event.Context.WORK,scene.kitchen_data.id)!=null,"WORK roll below 0.50 succeeds")
	# Uniform target selection over three current semantic workers.
	for rt in scene.resident_runtimes:
		if rt==actor: continue
		rt.data.activity=Activity.Type.WORKING
		rt.decision._work_cycle_active=true
		rt.decision._work_assignment={"location_id":scene.kitchen_data.id}
	service.rng=RandomNumberGenerator.new()
	service.set_seed(333)
	var counts: Dictionary={}
	for i in range(3000):
		var outcome=service.trigger(actor,Event.Context.MEAL,scene.kitchen_data.id)
		if outcome!=null: counts[outcome.resident_2_id]=counts.get(outcome.resident_2_id,0)+1
	check(counts.size()==3,"All eligible residents can be chosen")
	check(counts.values().reduce(func(total,value): return total+value,0)==3000,"All 3000 eligible MEAL triggers succeed")
	for amount in counts.values(): check(amount>900 and amount<1100,"Uniform random partner frequencies at 100% MEAL")
	# Feed bounded and expiry does not affect history or opinion.
	for i in range(8): scene.social_feed.add_message("message %d" % i)
	check(scene.social_feed.messages.size()==Balance.SOCIAL_FEED_MAX_MESSAGES,"Feed bounded")
	var label: Label=scene.social_feed.messages.back()
	var timer: Timer=scene.social_feed.get_children().back()
	timer.timeout.emit()
	check(scene.social_feed.messages.size()==3,"Real UI timeout expires message")
	check(not label in scene.social_feed.messages,"Expired message absent")
	for message in scene.social_feed.messages.duplicate(): scene.social_feed.expire_message(message)
	check(not scene.social_feed.visible,"Empty feed hides without game state mutation")
	await process_frame
	await process_frame
	for child in scene.social_feed.get_children():
		if child is Timer: child.timeout.emit()
	check(scene.social_feed.messages.is_empty(),"Timers of evicted/freed labels expire safely")

	var card=scene.get_node("HUD/ResidentCard")
	scene.resident_selection.select(actor.data)
	actor.data.diary_entries.clear()
	actor.data.add_diary_entry(Diary.new("today",Diary.Importance.TEMPORARY,scene.game_time.total_minutes))
	actor.data.add_diary_entry(Diary.new("key",Diary.Importance.KEY,scene.game_time.total_minutes))
	check(card.get_node("Margin/Column/Scroll/Content/Diary").text.contains("today"),"Diary signal updates ResidentCard")
	service._on_phase_changed("День")
	check(actor.data.diary_entries.size()==2,"Other phases do not expire history")
	scene.game_time.total_minutes+=1440
	service._on_phase_changed("Утро")
	check(actor.data.diary_entries.size()==1 and actor.data.diary_entries[0].text=="key","Next morning expiry signal updates diary")
	check(not card.get_node("Margin/Column/Scroll/Content/Diary").text.contains("today"),"Card reflects expiry")
	passer=scene.resident_runtimes[2]
	passer.free()
	service._on_phase_changed("Утро")
	check(actor.data.diary_entries.size()==1 and actor.data.diary_entries[0].text=="key","Morning tolerates stale runtime reference and retains key history")
	scene.free()
	# Real gatherer and builder hooks each fire once per started cycle.
	scene=Setup.make_scene(self); service=scene.social_events; service.enabled=true
	random=fixed(service)
	actor=scene.resident_runtimes[2]
	actor.data.work_location_id=scene.gatherer_hut_data.id
	scene.game_time.debug_next_phase()
	actor.decision.work_available=func(): return scene.production.can_work(actor.data)
	actor.schedule.request_work()
	actor.view._process(100)
	check(random.draws==1,"Gatherer actual cycle start hooked")
	actor.view._process(100)
	check(random.draws==1,"Repeated executor frame does not duplicate work start")

	starting_draws=random.draws
	actor.decision._on_completed(Intent.new(Intent.Type.MOVE_TO,&"unrelated",Vector2.ZERO,0,true))
	check(random.draws==starting_draws,"Unrelated completion not work roll")
	actor.decision._end_work_cycle("test boundary")
	actor.data.activity=Activity.Type.IDLE
	actor.schedule.request_work(); actor.view._process(100)
	check(random.draws==starting_draws+1,"Next gatherer work cycle rolls again")
	scene.free()
	scene=Setup.make_scene(self); service=scene.social_events; service.enabled=true
	random=fixed(service)
	actor=scene.resident_runtimes[1]
	scene.game_time.debug_next_phase()
	scene.player_control.assign_profession(actor.data.id,Profession.Type.BUILDER)
	scene.placement.select(Definition.for_type(BuildingType.Type.HOME))
	scene.placement.update_position(Vector2(-500,200))
	var site=scene.placement.confirm()
	site.add_delivered_material(ResourceType.Type.WOOD,10)
	check(actor.builder.request_work(),"Builder real task starts")
	actor.view._process(100)
	check(random.draws==1,"Builder building cycle start rolls once; transport not hooked")
	scene.free()
