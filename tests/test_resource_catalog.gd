extends SceneTree
const Catalog = preload("res://scripts/resource_catalog.gd")
const Categories = preload("res://scripts/resource_category.gd")
const Resources = preload("res://scripts/resource_type.gd")
const R = Resources.Type
const C = Categories.Type
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)

func run() -> void:
	check(R.FOOD==0 and R.LOG==1 and R.PLANK==2 and R.STONE==3 and R.size()==4,"Concrete IDs and registered goods stay unchanged")
	var names := {R.FOOD:"FOOD",R.LOG:"Бревно",R.PLANK:"Доски",R.STONE:"Камень"}
	var groups := {R.FOOD:C.SIMPLE_FOOD,R.LOG:C.LOG,R.PLANK:C.PLANK,R.STONE:C.STONE}
	for resource: int in R.values():
		var definition := Catalog.get_definition(resource)
		check(definition.id==resource and definition.category==groups[resource],"Each concrete type keeps its ID and one category")
		check(Catalog.get_category(resource)==groups[resource] and Catalog.types_in_category(groups[resource])==[resource],"Grouping returns concrete types rather than replacing their identity")
		check(Catalog.get_display_name(resource)==names[resource] and Resources.display_name(resource)==names[resource],"Catalog is the single source of unchanged display names")
		check(Catalog.is_ready_food(resource)==(resource==R.FOOD) and Catalog.get_food_quality(resource)==(Catalog.FoodQuality.SIMPLE if resource==R.FOOD else Catalog.FoodQuality.NONE),"Only legacy FOOD is ready simple food")
		check(Catalog.supports_quantity(resource),"All currently registered types remain interchangeable quantity goods")
		check(definition.is_read_only(),"Public definitions are read-only")
		var detached := definition.duplicate()
		detached.category=Categories.INVALID
		detached.display_name="Changed copy"
		check(Catalog.get_category(resource)==groups[resource] and Catalog.get_display_name(resource)==names[resource],"Editing a detached definition cannot change catalog metadata")
		var members := Catalog.types_in_category(groups[resource])
		members.clear()
		check(Catalog.types_in_category(groups[resource])==[resource],"Callers own membership arrays; clearing them never edits the catalog")
	check(Categories.display_name(C.SIMPLE_FOOD)=="Простая еда","Category has its own presentation name")
	for unknown: Variant in [-1,4,999,null,false,0.0,"0",[],{}]:
		check(Catalog.get_definition(unknown).is_empty() and Catalog.get_category(unknown)==Categories.INVALID and Catalog.get_display_name(unknown).is_empty(),"Unknown or non-integer ID never falls back to a valid good/category")
		check(not Catalog.is_ready_food(unknown) and not Catalog.supports_quantity(unknown) and Catalog.get_food_quality(unknown)==Catalog.FoodQuality.NONE,"Unknown metadata is explicitly unavailable")
		check(Catalog.types_in_category(unknown).is_empty() and Categories.display_name(unknown).is_empty(),"Unknown category has no implied concrete members")
	# Exercise the old dynamic-call fallback without an invalid enum literal.
	var legacy_display_name: Callable = Resources.display_name
	check(legacy_display_name.call(-1)=="Ресурс","Old display-name fallback stays compatible")
	# Local metadata fixture only: no game enum extension or catalog registration.
	var local_definitions := {1000:{"id":1000,"category":C.SIMPLE_FOOD},1001:{"id":1001,"category":C.SIMPLE_FOOD},1002:{"id":1002,"category":C.LOG}}
	check(Catalog._types_in_category(local_definitions,C.SIMPLE_FOOD)==[1000,1001],"Membership algorithm accepts multiple concrete definitions in one category")
	check(Catalog.get_definition(1000).is_empty() and Catalog.types_in_category(C.SIMPLE_FOOD)==[R.FOOD],"Fixture definitions never register as production goods")
	quantity_compatibility()
	food_compatibility()
	print("Resource catalog: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func quantity_compatibility() -> void:
	var balance = preload("res://scripts/balance_config.gd")
	check(balance.STORAGE_CATEGORY_QUOTAS=={C.LOG:40,C.STONE:20,C.PLANK:25,C.SIMPLE_FOOD:15} and balance.TOWN_CENTER_CATEGORY_QUOTAS=={C.LOG:10,C.STONE:10,C.PLANK:60,C.SIMPLE_FOOD:20},"Existing four category warehouse quotas are unchanged")
	var building = preload("res://scripts/building_instance.gd").new(&"catalog_store",preload("res://scripts/building_definition.gd").for_type(preload("res://scripts/building_type.gd").Type.STORAGE))
	check(building.resources.configure_warehouse(100,balance.STORAGE_CATEGORY_QUOTAS) and building.resources.add(R.LOG,2),"Warehouse category preset preserves concrete stock")
	var sources = preload("res://scripts/resource_sources.gd").new()
	sources.buildings={building.id:building}
	var source_ref = preload("res://scripts/resource_source_ref.gd").new(preload("res://scripts/resource_source_ref.gd").Kind.CONTAINER,building.id)
	check(sources.reserve(source_ref,R.LOG,&"catalog_haul") and building.resources.get_reserved_out(R.LOG)==1 and building.resources.get_reserved_out(R.FOOD)==0,"Reservation still belongs to concrete LOG, not an aggregate category")
	var job = preload("res://scripts/haul_job.gd").new(&"catalog_haul",building.id,&"catalog_receiver",R.LOG,1,"catalog_worker")
	job.source_ref=source_ref
	var inventory = preload("res://scripts/resident_inventory.gd").new()
	check(inventory.receive(job.resource_type,1,sources.pickup.bind(job.source_ref,job.resource_type,job.id)) and inventory.resource_type==R.LOG and inventory.amount==1 and building.resources.get_amount(R.LOG)==1,"SourceRef and cargo transfer preserve concrete type and quantity")
	var receiver = preload("res://scripts/resource_container.gd").new(&"catalog_receiver")
	receiver.set_capacity(R.LOG,12)
	check(receiver.reserve_in(R.LOG,1) and inventory.deliver(R.LOG,1,receiver.add_reserved.bind(R.LOG,1)) and receiver.get_amount(R.LOG)==1 and inventory.amount==0,"Delivery consumes the owned reservation without changing resource identity")
	var drop = preload("res://scripts/ground_resource.gd").new(R.STONE,3,Vector2.ZERO,0)
	check(drop._configure_cell(Vector2i.ZERO,Vector2.ZERO) and drop.capacity==4 and drop.reserve(&"a") and drop.reserve(&"b"),"STONE keeps capacity four and independent quantity claims")
	check(drop._take_reserved(&"a",1) and drop.amount==2 and drop.reserved_amount(&"b")==1 and drop.resource_type==R.STONE,"Partial pickup preserves the other owner's concrete stack reservation")

func food_compatibility() -> void:
	var world = preload("res://tests/need_test_setup.gd").make_scene(self,360,1)
	world.game_logger.console_enabled=false
	var actor = world.resident_runtimes[0]
	actor.decision._deciding=true
	actor.intents.abort_current(actor.intents.current_intent)
	actor.data.hunger=80
	check(actor.needs.try_eat(10000) and actor.needs._meal_selection.concrete_type==R.FOOD,"Existing Needs continues to reserve concrete FOOD")
	actor.view._process(20)
	check(world.kitchen_data.resources.get_amount(R.FOOD)==0 and world.kitchen_data.resources.get_reserved_out(R.FOOD)==0 and actor.data.activity==preload("res://scripts/resident_activity.gd").Type.EATING,"Real meal still consumes one FOOD on arrival")
	world.game_time.debug_skip_minutes(30)
	check(actor.data.hunger==20,"Existing paid meal restores hunger by the same amount")
	world.free()
