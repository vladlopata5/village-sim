extends "res://tests/test_event_effects.gd"
const N = preload("res://scripts/need_type.gd").Type
const Rules = preload("res://scripts/need_moodlet_rules.gd")
const Factory = preload("res://scripts/resident_factory.gd")
const Trait = preload("res://scripts/trait_type.gd")
const Dynamics = preload("res://scripts/need_dynamics.gd")
const Social = preload("res://scripts/social_event_service.gd")
const SocialEvent = preload("res://scripts/social_event.gd")
class ObservedStore extends Moodlets:
	var rebuilds := 0
	func _rebuild_numeric_cache(minute: int) -> void:
		rebuilds += 1
		super._rebuild_numeric_cache(minute)
class NegativeRng extends RefCounted:
	func randf() -> float: return 0.0
	func randi_range(_low: int, _high: int) -> int: return -100

func _run() -> void:
	formula()
	thresholds()
	recovery_rates()
	reentrancy()
	activation_and_cache()
	time_controls()
	event_cycle()
	await actual_ui()
	print("Mood system: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func record(type: String, value: float, minute: int = 0, expiry: Variant = null) -> Dictionary:
	return {"id":type,"type":type,"created_minute":minute,"expires_at_minute":expiry,"source_occurrence_id":"mood/%s/%d" % [type,minute],"modifiers":[{"channel":"mood.offset","value":value}]}

func formula() -> void:
	var data := Data.new("mood","Иван",20)
	check(data.mood == 50 and data.moodlets.size() == 0, "Base mood50 with no state")
	check(data.moodlets.add(record("positive",5)) and data.mood == 55, "Positive mood offset")
	check(data.moodlets.add(record("negative",-12.5)) and data.mood == 42.5, "Mixed signed fractional sum, no arbitrary rounding")
	check(data.moodlets.add(record("positive",10,1)) and data.moodlets.size() == 2, "Refresh replaces one slot")
	data.moodlets.advance(1)
	check(data.mood == 47.5, "Refresh does not stack")
	data.moodlets.remove("negative"); check(data.mood == 60, "Removal loses contribution")
	data.moodlets.add(record("large",1000,1)); check(data.mood == 100, "Upper clamp")
	data.moodlets.remove("large"); data.moodlets.add(record("large",-1000,1)); check(data.mood == 0, "Lower clamp")
	for modifier in [{"channel":"mood.offset","value":true},{"channel":"mood.offset","value":"-10"},{"channel":"mood.offset","value":NAN},{"channel":"mood.offset","value":INF},{"channel":"mood.offset","value":-10,"extra":1}]:
		var invalid := record("invalid",0); invalid.modifiers = [modifier]
		check(not data.moodlets.add(invalid), "Malformed offset rejected before any mutation")
	var opaque := record("opaque",0); opaque.modifiers = [{"channel":"mood","value":-100},{"channel":"future_channel","value":5}]
	check(data.moodlets.add(opaque) and data.mood == 0, "Legacy opaque channels remain inert")
	var fresh := Data.new("fresh","Анна",20)
	for type in ["angry","pride","well_fed","admiration","work_satisfaction"]: fresh.moodlets.add({"id":type,"type":type,"created_minute":0,"source_occurrence_id":type,"modifiers":[]})
	check(fresh.mood == 50, "Previously inert definitions do not receive implicit offsets")

func thresholds() -> void:
	for type in N.values():
		var data := Data.new("need%d" % type,"Тест",25); var facts: Array = []; var notices: Array = []
		data.need_state_changed.connect(func(context): facts.append(context))
		data.moodlets.changed.connect(func(changed_id): notices.append(changed_id))
		var need: RefCounted = data.get_need(type); var id: String = Rules.DEFINITIONS[type].id
		for value in [39,40,90]:
			need.value = value
			check(data.mood == 50 and data.moodlets.size() == 0 and facts.is_empty(), "Strict upper threshold, not yet active: " + str(value))
		need.value = 91
		check(data.mood == 40 and data.moodlets.size() == 1 and facts.size() == 1 and notices == [id], "Guaranteed activation on91 for each need")
		var entry: Dictionary = data.moodlets.get_entry(id)
		check(entry.expires_at_minute == null and entry.modifiers == [{"channel":"mood.offset","value":-10}], "Indefinite canonical state record")
		for value in [91,100,90,40]:
			need.value = value
			check(data.mood == 40 and data.moodlets.get_entry(id) == entry and facts.size() == 1, "No refresh or duplicate signal in active hysteresis state")
		need.value = 39
		check(data.mood == 50 and data.moodlets.size() == 0 and facts.size() == 2 and notices == [id,id], "Guaranteed removal only below40")
		check(facts[0].trigger == "need.state_changed" and facts[0].payload == {"need":N.keys()[type].to_lower(),"active":true,"deficit":91,"moodlet":id} and not facts[1].payload.active, "Owned ordered fact is available to future narrative adapters")
		need.value = 0; need.value = 100; need.value = 0
		check(facts.size() == 4 and data.mood == 50 and facts[0].occurrence_id != facts[2].occurrence_id, "Large jumps and distinct transition identities")
	var all := Data.new("all","Тест",25)
	for type in N.values(): all.get_need(type).value = 100
	check(all.mood == 10 and all.moodlets.size() == 4, "Four independent active states sum to-40")
	for type in N.values():
		all.get_need(type).value = 39
		check(all.moodlets.get_entry(Rules.DEFINITIONS[type].id).is_empty(), "Removing a need state affects its own ID")
	check(all.mood == 50, "All recovered needs restore base50 immediately")
	var created := Factory.create("initial","Анна",25,Profession.Type.NONE,[],91,100,&"",&"",[],[],Trait.GrammaticalGender.FEMININE)
	check(created.mood == 30 and created.moodlets.size() == 2, "Initial factory values get guaranteed states before runtime exists")
	for type in N.values():
		check(Rules.display_name(Rules.DEFINITIONS[type].id,Trait.GrammaticalGender.MASCULINE)==["Голодный","Измотанный","Одинокий","Скучающий"][type], "Male names")
		check(Rules.display_name(Rules.DEFINITIONS[type].id,Trait.GrammaticalGender.FEMININE)==["Голодная","Измотанная","Одинокая","Скучающая"][type], "Female names")

func recovery_rates() -> void:
	var activity_type = preload("res://scripts/resident_activity.gd").Type
	for row in [[N.HUNGER,activity_type.EATING],[N.FATIGUE,activity_type.RESTING],[N.FATIGUE,activity_type.SLEEPING],[N.SOCIAL,activity_type.TALKING],[N.LEISURE,activity_type.RELAXING]]:
		var person := Data.new("recovery%d" % row[1],"Тест",25); person.activity = row[1]
		var facts: Array = []; person.need_state_changed.connect(func(context): facts.append(context.payload))
		person.get_need(row[0]).value = 91
		var dynamics := Dynamics.new(); dynamics._data = person
		for minute in range(1,2001):
			dynamics._on_minute_changed(minute)
			if person.get_need(row[0]).value < 40: break
		var id: String = Rules.DEFINITIONS[row[0]].id
		check(person.get_need(row[0]).value < 40 and person.moodlets.get_entry(id).is_empty(), "Existing meal/rest/sleep/talk/leisure recovery removes its state")
		var own: Array = facts.filter(func(context):return context.moodlet==id)
		check(own.size() == 2 and own[0].active and not own[1].active, "Recovery crosses hysteresis once, without refresh attempts")
		dynamics.free()

func reentrancy() -> void:
	var data := Data.new("nested","Тест",25); var facts: Array = []
	data.need_state_changed.connect(func(context): facts.append(context.payload.active))
	var nested := func(id):
		if id == "hungry" and data.hunger == 91: data.hunger = 39
	data.moodlets.changed.connect(nested)
	data.hunger = 91
	check(facts == [true,false] and data.mood == 50 and data.moodlets.size() == 0, "Store callbacks retain factual transition order and final coherent state")
	data.moodlets.changed.disconnect(nested)

func activation_and_cache() -> void:
	var clock := Clock.new(); root.add_child(clock); clock.set_process(false); clock.total_minutes = 0
	var data := Data.new("timed","Тест",20); var store := ObservedStore.new(data.id); data.moodlets = store; store.bind_clock(clock)
	var mixed := record("mixed",5,10,20); mixed.modifiers.append({"channel":"need_growth_rate","need":"hunger","multiplier":0.5})
	store.add(mixed)
	var baseline: int = store.rebuilds
	for minute in range(1,10):
		clock.total_minutes = minute; store.advance(minute)
		check(data.mood == 50 and store.need_growth_factors(minute).is_empty() and store.rebuilds == baseline, "No per-minute traversal before activation")
	clock.total_minutes = 10; store.advance(10)
	check(data.mood == 55 and store.need_growth_factors(10)[N.HUNGER] == 0.5 and store.rebuilds == baseline+1, "Both channels activate at the same exact boundary")
	for minute in range(11,20): clock.total_minutes = minute; store.advance(minute); check(data.mood == 55 and store.rebuilds == baseline+1, "No repeated scan while active")
	clock.total_minutes = 20; store.advance(20)
	check(data.mood == 50 and store.need_growth_factors(20).is_empty() and store.size() == 0 and store.rebuilds == baseline+2, "Expiration clears both channels exactly before needs")
	#100 residents: prove no repeated cache rebuild until an actual state boundary.
	var people: Array = []; var counts: Array = []
	clock.total_minutes = 0
	for index in 100:
		var person := Data.new("many%d" % index,"Тест",20); person.moodlets = ObservedStore.new(person.id); person.moodlets.bind_clock(clock)
		for type in N.values(): person.get_need(type).value = 91
		person.moodlets.add(record("future",2,50,75)); people.append(person); counts.append(person.moodlets.rebuilds)
	for minute in range(1,100):
		clock.total_minutes = minute
		for index in people.size():
			var person: RefCounted = people[index]; person.moodlets.advance(minute)
			check(person.moodlets.rebuilds == counts[index]+(2 if minute>=75 else 1 if minute>=50 else 0), "100 residents: boundary-only shared numeric cache")
			check(person.mood == (12 if minute>=50 and minute<75 else 10), "100 residents: no stale mood")
	clock.total_minutes = 200
	store.add(record("skipped",7,110,120)); store.advance(200)
	check(data.mood == 50 and not store.is_active("skipped",200), "A jump past activation and expiry has no stale effect")
	clock.free()

func time_controls() -> void:
	var clock := Clock.new(); root.add_child(clock); clock.set_process(false); clock.total_minutes = 0
	var data := Data.new("time","Тест",25); data.moodlets.bind_clock(clock); clock.minute_changed.connect(data.moodlets.advance)
	data.moodlets.add(record("timed",-10,0,3))
	paused = true; clock.advance(5)
	check(clock.total_minutes == 0 and data.mood == 40, "Pause does not consume moodlet time")
	clock.debug_skip_minutes(3)
	check(data.mood == 50 and data.moodlets.size() == 0, "Explicit jump while paused expires precisely")
	paused = false; data.moodlets.add(record("fast",-10,3,7)); clock.set_speed(4); clock.advance(1)
	check(clock.total_minutes == 7 and data.mood == 50, "Acceleration uses the same minute boundaries")
	clock.free()

func event_cycle() -> void:
	var f := fixture(); var contexts: Array = []
	f.a.need_state_changed.connect(func(context): contexts.append(context))
	for type in [N.HUNGER,N.FATIGUE,N.SOCIAL]: f.a.get_need(type).value = 91
	check(f.a.mood == 20 and f.service.chronicle.size() == 0 and f.a.diary_entries.is_empty() and f.rng.draws == 0 and f.service.executor.rng.draws == 0 and contexts.size() == 3, "Guaranteed changes have no story record or RNG draw")
	var definition: Dictionary = f.service.catalog.definitions_for("skill.raised")[0]
	definition.effects = [{"op":"moodlet.add","owner":{"role":"actor"},"definition":"event_mood","modifiers":[{"channel":"mood.offset","value":3}]}]
	load_content(f,{"definitions":[definition]})
	var observations: Array = []
	f.a.moodlets.modifiers_changed.connect(func(): observations.append([f.a.mood,f.service.chronicle.size(),f.service.completed_events().size()]))
	check(raise_rank(f).status == "completed" and f.a.mood == 23 and observations == [[23.0,1,1]], "Event offset is visible only with the complete event and chronicle")
	f.a.moodlets.remove("event_mood"); observations.clear()
	var social := Social.new(); root.add_child(social); social.clock = f.clock; social.rng = NegativeRng.new(); f.service.attach_social(social)
	f.service._load_catalogs(); var quarrel: Dictionary = f.service.catalog.definitions_for("social.resolved").filter(func(d):return d.id=="social.rough_conversation")[0]
	load_content(f,{"definitions":[quarrel]}); f.service.selector.set_chance("social.resolved",1)
	var result: RefCounted = social.resolve(f.a,f.b,SocialEvent.Context.MEAL)
	check(f.service.replay(result.confirmed_context().occurrence_id).status == "completed" and f.a.mood == 20 and f.a.moodlets.is_active("angry",635), "Real need-derived20 admits Quarrel; angry itself stays numerically inert")
	var size: int = f.service.chronicle.size(); f.a.hunger = 39
	check(f.a.mood == 30 and f.service.chronicle.size() == size, "Recovery changes mood without generating a story")
	f.clock.total_minutes += 120
	result = social.resolve(f.a,f.b,SocialEvent.Context.WORK)
	check(f.service.replay(result.confirmed_context().occurrence_id).status == "no_match", "Recovered mood blocks Quarrel after independent cooldown expires")
	social.free()
	for connection in f.a.moodlets.modifiers_changed.get_connections(): f.a.moodlets.modifiers_changed.disconnect(connection.callable)
	cleanup(f)

func actual_ui() -> void:
	var world = load("res://scenes/main_3d.tscn").instantiate(); root.add_child(world); world.game_time.set_process(false); world.game_logger.console_enabled = false; world.social_events.enabled = false
	var person: RefCounted = world.residents[0]; person.grammatical_gender = Trait.GrammaticalGender.FEMININE
	world.resident_selection.select(person); world.game_ui.info_panel.set_expanded(true); world.game_ui.info_panel.select_tab(&"bio")
	for type in N.values(): person.get_need(type).value = 91
	await process_frame
	var card: Control = world.resident_card_view()
	check(person.mood == 10 and card.mood_label.text.contains("10/100"), "Real card shows derived mood")
	for name in ["Голодная","Измотанная","Одинокая","Скучающая"]: check(card.moodlets_label.text.contains(name), "Real feminine state label: " + name)
	person.grammatical_gender = Trait.GrammaticalGender.MASCULINE
	check(card.moodlets_label.text.contains("Голодный") and not card.moodlets_label.text.contains("Голодная"), "Gender switch updates cached display titles")
	check(world.game_events.chronicle.size() == 0 and person.diary_entries.is_empty(), "Need states have no UI-created narrative output")
	world.free(); await process_frame
