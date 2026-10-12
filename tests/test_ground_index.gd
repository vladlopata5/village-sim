extends SceneTree
const Ground = preload("res://scripts/ground_resources.gd")
const Drop = preload("res://scripts/ground_resource.gd")
const Sources = preload("res://scripts/resource_sources.gd")
const Ref = preload("res://scripts/resource_source_ref.gd")
const R = preload("res://scripts/resource_type.gd").Type
class CountedGround extends "res://scripts/ground_resources.gd":
	var lookups := 0
	func get_by_id(id: StringName) -> Drop:
		lookups+=1
		return super.get_by_id(id)
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func run() -> void:
	var clock=preload("res://scripts/game_time.gd").new()
	root.add_child(clock)
	clock.set_process(false)
	var ground=CountedGround.new()
	root.add_child(ground)
	ground.setup(clock)
	var sources=Sources.new()
	sources.bind_ground(ground)
	ground.added.connect(func(drop): check(ground.get_by_id(drop.id)==drop and drop in ground.drops,"added observes both owner collections"))
	ground.removed.connect(func(drop): check(ground.get_by_id(drop.id)==null and drop not in ground.drops and drop.reservation_owner_id.is_empty(),"removed observes absent identity and released claim"))
	check(ground.get_by_id(&"missing")==null,"Missing ID")
	check(not ground.register_drop(null),"Null registration rejected")
	var imported=Drop.new(R.LOG,7,Vector2.ZERO,clock.total_minutes)
	imported.id=&"ground_1"
	check(ground.register_drop(imported),"Owner registration supports stable imported identity")
	var duplicate=Drop.new(R.STONE,3,Vector2.ONE,clock.total_minutes)
	duplicate.id=imported.id
	check(not ground.register_drop(duplicate) and not ground.register_drop(imported) and ground.get_by_id(imported.id)==imported,"Duplicate live identity cannot overwrite")
	var generated=ground.create_drop(R.FOOD,1,Vector2.ZERO)
	check(generated.id==&"ground_2","Generated IDs skip existing imported IDs")
	ground.remove_drop(imported)
	ground.remove_drop(generated)
	check(ground.register_drop(imported) and ground.get_by_id(imported.id)==imported,"Re-registration keeps one availability connection")
	ground.remove_drop(imported)
	for count in [1,100,300]:
		var batch: Array=[]
		for index in count: batch.append(ground.create_drop(R.values()[index%4],index+1,Vector2(index,2)))
		for index in [0,count/2,count-1]:
			var expected=batch[int(index)]
			check(ground.get_by_id(expected.id)==expected,"First/middle/last identity")
		check(ground.drops==batch,"Enumeration order unchanged")
		for drop in batch:
			check(ground.remove_drop(drop) and ground.get_by_id(drop.id)==null,"Deletion removes each indexed identity")
		check(ground._by_id.is_empty() and ground.drops.is_empty(),"No retained dead entries")
	for resource in R.values():
		var drop=ground.create_drop(resource,3,Vector2(8,9))
		var reference=Ref.new(Ref.Kind.GROUND,drop.id)
		check(sources.resolve(reference)==drop and sources.point(reference)==drop.world_position,"Original object/position, every resource")
		drop.world_position=Vector2(12,14)
		check(sources.point(reference)==drop.world_position,"No cached position")
		check(sources.reserve(reference,resource,&"porter_a") and not sources.reserve(reference,resource,&"porter_b"),"One exclusive claim regardless quantity")
		sources.release(reference,resource,&"porter_a")
		check(sources.resolve(reference)==drop and drop.amount==3 and drop.reservation_owner_id.is_empty(),"Release retains physical drop and identity")
		var observations: Array=[]
		var observer=func(): observations.append({"indexed":ground.get_by_id(drop.id)==drop,"amount":drop.amount})
		drop.availability_changed.connect(observer)
		for unit in 3:
			check(sources.reserve(reference,resource,&"porter_a") and sources.pickup(reference,resource,&"porter_a"),"One-unit pickup preserves quantity semantics")
			check(drop.amount==2-unit and not sources.pickup(reference,resource,&"porter_b"),"No duplicate/unowned pickup")
			check((sources.resolve(reference)==null)==(drop.amount==0),"Only final pickup removes identity")
		check(observations[-1].indexed and observations[-1].amount==0,"Final pickup release callback retains original publication order")
		drop.availability_changed.disconnect(observer)
		check(ground.get_by_id(drop.id)==null and not ground.remove_drop(drop),"Repeated removal is harmless")
		var expired=ground.create_drop(resource,5,Vector2.ZERO)
		var expired_ref=Ref.new(Ref.Kind.GROUND,expired.id)
		sources.reserve(expired_ref,resource,&"porter")
		expired.availability_changed.connect(func(): check(sources.resolve(expired_ref)==null,"Expiration release callback observes absent source"))
		ground._on_minute(expired.created_at+expired.lifetime)
		check(sources.resolve(expired_ref)==null and expired.reservation_owner_id.is_empty(),"Expiration clears index and claim")
	for count in [30,100,150,300]:
		var batch: Array=[]
		for index in count: batch.append(ground.create_drop(R.LOG,1,Vector2(index,0)))
		ground.lookups=0
		for drop in batch: check(sources.available(Ref.new(Ref.Kind.GROUND,drop.id),R.LOG),"Available through indexed source API")
		check(ground.lookups==3*count,"Availability uses exactly three direct ID reads per drop")
		for drop in batch: ground.remove_drop(drop)
	for index in 500:
		var drop=ground.create_drop(R.STONE,2,Vector2.ZERO)
		check(ground.remove_drop(drop) and ground.get_by_id(drop.id)==null,"Repeated lifecycle stays indexed")
	check(ground._by_id.is_empty() and ground.drops.is_empty(),"All references released after repeated creation/removal")
	await process_frame
	ground.free()
	clock.free()
	print("Ground index: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
