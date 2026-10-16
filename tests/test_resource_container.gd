extends SceneTree
const LocalResources = preload("res://scripts/resource_container.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const Balance = preload("res://scripts/balance_config.gd")
const R = ResourceType.Type
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func key(code: Key, echo: bool = false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.shift_pressed = true
		event.pressed = pressed
		event.echo = echo
		root.push_input(event, true)
func make_scene() -> Node:
	var scene = preload("res://tests/domain_world.gd").instantiate()
	root.add_child(scene)
	preload("res://tests/resident_test_setup.gd").isolate_first(scene)
	preload("res://tests/resident_test_setup.gd").unbind_work(scene)
	scene.kitchen_data.resources.add(ResourceType.Type.FOOD, 3)
	scene.game_time.set_process(false)
	scene.resident_runtimes[0].view.set_process(false)
	return scene
func _run() -> void:
	check_warehouse_quotas()
	var stock = LocalResources.new(&"test_place")
	stock.set_capacity(ResourceType.Type.FOOD, 20)
	check(stock.get_amount(ResourceType.Type.FOOD) == 0, "Uninitialized resource is zero")
	check(stock.owner_id == &"test_place", "Container identifies its owner")
	var other_container = LocalResources.new(&"other_place")
	other_container.set_capacity(ResourceType.Type.FOOD, 30)
	other_container.add(ResourceType.Type.FOOD, 20)
	check(stock.get_amount(ResourceType.Type.FOOD) == 0, "Other place resources never appear in this container")
	stock.add(ResourceType.Type.FOOD, 10)
	check(stock.has_resource(ResourceType.Type.FOOD, 10) and not stock.has_resource(ResourceType.Type.FOOD, 11), "Presence check is local")
	check(stock.try_take(ResourceType.Type.FOOD, 1) and stock.get_amount(ResourceType.Type.FOOD) == 9, "Consumes exactly one resource")
	check(not stock.try_take(ResourceType.Type.FOOD, 10) and stock.get_amount(ResourceType.Type.FOOD) == 9, "Insufficient consumption is atomic")
	stock.add(ResourceType.Type.FOOD, -5)
	check(not stock.try_take(ResourceType.Type.FOOD, -1) and not stock.try_take(ResourceType.Type.FOOD, 0) and stock.get_amount(ResourceType.Type.FOOD) == 9, "Invalid operations cannot create or remove stock")
	var scene = preload("res://tests/need_test_setup.gd").make_scene(self, 360, 1)
	var r = scene.resident_runtimes[0]
	r.data.hunger = 80
	r.decision.request_decision()
	stock = scene.kitchen_data.resources
	check(stock.get_amount(ResourceType.Type.FOOD) == 1 and stock.get_available_amount(ResourceType.Type.FOOD) == 0, "Food belongs to kitchen and is promised to this resident")
	check(not stock.try_take(ResourceType.Type.FOOD, 1), "Other consumer cannot take promised meal")
	r.intents.force_set_intent(preload("res://scripts/resident_intent.gd").new())
	check(stock.get_reserved_out(ResourceType.Type.FOOD) == 0 and stock.get_amount(ResourceType.Type.FOOD) == 1, "Cancellation before consumption releases meal without losing food")
	r.decision.request_decision()
	r.view._process(20)
	check(stock.get_amount(ResourceType.Type.FOOD) == 0 and r.data.activity == Activity.Type.EATING and scene.kitchen_data.resources.get_amount(ResourceType.Type.FOOD) == 0, "Consume locally at start; UI reads actual stock")
	scene.game_time.debug_skip_minutes(30)
	check(r.data.hunger == 20 and stock.get_reserved_out(ResourceType.Type.FOOD) == 0, "Paid meal has gradual benefit and settled reservation")
	scene.free()
	# Empty Kitchen falls back to real warehouse stock; later FOOD cannot retarget a trip.
	scene = preload("res://tests/need_test_setup.gd").make_scene(self,360,0)
	r = scene.resident_runtimes[0]
	r.data.hunger = 80
	r.decision.request_decision()
	check(r.data.activity == Activity.Type.MOVING and r.needs._food_building == scene.warehouse_data and scene.warehouse_data.resources.get_amount(ResourceType.Type.FOOD) == 10,"Other-building meal reserves real stock, no remote benefit")
	var committed = r.intents.current_intent
	scene.resident_selection.select(r.data)
	key(KEY_8)
	check(r.intents.current_intent == committed and scene.kitchen_data.resources.get_amount(ResourceType.Type.FOOD) == 1 and scene.kitchen_data.resources.get_reserved_out(ResourceType.Type.FOOD) == 0,"New Kitchen FOOD does not redirect committed warehouse trip")
	r.view._process(20)
	scene.game_time.debug_skip_minutes(10)
	check(r.data.hunger == 20 and scene.warehouse_data.resources.get_amount(ResourceType.Type.FOOD) == 9 and scene.kitchen_data.resources.get_amount(ResourceType.Type.FOOD) == 1,"Actual warehouse arrival consumes one and grants original ten-minute benefit")
	r.data.hunger = 80
	r.decision.request_decision()
	check(r.needs._food_building == scene.kitchen_data and scene.kitchen_data.resources.get_reserved_out(ResourceType.Type.FOOD) == 1,"Next meal prefers newly stocked Kitchen")
	r.view._process(20)
	scene.game_time.debug_skip_minutes(30)
	check(r.data.hunger == 20 and scene.kitchen_data.resources.get_amount(ResourceType.Type.FOOD) == 0 and scene.warehouse_data.resources.get_amount(ResourceType.Type.FOOD) == 9,"Kitchen meal uses only its own actual portion")
	scene.free()
	print("Local resource checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)

func check_warehouse_quotas() -> void:
	var stock = LocalResources.new(&"warehouse")
	check(not stock.is_warehouse() and stock.shared_capacity == -1,"Ordinary containers do not opt into shared capacity")
	check(not stock.set_quota(R.LOG,1),"Quota edits require explicit warehouse setup")
	var events: Array = []
	stock.quotas_changed.connect(func(): events.append([stock.quota_revision,stock.get_allocated_capacity(),stock.get_capacity(R.LOG),stock.get_capacity(R.STONE)]))
	check(stock.configure_warehouse(Balance.WAREHOUSE_SHARED_CAPACITY,Balance.STORAGE_RESOURCE_QUOTAS),"Approved warehouse preset fits shared capacity")
	check(stock.shared_capacity == 100 and stock.get_allocated_capacity() == 100 and stock.get_shared_free_capacity() == 100,"Shared and allocated capacities are distinct from stock")
	check(stock.get_capacity(R.LOG)==40 and stock.get_capacity(R.STONE)==20 and stock.get_capacity(R.PLANK)==25 and stock.get_capacity(R.FOOD)==15,"Storage preset contains all approved quotas")
	check(not stock.configure_warehouse(50,{}) and not stock.set_capacity(R.LOG,500),"Setup and legacy setters cannot bypass warehouse invariants")
	check(stock.set_quotas({R.LOG:20,R.STONE:40}) and events.back()==[2,100,20,40],"Atomic reallocation notifies after the entire quota map is committed")
	check(stock.set_quota(R.LOG,10) and stock.get_allocated_capacity()==90,"Unallocated capacity is not redistributed")
	var revision: int = stock.quota_revision
	for invalid in [{R.LOG:-1},{R.LOG:1.5},{R.LOG:true},{R.LOG:"10"},{99:1},{"LOG":1},{R.LOG:100,R.STONE:0}]:
		check(not stock.set_quotas(invalid) and stock.get_capacity(R.LOG)==10 and stock.get_capacity(R.STONE)==40 and stock.quota_revision==revision,"Invalid quota patch leaves all quotas and notification revision unchanged")
	check(stock.set_quotas({}) and stock.set_quota(R.LOG,10) and stock.quota_revision==revision,"No-op quota updates do not notify")
	var other = LocalResources.new(&"other")
	check(other.configure_warehouse(100,Balance.STORAGE_RESOURCE_QUOTAS) and other.get_capacity(R.LOG)==40,"Containers copy presets rather than sharing mutable settings")
	check(other.set_quota(R.LOG,0) and stock.get_capacity(R.LOG)==10 and Balance.STORAGE_RESOURCE_QUOTAS[R.LOG]==40,"Quota edits do not change other warehouses or balance constants")
	var town = LocalResources.new(&"town")
	check(town.configure_warehouse(100,Balance.TOWN_CENTER_RESOURCE_QUOTAS),"Town Center preset fits")
	check(town.get_capacity(R.LOG)==10 and town.get_capacity(R.STONE)==10 and town.get_capacity(R.PLANK)==60 and town.get_capacity(R.FOOD)==20,"Town Center preset preserves starting resource space")
	check(town.add(R.PLANK,60) and town.add(R.FOOD,20) and town.get_total_amount()==80,"Existing Town Center starting stock fits prepared preset")
	for invalid_capacity in [-1,1.5,true,"100"]:
		var invalid = LocalResources.new(&"invalid")
		check(not invalid.configure_warehouse(invalid_capacity,{}) and not invalid.is_warehouse(),"Invalid shared capacity does not activate warehouse mode")
	var restricted = LocalResources.new(&"restricted")
	restricted.set_allowed_resource_types([R.LOG])
	check(not restricted.configure_warehouse(100,{R.FOOD:1}) and not restricted.configure_warehouse(100,{R.LOG:101}),"Setup validates allowed resources and quota sum before changing mode")
	restricted.set_capacity(R.LOG,10)
	restricted.add(R.LOG,2)
	restricted.reserve_in(R.LOG,1)
	check(not restricted.configure_warehouse(2,{R.LOG:2}) and restricted.get_capacity(R.LOG)==10 and not restricted.is_warehouse(),"Activation cannot shrink physical space beneath stock plus promises")
	check(restricted.configure_warehouse(3,{}) and restricted.add_reserved(R.LOG,1) and restricted.try_take(R.LOG,1),"Existing stock and inbound survive activation below individual quota; omitted quota is zero and still allows withdrawal")
	check(not restricted.set_allowed_resource_types([R.FOOD]) and restricted.allows_resource(R.LOG),"Omitted quota cannot hide physical stock through allowed-resource edits")
	var full = LocalResources.new(&"surplus")
	full.configure_warehouse(100,{R.PLANK:30,R.STONE:70})
	check(full.add(R.PLANK,30) and full.add(R.STONE,70),"Each resource unit takes one shared place")
	check(full.set_quotas({R.PLANK:10,R.STONE:90}) and full.get_total_amount()==100,"Lower quota keeps surplus stock physically present")
	check(full.get_available_free_capacity(R.STONE)==0 and not full.add(R.STONE,1) and not full.reserve_in(R.STONE,1),"Surplus blocks new arrivals even when the arriving resource has quota room")
	check(full.reserve_out(R.PLANK,20) and full.get_shared_free_capacity()==0,"Outgoing reservations do not free physical space")
	check(full.take_reserved(R.PLANK,1) and full.get_shared_free_capacity()==1 and full.get_available_free_capacity(R.STONE)==1,"Physical pickup frees shared space")
	check(full.reserve_in(R.STONE,1) and full.get_shared_free_capacity()==1 and full.get_available_free_capacity(R.STONE)==0,"Physical free space differs from room available for a new reservation")
	check(full.add_reserved(R.STONE,1) and full.get_total_amount()==100 and full.get_total_reserved_in()==0,"Own inbound fills its promised slot without requiring another free place")
	var ordinary = LocalResources.new(&"production")
	ordinary.set_capacity(R.LOG,2)
	ordinary.set_capacity(R.PLANK,2)
	ordinary.add(R.LOG,2)
	ordinary.add(R.PLANK,2)
	check(ordinary.get_total_amount()==4 and not ordinary.is_warehouse() and not ordinary.set_quota(R.LOG,0),"Production buffers retain independent resource capacities")
	ordinary.reserve_in(R.FOOD,1)
	check(not ordinary.set_capacity(R.LOG,1) and ordinary.get_free_capacity(R.LOG)==0,"Production capacity cannot shrink below physical stock")
	for connection in stock.quotas_changed.get_connections(): stock.quotas_changed.disconnect(connection.callable)
