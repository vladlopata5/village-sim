extends SceneTree
const Stock = preload("res://scripts/resource_container.gd")
const Catalog = preload("res://scripts/resource_catalog.gd")
const R = preload("res://scripts/resource_type.gd").Type
const C = preload("res://scripts/resource_category.gd").Type
const Surplus = preload("res://tests/test_warehouse_surplus.gd")
const Balance = preload("res://scripts/balance_config.gd")
const Priority = preload("res://scripts/logistics_priority.gd")
const Job = preload("res://scripts/haul_job.gd")

# Local metadata only. Reuse existing concrete enum values to exercise real logistics;
# LOG and PLANK share SIMPLE_FOOD here, never in the global gameplay catalog.
class GroupedStock extends Stock:
	func get_resource_category(resource: int) -> int:
		return C.SIMPLE_FOOD if resource in [R.LOG,R.PLANK] else Catalog.get_category(resource)

var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func stock(capacity: int = 20, quota: int = 10):
	var result = GroupedStock.new(&"grouped")
	check(result.configure_warehouse(capacity,{C.SIMPLE_FOOD:quota}),"Category configuration")
	return result

func container_checks() -> void:
	var c = stock()
	check(c.add(R.LOG,4) and c.add(R.PLANK,3),"Two concrete goods share one quota")
	check(c.get_capacity(R.LOG)==10 and c.get_category_quota(C.LOG)==0,"Concrete type query resolves metadata rather than reinterpreting its numeric ID as category")
	check(c.get_category_amount(C.SIMPLE_FOOD)==7 and c.get_category_contents(C.SIMPLE_FOOD)=={R.LOG:4,R.PLANK:3},"Aggregate derives from both concrete ledgers")
	var detached: Dictionary = c.get_category_contents(C.SIMPLE_FOOD)
	detached.clear()
	check(c.get_category_amount(C.SIMPLE_FOOD)==7,"Category view does not own stock")
	check(c.reserve_in(R.PLANK,2) and c.get_category_reserved_in(C.SIMPLE_FOOD)==2,"Concrete inbound joins category promises")
	check(c.get_available_free_capacity(R.LOG)==1 and c.get_available_free_capacity(R.PLANK)==1,"Both types see the same remaining place")
	var nested: Array = []
	var callback := func(_resource): nested.append(c.reserve_in(R.PLANK,1))
	c.reservations_changed.connect(callback,CONNECT_ONE_SHOT)
	check(c.reserve_in(R.LOG,1) and nested==[false] and not c.reserve_in(R.PLANK,1),"Committed aggregate prevents nested and competing overbooking")
	check(c.reserve_out(R.LOG,2) and c.get_available_free_capacity(R.LOG)==0,"Outbound does not create space")
	check(c.set_category_quota(C.SIMPLE_FOOD,0) and c.get_category_amount(C.SIMPLE_FOOD)==7,"Quota reduction preserves every good")
	check(c.add_reserved(R.LOG,1) and c.add_reserved(R.PLANK,2) and c.get_category_amount(C.SIMPLE_FOOD)==10,"Both previously confirmed types finish after quota reduction")
	check(c.get_category_reserved_in(C.SIMPLE_FOOD)==0 and not c.add(R.LOG,1),"Zero category quota blocks new arrivals")
	check(c.get_category_surplus(C.SIMPLE_FOOD)==8 and c.get_surplus_amount(R.LOG)==3 and c.get_surplus_amount(R.PLANK)==5,"One shared surplus, limited by each concrete unreserved stock")
	check(c.release_out(R.LOG,2) and c.get_category_surplus(C.SIMPLE_FOOD)==10,"Releasing outbound restores only actual surplus")
	var rev: int = c.quota_revision
	for invalid in [-1,99,null,true,"0",0.0]:
		check(not c.set_category_quota(invalid,1) and c.get_category_quota(invalid)==0 and c.quota_revision==rev,"Strict category validation, no numeric fallback")
	check(Catalog.get_category(R.LOG)==C.LOG and Catalog.get_category(R.PLANK)==C.PLANK,"Test metadata never changes the catalog")
	var full = stock(10)
	check(full.add(R.LOG,8) and full.set_category_quotas({C.SIMPLE_FOOD:2,C.STONE:8}),"Shared-capacity surplus fixture")
	check(full.reserve_in(R.STONE,2) and not full.reserve_in(R.STONE,1),"Physical cap includes other-category surplus and inbound")
	check(full.reserve_out(R.LOG,1) and full.get_available_free_capacity(R.STONE)==0,"Reserved outbound still occupies physical space")
	check(full.take_reserved(R.LOG,1) and full.get_available_free_capacity(R.STONE)==1,"Only physical pickup frees total room")
	check(not full.set_category_quotas({C.STONE:9}) and full.get_category_quota(C.STONE)==8,"Allocation sum is atomic")
	var restricted = stock()
	check(restricted.set_allowed_resource_types([R.LOG]) and restricted.add(R.LOG,1) and restricted.get_available_free_capacity(R.PLANK)==0 and not restricted.reserve_in(R.PLANK,1),"Category room cannot override concrete admission policy")
	var ordinary = Stock.new(&"production")
	ordinary.set_capacity(R.LOG,2)
	ordinary.set_capacity(R.PLANK,3)
	check(ordinary.add(R.LOG,2) and ordinary.add(R.PLANK,3) and not ordinary.set_category_quota(C.SIMPLE_FOOD,10) and ordinary.get_capacity(R.PLANK)==3 and ordinary.get_allocated_capacity()==5,"Production buffers keep per-good limits")
	var urgency = stock()
	urgency.add(R.LOG,4)
	urgency.add(R.PLANK,3)
	urgency.reserve_in(R.PLANK,1)
	check(is_equal_approx(Priority.import_priority(urgency,R.LOG),20.0*Balance.DEFAULT_BUILDING_LOGISTICS_WEIGHT*Balance.IMPORT_MULTIPLIER) and is_equal_approx(Priority.import_priority(urgency,R.LOG),Priority.import_priority(urgency,R.PLANK)),"Import priority uses joint stock and inbound, not each leaf")
	urgency.reserve_out(R.LOG,1)
	check(is_equal_approx(Priority.export_priority(urgency,R.LOG),60.0*Balance.DEFAULT_BUILDING_LOGISTICS_WEIGHT*Balance.EXPORT_MULTIPLIER) and is_equal_approx(Priority.export_priority(urgency,R.LOG),Priority.export_priority(urgency,R.PLANK)),"Export priority uses joint stock and outbound")

