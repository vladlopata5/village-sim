extends "res://tests/test_building_upgrades.gd"
var observer: Callable
func observe(world: Node,label: String,building: RefCounted) -> void:
	if observer.is_valid():await observer.call(world,label,building)
func click(world: Node,control: Control) -> void:
	await process_frame;await process_frame
	world.building_card_view()._widget("Scroll").ensure_control_visible(control)
	await process_frame;await process_frame
	check(control.is_visible_in_tree(),"Actual target control is visible before UI click")
	F.click(self,control)
	await process_frame;await process_frame
func run() -> void:
	root.size=Vector2i(1600,900)
	var world=F.create(self);var hut=F.building(world,T.LUMBERJACK_HUT,Vector3(-12,0,16))
	world.resident_selection.select_building(hut);world.game_ui.info_panel.set_expanded(true);world.game_ui.info_panel.select_tab(&"info")
	var card=world.building_card_view()
	await observe(world,"ui_hut_I",hut)
	await click(world,card.upgrade_button)
	check(card.upgrade_confirm.visible and card.upgrade_summary.text.contains("12 → 22") and card.upgrade_summary.text.contains("180 рабочих минут") and not hut.is_upgrading(),"Preview click shows actual terms without charging or stopping")
	await observe(world,"ui_preview",hut)
	await click(world,card.upgrade_back)
	check(not card.upgrade_confirm.visible and hut.is_built(),"Backing out leaves original building intact")
	await click(world,card.upgrade_button);await click(world,card.upgrade_confirm)
	check(hut.is_upgrading() and card.upgrade_cancel.visible and card.construction_work.text.contains("этап 1/3"),"Real confirmation click starts one B1 project")
	await observe(world,"ui_started",hut)
	await click(world,card.upgrade_cancel)
	check(hut.is_built() and hut.level==1 and not hut.is_upgrading() and card.upgrade_button.visible,"Zero-work cancel click restores original level immediately after cleanup")
	await click(world,card.upgrade_button);await click(world,card.upgrade_confirm)
	hut.add_delivered_material(R.STONE,2);hut.add_construction_work(40)
	await click(world,card.upgrade_cancel)
	check(hut.is_upgrading() and hut.work_direction==B.WorkDirection.DEMOLISH and card.get_node("%Demolish").text=="Демонтировать здание","Project cancellation never exposes a misleading inert undo-demolition button")
	hut.work_paused=false;hut.add_construction_work(40)
	await process_frame;await process_frame
	check(hut.is_built() and hut.level==1,"Positive-work cancellation returns after its B1 reverse work")
	await click(world,card.upgrade_button);await click(world,card.upgrade_confirm)
	finish_plan(hut)
	await process_frame;await process_frame
	check(hut.level==2 and not card.upgrade_section.visible and card.name_label.text.ends_with("II"),"Final UI exposes II with no false next upgrade")
	await observe(world,"ui_hut_II",hut)
	world.resident_selection.select_building(world.warehouse_data);await process_frame
	check(not card.upgrade_section.visible,"Warehouse has no level button after switching selection")
	world.resident_selection.select_building(hut);await process_frame
	check(not card.upgrade_section.visible,"No stale confirmation carried between building cards")
	world.free();await process_frame
	print("Upgrade UI: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
