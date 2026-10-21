extends SceneTree
const C = preload("res://scripts/resource_category.gd").Type
const F = preload("res://tests/residents_ui_fixture.gd")
const R = preload("res://scripts/resource_type.gd").Type
const T = preload("res://scripts/building_type.gd").Type
const P = preload("res://scripts/resident_profession.gd").Type
const Balance = preload("res://scripts/balance_config.gd")
const Candidate = preload("res://scripts/delivery_candidate.gd")
const Source = preload("res://scripts/resource_source_ref.gd")
const Job = preload("res://scripts/haul_job.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func settle() -> void: await process_frame; await process_frame
func capture(label: String) -> void:
	if "--render-qa" not in OS.get_cmdline_user_args(): return
	await settle()
	await RenderingServer.frame_post_draw
	var folder := "C:/Users/SW/Documents/Codex/outputs/food-f3/rendered"
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder+"/"+label+".png")
func edit(card: Node, category: int, text: String) -> void:
	var editor: LineEdit = card.storage_rows[category].editor
	editor.text = text
	editor.text_changed.emit(text)
	editor.grab_focus()
	var submitted: Array = []
	var on_submit := func(value): submitted.append(value)
	editor.text_submitted.connect(on_submit)
	F.key(self,KEY_ENTER)
	await process_frame
	editor.text_submitted.disconnect(on_submit)
	check(submitted==[text],"Enter submits exactly the current text: %s / %s" % [text,str(submitted)])
func walk(actor: Node) -> void:
	for step in range(5000):
		preload("res://tests/handling_test_step.gd").move_3d(actor,0.05)
		if not actor.view.movement.is_moving(): break

