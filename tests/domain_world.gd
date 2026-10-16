extends "res://scripts/main.gd"
## Isolated domain assembly: real resources/AI/time/assignment controllers and
## deterministic executors. GUI/world input is tested on main_3d, not this fixture.
const Seed = preload("res://tests/settlement_seed.gd")
func _ready() -> void:
	world_locations=preload("res://tests/domain_locations.gd").new()
	super._ready()
func _create_starting_buildings() -> void: Seed.buildings(self)
func _starting_home_id(index: int) -> StringName: return Seed.home_id(index)
func _create_starting_home(data: ResidentData, index: int) -> void: Seed.home(self,data,index)
func _create_resident_presentation(data: ResidentData, start: Vector2) -> Node:
	var actor=preload("res://tests/domain_actor.gd").new()
	actor.name="Actor_"+data.id
	actor.setup(data)
	actor.position=start
	$World.add_child(actor)
	actor.set_time_speed(game_time.speed_multiplier)
	game_time.speed_changed.connect(actor.set_time_speed)
	return actor
func _create_building_presentation(building: BuildingInstance) -> Node:
	var view=preload("res://tests/domain_building.gd").new()
	view.name=String(building.id)
	view.position=building.position
	view.setup(building)
	$World.add_child(view)
	return view
func _build_hud() -> void:
	var ui=$HUD/GameUI
	ui.time_controls.setup(game_time,_toggle_pause)
	ui.mount_messages(social_feed)
	ui.info_panel.setup(game_time,resident_selection,player_control,logistics.get_job,func(_id): return [])
func _show_ground_resource(drop) -> void:
	_ground_ids[drop]=drop.id
	interactions.register_target(drop.id,ResourceType.display_name(drop.resource_type)+" на земле",drop,_ground_position.bind(drop),[&"ground_resource"])
func _setup_construction() -> void:
	placement.setup(buildings)
	placement.placed.connect(_show_building)
	construction_panel=preload("res://scenes/ui/action_panel.tscn").instantiate()
	$HUD.add_child(construction_panel)
	$HUD/GameUI.mount_construction(construction_panel)
	_update_population()
static func instantiate() -> Node:
	return load("res://tests/domain_world.tscn").instantiate()

func cancel_construction(id: StringName) -> bool:
	var building=player_control.get_building(id)
	if building==null or building.is_built(): return false
	player_control.unregister_building(id)
	var activation=_activate_completed_building.bind(building)
	if building.construction_changed.is_connected(activation): building.construction_changed.disconnect(activation)
	for runtime in resident_runtimes: runtime.builder.unregister_building(building)
	if resident_selection.selected_building==building: resident_selection.clear()
	var view=world_locations.get_view(id)
	world_locations._views.erase(id)
	world_locations._locations.erase(id)
	if view!=null: view.queue_free()
	return true

# This isolated fixture has domain actors and no world geometry/cell mode.
# Canonical placement is covered by test_ground_stacks_world, not this adapter.
func _drop_cargo(resource: ResourceType.Type, amount: int, runtime: ResidentRuntime) -> int:
	if amount!=1 or not is_instance_valid(runtime): return DropResult.Status.FAILED
	return DropResult.Status.PLACED if ground_resources.create_drop(resource,amount,runtime.view.get_sim_position())!=null else DropResult.Status.FAILED
