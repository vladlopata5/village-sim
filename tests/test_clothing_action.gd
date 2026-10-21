extends SceneTree
const F=preload("res://tests/residents_ui_fixture.gd")
const Stacks=preload("res://tests/ground_stack_fixture.gd")
const Equipment=preload("res://scripts/resident_equipment.gd")
const Item=preload("res://scripts/equipped_item.gd")
const Source=preload("res://scripts/resource_source_ref.gd")
const R=preload("res://scripts/resource_type.gd").Type
const C=preload("res://scripts/resource_category.gd").Type
const T=preload("res://scripts/building_type.gd").Type
const Intent=preload("res://scripts/resident_intent.gd")
const Purpose=preload("res://scripts/building_slot_purpose.gd").Type
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(text)
func source(world: Node,type: int=T.TAILOR_WORKSHOP,units: int=1) -> RefCounted:
	var place=F.building(world,type,Vector3(-10,0,16))
	if place.definition.is_storage:
		place.resources.set_category_quota(C.PLANK,15);place.resources.set_category_quota(C.SIMPLE_CLOTHING,10)
	place.resources.add(R.WOOL_CLOTHING,units)
	return place
func walk(actor: Node) -> void:
	for step in 12000:
		if not actor.clothing._active:break
		actor.view._physics_process(.05)
func building_sources() -> void:
	for type in [T.STORAGE,T.TOWN_CENTER,T.TAILOR_WORKSHOP]:
		var world=F.create(self);var actor=world.resident_runtimes[0]
		var place: RefCounted
		if type==T.TOWN_CENTER:
			place=world.warehouse_data;place.resources.set_category_quota(C.PLANK,50);place.resources.set_category_quota(C.SIMPLE_CLOTHING,10);place.resources.add(R.WOOL_CLOTHING,1)
		else:place=source(world,type)
		check(actor.decision.collect_actions(false).any(func(a):return a.id=="CLOTHING"),"Personal task joins UtilitySelector candidates")
		var busy=Intent.new(Intent.Type.NONE,&"busy",Vector2.ZERO,50,false);actor.intents.submit(busy)
		check(not actor.clothing.start() and place.resources.get_reserved_out(R.WOOL_CLOTHING)==0,"Busy accepted work never interrupted or reserved")
		actor.intents.clear_completed(busy)
		check(actor.clothing.start() and actor.intents.forced_priority==0 and place.resources.get_reserved_out(R.WOOL_CLOTHING)==1,"Ordinary start reserves one before movement")
		var old=actor.clothing._intent
		actor.clothing._arrived(old)
		check(actor.data.equipment.item()==null and place.resources.get_amount(R.WOOL_CLOTHING)==1,"Fake distant arrival cannot grant clothing")
		check(actor.clothing.start(),"Can retry after rejected arrival")
		walk(actor)
		check(actor.data.equipment.item()!=null and actor.data.equipment.item().resource_type==R.WOOL_CLOTHING and actor.data.equipment.item().durability==1 and place.resources.get_amount(R.WOOL_CLOTHING)==0,"Physical courier approach transfers exactly one to equipment")
		actor.clothing._arrived(old);actor.clothing.cancel()
		check(place.resources.get_reserved_out(R.WOOL_CLOTHING)==0 and actor.data.inventory.amount==0 and not actor.view.is_inside_building(place.id),"Late arrival cannot duplicate; personal action releases courier and leaves cargo empty")
		world.free()
func ground_and_priority() -> void:
	var world=F.create(self);var actor=world.resident_runtimes[0]
	var ground=Stacks.create(world.ground_resources,R.WOOL_CLOTHING,3,actor.view.get_sim_position()+Vector2(60,0))
	var place=source(world,T.TAILOR_WORKSHOP,1)
	check(actor.clothing.offer().source.kind==Source.Kind.CONTAINER,"Available building beats nearer ground")
	world.navigation.add_blocker(&"separating_wall",Rect2(-64,10,128,1))
	check(actor.clothing.offer().source.kind==Source.Kind.GROUND,"Unreachable available building does not block reachable ground fallback")
	world.navigation.remove_blocker(&"separating_wall")
	check(actor.clothing.offer().source.kind==Source.Kind.CONTAINER,"Navigation revision restores building preference")
	place.definition.logistics_flow[R.WOOL_CLOTHING]["export"]=false
	check(actor.clothing.offer().source.kind==Source.Kind.GROUND,"Forbidden production export never supplies personal clothing")
	place.definition.logistics_flow[R.WOOL_CLOTHING]["export"]=true
	place.resources.reserve_out(R.WOOL_CLOTHING,1)
	check(actor.clothing.offer().source.kind==Source.Kind.GROUND,"Reserved container stock permits ground fallback")
	check(actor.clothing.start(),"Real ground stack can be claimed")
	var other=world.resident_runtimes[1]
	check(ground.reserve(&"foreign",1),"Another stack owner reserves a distinct unit")
	var id: StringName=ground.id
	walk(actor)
	check(actor.data.equipment.item()!=null and ground.id==id and ground.amount==2 and ground.reserved_amount(&"foreign")==1,"Personal pickup consumes one, keeps stack identity and foreign reserve")
	ground.release(&"foreign")
	place.resources.release_out(R.WOOL_CLOTHING,1)
	other.data.equipment.set_item(Equipment.Slot.CLOTHING,Item.new(R.WOOL_CLOTHING,432))
	check(not other.clothing.has_action(),"Exactly10 percent creates no task")
	other.data.equipment.advance(1)
	check(other.clothing.has_action(),"Below10 percent creates replacement task")
	world.free()
