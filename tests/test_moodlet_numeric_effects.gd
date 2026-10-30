extends "res://tests/test_trait_glutton.gd"
const Data = preload("res://scripts/resident_data.gd")
const Dynamics = preload("res://scripts/need_dynamics.gd")
const Modifiers = preload("res://scripts/resident_modifiers.gd")
const Need = preload("res://scripts/need_type.gd").Type
const Activity = preload("res://scripts/resident_activity.gd").Type
const Clock = preload("res://scripts/game_time.gd")
class ObservedNumericStore extends Store:
	var rebuilds := 0
	func _rebuild_growth_cache(minute: int) -> void:
		rebuilds+=1
		super._rebuild_growth_cache(minute)
class FixedEventRng extends RefCounted:
	func randf() -> float: return 0.0
func numeric_record(id: String, minute: int, duration: int = 120, need: String = "hunger", multiplier: float = 0.5) -> Dictionary:
	return {"id":id,"type":id,"created_minute":minute,"expires_at_minute":minute+duration,"source_occurrence_id":"source/%s/%d"%[id,minute],"modifiers":[{"channel":"need_growth_rate","need":need,"multiplier":multiplier}]}
func run() -> void:
	all_rates()
	cache_and_format()
	await real_meals()
	await clock_boundaries()
	await event_descriptors()
	await future_activation()
	large_rates()
	callback_snapshot()
	print("Moodlet numeric effects: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func all_rates() -> void:
	for trait_type in [-1]+Trait.values():
		for activity in Dynamics.FATIGUE_RATES:
			var baseline:=Data.new("baseline","Baseline",25);var fed:=Data.new("fed","Fed",25)
			for data in [baseline,fed]:
				if trait_type>=0:data.add_trait(trait_type)
				data.activity=activity;data.hunger=80 if activity==Activity.EATING else 20
				for need in [Need.FATIGUE,Need.SOCIAL,Need.LEISURE]:data.get_need(need).value=50
			fed.moodlets.add(numeric_record("well_fed",0))
			var normal:=Dynamics.new();var changed:=Dynamics.new();normal._data=baseline;changed._data=fed
			for dynamics in [normal,changed]:
				dynamics.ordinary_idle_provider=func():return activity==Activity.IDLE
				dynamics.active_work_provider=func():return true
				dynamics.caring_partner_provider=func():return true
			for minute in 60:normal._on_minute_changed(minute);changed._on_minute_changed(minute)
			if activity==Activity.EATING:check(fed.hunger==baseline.hunger and changed._fractions[Need.HUNGER]==normal._fractions[Need.HUNGER],"Meal recovery unchanged for every trait")
			else:
				var base_units: float=(baseline.hunger-20)*60+normal._fractions[Need.HUNGER]
				var fed_units: float=(fed.hunger-20)*60+changed._fractions[Need.HUNGER]
				check(is_equal_approx(fed_units,base_units*0.5),"Every positive hunger rate halved once, including fractional sleep growth")
			for need in [Need.FATIGUE,Need.SOCIAL,Need.LEISURE]:check(fed.get_need(need).value==baseline.get_need(need).value and changed._fractions[need]==normal._fractions[need],"Other needs/trait modifiers/fractions unchanged")
			check(fed.mood==baseline.mood and fed._skill_xp==baseline._skill_xp,"No mood or skill effect")
			normal.free();changed.free()
func cache_and_format() -> void:
	var store:=ObservedNumericStore.new("cache")
	check(store.add_or_refresh(numeric_record("well_fed",0)),"Numeric descriptor accepted by existing store API")
	check(store.need_growth_factors(0)=={Need.HUNGER:0.5} and store.rebuilds==1,"First read calculates one derived snapshot")
	for minute in range(1,100):check(store.need_growth_factors(minute)=={Need.HUNGER:0.5} and store.rebuilds==1,"Unchanged minute reads do not traverse moodlets")
	var copy: Dictionary=store.need_growth_factors(99);copy[Need.HUNGER]=9
	check(store.need_growth_factors(99)[Need.HUNGER]==0.5,"Consumer cannot mutate derived cache")
	check(store.add_or_refresh(numeric_record("well_fed",100)) and store.size()==1,"Repeat refresh keeps one record")
	check(store.need_growth_factors(100)[Need.HUNGER]==0.5 and store.rebuilds==2,"Refresh recomputes from data, never compounds old .5 into .25")
	check(not store.add_or_refresh(numeric_record("well_fed",100)) and store.need_growth_factors(100)[Need.HUNGER]==0.5 and store.rebuilds==2,"Rejected repeat does not invalidate or recalculate")
	check(store.expire(220)==1 and store.need_growth_factors(220).is_empty() and store.rebuilds==3,"Expiration invalidates before next numeric read")
	store.add(numeric_record("prototype",220,120,"fatigue",0.75))
	check(store.need_growth_factors(220)=={Need.FATIGUE:0.75} and Modifiers.need_growth_rate(Need.FATIGUE,4,store.need_growth_factors(220))==3,"Another type/need uses same numerical channel without special cases")
	store.remove("prototype");check(store.need_growth_factors(220).is_empty(),"Explicit removal invalidates contribution")
	var opaque:=numeric_record("legacy",220);opaque.modifiers=[{"channel":"future_channel","value":-3},{"channel":"mood","value":3}]
	check(store.add(opaque) and store.need_growth_factors(220).is_empty(),"Previously inert channels stay inert and retain their data")
	for change in [{"need":"missing"},{"multiplier":-1},{"multiplier":true},{"multiplier":"0.5"},{"extra":1}]:
		var bad:=numeric_record("bad",220);bad.modifiers[0].merge(change,true)
		check(not store.add(bad),"Malformed recognized descriptor rejected atomically")
	store.add(numeric_record("one",220,120,"hunger",0.5));store.add(numeric_record("two",220,120,"hunger",0.8))
	check(is_equal_approx(store.need_growth_factors(220)[Need.HUNGER],0.4),"Distinct explicit multipliers compose by existing multiplication rule")
	check(Modifiers.need_growth_rate(Need.HUNGER,-120,store.need_growth_factors(220))==-120 and Modifiers.need_growth_rate(Need.HUNGER,0,store.need_growth_factors(220))==0,"Recovery and zero rates never get growth factor")
func real_meals() -> void:
	var world:=fixture();var actor: Node=world.resident_runtimes[0]
	begin(world,80);world.game_time.advance(30)
	check(actor.data.hunger==20 and actor.data.moodlets.get_entry("well_fed").modifiers==[{"channel":"need_growth_rate","need":"hunger","multiplier":0.5}],"Real successful GLUTTON meal issues120-minute effect data")
	actor.need_dynamics._fractions[Need.HUNGER]=0;world.game_time.advance(60)
	check(actor.data.hunger==22 and actor.need_dynamics._fractions[Need.HUNGER]==0,"Sixty real awake minutes add2 hunger instead of4")
	begin(world,80);world.game_time.advance(30)
	check(actor.data.hunger==20 and actor.data.moodlets.size()==1 and actor.data.moodlets.need_growth_factors(world.game_time.total_minutes)[Need.HUNGER]==0.5,"Eating rate and duration unchanged while previous effect is active; repeat refresh stays half")
	var expiry: int=actor.data.moodlets.get_entry("well_fed").expires_at_minute
	world.game_time.advance(expiry-world.game_time.total_minutes-1)
	var before: float=actor.data.hunger*60+actor.need_dynamics._fractions[Need.HUNGER]
	world.game_time.advance(1)
	check(actor.data.moodlets.size()==0 and actor.data.hunger*60+actor.need_dynamics._fractions[Need.HUNGER]-before==4,"Exact expiry tick uses ordinary4 units after runtime cleanup")
	world.free();await process_frame
func clock_boundaries() -> void:
	for speed in [1,2,4,10,20]:
		var clock:=Clock.new();root.add_child(clock);clock.set_process(false);clock.total_minutes=0;clock.set_speed(speed)
		var person:=Data.new("clock","Clock",25);var store:=ObservedNumericStore.new(person.id);person.moodlets=store
		store.add(numeric_record("well_fed",0));clock.minute_changed.connect(store.expire)
		var dynamics:=Dynamics.new();root.add_child(dynamics);dynamics.setup(clock,person)
		clock.advance(60.0/speed)
		check(person.hunger==2 and store.rebuilds==1,"One sixty-minute skip and each acceleration preserve half hunger without scans")
		paused=true;clock.advance(100);paused=false
		check(clock.total_minutes==60 and person.hunger==2 and store.rebuilds==1,"Pause changes neither needs nor derived cache")
		clock.advance(60.0/speed)
		check(clock.total_minutes==120 and person.hunger==4 and dynamics._fractions[Need.HUNGER]==2 and store.rebuilds==2,"Skip crossing deadline recalculates once before exact normal-speed tick")
		dynamics.free();clock.free();await process_frame
func callback_snapshot() -> void:
	var person:=Data.new("nested","Nested",25);person.activity=Activity.WORKING;person.hunger=10
	var dynamics:=Dynamics.new();dynamics._data=person;dynamics._fractions[Need.HUNGER]=56
	var callback:=func():person.moodlets.add(numeric_record("callback",1,120,"fatigue",0.0))
	person.get_need(Need.HUNGER).changed.connect(callback)
	dynamics._on_minute_changed(1);person.get_need(Need.HUNGER).changed.disconnect(callback)
	check(dynamics._fractions[Need.FATIGUE]==4,"Callback during hunger update cannot change later needs in same minute snapshot")
	dynamics._on_minute_changed(2)
	check(dynamics._fractions[Need.FATIGUE]==4,"Next minute sees newly committed generic factor")
	dynamics.free()
func event_descriptors() -> void:
	var world=preload("res://tests/residents_ui_fixture.gd").create(self)
	var actor: Node=world.resident_runtimes[0];var service: Node=world.game_events
	var definition: Dictionary=service.catalog.definitions_for("skill.raised").filter(func(row):return row.id=="personal.skill_progress")[0]
	definition.id="test.numeric_need"
	definition.effects=[{"op":"moodlet.add","owner":{"role":"actor"},"definition":"prototype","duration_minutes":120,"modifiers":[{"channel":"need_growth_rate","need":"hunger","multiplier":0.5}]}]
	check(service.catalog.load_data({"definitions":[definition]},service.facts),"Existing event JSON accepts explicit numerical descriptor without format changes")
	service.selector.rng=FixedEventRng.new();service.executor.rng=FixedEventRng.new()
	var skill=preload("res://scripts/skill_type.gd").Type.GATHERING
	actor.data.add_skill_xp(skill,400)
	check(service.replay(service.last_occurrence().occurrence_id).status=="completed" and actor.data.moodlets.need_growth_factors(world.game_time.total_minutes)=={Need.HUNGER:0.5},"Actual event commits generic numeric moodlet through existing executor")
	var diary_count: int=actor.data.diary_entries.size();definition.effects[0].modifiers[0].multiplier=-1
	check(service.catalog.load_data({"definitions":[definition]},service.facts),"Invalid numeric value reaches store validation")
	actor.data.add_skill_xp(skill,600)
	check(service.replay(service.last_occurrence().occurrence_id).status=="prepare_failed" and actor.data.diary_entries.size()==diary_count and actor.data.moodlets.size()==1,"Invalid descriptor rejects whole event without partial diary or effect")
	world.free();await process_frame
func future_activation() -> void:
	var clock:=Clock.new();root.add_child(clock);clock.set_process(false);clock.total_minutes=0
	var person:=Data.new("future","Future",25);var store:=ObservedNumericStore.new(person.id);person.moodlets=store
	store.add(numeric_record("future",10,10));clock.minute_changed.connect(store.expire)
	var dynamics:=Dynamics.new();root.add_child(dynamics);dynamics.setup(clock,person)
	check(store.need_growth_factors(0).is_empty() and store.rebuilds==1,"Future numeric state is initially inactive")
	clock.advance(9);check(store.rebuilds==1 and dynamics._fractions[Need.HUNGER]==36,"No scan before future activation boundary")
	clock.advance(1);check(store.rebuilds==2 and dynamics._fractions[Need.HUNGER]==38,"Creation boundary applies half rate before that minute's need update")
	clock.advance(9);check(store.rebuilds==2 and dynamics._fractions[Need.HUNGER]==56,"Active interval reuses cache")
	clock.advance(1);check(store.rebuilds==3 and person.hunger==1 and dynamics._fractions[Need.HUNGER]==0 and store.size()==0,"Expiry boundary returns ordinary rate with exactly preserved fractional progress")
	store.add(numeric_record("earlier",110,10));store.add(numeric_record("later",130,10))
	check(store.need_growth_factors(100).is_empty() and store.need_growth_factors(135)=={Need.HUNGER:0.5} and store.need_growth_factors(150).is_empty(),"A single late read crosses several activation/expiration intervals without stale effects")
	dynamics.free();clock.free();await process_frame
func large_rates() -> void:
	for need in ["hunger","fatigue","social","leisure"]:
		var person:=Data.new("large","Large",25);person.activity=Activity.WORKING
		person.moodlets.add(numeric_record("explicit_large",0,120,need,1e200))
		var dynamics:=Dynamics.new();dynamics._data=person;dynamics._on_minute_changed(0)
		check(person.get_need(Need[need.to_upper()]).value==100,"Finite large growth saturates existing0..100 bound without integer overflow")
		dynamics.free()
