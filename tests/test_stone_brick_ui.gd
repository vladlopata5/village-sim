extends "res://tests/test_clay_ui.gd"
func run() -> void:
	root.size=Vector2i(1600,900)
	var world=F.create(self)
	check(CatalogData.categories()[0].entries.any(func(entry):return entry.definition.type==T.STONEMASON_WORKSHOP),"Workshop in ordinary construction catalog")
	check(preload("res://scripts/resident_profession.gd").display_name(P.STONEMASON)=="Каменотёс" and P.MINER==6 and P.POTTER==14,"New profession distinct from unchanged miner/potter IDs")
	world.construction_panel.set_collapsed(false)
	var catalog=world.construction_panel.catalogue;catalog.select_category(&"production")
	await process_frame;await process_frame
	var tile: Button=catalog.tile_for_type(T.STONEMASON_WORKSHOP)
	catalog._scroll.ensure_control_visible(tile);await process_frame;await process_frame
	F.click(self,tile)
	check(world.placement.is_active() and world.placement.selected_definition.type==T.STONEMASON_WORKSHOP,"Real catalog tile selects new B1 tool")
	await observe(world,"catalog")
	world._cancel_active_world_tool();world.construction_panel.set_collapsed(true)
	var shop=F.building(world,T.STONEMASON_WORKSHOP,Vector3(5,0,16))
	world.resident_selection.select_building(shop);world.game_ui.info_panel.set_expanded(true);world.game_ui.info_panel.select_tab(&"info")
	var card=world.building_card_view()
	check(card.staffing_buttons.has(P.STONEMASON) and card.staffing_buttons.has(P.PORTER) and not card.upgrade_section.visible,"Shared card shows one mason, one porter, no unsupported upgrade")
	check(card.resources_label.text.contains("Камень: 0 / 10") and card.resources_label.text.contains("Каменный кирпич: 0 / 10") and card.consumable_rows.is_empty(),"Input/output stock labels without fuel/water rows")
	var worker=world.resident_runtimes[0]
	check(world.player_control.assign_workplace(worker.data.id,shop.id) and worker.data.profession==P.STONEMASON,"Shared staffing command assigns new profession")
	world.resident_selection.select(worker.data)
	var resident_card=world.resident_card_view()
	var index: int=resident_card.profession_choice.get_item_index(P.STONEMASON)
	check(index>=0 and resident_card.profession_choice.get_item_text(index)=="Каменотёс","Existing profession selector exposes new role")
	world.resident_selection.select_building(shop);world.game_ui.info_panel.select_tab(&"production");await process_frame
	var view=card.recipe_views[&"cut_stone_brick"]
	check(view.title.text=="Каменный кирпич" and view.composition.text.contains("Камень ×1 → Каменный кирпич ×1") and view.composition.text.contains("30 рабочих минут") and not view.composition.text.contains("Топливо"),"Shared recipe UI reads no-consumable recipe")
	view.mode.select(B.ProductionMode.ORDER);view.mode.item_selected.emit(B.ProductionMode.ORDER);view.amount.text="1";view.amount.text_changed.emit("1")
	await ui_click(world,view.apply_button)
	check(shop.get_recipe_mode(&"cut_stone_brick")==B.ProductionMode.ORDER and shop.get_order_remaining(&"cut_stone_brick")==1,"Actual Apply click configures one output order")
	shop.resources.add(R.STONE,1)
	world.game_ui.info_panel.select_tab(&"info");await process_frame
	check(card.resources_label.text.contains("Камень: 1 / 10"),"Local stock event updates shared card")
	await observe(world,"stone-stock")
	if await start_recipe(world,worker):
		world.game_time.debug_skip_minutes(7)
		world.game_ui.info_panel.select_tab(&"production");card._process(.3)
		check(view.batches.text.contains("7 / 30"),"Shared batch UI shows actual paid work")
		await observe(world,"batch")
		world.game_time.debug_skip_minutes(23)
		check(shop.resources.get_amount(R.STONE_BRICK)==1 and shop.production_batches.is_empty(),"UI-controlled order yields exactly one brick")
		world.game_ui.info_panel.select_tab(&"info")
		await observe(world,"output")
	world.resident_selection.select_building(world.warehouse_data);world.game_ui.info_panel.select_tab(&"storage");await process_frame
	check(card.storage_rows.has(C.STONE_BRICK) and card.storage_rows.has(C.BRICK),"Separate editable warehouse categories exist for both bricks")
	await observe(world,"warehouse")
	world.free();await process_frame
	print("Stone brick UI: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