func ground_cancel_and_reentry() -> void:
	var world=F.create(self);var actor=world.resident_runtimes[0]
	var drop=Stacks.create(world.ground_resources,R.WOOL_CLOTHING,2,actor.view.get_sim_position()+Vector2(75,0))
	check(actor.clothing.start(),"Ground task starts with exact owner")
	var previous=actor.clothing._intent
	world.ground_resources.remove_drop(drop)
	actor.clothing._arrived(previous)
	check(not actor.clothing._active and actor.data.equipment.item()==null,"Ground removal cancels, stale arrival creates no item")
	world.free()
	world=F.create(self);actor=world.resident_runtimes[0]
	var place=source(world,T.TAILOR_WORKSHOP,2)
	var interrupt=func(_r):actor.intents.force_set_intent(Intent.new(Intent.Type.NONE,&"reserve_callback",Vector2.ZERO,100,false),100)
	place.resources.reservations_changed.connect(interrupt,CONNECT_ONE_SHOT)
	check(not actor.clothing.start() and place.resources.get_amount(R.WOOL_CLOTHING)==2 and place.resources.get_reserved_out(R.WOOL_CLOTHING)==0,"Forced cancel inside reserve rolls back exact obligation")
	actor.intents.clear_completed(actor.intents.current_intent)
	check(actor.clothing.start(),"Can start a new generation after reserve rollback")
	var forced=Intent.new(Intent.Type.NONE,&"pickup_callback",Vector2.ZERO,100,false)
	place.resources.changed.connect(func(_r,_n):actor.intents.force_set_intent(forced,100),CONNECT_ONE_SHOT)
	walk(actor)
	check(actor.data.equipment.item()!=null and place.resources.get_amount(R.WOOL_CLOTHING)==1 and place.resources.get_reserved_out(R.WOOL_CLOTHING)==0 and actor.intents.current_intent==forced,"Reentrant pickup commits one item and cannot overwrite newer forced intent")
	actor.clothing.cancel()
	check(place.resources.get_amount(R.WOOL_CLOTHING)==1,"Second cleanup cannot issue another item")
	world.free()
func negative_availability() -> void:
	var world=F.create(self);var actor=world.resident_runtimes[0];var place=source(world,T.TAILOR_WORKSHOP,0)
	for i in 100:check(not actor.clothing.has_action(),"Empty unchanged source never creates a task or reservation")
	check(place.resources.get_reserved_out(R.WOOL_CLOTHING)==0,"Read-only miss does not reserve")
	place.resources.add(R.WOOL_CLOTHING,1)
	check(actor.clothing.has_action(),"New production output invalidates cached absence on next ordinary read")
	world.free()
func cancellation_and_races() -> void:
	for cause in ["forced","critical","demolition","reserve","removed","unregistered","actor"]:
		var world=F.create(self);var place=source(world,T.TAILOR_WORKSHOP,2);var actor=world.resident_runtimes[0]
		var old=Item.new(R.WOOL_CLOTHING,380);actor.data.equipment.set_item(Equipment.Slot.CLOTHING,old)
		check(actor.clothing.start(),"Replacement starts: "+cause)
		var stale=actor.clothing._intent;var data: RefCounted=actor.data
		match cause:
			"forced":actor.intents.force_set_intent(Intent.new(Intent.Type.MOVE_TO,&"player_test",Vector2(100,100),100,false),100)
			"critical":actor.decision._deciding=false;actor.data.hunger=100
			"demolition":world.change_construction_direction(place.id,true)
			"reserve":place.resources.release_out(R.WOOL_CLOTHING,1)
			"removed":world.logistics.remove_building(place.id)
			"unregistered":world.player_control.unregister_resident(actor.data.id)
			"actor":actor.view.free()
		actor.clothing.cancel();actor.clothing._arrived(stale)
		check(not actor.clothing._active and data.equipment.item()==old and place.resources.get_amount(R.WOOL_CLOTHING)==2 and place.resources.get_reserved_out(R.WOOL_CLOTHING)==0,"Cancel/stale callback preserve old gear and all stock: "+cause)
		world.free()