func run() -> void:
	var world = F.create(self)
	await settle()
	var town = world.warehouse_data
	var control = world.player_control
	var selection = world.resident_selection
	var card = world.building_card_view()
	var panel = world.game_ui.info_panel
	selection.select_building(town)
	panel.set_expanded(true)
	panel.select_tab(&"storage")
	await settle()
	check(town.resources.is_warehouse() and town.resources.shared_capacity==100 and town.resources.get_total_amount()==30,"Canonical Town Center preserves initial stock in shared capacity")
	for category in C.values(): check(town.resources.get_category_quota(category)==Balance.TOWN_CENTER_CATEGORY_QUOTAS.get(category,0),"Approved Town Center preset, wool initially unallocated")
	check(card.storage_rows.size()==12 and card.get_node("%StorageSummary").text=="Занято: 30 / 100\nВ пути: 0\nРаспределено: 100 / 100","All twelve category rows and approved starter totals")
	await capture("town-initial")
	card.storage_rows[C.SIMPLE_FOOD].expand.button_pressed = true
	check(card.storage_rows[C.SIMPLE_FOOD].contents.visible and card.storage_rows[C.SIMPLE_FOOD].contents.text == "  FOOD: 20","Expanded category shows real concrete stock")
	await capture("town-food-expanded")
	var tab_rebuilds: int = panel.tab_rebuild_count
	check(town.resources.add(R.PLANK,30),"Explicit stock for over-quota UI regression")
	var row = card.storage_rows[C.PLANK]
	await edit(card,C.PLANK,"10")
	check(town.resources.get_amount(R.PLANK)==30 and town.resources.get_capacity(R.PLANK)==10 and row.amount.text=="30 /" and row.editor.text=="10","Inline edit preserves and displays over-quota stock")
	check(card.get_node("%StorageSummary").text.contains("Распределено: 60 / 100") and panel.tab_rebuild_count==tab_rebuilds,"Quota edit updates totals without rebuilding tabs")
	await capture("town-surplus")
	for invalid in ["-1","1.5","abc","100","99999999999999999999"]:
		await edit(card,C.PLANK,invalid)
		check(town.resources.get_capacity(R.PLANK)==10 and not card.get_node("%StorageError").text.is_empty(),"Invalid edit rejected with an explanation")
		check(card.get_node("%StorageError").text.contains("Сумма") if invalid=="100" else card.get_node("%StorageError").text.contains("целое"),"Error for %s: %s" % [invalid,card.get_node("%StorageError").text])
	await edit(card,C.PLANK,"100")
	await capture("town-invalid")
	await edit(card,C.PLANK,"10")
	var editor: LineEdit = card.storage_rows[C.LOG].editor
	editor.grab_focus()
	editor.text="17"
	editor.text_changed.emit("17")
	town.resources.add(R.STONE,1)
	town.resources.reserve_in(R.FOOD,0) # Invalid operations must not disturb the draft either.
	card._process(0.3)
	check(editor.text=="17" and town.resources.get_capacity(R.LOG)==10,"Resource updates preserve an unfinished draft")
	card.storage_rows[C.LOG].apply.pressed.emit()
	check(town.resources.get_capacity(R.LOG)==17 and card.get_node("%StorageError").text.is_empty(),"Inline apply button uses PlayerControl")
	await edit(card,C.LOG,"0")
	check(card.storage_rows[C.LOG].row.visible and card.storage_rows[C.LOG].editor.text=="0","Zero quota remains visible")
	var store = F.building(world,T.STORAGE,Vector3(30,0,24))
	for category in C.values(): check(store.resources.get_category_quota(category)==Balance.STORAGE_CATEGORY_QUOTAS.get(category,0),"Activated Storage gets approved preset; wool quota is zero")
	check(store.resources.is_warehouse() and store.resources.get_total_amount()==0 and store.resources.shared_capacity==100,"New Storage starts empty with shared capacity")
	selection.select_building(store)
	check(not card.storage_rows[C.SIMPLE_FOOD].contents.visible and not card.storage_rows[C.SIMPLE_FOOD].expand.button_pressed,"Selection clears category expansion")
	check(not town.resources.changed.is_connected(card._on_resources_changed) and not town.resources.reservations_changed.is_connected(card._on_reservations_changed) and not town.resources.quotas_changed.is_connected(card._refresh),"Changing selection disconnects all old container callbacks")
	await edit(card,C.LOG,"5")
	check(store.resources.get_capacity(R.LOG)==5 and town.resources.get_capacity(R.LOG)==0,"Warehouse settings are independent")
	var refreshes: int = card.refresh_count
	control.set_warehouse_category_quota(town.id,C.LOG,1)
	check(card.refresh_count==refreshes and card.storage_rows[C.LOG].editor.text=="5","Old warehouse quota notifications cannot refresh the selected warehouse")
	for index in range(5): selection.select_building(town); selection.select_building(store)
	check(store.resources.quotas_changed.get_connections().filter(func(c): return c.callable==card._refresh).size()==1,"Repeated selection does not duplicate local subscriptions")
	var editor_before = card.storage_rows[C.SIMPLE_FOOD].editor
	store.resources.reserve_in(R.FOOD,1)
	check(card.get_node("%StorageSummary").text.contains("В пути: 1") and card.storage_rows[C.SIMPLE_FOOD].editor==editor_before,"Inbound-only event updates totals while retaining widgets")
	store.resources.release_in(R.FOOD,1)
	check(card.get_node("%StorageSummary").text.contains("В пути: 0"),"Inbound release immediately refreshes totals")
	var saw = F.building(world,T.SAWMILL,Vector3(-15,0,-14))
	check(not saw.resources.is_warehouse() and saw.resources.get_capacity(R.LOG)==12 and saw.resources.get_capacity(R.PLANK)==12,"Production buffers remain independent and unchanged")
	check(not control.set_warehouse_category_quota(saw.id,C.LOG,1).ok and not control.set_warehouse_category_quota(&"missing",C.LOG,1).ok,"Management API rejects production and absent targets")
	for invalid_category in [-1,99,null,true,0.0,"0"]:
		var before: int = store.resources.quota_revision
		check(not control.set_warehouse_category_quota(store.id,invalid_category,1).ok and store.resources.quota_revision==before,"Unknown category is rejected without fallback or notification")
	for invalid in [-1,1.5,true,"5"]: check(not control.set_warehouse_category_quota(store.id,C.LOG,invalid).ok,"Management API rejects invalid quota types")
	# A warehouse at capacity cannot accept another type just because that quota has room.
	check(store.resources.set_category_quotas({C.LOG:0,C.STONE:0,C.PLANK:100,C.SIMPLE_FOOD:0}) and store.resources.add(R.PLANK,100),"Fill real shared warehouse")
	check(store.resources.set_category_quotas({C.PLANK:0,C.SIMPLE_FOOD:100}) and store.resources.get_available_free_capacity(R.FOOD)==0 and not store.resources.reserve_in(R.FOOD,1),"Physical surplus prevents a new reservation of a different resource")
	store.resources.try_take(R.PLANK,100)
	store.resources.set_category_quotas({C.SIMPLE_FOOD:15,C.LOG:40,C.PLANK:25,C.STONE:20})
	check(control.set_warehouse_category_quota(store.id,C.PLANK,20).ok and control.set_warehouse_category_quota(store.id,C.MUSHROOM,5).ok,"Explicit fixture reallocation for real raw supply")
	# An accepted real delivery completes physically after the recipient quota becomes zero.
	var gatherer = F.building(world,T.GATHERER_HUT,Vector3(-15,0,20))
	gatherer.resources.add(R.MUSHROOM,2)
	var actor = world.resident_runtimes[0]
	check(control.assign_workplace(actor.data.id,store.id,P.PORTER),"Real porter assigned to its own Storage")
	var candidate = Candidate.new()
	candidate.source=gatherer
	candidate.source_ref=Source.new(Source.Kind.CONTAINER,gatherer.id)
	candidate.destination=store
	candidate.resource_type=R.MUSHROOM
	var delivery = world.logistics._claim_delivery(actor.data,candidate)
	check(delivery!=null,"Ordinary new delivery reserves one shared slot")
	if delivery!=null:
		check(control.set_warehouse_category_quota(store.id,C.MUSHROOM,0).ok and world.logistics.inbound_valid(delivery),"Confirmed inbound survives quota reduction")
		check(control.assign_workplace(world.resident_runtimes[1].data.id,store.id,P.PORTER),"Second porter legally assigned to the same store")
		check(world.logistics._claim_delivery(world.resident_runtimes[1].data,candidate)==null,"Further eligible worker cannot accept a new shipment above quota")
		check(world.logistics.start_claimed_job(delivery,actor.data.id),"Existing delivery starts with its own reservation, not fresh room")
		for boundary in range(6):
			if not delivery.is_active(): break
			walk(actor)
			await process_frame
			world.game_time.debug_skip_minutes(10)
		check(delivery.state==Job.State.COMPLETED and store.resources.get_amount(R.MUSHROOM)==1 and actor.data.inventory.amount==0,"Physical pickup, movement and accepted delivery complete despite zero quota")
		check(store.resources.get_total_reserved_in()==0 and gatherer.resources.get_reserved_out(R.MUSHROOM)==0,"Completed delivery leaves no reservations")
	var kitchen = F.building(world,T.FOOD,Vector3(0,0,20))
	check(world.logistics.allows_external_delivery(store,kitchen,R.MUSHROOM),"Zero quota does not prevent export to an ordinary consumer")
	check(not world.logistics.allows_external_delivery(store,town,R.MUSHROOM) and not world.logistics.allows_external_delivery(town,store,R.MUSHROOM),"Warehouse exchange remains forbidden")
	var export_candidate = Candidate.new()
	export_candidate.source=store
	export_candidate.source_ref=Source.new(Source.Kind.CONTAINER,store.id)
	export_candidate.destination=kitchen
	export_candidate.resource_type=R.MUSHROOM
	var export_job = world.logistics._claim_delivery(actor.data,export_candidate)
	check(export_job!=null,"Zero-quota warehouse stock can be reserved for ordinary export")
	if export_job!=null:
		check(world.logistics.start_claimed_job(export_job,actor.data.id),"Ordinary export from zero-quota warehouse starts")
		for boundary in range(6):
			if not export_job.is_active(): break
			walk(actor)
			await process_frame
			world.game_time.debug_skip_minutes(10)
		check(export_job.state==Job.State.COMPLETED and kitchen.resources.get_amount(R.MUSHROOM)==1 and store.resources.get_amount(R.MUSHROOM)==0,"Zero-quota export physically delivers existing stock exactly once")
	selection.select_building(store)
	await capture("store-zero-quota")
	world.free()
	print("Warehouse UI: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
