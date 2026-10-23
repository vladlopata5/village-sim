extends "res://tests/test_textile_production.gd"
const Stage=preload("res://scripts/construction_stage.gd")
const View=preload("res://scripts/world_3d/building_view_3d.gd")
const Expected=preload("res://tests/construction_recipe_expectations.gd")
const TIMES=[240,240,180,180,180,240,240,180,180,180,240,240,180,120,180,180,180]
func run() -> void:
	definitions_and_execution()
	validation()
	await card_and_reverse()
	print("Staged construction: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func definitions_and_execution() -> void:
	var costs: Dictionary=Expected.COSTS.duplicate(true)
	costs.merge({T.STONEMASON_WORKSHOP:{R.LOG:4,R.PLANK:6,R.STONE:4},T.CLAY_HUT:{R.LOG:8,R.STONE:4},T.POTTERY_WORKSHOP:{R.LOG:4,R.PLANK:6,R.STONE:4},T.TOWN_CENTER:{},T.WELL:{R.LOG:4,R.STONE:4},T.WEAVER_WORKSHOP:{R.LOG:4,R.PLANK:6,R.STONE:4},T.TAILOR_WORKSHOP:{R.LOG:6,R.PLANK:8,R.STONE:4},T.FARM:{R.LOG:6,R.PLANK:8,R.STONE:4},T.WINDMILL:{R.LOG:4,R.PLANK:6,R.STONE:4}})
	for type in T.values():
		var definition=D.for_type(type)
		check(definition.validate_construction_stages() and definition.construction_requirements==costs[type] and definition.construction_work_required==TIMES[type],"Every current type retains independently expected cost/time")
		check(definition.construction_stages.size()==(1 if type==T.TOWN_CENTER else 2 if type==T.WELL else 3),"Individual finite stage counts, including one-step special definition")
		var site=B.new(&"staged",definition,Vector2.ZERO,B.State.UNDER_CONSTRUCTION)
		var view=View.new();root.add_child(view);view.setup(site)
		check(view.construction_visual!=null and view.construction_visual.visual_id==&"site" and view.construction_visual.multimesh.instance_count==1,"Initial site is a single temporary batch, not the finished building")
		var nested: Array=[]
		var callback=func():nested.append(site.add_construction_work(10000))
		var before:=0
		for index in definition.construction_stages.size():
			var stage: RefCounted=definition.construction_stages[index]
			check(site.construction_stage_index()==index and site.stage_work_progress()==0,"Stage state starts at the next unpaid work boundary")
			if not stage.materials.is_empty():check(not site.add_construction_work(1),"Missing active materials block work")
			for resource in R.values():
				if not stage.materials.has(resource):check(site.get_uncovered_construction_amount(resource)==0 and not site.reserve_construction_material(resource,1),"No inbound orders for future or unrelated materials")
			for resource in stage.materials:
				check(site.reserve_construction_material(resource,stage.materials[resource]),"Reserve only current stage quantity")
				check(not site.reserve_construction_material(resource,1) and site.deliver_reserved_construction_material(resource,stage.materials[resource]),"Own reserve delivers once without surplus")
			check(site.are_stage_materials_complete() and site.ready_for_structural_work(),"Current complete stage admits labour without future materials")
			var visual: StringName=view.construction_visual.visual_id
			if stage.work_minutes>1:
				check(site.add_construction_work(stage.work_minutes-1) and site.construction_stage_index()==index and view.construction_visual.visual_id==visual,"No premature stage or visual switch")
			site.construction_changed.connect(callback)
			check(site.add_construction_work(10000),"Oversized labour callback stops exactly at one active boundary")
			site.construction_changed.disconnect(callback)
			check(site.construction_progress==before+stage.work_minutes and site.completed_construction_stage_count()==index+1 and nested.back()==false,"Transition published atomically; nested work cannot skip the next stage")
			check(site.get_construction_progress_ratio()>=float(before)/definition.construction_work_required,"Overall work progress never resets between stages")
			before=site.construction_progress
			if index+1<definition.construction_stages.size():check(not site.is_built() and view.construction_visual.visual_id==stage.visual_id,"Completed step updates presentation without activating building")
		check(site.construction_delivered==costs[type],"Cumulative delivered ledger preserves all completed-stage materials for D1")
		check(site.complete_construction() and not site.complete_construction() and site.is_built() and view.construction_visual==null,"Final completion once frees temporary geometry and exposes original model")
		view.free()
func validation() -> void:
	var definition=D.new(&"custom",T.HOME,"Custom",Vector2.ONE,{R.LOG:2},12,2)
	check(definition.validate_construction_stages(),"Custom one-stage declaration is supported")
	definition.construction_stages[0].work_minutes=0
	check(not definition.validate_construction_stages(),"Zero duration rejected")
	definition.construction_stages[0].work_minutes=12;definition.construction_stages[0].materials[R.LOG]=-1
	check(not definition.validate_construction_stages(),"Negative material rejected")
	definition.construction_stages[0].materials={R.LOG:1}
	check(not definition.validate_construction_stages(),"Missing material rejected")
	definition.construction_stages[0].materials={R.LOG:2,R.STONE:1}
	check(not definition.validate_construction_stages(),"Additional material rejected")
	definition.construction_stages[0].materials={R.LOG:2};definition.construction_stages[0].work_minutes=11
	check(not definition.validate_construction_stages(),"Changed total duration rejected")
	definition.construction_stages[0].work_minutes=6
	definition.construction_stages.append(Stage.new(&"build","Duplicate",{},6,&"complete"))
	check(not definition.validate_construction_stages(),"Duplicate stage identity rejected")
func card_and_reverse() -> void:
	var world=F.create(self)
	world.placement.select(D.for_type(T.STORAGE));world.placement.update_world_position(Vector3(-12,0,16))
	var site=world.placement.confirm();world.resident_selection.select_building(site)
	var card=world.building_card_view()
	check(card.construction_work.text.contains("этап 1/3") and card.construction_materials.text.contains("Камень: 0 / 4") and not card.construction_materials.text.contains("Доски"),"Card shows only active materials and stage title")
	site.add_delivered_material(R.STONE,4);site.add_construction_work(60)
	check(card.construction_work.text.contains("этап 2/3") and card.construction_work.text.contains("0 / 100") and card.structural_progress.value==25 and card.construction_materials.text.contains("Бревно: 0 / 2"),"UI changes stage while cumulative work bar stays25 percent")
	site.add_delivered_material(R.LOG,1)
	var delivered: Dictionary=site.construction_delivered
	check(site.set_work_direction(B.WorkDirection.DEMOLISH),"Cancel after a completed stage begins existing reverse work")
	site.work_paused=false;site.add_construction_work(20)
	check(site.construction_progress==40 and site.set_work_direction(B.WorkDirection.BUILD),"Reverse uses the same structural minutes")
	site.work_paused=false
	check(site.add_construction_work(20) and site.construction_progress==60 and site.construction_delivered==delivered and site.get_missing_amount(R.LOG)==1,"Restoring an earlier step never charges its material twice")
	world.placement.select(D.for_type(T.FOOD));world.placement.update_world_position(Vector3(16,0,16))
	var kitchen=world.placement.confirm();world.resident_selection.select_building(kitchen)
	check(card.consumable_rows.is_empty(),"Unfinished selected kitchen has no fictional numerical stocks")
	Expected.complete(kitchen)
	check(card.consumable_rows.size()==2 and card.consumable_rows[&"water"].label.text.contains("0 / 20") and card.consumable_rows[&"fuel"].label.text.contains("0 / 20"),"Same selected kitchen creates both local stock bars on final completion without reselection")
	card._refresh();card._refresh()
	for stock in kitchen.consumable_stocks.values():
		check(stock.changed.get_connections().filter(func(connection):return connection.callable==card._refresh_consumables).size()==1,"Completion and repeated refresh never duplicate local stock subscription")
	world.resident_selection.select_building(world.warehouse_data)
	for stock in kitchen.consumable_stocks.values():check(not stock.changed.is_connected(card._refresh_consumables),"Changing selection disconnects stocks attached at completion")
	world.free();await process_frame
