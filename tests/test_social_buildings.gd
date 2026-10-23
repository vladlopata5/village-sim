extends "res://tests/test_staged_builder.gd"
const Types=preload("res://scripts/building_type.gd").Type
var ui_observer: Callable
func capture(world: Node,label: String,site: RefCounted) -> void:
	if ui_observer.is_valid():await ui_observer.call(world,label,site)
func run() -> void:
	for type in [T.GAZEBO,T.FLOWERBED]:
		var definition=D.for_type(type);var pavilion: bool=type==T.GAZEBO
		check(definition.footprint_cells==(Vector2i(6,6) if pavilion else Vector2i(2,2)),"Approved3x3/1x1m footprints")
		check(definition.construction_requirements==({R.LOG:4,R.PLANK:6,R.STONE:2} if pavilion else {R.PLANK:1,R.STONE:1}) and definition.construction_work_required==(120 if pavilion else 30) and definition.validate_construction_stages(),"Exact B1 cost and finite stages")
		check(definition.worker_capacity==0 and definition.porter_capacity==0 and definition.worker_profession==P.NONE and definition.production_recipes.is_empty() and definition.consumable_definitions.is_empty() and definition.resource_capacities.is_empty() and definition.upgrades.is_empty(),"No permanent jobs, stocks, recipes, consumables, or upgrades")
		check(definition.visitor_capacity==(4 if pavilion else 0),"Only gazebo has four visitors")
		var layout=preload("res://scripts/world_3d/building_layouts_3d.gd").create(definition)
		check(preload("res://scripts/world_3d/building_layouts_3d.gd").validate(layout,definition),"Authored layout and construction/courier/visitor slots match")
		layout.free()
		var world=F.create(self)
		world.construction_panel.set_collapsed(false)
		var catalog=world.construction_panel.catalogue
		catalog.select_category(&"social" if pavilion else &"decoration")
		await process_frame;await process_frame
		var tile: Button=catalog.tile_for_type(type)
		F.click(self,tile);check(world.placement.is_active() and world.placement.selected_definition.type==type,"Actual social/decor category tile selects its B1 tool")
		world.placement.update_world_position(Vector3(-12,0,16));var site=world.placement.confirm()
		check(site!=null and not site.is_built(),"Ordinary placement creates unbuilt site")
		world.construction_panel.set_collapsed(true)
		world.resident_selection.select_building(site);world.game_ui.info_panel.set_expanded(true)
		await capture(world,"construction",site)
		supply(world,site);var actors=workers(world)
		check(not world.player_control.assign_workplace(world.residents[2].id,site.id,P.PORTER),"No fictional courier profession before/after build")
		world.game_time.set_speed(20);await drive(world,site,actors)
		check(site.is_built() and site.construction_progress==definition.construction_work_required and site.construction_delivered==definition.construction_requirements,"Physical builder trips deliver exact approved cost and finish all stages")
		var card=world.building_card_view();card._refresh()
		check(card.available_tabs()==[&"info"] and card.staffing_buttons.is_empty() and card.recipe_views.is_empty() and not card.resources_label.visible and not card.upgrade_section.visible and not card.production_section.visible,"Info-only card without empty manufacturing/stock/jobs")
		check(card.get_node("%Summary").text.contains("Постоянных работников нет") if pavilion else card.get_node("%Summary").text.contains("Работников и производства нет"),"Card explicitly explains social/decor function")
		if pavilion:
			var markers: Array=world.building_uses.choices(site.id,2,Vector3(-15,0,18))
			check(markers.size()==4 and markers.all(func(marker):return world.navigation.is_world_walkable(marker.global_position)),"All four open gazebo positions lie on walkable geometry")
			for first in markers:
				for second in markers:
					if first!=second:check(first.global_position.distance_to(second.global_position)>=.8,"Visitor body radii never overlap")
		else:check(world.social_venues._buildings.is_empty(),"Flowerbed has no social registration or behavior")
		await capture(world,"built",site)
		check(world.change_construction_direction(site.id,true),"Normal D1 demolition command accepted")
		await drive(world,site,actors)
		check(site.state==B.State.REMOVED and world.demolition_results.has(site.id) and world.building_uses.view(site.id)==null,"Physical reverse work removes view, footprint and slots")
		world.free();await process_frame
	await cancellation_building()
	print("Social buildings: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func cancellation_building() -> void:
	# Cancellation still uses B1; no special decorative lifecycle.
	var world=F.create(self);var site=place(world,T.GAZEBO,Vector3(-12,0,16));supply(world,site);var actors=workers(world)
	world.game_time.set_speed(20);await drive(world,site,actors,func():return site.completed_construction_stage_count()==1)
	check(world.cancel_construction(site.id),"Cancel built foundation through existing B1 command")
	await drive(world,site,actors)
	check(site.state==B.State.REMOVED and site.active_builder_ids.is_empty(),"Cancelled gazebo leaves no building or worker claims")
	for resource in [R.LOG,R.PLANK,R.STONE]:check(site.get_construction_reserved_in(resource)==0 and world.warehouse_data.resources.get_reserved_out(resource)==0,"Cancellation releases exact resource promises")
	world.free();await process_frame
