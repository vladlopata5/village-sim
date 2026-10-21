extends SceneTree
const Service = preload("res://scripts/debug_spawn_service.gd")
const P = preload("res://scripts/resident_profession.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const BT = preload("res://scripts/building_type.gd").Type
const C = preload("res://scripts/world_3d/world_coordinates.gd")
var failures := 0
var checks := 0
func check(ok: bool, text: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(text)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_logger.console_enabled=false
	var service := Service.new()
	service.world=world
	var nav_revision: int = world.navigation.revision
	var porters_before: int=world.player_control.get_porters(world.warehouse_data.id).size()
	var result := service.spawn_residents(Vector3(0,0,-25),10,P.PORTER)
	check(result.created==10,"Ten actual residents")
	var ids: Dictionary = {}
	for data in world.residents:
		check(not ids.has(data.id),"Unique resident ID")
		ids[data.id]=true
	for data in result.objects:
		var runtime = world.get_resident_runtime(data)
		check(runtime!=null and world.social_world.residents[data.id]==runtime and world.logistics._residents[data.id]==data,"All production registries")
		check(runtime.get_node("Lumberjack")!=null and runtime.get_node("Miner")!=null,"Natural work controllers")
		check(world.navigation.is_world_walkable(runtime.view.get_world_position()),"Outside obstacles")
		check(data.profession==P.PORTER and (data.work_location_id==world.warehouse_data.id or data.work_location_id.is_empty()),"Capacity-safe profession assignment, including unassigned")
		world.resident_selection.select(data)
		check(world.resident_selection.selected_resident==data and world.resident_card_view()._assignment_resident==data and world.resident_card_view().visible,"Normal resident selection")
	check(world.player_control.get_porters(world.warehouse_data.id).size()==porters_before and result.reason.contains("Без места работы: 10"),"Profession-only spawning does not take any workplace")
	check(world.navigation.revision==nav_revision,"Residents do not edit NavigationGrid")
	for resource in R.values():
		result=service.spawn_resources(Vector3(-45,0,15),10,resource)
		check(result.created==10 and result.objects.all(func(d): return d.resource_type==resource and d.amount>0 and d.amount<=d.capacity),"Quantity Ground stacks")
		var drop = result.objects[0]
		check(drop.reserve(&"test") and drop.reserve(&"other") and drop.reserved_amount(&"test")==1 and drop.reserved_amount(&"other")==1,"Independent quantity claims")
		drop.release(&"test")
		drop.release(&"other")
		for stack in result.objects: world.ground_resources.remove_drop(stack)
	check(world.navigation.revision==nav_revision,"Ground spawn has no navigation rebuild")
	check(not service.spawn_residents(Vector3(INF,0,0),1,P.BUILDER).ok,"Invalid coordinates")
	check(not service.spawn_resources(Vector3.ZERO,101,R.LOG).ok,"Quantity bounds")
	var unassigned: Dictionary=service.spawn_residents(Vector3(0,0,20),1,P.MINER)
	check(unassigned.created==1 and unassigned.objects[0].profession==P.MINER and unassigned.objects[0].work_location_id.is_empty() and unassigned.objects[0].work_area_id.is_empty(),"Absent Quarry creates legitimate unassigned Miner, no fake area")
	var stock: int = world.warehouse_data.resources.get_amount(R.PLANK)
	for index in service.building_catalog().size():
		var definition = service.building_catalog()[index]
		result=service.spawn_building(Vector3(-50+(index%8)*15,0,30-floori(float(index)/8)*12),definition)
		check(result.ok,"Built catalog spawn "+String(definition.id))
		if not result.ok: continue
		var building = result.objects[0]
		check(building.is_built() and building in world.buildings and world.world_locations.get_view(building.id)!=null,"Real BUILT lifecycle")
		check(world.build_grid.occupied_cells(building.id).size()==definition.footprint_cells.x*definition.footprint_cells.y,"BuildGrid footprint")
		check(world.navigation._blockers.has(building.id),"Navigation blocker")
		check(world.player_control.get_building(building.id)==building,"PlayerControl registration")
		check(world.building_uses.view(building.id)!=null,"Ordinary authored layout / uses")
		check(preload("res://scripts/world_3d/building_layouts_3d.gd").validate(world.world_locations.get_view(building.id).layout,definition),"Real WORKER/COURIER/entrance layout capacities")
		for resource in definition.logistics_flow: check(building.resources.get_capacity(resource)>0 or (definition.is_storage and resource in [R.MUSHROOM,R.WOOL,R.WOOL_CLOTH,R.WOOL_CLOTHING,R.WHEAT,R.SHEAF,R.STRAW] and building.resources.get_category_quota(preload("res://scripts/resource_catalog.gd").get_category(resource))==0),"Normal buffer or approved zero mushroom/wool/textile warehouse quota")
		if not definition.logistics_flow.is_empty(): check(world.logistics._buildings.get(building.id)==building,"Resource container registration")
		check(not service.spawn_building(C.to_world(building.position),definition).ok,"Overlap rejected")
		world.resident_selection.select_building(building)
		check(world.resident_selection.selected_building==building and world.building_card_view()._building==building and world.building_card_view().visible,"Normal BuildingCard selection")
	var sawyers: Dictionary=service.spawn_residents(Vector3(0,0,-25),2,P.SAWYER)
	check(sawyers.created==2 and sawyers.objects[0].work_location_id.is_empty(),"Spawned Sawyer needs an explicit workplace even when one is free")
	check(sawyers.objects[1].profession==P.SAWYER and sawyers.objects[1].work_location_id.is_empty(),"Both spawned Sawyers remain unassigned")
	check(unassigned.objects[0].work_location_id.is_empty(),"New Quarry does not auto-relocate existing unassigned Miner")
	check(world.warehouse_data.resources.get_amount(R.PLANK)==stock,"No material spending")
	var day: int = world.game_time.total_minutes/1440
	check(service.advance_to_time(7,0).ok and world.game_time.get_clock_text()=="07:00","Forward clock and WORK phase")
	check(service.advance_to_time(6,0).ok and world.game_time.total_minutes/1440==day+1,"Earlier hour advances next day")
	check(service.next_day().ok and world.game_time.get_clock_text()=="00:00","Next midnight")
	world.free()
	print("Debug spawn: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
