extends "res://tests/test_staged_builder.gd"
func run() -> void:
	var definition=D.for_type(T.STONEMASON_WORKSHOP);var pottery=D.for_type(T.POTTERY_WORKSHOP)
	check(definition.id==&"stonemason_workshop" and definition.display_name=="Каменотёсная мастерская" and definition.worker_profession==P.STONEMASON,"Independent type/profession registration")
	check(definition.worker_capacity==1 and definition.porter_capacity==1 and definition.upgrades.is_empty(),"One worker/courier, only base level")
	check(definition.construction_requirements==pottery.construction_requirements and definition.construction_work_required==180 and definition.max_builders==2,"Exact current pottery B1 cost/work/builders")
	for index in pottery.construction_stages.size():
		var stage=definition.construction_stages[index];var original=pottery.construction_stages[index]
		check(stage.materials==original.materials and stage.work_minutes==original.work_minutes and stage.visual_id==original.visual_id,"Same three physical construction stages")
	var layouts=preload("res://scripts/world_3d/building_layouts_3d.gd");var layout=layouts.create(definition)
	check(layouts.validate(layout,definition),"Authored entrance, WORKER, COURIER and construction points validate")
	layout.free()
	for type in T.values():check(not D.for_type(type).construction_requirements.has(R.STONE_BRICK),"No new or circular building costs")
	var world=F.create(self);var site=await catalog_placement(world);supply(world,site)
	var actors=workers(world)
	world.resident_selection.select_building(site)
	await observe(world,site,"construction")
	check(site.resources.get_capacity(R.STONE)==0 and not world.player_control.assign_workplace(world.residents[2].id,site.id),"No workplace/buffers before completion")
	check(world._request_work(actors[0]) and world._request_work(actors[1]) and not site.claim_builder_slot("third"),"Physical construction admits two builders only")
	world.game_time.set_speed(20)
	await drive(world,site,actors)
	check(site.is_built() and site.construction_progress==180 and site.construction_delivered=={R.STONE:4,R.LOG:4,R.PLANK:6},"Real logistics and builders finish exact three-stage workshop")
	check(world._activated_buildings.has(site.id) and world.logistics._buildings.has(site.id) and site.resources.get_capacity(R.STONE)==10 and site.consumable_stocks.is_empty(),"Final activation registers normal buffers/logistics without fuel")
	await observe(world,site,"built")
	check(world.player_control.assign_workplace(world.residents[2].id,site.id) and world.residents[2].profession==P.STONEMASON,"Newly built shop accepts default mason profession")
	check(world.change_construction_direction(site.id,true),"D1 demolishes ordinary base-level workshop")
	await drive(world,site,actors)
	check(site.state==B.State.REMOVED and world.demolition_results.has(site.id) and site.production_batches.is_empty(),"Demolition removes workshop and processes")
	world.free();await process_frame
	world=F.create(self);site=place(world,T.STONEMASON_WORKSHOP,Vector3(-12,0,16));supply(world,site);actors=workers(world)
	world.game_time.set_speed(20)
	await drive(world,site,actors,func():return site.completed_construction_stage_count()==1)
	check(world.cancel_construction(site.id),"B1 cancel at real stone-base boundary")
	await drive(world,site,actors)
	check(site.state==B.State.REMOVED and actors.all(func(actor):return actor.data.inventory.amount==0 and actor.builder.site==null),"Cancellation frees owned cargo and builder work")
	for resource in [R.STONE,R.LOG,R.PLANK]:check(site.get_construction_reserved_in(resource)==0 and world.warehouse_data.resources.get_reserved_out(resource)==0,"Cancelled build releases resource promises")
	world.free();await process_frame
	print("Stone brick building: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)

func catalog_placement(world: Node) -> RefCounted:
	world.construction_panel.set_collapsed(false)
	var catalog=world.construction_panel.catalogue;catalog.select_category(&"production")
	await process_frame;await process_frame
	var tile: Button=catalog.tile_for_type(T.STONEMASON_WORKSHOP)
	catalog._scroll.ensure_control_visible(tile);await process_frame;await process_frame
	F.click(self,tile)
	check(world.placement.is_active() and world.placement.selected_definition.type==T.STONEMASON_WORKSHOP,"Actual catalog tile selects new construction")
	world.placement.update_world_position(Vector3(-12,0,16))
	var site=world.placement.confirm()
	check(site!=null and site.type==T.STONEMASON_WORKSHOP,"Catalog-selected tool confirms actual legal site")
	world.construction_panel.set_collapsed(true)
	return site
