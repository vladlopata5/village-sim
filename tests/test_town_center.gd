extends SceneTree
const Types = preload("res://scripts/building_type.gd").Type
const Definition = preload("res://scripts/building_definition.gd")
const Building = preload("res://scripts/building_instance.gd")
const Resources = preload("res://scripts/resource_type.gd").Type
const Profession = preload("res://scripts/resident_profession.gd").Type
const Activity = preload("res://scripts/resident_activity.gd").Type
const Resident = preload("res://scripts/resident_data.gd")
const Source = preload("res://scripts/resource_source_ref.gd")
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var world = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.social_events.enabled = false
	for actor in world.resident_runtimes:
		actor.decision._deciding = true
		actor.intents.abort_current(actor.intents.current_intent)
		actor.view.set_physics_process(false)
	await physics_frame
	var center = world.buildings[0]
	check(world.buildings.size()==1 and center.type==Types.TOWN_CENTER and center.is_built(),"Exactly one BUILT Town Center replaces all starter infrastructure")
	check(world.residents.size()==4 and world.trees.size()>0,"Residents and forest retained")
	check(center.definition.is_storage and center.definition.fallback_housing_capacity==10,"Data-driven storage and fallback capacity")
	check(center.resources.get_amount(Resources.PLANK)==60 and center.resources.get_amount(Resources.FOOD)==20 and center.resources.get_amount(Resources.LOG)==0,"Initial stock 60 PLANK / 20 FOOD / 0 LOG")
	for resource in Resources.values():
		check(center.resources.get_capacity(resource)==100 and center.definition.allows_external_import(resource) and center.definition.allows_external_export(resource),"All current resources have capacity and external policies")
	check(Definition.for_type(Types.STORAGE).is_storage and not Definition.for_type(Types.SAWMILL).is_storage,"Storage capability preserves ordinary warehouse")
	check(world.build_grid.occupied_cells(center.id).size()==192 and not world.navigation.is_world_walkable(Coordinates.to_world(center.position)),"Town Center uses common build/nav footprint")
	check(world.world_locations.resolve_action_position(center) is Vector2,"Town Center has ordinary default access point")
	check(not world.cancel_construction(center.id),"BUILT Town Center cannot be cancelled")
	check(world.construction_panel.building_buttons.get_children().all(func(button): return button.text!="Городской центр"),"Town Center absent from construction catalog")
	world.placement.select(center.definition)
	world.placement.update_world_position(Vector3(30,0,20))
	check(world.placement.confirm()==null,"Town Center has no player placement recipe")
	world.placement.cancel()
	var actor = world.resident_runtimes[0]
	check(world.player_control.assign_profession(actor.data.id,Profession.PORTER) and actor.data.work_location_id==center.id,"Porter can use storage-capable Town Center workplace")
	var source = Source.new(Source.Kind.CONTAINER,center.id)
	check(world.logistics.sources.available(source,Resources.PLANK),"Builder source service can obtain Town Center PLANK")
	var producer = Building.new(&"fixture_producer",Definition.for_type(Types.SAWMILL),Vector2(800,400))
	world.logistics.register_building(producer)
	check(center in world.logistics.sources.storage_destinations(Source.new(Source.Kind.CONTAINER,producer.id),Resources.PLANK,producer.position),"Producer storage destination selection includes Town Center")
	check(world.residents.all(func(data): return data.home_location_id.is_empty()),"Town Center never assigned as permanent home")
	for index in range(10):
		check(world.fallback_housing.claim("capacity_%d"%index)==center.id,"Ten deterministic fallback claims succeed")
	check(world.fallback_housing.claim("eleventh").is_empty(),"Eleventh fallback claim rejected")
	actor.schedule._on_phase_changed("Ночь")
	check(actor.data.activity==Activity.SLEEPING and actor.data.current_sleep_quality==0.6 and actor.schedule._fallback_id.is_empty(),"Capacity-full homeless action uses outdoor sleep")
	actor.schedule._on_phase_changed("Утро")
	actor.intents.abort_current(actor.intents.current_intent)
	world.fallback_housing.release("capacity_0")
	check(world.fallback_housing.claim("eleventh")==center.id,"Released capacity can be reused")
	for index in range(10): world.fallback_housing.release("capacity_%d"%index)
	world.fallback_housing.release("eleventh")
	actor.schedule._on_phase_changed("Ночь")
	var trip = actor.intents.current_intent
	check(actor.schedule._fallback_id==center.id and trip.target_position==world.world_locations.get_position(center.id),"Homeless ordinary sleep commits Town Center access-point trip")
	for step in range(800):
		if actor.data.activity==Activity.SLEEPING: break
		actor.view._physics_process(0.05)
	check(actor.data.activity==Activity.SLEEPING and actor.data.current_sleep_quality==1.0,"Physical arrival starts home-quality fallback sleep")
	check(world.fallback_housing.count(center.id)==1 and actor.data.home_location_id.is_empty(),"Sleep keeps runtime capacity without home ownership")
	actor.data.activity=Activity.IDLE
	check(world.fallback_housing.count(center.id)==0,"Wake releases fallback capacity")
	actor.schedule._on_phase_changed("Утро")
	actor.schedule._on_phase_changed("Ночь")
	check(world.player_control.move_to(actor.data.id,Vector2(500,500)),"PlayerCommand interrupts fallback trip")
	check(world.fallback_housing.count(center.id)==0,"PlayerCommand releases fallback capacity")
	actor.commands.cancel_current()
	actor.intents.abort_current(actor.intents.current_intent)
	actor.schedule._on_phase_changed("Ночь")
	check(actor.needs.try_rest(10000,100),"Critical fatigue interrupts fallback trip")
	check(world.fallback_housing.count(center.id)==0 and actor.data.current_sleep_quality==0.6,"Critical interrupt frees slot and sleeps on spot with outdoor quality")
	actor.intents.abort_current(actor.intents.current_intent)
	actor.schedule._on_phase_changed("Утро")
	actor.schedule._on_phase_changed("Ночь")
	world.buildings.erase(center)
	world.fallback_housing.validate()
	check(actor.schedule._fallback_id.is_empty() and actor.data.activity==Activity.SLEEPING and actor.data.current_sleep_quality==0.6,"Invalidated fallback building safely releases capacity and uses outdoor sleep")
	world.buildings.append(center)
	actor.schedule._on_phase_changed("Утро")
	actor.intents.abort_current(actor.intents.current_intent)
	var home = Building.new(&"normal_home",Definition.for_type(Types.HOME),Vector2(750,500))
	world.buildings.append(home)
	world._show_building(home)
	check(world.player_control.assign_home(actor.data.id,home.id),"Ordinary HOME assignment works")
	actor.schedule._on_phase_changed("Ночь")
	check(actor.schedule._fallback_id.is_empty() and actor.intents.current_intent.target_position==world.world_locations.get_position(home.id),"Normal HOME has priority over fallback housing")
	world.resident_selection.select_building(center)
	var card = world.get_node("HUD/BuildingCard")
	check(card.management_button.visible and card.resources_label.text.contains("60"),"Town Center card exposes stock and management")
	card.management_button.pressed.emit()
	check(world.settlement_panel.visible and world.settlement_panel.resident_buttons.size()==4,"Settlement panel lists current residents")
	world.settlement_panel.resident_buttons[world.residents[1].id].pressed.emit()
	check(world.resident_selection.selected_resident==world.residents[1] and world.get_node("HUD/ResidentCard").visible,"Population list uses existing selection/card")
	var extra = Resident.new("population_fixture","Новый житель",20)
	extra.id="population_fixture"
	extra.resident_name="Новый житель"
	world.player_control.register_resident(extra)
	check(world.settlement_panel.resident_buttons.has(extra.id),"Resident-added signal refreshes list")
	world.player_control.unregister_resident(extra.id)
	check(not world.settlement_panel.resident_buttons.has(extra.id),"Resident-removed signal refreshes list")
	var removed_actor = world.resident_runtimes[3]
	removed_actor.schedule._on_phase_changed("Ночь")
	check(world.fallback_housing.owns(removed_actor.data.id,center.id),"Resident removal fixture holds committed fallback slot")
	var removed_id: String = removed_actor.data.id
	removed_actor.free()
	check(not world.fallback_housing.owns(removed_id,center.id) and world.fallback_housing.count(center.id)==0,"Runtime exit releases fallback allocation")
	world.free()
	print("Town Center: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
