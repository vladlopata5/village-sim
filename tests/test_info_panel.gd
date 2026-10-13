extends SceneTree
const Def = preload("res://scripts/building_definition.gd")
const Types = preload("res://scripts/building_type.gd").Type
const P = preload("res://scripts/resident_profession.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const Need = preload("res://scripts/need_type.gd").Type
const Skill = preload("res://scripts/skill_type.gd").Type
const Diary = preload("res://scripts/diary_entry.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func quiet(world: Node) -> void:
	world.game_time.set_process(false)
	world.game_logger.console_enabled=false
	world.social_events.enabled=false
	for actor in world.resident_runtimes:
		actor.decision._deciding=true
		actor.intents.abort_current(actor.intents.current_intent)
		actor.view.set_physics_process(false)
		for need in actor.data.needs.values(): need.value=0
func run() -> void:
	var world = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	quiet(world)
	await process_frame
	var panel=world.game_ui.info_panel
	var resident=world.resident_card_view()
	var building=world.building_card_view()
	var selection=world.resident_selection
	var a=world.residents[0]
	var b=world.residents[1]
	var camera: Camera3D=world.get_node("World/Camera3D")
	var transform_before:=camera.global_transform
	var zoom_before:=camera.size
	check(world.game_ui.residents_button.text=="↗ Жители: 4","Existing residents caption uses correct UTF-8 text")
	check(panel.visible and panel.day_summary.visible and panel.day_summary.text=="День 1" and not panel.expanded,"Initial persistent day card")
	selection.select(a)
	check(resident.visible and not panel.expanded and panel.active_tab==&"bio","First selection compact with default Bio")
	check(resident.name_label.text.contains(a.resident_name) and resident.age_label.text.contains(str(a.age)) and resident.summary_label.text==preload("res://scripts/resident_profession.gd").display_name(a.profession),"Real compact resident fields")
	panel.set_expanded(true)
	panel.select_tab(&"work")
	panel.clear_type_preview()
	check(panel.expanded and panel.active_tab==&"work","Clearing absent preview cannot change selected card state")
	selection.select(b)
	check(panel.expanded and panel.active_tab==&"work","Direct resident change preserves expansion and compatible tab")
	selection.select_building(world.warehouse_data)
	check(panel.expanded and panel.active_tab==&"info" and not resident.visible and building.visible,"Resident to building preserves expansion, falls back to Info")
	check(panel._tabs==[&"info",&"storage"],"Town Center has storage and no production")
	var stocks: String=building.get_node("%StorageAmounts").text
	world.warehouse_data.resources.reserve_out(R.FOOD,3)
	building._refresh()
	check(building.get_node("%StorageAmounts").text==stocks and stocks.contains("20 / 100") and stocks.contains("60 / 100"),"Storage shows actual per-resource quantity/capacity, reserves not subtracted")
	world.warehouse_data.resources.release_out(R.FOOD,3)
	world.warehouse_data.resources.add(R.STONE,2)
	check(building.get_node("%StorageAmounts").text.contains("Камень: 2 / 100"),"ResourceContainer.changed updates immediately")
	var demolish: Button=building.get_node("%Demolish")
	check(demolish.disabled and demolish.pressed.get_connections().is_empty(),"Demolish disabled with no removal callbacks")
	selection.select(a)
	check(panel.expanded and panel.active_tab==&"bio","Building to resident falls back to Bio")
	a.get_need(Need.HUNGER).value=73
	check(resident.hunger_label.text.contains("73"),"Need.changed immediately updates Bio")
	a.add_skill_xp(Skill.CONSTRUCTION,4)
	check(resident.skills_label.text.contains("4 XP"),"Skill signal updates actual XP")
	resident.get_node("%SkillsToggle").button_pressed=true
	check(resident.skills_label.visible,"Skills foldout operates")
	world.game_time.total_minutes=1500
	world.game_time.minute_changed.emit(1500)
	a.add_diary_entry(Diary.new("Старый ключевой факт",Diary.Importance.KEY,360))
	a.add_diary_entry(Diary.new("Сегодняшняя запись",Diary.Importance.TEMPORARY,1490))
	var diary: Label=resident.get_node("%Diary")
	check(diary.text.contains("Сегодняшняя запись") and not diary.text.contains("Старый ключевой факт") and a.diary_entries.size()==2,"Diary filters current day without deleting old KEY or changing retention")
	resident.get_node("%DiaryToggle").button_pressed=true
	check(diary.visible,"Diary foldout operates")
	world.game_time.total_minutes=2880
	world.game_time.minute_changed.emit(2880)
	check(panel.day_summary.text=="День 3" and diary.text.contains("За текущий день записей нет"),"Midnight changes day and diary empty state")
	var old_connections: int=a.relationship_changed.get_connections().size()
	selection.select(b)
	check(a.relationship_changed.get_connections().size()==old_connections-1 and not a.get_need(Need.HUNGER).changed.is_connected(resident._refresh),"Old relationship/need subscriptions disconnected")
	var text_before: String=resident.skills_label.text
	a.add_skill_xp(Skill.CONSTRUCTION,2)
	check(resident.skills_label.text==text_before,"Old object callbacks cannot change current skills")
	check(resident.get_node("%RelationshipLinks").get_child_count()==0 and b.relationships.is_empty(),"No neutral records synthesized")
	b.set_opinion(StringName(a.id),23)
	a.set_opinion(StringName(b.id),-9)
	check(resident.get_node("%RelationshipLinks").get_child_count()==1 and resident.get_node("%RelationshipLinks").get_child(0).text.contains("+23"),"Known directed B to A displayed, not reverse opinion")
	panel.select_tab(&"relations")
	resident.get_node("%RelationshipLinks").get_child(0).pressed.emit()
	check(selection.selected_resident==a and panel.expanded and panel.active_tab==&"relations","Relationship name selects resolved resident without clear")
	selection.clear()
	check(panel.day_summary.visible and not panel.expanded,"Full clear resets compact day state")
	selection.select(b)
	check(not panel.expanded and panel.active_tab==&"bio","Selection after clear starts compact")
	# Real buildings through the normal debug spawn API; no UI-only instances.
	var house_result: Dictionary=world.debug_spawn.spawn_building(Vector3(-15,0,15),Def.for_type(Types.HOME))
	check(house_result.ok,"Real built house registration")
	var house=house_result.objects[0]
	world.player_control.assign_home(b.id,house.id)
	selection.select_building(house)
	panel.set_expanded(true)
	check(panel._tabs==[&"info"] and building.housing_count.text.contains("1 / 4"),"Home uses Info/housing only")
	var home_row=building.get_node("%People").get_children().filter(func(row): return row is HBoxContainer)[0]
	home_row.get_child(0).pressed.emit()
	check(selection.selected_resident==b,"Home occupant name link")
	resident.get_node("%ClearHome").pressed.emit()
	check(b.home_location_id.is_empty() and resident.home_label.text.contains("Нет дома"),"Housing clear uses existing PlayerControl API")
	var saw_result: Dictionary=world.debug_spawn.spawn_building(Vector3(-15,0,-14),Def.for_type(Types.SAWMILL))
	check(saw_result.ok,"Real Sawmill registration")
	var saw=saw_result.objects[0]
	world.player_control.assign_workplace(b.id,saw.id,P.SAWYER)
	selection.select_building(saw)
	check(panel._tabs==[&"info",&"production"],"Sawmill has production without storage")
	panel.select_tab(&"production")
	check(building.get_node("%Recipe").text.contains("Бревно") and building.get_node("%Recipe").text.contains("Доски") and building.resources_label.text.contains("Вход") and building.resources_label.text.contains("Выход"),"Recipe inputs/outputs and actual distinct buffers")
	check(not building.get_node("%Info").visible,"Inactive Info remains hidden")
	saw.resources.add(R.LOG,1)
	check(not building.get_node("%Info").visible and building.get_node("%ProductionTab").visible,"Resource callback cannot reopen a hidden tab")
	world.placement.select(Def.for_type(Types.STORAGE))
	world.placement.update_world_position(Vector3(29,0,24))
	var site=world.placement.confirm()
	check(site!=null,"Real placement creates construction instance")
	selection.select_building(site)
	check(panel.active_tab==&"info" and panel._tabs==[&"info"] and building.construction_section.visible,"UC has Info/materials/work, no production/storage")
	for resource in site.definition.construction_requirements: site.add_delivered_material(resource,site.get_required_amount(resource))
	site.add_construction_work(10)
	check(building.construction_work.text.contains("10 / 240"),"Actual incremental construction signal reaches card")
	site.add_construction_work(230)
	site.complete_construction()
	check(selection.selected_building==site and site.is_built() and panel._tabs==[&"info",&"storage"] and not building.construction_section.visible,"Same instance UC to BUILT changes applicable tabs")
	selection.clear()
	var count_before: int=world.buildings.size()
	check(panel.show_type_preview(Def.for_type(Types.SAWMILL)),"Standalone real definition preview available")
	check(panel.preview.get_node("Footprint").text.contains("12 × 8") and panel.preview.get_node("Materials").text.contains("Камень: 6") and world.buildings.size()==count_before and selection.selected_entity==null,"Preview from definition footprint/recipe, no BuildingInstance/selection created")
	panel.clear_type_preview()
	check(panel.day_summary.visible,"Clearing preview returns to day")
	selection.select(b)
	resident.bind_selection(selection)
	resident.bind_control(world.player_control)
	check(b.relationship_changed.get_connections().filter(func(c): return c.callable==resident._on_relationship_changed).size()==1,"Repeated binding never duplicates selected subscriptions")
	world.player_control.unregister_resident(b.id)
	check(selection.selected_entity==null and panel.day_summary.visible,"Unregister selected resident clears stale selection")
	selection.select_building(house)
	world.player_control.unregister_building(house.id)
	check(selection.selected_entity==null,"Unregister selected building clears stale selection")
	check(camera.global_transform==transform_before and camera.size==zoom_before,"All card transitions leave camera transform/zoom unchanged")
	var control=world.player_control
	world.free()
	check(a.relationship_changed.get_connections().all(func(c): return c.callable.get_object()!=resident),"Destroyed card leaves no relationship callbacks")
	check(control.profession_changed.get_connections().is_empty(),"Destroyed panel removes PlayerControl subscriptions")
	print("E2 InfoPanel: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
