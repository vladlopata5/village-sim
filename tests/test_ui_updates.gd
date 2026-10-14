extends SceneTree
const F=preload("res://tests/residents_ui_fixture.gd")
const N=preload("res://scripts/need_type.gd").Type
const S=preload("res://scripts/skill_type.gd").Type
const P=preload("res://scripts/resident_profession.gd").Type
const R=preload("res://scripts/resource_type.gd").Type
const T=preload("res://scripts/building_type.gd").Type
const Diary=preload("res://scripts/diary_entry.gd")
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(message)
func settle() -> void: await process_frame;await process_frame
func run() -> void:
	var world=F.create(self)
	await settle()
	var ui=world.game_ui
	var selection=world.resident_selection
	var window=world.settlement_panel
	var card=ui.resident_card
	var building=ui.building_card
	var a=world.residents[0]
	var b=world.residents[1]
	var closed_scans: int=window.registry_scan_count
	var closed_poll: int=window.poll_count
	for step in range(8): window._process(1.0)
	check(window.registry_scan_count==closed_scans and window.poll_count==closed_poll and window.rows.is_empty(),"Closed roster never polls/scans/creates TreeItems")
	ui.open_window(&"residents")
	await settle()
	check(window.theme_type_variation==&"WindowPanel" and not window.has_theme_stylebox_override("panel"),"Mounted roster uses common neutral Theme")
	var parent_poll: int=window.poll_count
	ui.hide()
	window._process(2.0)
	check(window.poll_count==parent_poll,"Ancestor-hidden roster does not poll")
	ui.show()
	await settle()
	var item: TreeItem=window.rows[a.id]
	var created: int=window.row_creation_count
	var refreshed: int=window.refresh_count
	window._row_changed(a.id);window._row_changed(a.id);window._row_changed(b.id)
	await settle()
	check(window.refresh_count==refreshed+1 and window.row_creation_count==created,"Several assignment signals coalesce without recreating rows")
	a.resident_name="Ярослав Длинное Русское Имя Для Проверки"
	a.age=99
	window._poll_visible()
	await settle()
	check(window.rows[a.id]==item and item.get_text(0)==a.resident_name,"Silent name refresh preserves row identity")
	window.sort_order.select(1);window.reverse_order.set_pressed_no_signal(true);window._projection_changed()
	await settle()
	check(window.visible_ids[0]==a.id,"Silent age participates in actual sorting")
	window.search.text="яРОСЛАВ";window._projection_changed()
	await settle()
	check(window.visible_ids==[a.id],"Live name and case-insensitive search agree")
	window.search.text="Нет Такого Жителя";window._projection_changed()
	await settle()
	check(window.visible_ids.is_empty() and window.count_label.text.contains("Совпадений нет"),"Visible empty search result")
	window.preset_profession()
	ui.close_window()
	var scans: int=window.registry_scan_count
	var polls: int=window.poll_count
	world.player_control.assign_profession(b.id,P.BUILDER)
	for step in range(8): window._process(1.0)
	await settle()
	check(window.registry_scan_count==scans and window.poll_count==polls,"Hidden roster stores dirty events without a population scan")
	ui.open_window(&"residents");await settle()
	check(window.rows[b.id].get_text(1)==preload("res://scripts/resident_profession.gd").display_name(P.BUILDER) and window.row_creation_count==created,"Reopening reads dirty row, no rebuild")
	selection.select(a);ui.info_panel.set_expanded(true)
	var links: int=card.relationship_rebuild_count
	var assignments: int=card.assignment_rebuild_count
	for step in range(10): card._process(0.25)
	check(card.relationship_rebuild_count==links and card.assignment_rebuild_count==assignments,"Visible scalar polling never rebuilds unchanged lists")
	a.get_need(N.HUNGER).value=71
	a.add_skill_xp(S.CONSTRUCTION,5)
	check(card.hunger_label.text.contains("71") and card.skills_label.text.contains("5 XP"),"Actual need/skill signals update current resident")
	a.resident_name="Новое Имя Без Сигнала";a.age=77
	card._process(0.25)
	check(card.name_label.text.contains(a.resident_name) and card.age_label.text.contains("77"),"Bounded visible scalar fallback updates silent fields")
	a.set_opinion(StringName(b.id),17)
	ui.info_panel.select_tab(&"relations")
	b.resident_name="Изменённое Имя Собеседника"
	card._process(0.25)
	check(card.get_node("%RelationshipLinks").get_children().any(func(node): return node is Button and node.text.contains(b.resident_name)),"Silent linked name refresh uses actual sparse directed relation")
	var old_connections: int=a.relationship_changed.get_connections().size()
	selection.select(b)
	check(a.relationship_changed.get_connections().size()==old_connections-1,"Selection disconnects old callbacks")
	b.mood=77
	b.activity=preload("res://scripts/resident_activity.gd").Type.MOVING
	card._process(0.25)
	check(card.mood_label.text.contains("77") and card.activity_label.text.contains("Идёт"),"Real mood fallback and activity signal")
	var text: String=card.skills_label.text
	a.add_skill_xp(S.CONSTRUCTION,9)
	check(card.skills_label.text==text,"Old resident cannot update current card")
	for step in range(12): selection.select(a);selection.select(b)
	check(b.relationship_changed.get_connections().filter(func(connection):return connection.callable==card._on_relationship_changed).size()==1,"Switches do not accumulate subscriptions")
	var hidden_count: int=building.refresh_count
	for step in range(8): building._process(1.0)
	check(building.refresh_count==hidden_count,"Hidden building card has no fallback work")
	selection.select_building(world.warehouse_data)
	ui.info_panel.select_tab(&"storage")
	var tab_rebuilds: int=ui.info_panel.tab_rebuild_count
	var people_rebuilds: int=building.people_rebuild_count
	world.warehouse_data.resources.add(R.STONE,2)
	world.warehouse_data.resources.reserve_out(R.STONE,1)
	check(building.get_node("%StorageAmounts").text.contains("Камень: 2 / 100"),"Actual amount, never availability minus reservations")
	world.warehouse_data.resources.set_capacity(R.STONE,120)
	building._process(0.25)
	check(building.get_node("%StorageAmounts").text.contains("2 / 120"),"Per-resource capacity visible fallback")
	for step in range(10): building._process(0.25)
	check(building.people_rebuild_count==people_rebuilds and ui.info_panel.tab_rebuild_count==tab_rebuilds,"Resource/visible updates reuse unchanged people and tabs")
	var house=F.building(world,T.HOME,Vector3(-18,0,12))
	world.player_control.assign_home(b.id,house.id)
	selection.select(b)
	check(card.home_label.text.contains(house.display_name),"Home reads real housing assignment")
	house.definition.display_name="Дом Новое Название"
	card._process(0.25)
	check(card.home_label.text.contains("Дом Новое Название"),"Silent home label updates from current building")
	selection.select_building(house)
	check(building.housing_count.text=="Жильцы: 1 / 4","Actual building occupants")
	world.player_control.clear_home(b.id)
	check(building.housing_count.text=="Жильцы: 0 / 4","Housing signal updates count")
	world.placement.select(preload("res://scripts/building_definition.gd").for_type(T.STORAGE))
	world.placement.update_world_position(Vector3(28,0,24))
	var site=world.placement.confirm()
	check(site!=null,"Real registered construction site")
	selection.select_building(site)
	check(ui.info_panel._tabs==[&"info"],"UC hides storage/production")
	for resource in site.definition.construction_requirements: site.add_delivered_material(resource,site.get_required_amount(resource))
	site.add_construction_work(site.definition.construction_work_required)
	site.complete_construction()
	check(site.is_built() and ui.info_panel._tabs==[&"info",&"storage"],"Same actual instance updates tabs UC to BUILT")
	check(building.get_node("%Demolish").disabled and building.get_node("%Demolish").pressed.get_connections().is_empty(),"Demolish remains inert")
	var paints: int=ui.time_controls.refresh_count
	world.game_time.set_speed(20)
	world.game_time.debug_skip_minutes(60)
	await settle()
	check(ui.time_controls.refresh_count==paints+1 and ui.time_controls.clock_label.text==world.game_time.get_clock_text(),"x20/debug minute burst paints clock once with final domain time")
	world.player_control.unregister_building(site.id)
	check(selection.selected_entity==null,"Freed selected building clears UI")
	selection.select(b);world.player_control.unregister_resident(b.id)
	check(selection.selected_entity==null and ui.info_panel.day_summary.visible,"Freed resident clears scoped presentation")
	ui.close_window()
	var hidden_refresh: int=card.refresh_count
	for step in range(8): card._process(1.0)
	check(card.refresh_count==hidden_refresh,"Hidden resident card never polls")
	var feed=world.social_feed
	for index in range(10): feed.add_message("Сообщение %d" % index)
	await settle()
	check(feed.messages.size()==4 and feed._column.get_child(0).text=="Сообщение 9" and feed.messages[0].text=="Сообщение 6","Newest-first display preserves oldest-first eviction and limit")
	check(feed._column.get_child(0).get_meta("expiry_timer").get_ref() is Timer and feed._column.get_child(0).get_meta("expiry_timer").get_ref().wait_time==12.0,"Existing 12-second real Timer, no second game clock")
	check(not ui.pointer_blocked(feed.get_global_rect().get_center()),"Passive feed never blocks world pointer")
	var timer: Timer=feed._column.get_child(0).get_meta("expiry_timer").get_ref()
	# Accelerate only this test timer after asserting the production lifetime.
	timer.start(0.05)
	await create_timer(0.08,true).timeout
	check(feed.messages.size()==3 and feed._column.get_child(0).text=="Сообщение 8","Real timeout removes its original message")
	world.free()
	print("E5 UI updates: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