func last_unit_race() -> void:
	var world=F.create(self);var place=source(world);var first=world.resident_runtimes[0];var second=world.resident_runtimes[1]
	check(first.clothing.has_action() and second.clothing.has_action(),"Two reads may see one free unit")
	check(first.clothing.start() and not second.clothing.start(),"Last concrete unit claimed once")
	first.clothing.cancel()
	check(second.clothing.start(),"Cancelled own claim restores availability")
	second.data.equipment.set_item(Equipment.Slot.CLOTHING,Item.new(R.WOOL_CLOTHING,1))
	world.game_time.debug_skip_minutes(1)
	check(second.data.equipment.item()==null and second.clothing._active,"Wear to zero on route does not cancel accepted source")
	walk(second)
	check(second.data.equipment.item()!=null and place.resources.get_amount(R.WOOL_CLOTHING)==0,"Accepted task equips full replacement after old item expires")
	world.free()
func ui() -> void:
	var world=F.create(self);var actor=world.resident_runtimes[0];var other=world.resident_runtimes[1]
	world.resident_selection.select(actor.data);world.game_ui.info_panel.set_expanded(true);world.game_ui.info_panel.select_tab(&"inventory")
	await process_frame;await process_frame
	var card=world.game_ui.info_panel.resident_details
	check(world.game_ui.info_panel._tabs==[&"bio",&"work",&"relations",&"inventory"] and card.equipment_label.text=="Одежда: отсутствует" and card.equipment_quality.text=="Примитивные обмотки","Inventory tab preserves existing tabs and displays empty clothing")
	actor.data.equipment.set_item(Equipment.Slot.CLOTHING,Item.new(R.WOOL_CLOTHING))
	check(card.equipment_label.text=="Шерстяная одежда" and card.equipment_quality.text=="Простая одежда" and card.durability_bar.value==100,"Concrete title, quality and full visual durability")
	actor.data.equipment.advance(2160)
	check(card.durability_bar.value==50 and card.equipment_durability.text.contains("50%"),"Live minute wear updates same UI controls")
	world.resident_selection.select(other.data)
	check(card._equipment_view==other.data.equipment and card.equipment_label.text=="Одежда: отсутствует" and not actor.data.equipment.changed.is_connected(card._refresh_equipment),"Switching residents disconnects unrelated inventory")
	world.game_ui.info_panel.set_expanded(false)
	check(card._equipment_view==null and not other.data.equipment.changed.is_connected(card._refresh_equipment),"Closed inventory has no data-update subscription")
	world.game_ui.info_panel.set_expanded(true);world.player_control.unregister_resident(other.data.id)
	check(world.resident_selection.selected_resident==null and card._equipment_view==null,"Removing selected owner releases UI binding")
	world.free()
func activity_wear() -> void:
	var world=F.create(self);var actor=world.resident_runtimes[0]
	var equipment: RefCounted=actor.data.equipment
	# The shared fixture resets its clock after runtime setup; establish this test epoch.
	actor.clothing._minute(world.game_time.total_minutes)
	equipment.set_item(Equipment.Slot.CLOTHING,Item.new(R.WOOL_CLOTHING))
	var elapsed:=0
	for activity in preload("res://scripts/resident_activity.gd").Type.values():
		actor.data.activity=activity
		world.game_time.debug_skip_minutes(1);elapsed+=1
		actor.clothing._minute(world.game_time.total_minutes)
		check(equipment.item().remaining_minutes==4320-elapsed,"Every activity, including work and sleep, wears once per game minute")
	var now: int=world.game_time.total_minutes+100
	world.game_time.total_minutes=now;world.game_time.minute_changed.emit(now)
	check(equipment.item().remaining_minutes==4320-elapsed-100,"Controller catches a large elapsed interval exactly once")
	world.free()
func run() -> void:
	building_sources();ground_and_priority();cancellation_and_races();last_unit_race();ground_cancel_and_reentry();negative_availability();activity_wear();await ui()
	print("Clothing action: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
