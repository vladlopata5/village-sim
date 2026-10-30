extends "res://tests/test_social_partner_preferences.gd"
const Dynamics = preload("res://scripts/need_dynamics.gd")
const Need = preload("res://scripts/need_type.gd").Type
const F = preload("res://tests/residents_ui_fixture.gd")
func run() -> void:
	weights()
	recovery()
	await actual_conversations()
	await venue_conversation()
	generation()
	print("CARING_SELECTION ",JSON.stringify(simulations))
	print("CARING: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
func weights() -> void:
	var person:=Data.new("pure","Pure",25)
	for trait_type in [-1,Trait.SOCIABLE,Trait.INTROVERTED]:
		configure(person,trait_type)
		for deficit in [0,50,100]:near(Modifiers.social_partner_need_multiplier(person,deficit),1.0,"Unchanged weights without CARING")
		person.add_trait(Trait.CARING)
		for deficit in [0,50,100]:near(Modifiers.social_partner_need_multiplier(person,deficit),1.0+deficit/100.0,"Exact CARING anchors, independent of own social trait")
		var container:=fixture(3);var world: Node=container.get_child(0);var actor: Node=world.get_runtime("chooser")
		actor.data.set_traits(person.traits)
		var expected: Array[float]=[]
		for index in 3:
			world.get_runtime("target_%d"%(index+1)).data.get_need(Need.SOCIAL).value=index*50
			expected.append((1.0+index*0.5)*(1.3 if trait_type==Trait.SOCIABLE else 1.0))
		configure(actor.data,trait_type)
		var baseline: Array[float]=[1.0,1.0,1.0]
		if trait_type==Trait.SOCIABLE:baseline=[1.3,1.3,1.3]
		sample(world,actor,"baseline_individual_%s"%trait_type,baseline)
		actor.data.add_trait(Trait.CARING)
		sample(world,actor,"caring_individual_%s"%trait_type,expected)
		var direct: Dictionary=world.target_option(actor.data.id,"target_1")
		world.get_runtime("target_1").data.get_need(Need.SOCIAL).value=100
		check(world.target_option(actor.data.id,"target_1")==direct,"Deficit preference never changes exact player target")
		world.get_runtime("target_1").data.activity=Activity.WORKING
		check(world.options_for(actor.data.id).size()==2,"High deficit never bypasses busy candidate filter")
		container.free()
		container=fixture(6);world=container.get_child(0);actor=world.get_runtime("chooser");actor.data.set_traits(person.traits)
		for pair in [[1,2],[3,4]]:
			var group=world.create_group(Vector2(100,0))
			for index in pair:
				var member: Node=world.get_runtime("target_%d"%index);member.data.activity=Activity.TALKING;group.add_participant(member.data.id)
				actor.data.set_opinion(StringName(member.data.id),100 if index%2==1 else -100)
				member.data.get_need(Need.SOCIAL).value=100 if index in [2,3] else 0
		world.get_runtime("target_5").data.get_need(Need.SOCIAL).value=50
		world.get_runtime("target_6").data.activity=Activity.MOVING
		var group_weights: Array[float]=[1.35,1.65,1.5]
		if trait_type==Trait.SOCIABLE:group_weights=[1.65,1.65,1.95]
		elif trait_type==Trait.INTROVERTED:group_weights=[1.08,1.62,1.5]
		configure(actor.data,trait_type)
		var baseline_groups: Array[float]=[1.0,1.0,1.0]
		if trait_type==Trait.SOCIABLE:baseline_groups=[1.1,1.1,1.3]
		elif trait_type==Trait.INTROVERTED:baseline_groups=[0.9,0.9,1.0]
		sample(world,actor,"baseline_company_%s"%trait_type,baseline_groups)
		actor.data.add_trait(Trait.CARING)
		sample(world,actor,"caring_company_%s"%trait_type,group_weights)
		world.get_runtime("target_2").data.activity=Activity.MOVING
		near(world.options_for(actor.data.id)[0].option_weight/(500.0/1.1),Modifiers.social_partner_multiplier(actor.data,100),"Inactive member removed from both mean and company size")
		world.position_provider=func(id):return Vector2.ZERO if id=="chooser" else Vector2(1000,0)
		near(world.options_for(actor.data.id)[0].option_weight,250.0*Modifiers.social_partner_multiplier(actor.data,100),"Distance penalty preserved")
		container.free()
func recovery() -> void:
	for trait_type in [-1,Trait.SOCIABLE,Trait.INTROVERTED]:
		for own_caring in [false,true]:
			for activity in Dynamics.SOCIAL_RATES:
				for partner in [false,true]:
					var person:=Data.new("rate","Rate",25);configure(person,trait_type)
					if own_caring:person.add_trait(Trait.CARING)
					person.activity=activity
					var neutral:=Data.new("control","Control",25);neutral.set_traits(person.traits);neutral.activity=activity
					for data in [person,neutral]:
						for need in 4:data.get_need(need).value=50
					var dynamics:=Dynamics.new();dynamics._data=person;dynamics.caring_partner_provider=func():return partner
					var baseline:=Dynamics.new();baseline._data=neutral
					for minute in 4:dynamics._on_minute_changed(minute);baseline._on_minute_changed(minute)
					if activity==Activity.TALKING:
						var restored: float=12*(0.75 if trait_type==Trait.SOCIABLE else 1.25 if trait_type==Trait.INTROVERTED else 1.0)*(1.25 if partner else 1.0)
						near(50-person.get_need(Need.SOCIAL).value-float(dynamics._fractions[Need.SOCIAL])/300000,restored,"Own recovery times one partner multiplier, with exact fractions")
					else:check(person.get_need(Need.SOCIAL).value==neutral.get_need(Need.SOCIAL).value and dynamics._fractions[Need.SOCIAL]==baseline._fractions[Need.SOCIAL],"No partner bonus outside TALKING, including growth")
					for need in [Need.HUNGER,Need.FATIGUE,Need.LEISURE]:check(person.get_need(need).value==neutral.get_need(need).value and dynamics._fractions[need]==baseline._fractions[need],"All other needs and fractional changes unchanged")
					dynamics.free();baseline.free()
	var data:=Data.new("zero","Zero",25);data.add_trait(Trait.CARING)
	check(Modifiers.social_need_rate(data,0,true)==0 and Modifiers.social_need_rate(data,60,true)==60,"Zero and positive rates never receive recovery bonus")
func reset_social(actors: Array) -> void:
	for actor in actors:actor.data.get_need(Need.SOCIAL).value=80;actor.need_dynamics._fractions[Need.SOCIAL]=0
func actual_conversations() -> void:
	var world=F.create(self);var actors: Array=world.resident_runtimes
	for actor in actors:actor.data.set_traits([])
	actors[0].data.add_trait(Trait.CARING)
	check(actors[0].social.try_social_at(actors[1].data.id,5600),"CARING starts original targeted social action")
	F.walk(world,actors[0]);reset_social(actors)
	check(not actors[0].social.has_caring_partner() and actors[1].social.has_caring_partner(),"Only the other participant receives CARING bonus")
	world.game_time.debug_skip_minutes(4)
	check(actors[0].data.get_need(Need.SOCIAL).value==68 and actors[1].data.get_need(Need.SOCIAL).value==65,"Actual clock restores12 to CARING and15 to its partner")
	actors[1].data.add_trait(Trait.CARING)
	for index in [2,3]:
		check(actors[index].social.try_social_at(actors[0].data.id,5600),"Existing group admits ordinary joining action")
		F.walk(world,actors[index])
	actors[3].data.add_trait(Trait.SOCIABLE);reset_social(actors)
	world.game_time.debug_skip_minutes(4)
	for index in [0,1,2]:check(actors[index].data.get_need(Need.SOCIAL).value==65,"Two CARING give exactly one bonus, also to one another")
	near(80-actors[3].data.get_need(Need.SOCIAL).value-float(actors[3].need_dynamics._fractions[Need.SOCIAL])/300000,11.25,"SOCIABLE own .75 and one caring1.25 compose once")
	actors[0].social.cancel_social();actors[1].social.cancel_social();reset_social(actors)
	check(not actors[2].social.has_caring_partner() and not actors[3].social.has_caring_partner(),"Departure removes bonus immediately for continuing conversation")
	world.game_time.debug_skip_minutes(4)
	check(actors[2].data.get_need(Need.SOCIAL).value==68 and actors[3].data.get_need(Need.SOCIAL).value==71,"Remaining pair returns to original recovery")
	world.free();await process_frame
	var container:=fixture(2);var social_world: Node=container.get_child(0);var group=social_world.create_group(Vector2.ZERO)
	for id in ["chooser","target_1","target_2"]:
		var actor: Node=social_world.get_runtime(id);actor.data.activity=Activity.TALKING;group.add_participant(id)
	social_world.get_runtime("target_1").data.add_trait(Trait.CARING)
	check(social_world.has_caring_partner("chooser"),"Live group member supplies bonus")
	social_world.get_runtime("target_1").free()
	check(not social_world.has_caring_partner("chooser"),"Stale member never supplies bonus")
	social_world.groups.clear()
	check(not social_world.has_caring_partner("chooser"),"TALKING marker alone cannot supply bonus")
	container.free()
func venue_conversation() -> void:
	var world=F.create(self);var actors: Array=world.resident_runtimes
	F.building(world,preload("res://scripts/building_type.gd").Type.GAZEBO,Vector3(-12,0,16))
	for index in actors.size():
		actors[index].data.set_traits([]);actors[index].view.global_position=Vector3(-16+index*1.5,0,20)
	actors[2].data.add_trait(Trait.CARING)
	check(actors[0].social.try_social_at(actors[1].data.id,5600),"Physical gazebo meeting planned")
	F.walk(world,actors[0])
	check(not actors[0].social.has_caring_partner(),"Pending first arrival has no remote conversation bonus")
	F.walk(world,actors[1])
	check(actors[2].social.try_social_at(actors[0].data.id,5600),"CARING reserves pending gazebo place")
	check(not actors[0].social.has_caring_partner() and not actors[2].social.has_caring_partner(),"Pending CARING is neither donor nor recipient")
	F.walk(world,actors[2])
	check(actors[0].social.has_caring_partner() and not actors[2].social.has_caring_partner(),"Physical arrival enables one-way bonus")
	actors[3].data.add_trait(Trait.CARING);check(actors[3].social.try_social_at(actors[0].data.id,5600),"Second CARING uses existing fourth visitor place")
	F.walk(world,actors[3]);reset_social(actors);world.game_time.debug_skip_minutes(4)
	for actor in actors:check(actor.data.get_need(Need.SOCIAL).value==65,"Full gazebo with two CARING has no stacking")
	check(world.debug_spawn.spawn_residents(Vector3(-10,0,24),1,preload("res://scripts/resident_profession.gd").Type.NONE).created==1,"Extra real chooser created")
	var extra: Node=world.resident_runtimes[-1];extra.data.set_traits([Trait.CARING]);extra.decision._deciding=true
	var group=world.social_world.group_of(actors[0].data.id)
	check(world.social_world.options_for(extra.data.id).all(func(option):return option.group_id!=group.id) and not extra.social.try_social_at(actors[0].data.id,5600),"CARING cannot bypass full gazebo capacity")
	world.free();await process_frame
func generation() -> void:
	var catalog=preload("res://scripts/trait_type.gd");var generator=preload("res://scripts/resident_generator.gd").new(42);var repeat=preload("res://scripts/resident_generator.gd").new(42);var seen: Dictionary={}
	for index in 500:
		var person=generator.generate();var same=repeat.generate();var description: String=person.trait_description()
		check(person.traits.size()==2 and catalog.compatible(person.traits) and person.traits==same.traits and person.grammatical_gender==same.grammatical_gender,"Two compatible traits and grammatical metadata reproducible")
		check(description==same.trait_description() and description==person.trait_description(),"Ordered composite description stable")
		for type in person.traits:seen[type]=true
	check(seen.size()==13 and catalog.GENERATION_POOL.size()==13,"All thirteen traits generated")
	check(catalog.description([Trait.CARING,Trait.PRUDENT])=="Заботливый прагматик" and catalog.description([Trait.CARING,Trait.PRUDENT],catalog.GrammaticalGender.FEMININE)=="Заботливая прагматичка","Both CARING grammatical forms")
