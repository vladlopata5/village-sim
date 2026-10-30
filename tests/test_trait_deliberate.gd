extends "res://tests/test_trait_hasty.gd"
func run() -> void:
	deliberate_rates()
	deliberate_needs()
	await construction(Trait.DELIBERATE,0.9)
	await all_recipes(Trait.DELIBERATE,0.9)
	await extraction(Trait.DELIBERATE,0.9)
	await field_and_plant(Trait.DELIBERATE,0.9)
	await gathering_and_transport(Trait.DELIBERATE,0.9)
	await ordinary_builder_transport(Trait.DELIBERATE)
	deliberate_generation()
	print("DELIBERATE: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
func deliberate_rates() -> void:
	var person:=Data.new("deliberate","Неторопливый",25);person.add_trait(Trait.DELIBERATE)
	for row in [[0,0.9],[1600,1.08],[10000,1.35]]:
		for skill in S.values():person._skill_xp[skill]=row[0]
		for operation in Ops.OPERATIONS.keys()+Ops.RECIPES.keys()+[&"gather_loading"]:
			if operation==&"delivery":continue
			var rate: float=Modifiers.work_rate(person,Ops.for_operation(operation))
			check(is_equal_approx(rate,row[1]),"Exact .9/1.08/1.35 across existing work types")
			for required in [10,30,60,120]:
				var progress:=0.0;var minutes:=ceili(float(required)/rate)
				for minute in minutes-1:progress=Work.advance(progress,rate,required)
				check(not Work.reached(progress,required),"Slow fractional work cannot finish before last minute")
				progress=Work.advance(progress,rate,required)
				check(progress==required,"Final minute clips without overflow at sub-unit rate")
		for operation in [&"loading",&"unloading"]:
			check(is_equal_approx(Modifiers.work_rate(person,Ops.for_operation(operation),false),1+0.5*sqrt(float(row[0])/10000)),"Logistics receives only original skill speed")
	var handling=preload("res://scripts/resource_handling.gd").new()
	check(handling.start(&"gather_loading",0,10,0.9) and not handling.advance(11),"Natural gather accepts .9 and remains incomplete after eleven ticks")
	check(handling.advance(12) and not handling.advance(12),"Twelfth gather tick completes once")
	check(not handling.start(&"loading",12,10,0.9) and not handling.start(&"unloading",12,10,0.9),"Ordinary handling still rejects a sub-unit supplied rate")
	check(not handling.start(&"gather_loading",12,10,0.89) and not handling.start(&"gather_loading",12,10,0),"Invalid gathering rates still rejected")
	check(handling.start(&"gather_loading",12,10,1.5*1.15),"HASTY maximum remains accepted")
	handling.cancel()
	var hasty:=Data.new("hasty-control","Hasty",25);hasty.add_trait(Trait.HASTY)
	check(is_equal_approx(Modifiers.work_rate(hasty,Ops.for_operation(&"construction")),1.15),"HASTY speed unchanged")
	check(Modifiers.fatigue_need_rate(hasty,4,true)==5.2,"HASTY fatigue unchanged")
	check(not person.add_trait(Trait.HASTY) and not hasty.add_trait(Trait.DELIBERATE),"Mutual exclusion both directions")
	for action in Modifiers.Action.values():check(Modifiers.action_utility(person,action,5000)==5000,"No utility effects")
	check(Modifiers.movement_speed(person,100)==100,"Walking unchanged")
func deliberate_needs() -> void:
	for activity in Dynamics.FATIGUE_RATES:
		for active in [false,true]:
			var person:=Data.new("needs","Needs",25);person.add_trait(Trait.DELIBERATE)
			var normal:=Data.new("normal","Normal",25)
			person.activity=activity;normal.activity=activity;person.current_sleep_quality=0.5;normal.current_sleep_quality=0.5
			for data in [person,normal]:
				for need in 4:data.get_need(need).value=50
			var dynamics:=Dynamics.new();dynamics._data=person;dynamics.active_work_provider=func():return active
			var baseline:=Dynamics.new();baseline._data=normal;baseline.active_work_provider=func():return active
			for minute in 60:dynamics._on_minute_changed(minute);baseline._on_minute_changed(minute)
			var rate: float=Dynamics.FATIGUE_RATES[activity]
			var expected: float=rate*(0.75 if active and activity in [Activity.WORKING,Activity.HAULING] else 1.0)*(0.5 if activity==Activity.SLEEPING else 1.0)
			check(is_equal_approx((person.fatigue-50)*60+dynamics._fractions[Need.FATIGUE],expected*60),"Only actual work growth gets .75; sleep/rest/movement retain base")
			for need in [Need.HUNGER,Need.SOCIAL,Need.LEISURE]:check(person.get_need(need).value==normal.get_need(need).value and dynamics._fractions[need]==baseline._fractions[need],"Other needs and fractional storage unchanged")
			dynamics.free();baseline.free()
	var long_person:=Data.new("long","Long",25);long_person.add_trait(Trait.DELIBERATE);long_person.activity=Activity.WORKING
	var long_run:=Dynamics.new();long_run._data=long_person;long_run.active_work_provider=func():return true
	for minute in 600:long_run._on_minute_changed(minute)
	check(long_person.fatigue==30 and long_run._fractions[Need.FATIGUE]==0,"Six hundred work minutes give exactly thirty fatigue points")
	check(Modifiers.fatigue_need_rate(long_person,5,true)==3.75 and Modifiers.fatigue_need_rate(long_person,4,true)==3 and Modifiers.fatigue_need_rate(long_person,0,true)==0 and Modifiers.fatigue_need_rate(long_person,-10,true)==-10,"Exact gather/working/zero/recovery rates")
	long_run.free()
func deliberate_generation() -> void:
	var catalog=preload("res://scripts/trait_type.gd");var generator=preload("res://scripts/resident_generator.gd").new(42);var repeat=preload("res://scripts/resident_generator.gd").new(42);var found:=0
	for index in 500:
		var person=generator.generate();var same=repeat.generate()
		check(catalog.compatible(person.traits) and person.traits==same.traits and person.trait_description()==same.trait_description(),"Generation and ordered descriptions reproducible")
		for type in person.traits+person.liked_traits+person.disliked_traits:check(type!=Trait.CARING,"CARING excluded from all random issue")
		if person.has_trait(Trait.DELIBERATE):found+=1;check(not person.add_trait(Trait.HASTY),"Generated DELIBERATE rejects HASTY")
	check(found>0 and catalog.GENERATION_POOL.size()==12 and catalog.description([Trait.DELIBERATE,Trait.PRUDENT])=="Неторопливый прагматик" and catalog.description([Trait.DELIBERATE,Trait.CALM],catalog.GrammaticalGender.FEMININE)=="Неторопливая флегматичка","DELIBERATE generated with both grammatical forms")
