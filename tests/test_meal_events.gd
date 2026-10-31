extends "res://tests/test_trait_glutton.gd"
const Data = preload("res://scripts/resident_data.gd")
const Service = preload("res://scripts/game_event_service.gd")
const PlayerRegistry = preload("res://scripts/player_control.gd")
const Clock = preload("res://scripts/game_time.gd")
class MealProducer extends Node:
	signal meal_completed(snapshot: Dictionary)
	func complete(snapshot: Dictionary) -> void: meal_completed.emit(snapshot)
class RejectingMealDiary extends Data:
	func can_add_diary_entry(_entry: RefCounted) -> bool: return false

func run() -> void:
	real_outcomes()
	eligibility_and_interruptions()
	refresh_and_duplicates()
	logger_reentrancy()
	atomic_chat()
	statistics()
	print("Meal events: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func real_outcomes() -> void:
	for rolls in [[0.1,0.1],[0.1,0.9],[0.9,0.1],[0.9,0.9],[0.8,0.5]]:
		var world := fixture(); var actor: Node = world.resident_runtimes[0]
		var rng := MealRng.new(); rng.values = rolls
		world.game_events.executor.rng = rng
		var selection_rng := MealRng.new(); world.game_events.selector.rng = selection_rng
		var snapshots: Array = []; var messages: Array = []
		actor.needs.meal_completed.connect(func(snapshot): snapshots.append(snapshot.duplicate(true)))
		world.game_events.resident_message.connect(func(id, resident_name, text): messages.append([id,resident_name,text]))
		var intent := begin(world,80)
		world.game_time.advance(29)
		check(snapshots.is_empty() and actor.data.diary_entries.is_empty() and rng.draws == 0, "No event or consequence RNG before successful completion")
		world.game_time.advance(1)
		var fed: bool = rolls[0] < 0.8; var said: bool = rolls[1] < 0.5
		check(snapshots.size() == 1 and snapshots[0].resident_id == actor.data.id and snapshots[0].hunger == 20 and snapshots[0].minute == 450 and not snapshots[0].meal_id.is_empty(), "Real meal publishes unique immutable completion context with final hunger")
		var context: Dictionary = world.game_events.last_occurrence()
		check(context.trigger == "meal.completed" and context.actor.id == actor.data.id and context.payload.meal_id == snapshots[0].meal_id, "The ordinary event adapter receives real completed meal identity")
		check(actor.data.diary_entries.size() == 1 and actor.data.diary_entries[0].text == actor.data.resident_name + " вкусно поел." and world.game_events.completed_events().size() == 1, "Mandatory ordinary diary for every combination, including no consequences")
		check(actor.data.moodlets.is_active("well_fed",450) == fed and messages.size() == int(said) and rng.draws == 2, "Two independent rolls: " + str(rolls))
		if said:
			check(messages[0] == [actor.data.id,actor.data.resident_name,"я вкусно поел"], "Exact resident sender and message, not a system notification")
			check(world.social_feed.messages.back().text == "%s: «я вкусно поел»." % actor.data.resident_name, "Message reaches existing game chat with the concrete speaker")
		if fed:
			var entry: Dictionary = actor.data.moodlets.get_entry("well_fed")
			check(entry.expires_at_minute == 570 and entry.modifiers == [{"channel":"need_growth_rate","need":"hunger","multiplier":0.5}], "Event uses unchanged120-minute numerical hunger effect")
		var count: int = world.social_feed.messages.size()
		actor.needs._finish(); actor.needs.eat_outcome.emit(intent,&"completed",world.kitchen_data.id)
		actor.needs.meal_completed.emit(snapshots[0]); world.game_events.executor.publish(context.occurrence_id)
		check(rng.draws == 2 and selection_rng.draws == 2 and actor.data.diary_entries.size() == 1 and world.social_feed.messages.size() == count and world.game_events.replay(context.occurrence_id).duplicate, "Repeated callbacks, trigger and publish cannot repeat rolls, diary, chat or moodlet")
		world.free()

func eligibility_and_interruptions() -> void:
	for glutton in [false,true]:
		for hunger in [60,80,81]:
			var world := fixture(glutton); var actor: Node = world.resident_runtimes[0]
			var snapshots: Array = []
			actor.needs.meal_completed.connect(func(snapshot): snapshots.append(snapshot))
			begin(world,hunger); world.game_time.advance(30)
			var eligible: bool = glutton and hunger <= 80
			check(snapshots.size() == 1 and snapshots[0].hunger == hunger-60, "Every successful meal emits, regardless of GLUTTON or threshold")
			check(actor.data.diary_entries.size() == int(eligible) and actor.data.moodlets.size() == int(eligible), "JSON-only GLUTTON and final HUNGER0/20/21 conditions")
			world.free()
	for eating in [false,true]:
		var world := fixture(); var actor: Node = world.resident_runtimes[0]; var snapshots: Array = []
		actor.needs.meal_completed.connect(func(snapshot): snapshots.append(snapshot))
		actor.data.hunger = 60; check(actor.needs.try_eat(8000), "Cancelable meal begins")
		if eating: actor.view._process(100); world.game_time.advance(20)
		actor.intents.abort_current(actor.intents.current_intent); world.game_time.advance(30)
		check(snapshots.is_empty() and actor.data.diary_entries.is_empty() and actor.data.moodlets.size() == 0 and world.game_events.executor.rng.draws == 0, "Interrupted trip or paid meal never publishes completion or event")
		world.free()
	var disabled := fixture(); var resident: Node = disabled.resident_runtimes[0]
	disabled.game_events.enabled = false
	begin(disabled,80); disabled.game_time.advance(30)
	check(resident.data.moodlets.size() == 0 and resident.data.diary_entries.is_empty(), "There is no parallel direct moodlet award when the event service is disabled")
	disabled.free()

func refresh_and_duplicates() -> void:
	var world := fixture(); var actor: Node = world.resident_runtimes[0]
	var snapshots: Array = []; actor.needs.meal_completed.connect(func(snapshot): snapshots.append(snapshot))
	begin(world,80); world.game_time.advance(30)
	var original: Dictionary = actor.data.moodlets.get_entry("well_fed")
	var failing := MealRng.new(); failing.values = [0.9,0.1]; world.game_events.executor.rng = failing
	begin(world,80); world.game_time.advance(30)
	check(actor.data.moodlets.get_entry("well_fed") == original and actor.data.diary_entries.size() == 2, "Failed80% roll leaves existing deadline unchanged while event and chat can succeed")
	world.game_events.executor.rng = MealRng.new()
	var callbacks: Array = []
	var on_change := func(id: String):
		callbacks.append(id)
		var token: String = world.game_events.last_occurrence().occurrence_id
		check(world.game_events.replay(token).status == "completed" and actor.needs._active_intent == null, "Callbacks see committed metadata and released meal ownership")
		actor.needs._finish(); actor.needs.meal_completed.emit(snapshots[1]); world.game_events.executor.publish(token)
	actor.data.moodlets.changed.connect(on_change)
	begin(world,80); world.game_time.advance(30)
	actor.data.moodlets.changed.disconnect(on_change)
	var updated: Dictionary = actor.data.moodlets.get_entry("well_fed")
	check(updated.expires_at_minute == 630 and updated.source_occurrence_id != original.source_occurrence_id and actor.data.moodlets.size() == 1 and callbacks == ["well_fed"], "New successful event refreshes one singleton without reentrant duplicates")
	check(snapshots.size() == 4 and snapshots[0].meal_id != snapshots[1].meal_id and snapshots[1].meal_id != snapshots[3].meal_id, "Distinct completed meals have distinct identity, replay keeps old identity")
	check(actor.data.moodlets.need_growth_factors(510)[0] == 0.5, "Refresh never compounds numeric factor")
	actor.need_dynamics._fractions[0] = 0; world.game_time.advance(60)
	check(actor.data.hunger == 22, "Live event-issued moodlet halves awake hunger growth")
	world.game_time.advance(59)
	var before: float = actor.data.hunger*60+actor.need_dynamics._fractions[0]
	world.game_time.advance(1)
	check(actor.data.moodlets.size() == 0 and actor.data.hunger*60+actor.need_dynamics._fractions[0]-before == 4, "Exact120-minute expiry automatically restores ordinary hunger before needs update")
	world.free()

func isolated(person: RefCounted = null) -> Dictionary:
	if person == null: person = Data.new("meal_actor","Тест",25)
	person.set_traits([Trait.GLUTTON])
	var control := PlayerRegistry.new(); control.register_resident(person)
	var clock := Clock.new(); root.add_child(clock); clock.set_process(false); clock.total_minutes = 500
	var service := Service.new(); root.add_child(service); service.setup(control,clock,func(_data): return true)
	service.selector.rng.seed = 123
	service.executor.rng = MealRng.new()
	var producer := MealProducer.new(); root.add_child(producer); service.observe_meals(producer,person); service.observe_meals(producer,person)
	var messages: Array = []; service.resident_message.connect(func(id,resident_name,text): messages.append([id,resident_name,text]))
	return {"actor":person,"control":control,"clock":clock,"service":service,"producer":producer,"messages":messages}

func logger_reentrancy() -> void:
	var world := fixture(); var actor: Node = world.resident_runtimes[0]
	var calls := [0]; var snapshots: Array = []
	actor.needs.meal_completed.connect(func(snapshot): snapshots.append(snapshot))
	var callback := func(line: String, _level):
		if not line.contains("закончил есть"): return
		calls[0] += 1
		check(actor.needs._active_intent == null and actor.needs._meal_selection == null and not actor.needs._meal_active, "Even logger callbacks see fully released meal ownership")
		actor.needs._finish()
	world.game_logger.line_logged.connect(callback)
	begin(world,80); world.game_time.advance(30)
	check(calls[0] == 1 and snapshots.size() == 1 and actor.data.diary_entries.size() == 1 and actor.data.moodlets.size() == 1, "Nested finish from logger cannot recursively finish or duplicate a meal event")
	world.game_logger.line_logged.disconnect(callback)
	world.free()

func emit_meal(f: Dictionary, token: String) -> Dictionary:
	f.producer.complete({"resident_id":f.actor.id,"meal_id":token,"minute":f.clock.total_minutes,"hunger":20})
	return f.service.replay(f.service.last_occurrence().occurrence_id)

func dispose(f: Dictionary) -> void:
	f.service.free(); f.producer.free(); f.clock.free()

func atomic_chat() -> void:
	var f := isolated(RejectingMealDiary.new("reject","Отказ",25))
	check(emit_meal(f,"rejected-diary").status == "diary_failed" and f.actor.moodlets.size() == 0 and f.messages.is_empty(), "Diary rejection cannot leave a moodlet or visible chat without committed event")
	dispose(f)
	f = isolated()
	var definitions: Array = f.service.catalog.definitions_for("meal.completed")
	definitions[0].effects[1].text = " "
	check(f.service.catalog.load_data({"definitions":definitions},f.service.facts), "Structurally valid test with empty selected chat text")
	check(emit_meal(f,"invalid-chat").status == "text_failed" and f.actor.diary_entries.is_empty() and f.actor.moodlets.size() == 0 and f.messages.is_empty(), "Invalid chat aborts preparation before any diary or moodlet writes")
	dispose(f)
	f = isolated()
	var count := [0]
	var callback := func(_id, _name, _text):
		count[0] += 1
		emit_meal(f,"nested"); f.service.executor.publish(f.service.last_occurrence().occurrence_id)
	f.service.resident_message.connect(callback)
	check(emit_meal(f,"nested").status == "completed" and count[0] == 1 and f.messages.size() == 1 and f.actor.diary_entries.size() == 1, "Chat callback cannot republish or reroll committed event")
	f.service.resident_message.disconnect(callback)
	dispose(f)
	f = isolated()
	f.control.unregister_resident(f.actor.id)
	check(emit_meal(f,"inactive").status == "inactive_source" and f.actor.diary_entries.is_empty() and f.actor.moodlets.size() == 0 and f.messages.is_empty(), "Stale resident completion cannot issue consequences or chat")
	dispose(f)

func statistics() -> void:
	var totals := [0,0,0,0]
	for seed_value in [17,42,916,2026]:
		var f := isolated(); var rng := RandomNumberGenerator.new(); rng.seed = seed_value; f.service.executor.rng = rng
		var counts := [0,0,0,0]
		for i in 2500:
			f.clock.total_minutes = 500+i
			var result := emit_meal(f,"stat/%d/%d" % [seed_value,i])
			var fed := false; var said := false
			for effect in result.get("effects",[]):
				if effect.op == "moodlet.add": fed = true
				if effect.op == "chat.say": said = true
			var index := (0 if fed else 2) + (0 if said else 1)
			counts[index] += 1
			if result.status != "completed": check(false,"Seeded statistical event must commit")
		check(f.actor.diary_entries.size() == 2500 and f.service.completed_events().size() == 2500 and f.messages.size() == counts[0]+counts[2] and f.actor.moodlets.size() == 1, "Statistics preserve diary/chat/singleton accounting")
		for i in 4: totals[i] += counts[i]
		print("Meal outcomes seed=",seed_value," N=2500 both/fed/chat/neither=",counts)
		dispose(f)
	for i in 4:
		check(absf(totals[i]/10000.0-[0.4,0.4,0.1,0.1][i]) < 0.02, "Fixed-seed joint probability near agreed distribution")
	check(absf((totals[0]+totals[1])/10000.0-0.8)<0.02 and absf((totals[0]+totals[2])/10000.0-0.5)<0.02, "Marginals near80% and50%")
	print("Meal outcomes aggregate N=10000 both/fed/chat/neither=",totals)
