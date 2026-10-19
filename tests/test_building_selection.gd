extends SceneTree
const C = preload("res://scripts/resource_category.gd").Type
const F=preload("res://tests/canonical_ui_fixture.gd")
const D=preload("res://scripts/building_definition.gd")
const T=preload("res://scripts/building_type.gd").Type
const R=preload("res://scripts/resource_type.gd").Type
var failures:=0
var checks:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func run() -> void:
	var world=F.make(self)
	var card=world.building_card_view()
	var selection=world.resident_selection
	var building=world.warehouse_data
	await physics_frame
	await physics_frame
	F.click(self,F.screen(world,building.position))
	await physics_frame
	await physics_frame
	check(selection.selected_building==building and card.visible,"Real perspective ray selects original building")
	check(card.name_label.text==building.display_name,"Common header name")
	world.game_ui.info_panel.set_expanded(true)
	world.game_ui.info_panel.select_tab(&"storage")
	check(card.storage_rows[C.PLANK].amount.text=="%d /" % building.resources.get_amount(R.PLANK) and card.storage_rows[C.PLANK].editor.text==str(building.resources.get_capacity(R.PLANK)),"Real stock and per-resource quota")
	building.resources.try_take(R.PLANK,1)
	check(card.storage_rows[C.PLANK].amount.text=="%d /" % building.resources.get_amount(R.PLANK) and card.storage_rows[C.PLANK].editor.text==str(building.resources.get_capacity(R.PLANK)),"Resource signal updates current card")
	F.click(self,card.name_label.get_global_rect().get_center())
	await physics_frame
	await physics_frame
	check(selection.selected_building==building,"Blue click doesn't select world")
	F.click(self,card.close_button.get_global_rect().get_center())
	await process_frame
	check(selection.selected_entity==null and not card.visible,"Close clears selection")
	world.placement.select(D.for_type(T.GATHERER_HUT))
	world.placement.update_world_position(Vector3(-20,0,12))
	var site=world.placement.confirm()
	check(site!=null,"Real site fixture placed")
	selection.select_building(site)
	check(card.construction_section.visible and card.available_tabs()==[&"info"],"Construction has only applicable tab")
	for resource in site.definition.construction_requirements: site.add_delivered_material(resource,site.get_required_amount(resource))
	site.add_construction_work(site.definition.construction_work_required)
	check(site.complete_construction(),"One-way real construction lifecycle")
	check(not card.construction_section.visible and &"production" in card.available_tabs(),"Same selected object updates tabs on BUILT")
	site.production_progress=17
	card._process(0.25)
	check(card.production_label.text.contains("сбор 10 мин") and card.production_label.text.contains("разгрузка 10 мин") and not card.production_label.text.contains("17 / 30"),"Gatherer card describes physical collection instead of removed virtual progress")
	selection.select(world.residents[0])
	check(not card.visible and world.resident_card_view().visible,"Resident replaces building card")
	world.free()
	print("Building selection: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
