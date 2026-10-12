extends SceneTree
const View = preload("res://scripts/world_3d/building_view_3d.gd")
const Layouts = preload("res://scripts/world_3d/building_layouts_3d.gd")
const Slot = preload("res://scripts/world_3d/building_slot_3d.gd")
const Entrance = preload("res://scripts/world_3d/building_entrance_3d.gd")
const B = preload("res://scripts/building_instance.gd")
const Def = preload("res://scripts/building_definition.gd")
const Types = preload("res://scripts/building_type.gd").Type
const Resources = preload("res://scripts/resource_type.gd").Type
class CountedView extends "res://scripts/world_3d/building_view_3d.gd":
	var visits := 0
	var builds := 0
	func _index_markers(node: Node) -> void:
		visits+=1
		super._index_markers(node)
	func rebuild_marker_index() -> void:
		builds+=1
		super.rebuild_marker_index()
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func run() -> void:
	var nav=preload("res://scripts/navigation_grid.gd").new()
	for type in Types.values():
		for turns in 4:
			var definition=Def.for_type(type)
			var data=B.new(&"indexed",definition,Vector2.ZERO,B.State.UNDER_CONSTRUCTION if definition.player_buildable else B.State.BUILT)
			data.quarter_turns=turns
			var view=CountedView.new()
			root.add_child(view)
			view.setup(data)
			var uses=preload("res://scripts/world_3d/building_use_3d.gd").new()
			uses.navigation=nav
			uses.register(data,view)
			var expected_slots=Layouts.markers(view.layout,Slot)
			var expected_entry=Layouts.markers(view.layout,Entrance)
			check(view.get_markers(Slot)==expected_slots and view.get_markers(Entrance)==expected_entry,"Every type/orientation keeps authored order and node identity")
			var copied=view.get_markers(Slot)
			copied.reverse()
			copied.clear()
			check(view.get_markers(Slot)==expected_slots,"Caller cannot mutate stored order")
			view.visits=0
			for query in 1000:
				view.get_markers(Slot)
				uses.entrance(data.id)
			check(view.visits==0 and view.builds==1,"Repeated query does not traverse the layout")
			check(uses.entrance(data.id)==expected_entry[0].global_position,"Entrance remains live rotated geometry")
			if not data.is_built():
				check(uses.courier_position(data.id)==null,"UC cannot expose interior Courier")
				data.claim_builder_slot("builder")
				var construction=uses.acquire(data.id,Slot.Purpose.CONSTRUCTION,"builder",Vector3.ZERO)
				check(construction!=null and construction in expected_slots,"Construction uses original perimeter marker")
				uses.release(data.id,construction,"builder")
				data.release_builder_slot("builder")
				for resource in Resources.values():
					var required: int=data.get_required_amount(resource)
					if required>0: data.add_delivered_material(resource,required)
				data.add_construction_work(definition.construction_work_required)
				check(data.complete_construction(),"Existing completion lifecycle")
			check(view.get_markers(Slot)==expected_slots and view.visits==0,"BUILT preserves index and marker identity")
			var events: Array=[]
			var observe=func(event_id: StringName,event_purpose: int): events.append({"id":event_id,"purpose":event_purpose,"count":uses.inside_count(event_id)})
			uses.slots_changed.connect(observe)
			var courier=uses.acquire(data.id,Slot.Purpose.COURIER,"porter",Vector3.ZERO)
			check(courier!=null and courier in expected_slots and courier.occupant=="porter","Occupancy lives on original marker")
			check(uses.occupied_by(data.id,"porter",Slot.Purpose.COURIER) and uses.choices(data.id,Slot.Purpose.COURIER,Vector3.ZERO).is_empty(),"Occupied state never cached separately")
			check(uses.acquire(data.id,Slot.Purpose.COURIER,"other",Vector3.ZERO)==null,"Second Courier waits through existing contract")
			uses.release(data.id,courier,"porter")
			check(courier.occupant.is_empty() and not uses.choices(data.id,Slot.Purpose.COURIER,Vector3.ZERO).is_empty(),"Release immediately visible")
			check(events.size()==2 and events[0].count==1 and events[1].count==0,"Acquire and release notification semantics unchanged")
			uses.slots_changed.disconnect(observe)
			var reentrant=func(event_id: StringName,event_purpose: int):
				if event_purpose==Slot.Purpose.COURIER and uses.occupied_by(event_id,"reentrant",event_purpose): uses.release(event_id,courier,"reentrant")
			uses.slots_changed.connect(reentrant)
			uses.acquire(data.id,Slot.Purpose.COURIER,"reentrant",Vector3.ZERO)
			check(courier.occupant.is_empty() and uses.inside_count(data.id)==0,"Reentrant notification sees latest occupancy")
			uses.slots_changed.disconnect(reentrant)
			var visits_before: int=view.visits
			courier.free()
			check(view.get_markers(Slot).size()==expected_slots.size()-1 and uses.courier_position(data.id)==null and view.visits==visits_before,"Destroyed marker pruned without DFS")
			var old_layout=view.layout
			var replacement=Layouts.create(definition)
			replacement.rotation.y=turns*PI/2.0
			view.add_child(replacement)
			view.layout=replacement
			check(view.get_markers(Slot)==Layouts.markers(replacement,Slot) and view.builds==2,"Changed layout identity rebuilt once")
			old_layout.free()
			view.rebuild_marker_index()
			check(view.get_markers(Slot)==Layouts.markers(replacement,Slot) and view.builds==3,"Explicit rebuild does not duplicate subscriptions")
			root.remove_child(view)
			check(view.get_markers(Slot)==Layouts.markers(replacement,Slot),"Late cleanup query on exited live layout")
			root.add_child(view)
			check(view.get_markers(Slot)==Layouts.markers(replacement,Slot),"Re-entered view restores references without duplicate hooks")
			uses.unregister(data.id)
			check(uses.view(data.id)==null and uses.entrance(data.id)==null,"Unregister removes current view")
			uses.register(data,view)
			check(uses.courier_position(data.id)!=null,"Re-register uses current layout references")
			var entry=view.get_markers(Entrance)[0]
			entry.free()
			check(uses.entrance(data.id)==null,"Missing Entrance is unavailable without invalid indexing")
			replacement.free()
			check(view.get_markers(Slot).is_empty() and view._marker_groups.is_empty(),"Freed layout clears all references")
			view.free()
			check(uses.view(data.id)==null and uses.choices(data.id,0,Vector3.ZERO).is_empty(),"Freed view is unavailable")
	var detached=View.new()
	detached.setup(B.new(&"detached",Def.for_type(Types.HOME)))
	var detached_marker=detached.get_markers(Slot)[0]
	detached_marker.free()
	check(detached.get_markers(Slot)==Layouts.markers(detached.layout,Slot),"Detached layout fallback cannot return freed nodes")
	detached.free()
	# A freed live Courier invalidates normal hauling; cleanup must not dereference it.
	var world=load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_time.total_minutes=420
	world.game_logger.console_enabled=false
	world.social_events.enabled=false
	for actor in world.resident_runtimes:
		actor.decision._deciding=true
		actor.intents.abort_current(actor.intents.current_intent)
		actor.view.set_physics_process(false)
		for need in actor.data.needs.values(): need.value=0
	var worker=world.resident_runtimes[0]
	var loose=world.ground_resources.create_drop(Resources.LOG,1,Vector2(250,550))
	var source=preload("res://scripts/resource_source_ref.gd")
	var job=world.logistics.claim_transport(worker.data.id,source.new(source.Kind.GROUND,loose.id),world.warehouse_data,Resources.LOG,func(): return true)
	check(job!=null and world.logistics.start_claimed_job(job,worker.data.id),"Real haul uses indexed Ground")
	for step in 2000:
		worker.view._physics_process(0.05)
		if not worker.view.movement.is_moving(): break
	world.game_time.advance(10.0)
	for step in 2000:
		worker.view._physics_process(0.05)
		if not worker.view.movement.is_moving(): break
	var safe_entry: Vector3=world.building_uses.entrance(world.warehouse_data.id)
	check(worker.view._marker!=null and worker.data.inventory.amount==1,"Courier holds real cargo during unloading")
	worker.view._marker.free()
	world.game_time.advance(1.0)
	await process_frame
	check(job.state==preload("res://scripts/haul_job.gd").State.CANCELLED and worker.view._marker==null and not worker.view._waiting,"Freed Courier cancels through existing validation")
	check(worker.data.inventory.amount==0 and world.warehouse_data.resources.get_reserved_in(Resources.LOG)==0 and world.ground_resources.drops.size()==1,"Cargo and inbound cleanup conserved")
	check(world.ground_resources.drops[0].world_position==preload("res://scripts/world_3d/world_coordinates.gd").to_sim(safe_entry),"Interrupted interior cargo still drops at entrance")
	world.free()
	print("Building marker index: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