func logistics_checks() -> void:
	var helper = Surplus.new()
	var f: Dictionary = helper.fixture()
	# Replace only these test containers, before subscribing the real service.
	f.s.assignment_control = null
	for building in [f.a,f.b,f.base]: f.s.remove_building(building.id)
	f.s.assignment_control = f.player
	f.a.resources = stock(100,10)
	f.b.resources = stock(100,10)
	f.base.resources = stock(100,0)
	for building in [f.a,f.b,f.base]: f.s.register_building(building)
	check(f.a.resources.add(R.LOG,8) and f.a.resources.add(R.PLANK,2) and f.a.resources.set_category_quota(C.SIMPLE_FOOD,8),"Neither leaf individually exceeds quota, joint surplus is two")
	check(f.s.surplus_available(f.a,R.LOG)==2 and f.s.surplus_available(f.a,R.PLANK)==2,"Both concrete goods may satisfy the one shared excess")
	var first = f.s._claim_delivery(f.first,helper.offer(f.a,f.b,R.LOG))
	var second = f.s._claim_delivery(f.second,helper.offer(f.a,f.b,R.PLANK))
	check(first!=null and second!=null and first.resource_type==R.LOG and second.resource_type==R.PLANK,"Real transport claims preserve both concrete types")
	check(f.s.surplus_available(f.a,R.LOG)==0 and f.s.surplus_available(f.a,R.PLANK)==0 and f.s._claim_delivery(f.first,helper.offer(f.a,f.b,R.PLANK))==null,"All outbound promises share the same surplus ceiling")
	if first!=null and second!=null:
		check(f.s.surplus_job_valid(first) and f.s.surplus_job_valid(second),"Each own unit remains valid with the other type reserved")
		for pair in [[first,f.first],[second,f.second]]:
			var job = pair[0]
			var worker = pair[1]
			check(worker.inventory.receive(job.resource_type,1,f.s.sources.pickup.bind(job.source_ref,job.resource_type,job.id)),"Real pickup transfers ownership once")
			job.state = Job.State.CARRYING
			check(worker.inventory.resource_type==job.resource_type and worker.inventory.deliver(job.resource_type,1,f.s.deliver_inbound.bind(job)),"Real inventory delivery preserves concrete identity")
			job.state = Job.State.COMPLETED
			f.s.finish_job(job)
		check(f.a.resources.get_category_amount(C.SIMPLE_FOOD)==8 and f.b.resources.get_category_contents(C.SIMPLE_FOOD)=={R.LOG:1,R.PLANK:1},"Two transfers conserve exact goods")
		check(f.a.resources.get_amount(R.LOG)+f.b.resources.get_amount(R.LOG)==8 and f.a.resources.get_amount(R.PLANK)+f.b.resources.get_amount(R.PLANK)==2,"Each concrete resource ledger balances")
		check(f.s.sources._claims.is_empty() and f.s._inbound.is_empty() and not f.s.has_available_job(f.first.id),"No leftover reservations or cyclic return transport")
	check(f.a.resources.set_category_quota(C.SIMPLE_FOOD,7),"Lowering quota exposes fresh excess")
	var cancelled = f.s._claim_delivery(f.first,helper.offer(f.a,f.b,R.PLANK))
	check(cancelled!=null,"Fresh category excess is discoverable")
	if cancelled!=null: f.s.cancel_job(cancelled)
	check(f.a.resources.get_category_reserved_out(C.SIMPLE_FOOD)==0 and f.b.resources.get_category_reserved_in(C.SIMPLE_FOOD)==0 and f.s.sources._claims.is_empty(),"Cancellation releases the exact concrete promises")
	# A competing type fills the recipient's last joint slot.
	f.b.resources.set_category_quota(C.SIMPLE_FOOD,3)
	check(f.b.resources.reserve_in(R.LOG,1),"Other concrete type claims final category space")
	check(f.s._claim_delivery(f.first,helper.offer(f.a,f.b,R.PLANK))==null and f.a.resources.get_reserved_out(R.PLANK)==0,"Recipient category rejection leaves no source reservation")
	f.b.resources.release_in(R.LOG,1)
	helper.free()

func run() -> void:
	container_checks()
	logistics_checks()
	print("Category quotas: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
