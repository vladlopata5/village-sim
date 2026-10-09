extends SceneTree
const Sources = preload("res://scripts/resource_sources.gd")
const Ref = preload("res://scripts/resource_source_ref.gd")
const DropService = preload("res://scripts/ground_resources.gd")
const Instance = preload("res://scripts/building_instance.gd")
const Def = preload("res://scripts/building_definition.gd")
const Types = preload("res://scripts/building_type.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var clock = preload("res://scripts/game_time.gd").new()
	root.add_child(clock)
	clock.set_process(false)
	var ground = DropService.new()
	root.add_child(ground)
	ground.setup(clock)
	var sources = Sources.new()
	sources.bind_ground(ground)
	var saw = Instance.new(&"saw",Def.for_type(Types.SAWMILL),Vector2(10,0))
	var storage = Instance.new(&"storage",Def.for_type(Types.STORAGE),Vector2(50,0))
	saw.resources.set_capacity(R.LOG,12)
	saw.resources.set_capacity(R.PLANK,12)
	storage.resources.set_capacity(R.PLANK,35)
	saw.resources.add(R.LOG,2)
	saw.resources.add(R.PLANK,2)
	sources.buildings = {saw.id:saw,storage.id:storage}
	var reference = Ref.new(Ref.Kind.CONTAINER,saw.id)
	check(sources.resolve(reference)==saw and sources.point(reference)==saw.position,"Stable reference resolves live container truth")
	check(not sources.available(reference,R.LOG) and not sources.reserve(reference,R.LOG,&"builder") and not sources.reserve(reference,R.LOG,&"sawyer_b") and not sources.reserve(reference,R.LOG,&"porter"),"Sawmill LOG external_export=false protects against every external workflow")
	check(sources.available(reference,R.PLANK) and sources.reserve(reference,R.PLANK,&"a") and sources.reserve(reference,R.PLANK,&"b"),"Exportable PLANK permits distinct container reservations")
	check(not sources.reserve(reference,R.PLANK,&"c") and saw.resources.get_reserved_out(R.PLANK)==2,"No container over-reservation")
	check(not sources.reserved(reference,R.PLANK,&"wrong") and not sources.pickup(reference,R.PLANK,&"wrong"),"Source ownership revalidated before pickup")
	check(sources.pickup(reference,R.PLANK,&"a") and sources.reserved(reference,R.PLANK,&"b"),"Pickup consumes one reservation without invalidating another")
	sources.release(reference,R.PLANK,&"a")
	check(saw.resources.get_reserved_out(R.PLANK)==1,"Stale owner release preserves another reservation")
	sources.release(reference,R.PLANK,&"b")
	check(saw.resources.get_reserved_out(R.PLANK)==0 and saw.resources.get_amount(R.PLANK)==1,"Release preserves physical stock")
	var drop = ground.create_drop(R.LOG,2,Vector2.ZERO)
	var loose = Ref.new(Ref.Kind.GROUND,drop.id)
	check(sources.available(loose,R.LOG) and not sources.available(loose,R.PLANK),"Ground resource type resolved from domain")
	check(sources.reserve(loose,R.LOG,&"sawyer") and not sources.reserve(loose,R.LOG,&"lumberjack") and not sources.reserve(loose,R.LOG,&"porter"),"Ground exclusive claim globally shared, no workflow ownership")
	check(sources.pickup(loose,R.LOG,&"sawyer") and drop.amount==1 and drop.reservation_owner_id.is_empty(),"One unit ground pickup releases whole-drop claim")
	check(sources.reserve(loose,R.LOG,&"porter"),"Next competing workflow can claim remaining Ground")
	ground._on_minute(drop.created_at+drop.lifetime)
	check(sources.resolve(loose)==null and drop.reservation_owner_id.is_empty() and not sources.pickup(loose,R.LOG,&"porter"),"Despawn clears claim and invalidates reference")
	var near = ground.create_drop(R.PLANK,1,Vector2(2,1))
	var matches: Array = sources.find(R.PLANK,Vector2.ZERO,Vector2(0,15))
	check(matches[0].id==near.id,"Shared selection compares full route rather than absolute container priority")
	sources.route_available = func(_a,_b): return false
	check(sources.find(R.PLANK,Vector2.ZERO,Vector2(0,15)).is_empty(),"Unreachable sources filtered centrally")
	sources.route_available = Callable()
	check(sources.storage_destinations(reference,R.PLANK,Vector2.ZERO)==[storage],"Worker output destinations are BUILT accepting Storage")
	storage = Instance.new(&"storage",Def.for_type(Types.STORAGE),Vector2(50,0),Instance.State.UNDER_CONSTRUCTION)
	sources.buildings[storage.id] = storage
	check(sources.storage_destinations(reference,R.PLANK,Vector2.ZERO).is_empty(),"Construction is not an ordinary destination")
	ground.free()
	clock.free()
	print("Resource sources: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
