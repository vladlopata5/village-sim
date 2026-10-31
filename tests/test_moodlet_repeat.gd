extends "res://tests/test_social_game_events.gd"
class ObservedRepeatStore extends Moodlets:
	var rebuilds := 0
	func _rebuild_growth_cache(minute: int) -> void:
		rebuilds += 1
		super._rebuild_growth_cache(minute)

func state(type: String, source: String, minute: int, duration: int = 120, factor: float = 0.5) -> Dictionary:
	return {"id":"instance/"+source,"type":type,"created_minute":minute,"expires_at_minute":minute+duration,"source_occurrence_id":source,"target":{"kind":"resident","id":source},"context":{"reason":source},"tags":["positive"],"modifiers":[{"channel":"need_growth_rate","need":"hunger","multiplier":factor}]}

func _run() -> void:
	all_types()
	cache_and_activation()
	ordinary_events()
	duplicate_slots()
	social_context()
	print("Moodlet repeat: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func all_types() -> void:
	for type in ["well_fed","angry","pride","envy","success_envy","admiration","work_satisfaction","future_kind"]:
		var store := ObservedRepeatStore.new("owner"); var notices: Array = []
		var callback := func(id: String):
			var committed: Dictionary = store.get_entry(id)
			notices.append(committed)
			check(store.size() == 1 and store.next_expiry_minute() == committed.expires_at_minute, "Notification sees one complete record and correct deadline")
			check(not store.add(committed), "Reentrant same-source addition is a no-op")
		store.changed.connect(callback)
		check(store.add(state(type,"first",100)), "Ordinary add accepts type: "+type)
		check(store.get_entry(type).id == type and store.get_entry("instance/first").is_empty(), "Canonical type ID is independent of occurrence instance ID")
		check(store.need_growth_factors(100) == {Need.Type.HUNGER:0.5} and store.rebuilds == 1, "Initial numerical contribution")
		var next := state(type,"second",110,90,0.8); next.tags = ["updated"]
		check(store.add(next) and store.size() == 1, "New event refreshes default add for every type")
		var record: Dictionary = store.get_entry(type)
		check(record.created_minute == 110 and record.expires_at_minute == 200 and record.target.id == "second" and record.context.reason == "second" and record.tags == ["updated"], "Whole record is replaced, with new duration, target, context and provenance")
		check(is_equal_approx(store.need_growth_factors(110)[Need.Type.HUNGER],0.8) and store.rebuilds == 2, "New factor replaces old factor rather than multiplying")
		var duplicate := next.duplicate(true); duplicate.id = "another-id"; duplicate.created_minute = 120; duplicate.expires_at_minute = 999
		check(not store.add_or_refresh(duplicate) and store.get_entry(type) == record and notices.size() == 2 and store.rebuilds == 2, "Same source with changed ID/time cannot refresh or invalidate cache")
		check(not store.add(state(type,"stale",109)) and store.get_entry(type) == record, "Older replacement cannot overwrite newer state")
		check(store.is_active(type,199) and not store.is_active(type,200), "Half-open refreshed lifetime")
		store.changed.disconnect(callback)
		check(store.expire(199) == 0 and store.expire(200) == 1 and store.size() == 0 and store.need_growth_factors(200).is_empty(), "Refreshed deadline expires exactly, without stacked remnants")
	var owner := Moodlets.new("owner"); var other := Moodlets.new("other")
	owner.add(state("a","one",10)); owner.add(state("b","one",10)); other.add(state("a","one",10))
	check(owner.size() == 2 and other.size() == 1 and owner.remove("a") and owner.get_entry("b").type == "b" and other.size() == 1, "Types and residents remain independent, even with shared source or supplied ID")

func cache_and_activation() -> void:
	var store := ObservedRepeatStore.new("owner")
	store.add(state("prototype","a",10))
	check(store.need_growth_factors(10) == {Need.Type.HUNGER:0.5}, "Initial active numerical record")
	store.add(state("prototype","future",20,20,0.75))
	check(store.size() == 1 and store.need_growth_factors(10).is_empty() and store.rebuilds == 2, "Future replacement is one inactive record; old active effect is replaced")
	for minute in range(11,20): check(store.need_growth_factors(minute).is_empty() and store.rebuilds == 2, "No scan before future activation")
	check(store.need_growth_factors(20) == {Need.Type.HUNGER:0.75} and store.rebuilds == 3, "Replaced record activates at exact boundary")
	check(store.need_growth_factors(39) == {Need.Type.HUNGER:0.75} and store.rebuilds == 3, "Cached through last active minute")
	check(store.expire(40) == 1 and store.need_growth_factors(40).is_empty() and store.rebuilds == 4, "Expiration removes effect before needs consumer")
	var indefinite := state("prototype","indefinite",40); indefinite.expires_at_minute = null
	store.add(indefinite); check(store.next_expiry_minute() == -1 and store.need_growth_factors(40) == {Need.Type.HUNGER:0.5}, "Indefinite replacement retains existing supported lifetime")
	store.add(state("prototype","timed",50,10))
	check(store.next_expiry_minute() == 60 and store.expire(1000) == 1 and store.need_growth_factors(1000).is_empty(), "Replacement of indefinite record and large time jump use existing cleanup")

func ordinary_events() -> void:
	var f := fixture(); var definition: Dictionary = content(f.service).definitions[0]
	definition.effects = [{"op":"moodlet.add","owner":{"role":"actor"},"definition":"pride","duration_minutes":120,"modifiers":[{"channel":"need_growth_rate","need":"hunger","multiplier":0.5}]}]
	load_content(f,{"definitions":[definition]})
	check(raise_rank(f).status == "completed", "First actual rank event")
	var first: Dictionary = f.service.last_occurrence(); var first_record: Dictionary = f.a.moodlets.get_entry("pride")
	f.clock.total_minutes += 10; definition.id = "test.another_source"
	load_content(f,{"definitions":[definition]})
	var observed: Array = []
	var callback := func(id: String):
		observed.append(id)
		check(f.a.diary_entries.size() == 2 and f.a.moodlets.size() == 1 and f.service.completed_events().size() == 2 and f.service.replay(f.service.last_occurrence().occurrence_id).status == "completed", "Refreshed store notice sees atomic diary/store/completion metadata")
	f.a.moodlets.changed.connect(callback)
	check(raise_rank(f).status == "completed" and observed == ["pride"], "Different JSON definition refreshes same type with one notification")
	f.a.moodlets.changed.disconnect(callback)
	var refreshed: Dictionary = f.a.moodlets.get_entry("pride")
	check(refreshed.source_occurrence_id != first_record.source_occurrence_id and refreshed.context._event.definition_id == definition.id and refreshed.expires_at_minute == f.clock.total_minutes+120 and f.a.moodlets.need_growth_factors(f.clock.total_minutes)[Need.Type.HUNGER] == 0.5, "New source owns refreshed state; numerical effect does not accumulate")
	var draws: int = f.service.executor.rng.draws; f.clock.total_minutes += 10
	f.a.skill_raised.emit(1,Skill.Type.GATHERING,0,1); f.service.executor.execute({},first,f.clock.total_minutes,f.a); f.service.executor.publish(first.occurrence_id)
	check(f.a.moodlets.get_entry("pride") == refreshed and f.service.executor.rng.draws == draws and f.a.diary_entries.size() == 2, "Old event replay after another source refreshes cannot overwrite, reroll or duplicate")
	f.a.moodlets.expire(refreshed.expires_at_minute); f.a.skill_raised.emit(2,Skill.Type.GATHERING,1,2)
	check(f.a.moodlets.size() == 0 and f.a.diary_entries.size() == 2 and f.service.executor.rng.draws == draws, "Replay after expiration cannot resurrect refreshed moodlet")
	cleanup(f)

func duplicate_slots() -> void:
	var f := fixture(); var definition: Dictionary = content(f.service).definitions[0]
	definition.effects = [{"op":"moodlet.add","owner":{"role":"actor"},"definition":"prototype","duration_minutes":120}]
	definition.effects.append(definition.effects[0].duplicate(true))
	load_content(f,{"definitions":[definition]})
	check(raise_rank(f).status == "prepare_failed" and f.a.diary_entries.is_empty() and f.a.moodlets.size() == 0 and f.service.completed_events().is_empty(), "Two selected writes to same resident/type reject atomically without choosing an implicit winner")
	definition.effects[1].definition = "another"
	load_content(f,{"definitions":[definition]})
	check(raise_rank(f).status == "completed" and f.a.moodlets.size() == 2 and f.a.diary_entries.size() == 1, "Same event can still award independent types")
	cleanup(f)

func social_context() -> void:
	for followup in ["social.success_envy","social.success_admiration"]:
		var f := fixture(); var definitions: Array = []
		# Use real full-catalog definitions without changing conditions or probabilities.
		f.service._load_catalogs()
		for trigger in ["skill.raised","social.resolved"]:
			definitions.append_array(f.service.catalog.definitions_for(trigger).filter(func(d): return d.id in ["personal.skill_progress",followup]))
		load_content(f,{"definitions":definitions})
		prime(f); prime(f,f.b,Skill.Type.CONSTRUCTION)
		check(f.b.moodlets.size() == 1 and f.b.moodlets.get_entry("pride").context.skill == "construction", "Latest actual skill event replaces old pride context")
		f.social.rng.rolls = [-100,0] if followup == "social.success_envy" else [100,0]
		f.social.resolve(f.a,f.b,SocialResult.Context.CONVERSATION)
		var selected: Dictionary = f.service.selector.run(f.service.last_occurrence())
		check(selected.selected.id == followup and selected.bindings.skill == "construction" and f.a.moodlets.find()[0].type == ("success_envy" if followup == "social.success_envy" else "admiration"), "Unchanged social JSON conditions and consequence use latest pride skill")
		cleanup(f)
