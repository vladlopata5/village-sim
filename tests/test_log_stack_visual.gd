extends "res://tests/test_textile_production.gd"
const Visual=preload("res://scripts/world_3d/log_stack_visual_3d.gd")
const GroundView=preload("res://scripts/world_3d/ground_resource_view_3d.gd")
const Ground=preload("res://scripts/ground_resource.gd")
const Coord=preload("res://scripts/world_3d/world_coordinates.gd")
const Source=preload("res://scripts/resource_source_ref.gd")
var observer: Callable
func observe(world: Node,stack: RefCounted,label: String) -> void:
	if observer.is_valid():await observer.call(world,stack,label)
func descendants(node: Node) -> Array:
	var nodes: Array=[node]
	for child in node.get_children():nodes.append_array(descendants(child))
	return nodes
func run() -> void:
	await geometry_and_stability()
	await world_and_transport()
	print("Log visuals: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func geometry_and_stability() -> void:
	var drop=Ground.new(R.LOG,1,Vector2(100,200),10)
	var view=GroundView.new();root.add_child(view);view.setup(drop)
	var visual=view.log_visual
	check(visual!=null and visual.visible_count==1 and visual.MODEL==load("res://assets/models/resources/log.glb"),"LOG uses the single shared imported PackedScene")
	check(is_equal_approx(Visual.model_bounds.size.x,.48) and is_equal_approx(Visual.model_bounds.size.y,.13353945) and is_equal_approx(Visual.model_bounds.size.z,.14744392),"Imported real mesh bounds, not an extra .08 scale")
	var stable: Dictionary={}
	for count in [1,2,3,4,6,7,9,10,11,15,10,8,5,1,0,6,10]:
		drop.amount=count;drop.availability_changed.emit()
		check(drop.amount==count and drop.capacity==10 and visual.visible_count==mini(count,10),"Visible cap never edits gameplay quantity/capacity: %d"%count)
		check(visual.instances.filter(func(instance):return instance.visible).size()==mini(count,10) and not view.quantity_label.visible,"Only the expected prefix is visible and LOG has no label")
		for index in visual.instances.size():
			var slot: Node3D=visual.instances[index]
			if stable.has(index):check(stable[index]==[slot.get_instance_id(),slot.transform],"Existing slot transform/identity never changes")
			else:stable[index]=[slot.get_instance_id(),slot.transform]
			check(slot.basis.get_scale().is_equal_approx(Vector3.ONE) and slot.get_node("ModelBasis").basis.get_scale().is_equal_approx(Vector3.ONE),"Transforms rotate/recenter without changing model dimensions")
			var model: Node=slot.get_node("ModelBasis").get_child(0)
			check(model.scene_file_path==Visual.MODEL.resource_path,"Each visible object instantiates the actual supplied model")
		check(view.position==Coord.to_world(drop.world_position) and drop.world_position==Vector2(100,200),"Visual offsets never move logical stack coordinates")
	for layer in 3:
		var first: Node3D=visual.instances[layer*3]
		for index in range(layer*3,layer*3+3):
			var slot: Node3D=visual.instances[index]
			check(slot.basis.x.is_equal_approx(first.basis.x) and is_equal_approx(slot.position.y,first.position.y),"Three parallel logs in one horizontal layer")
			var box: AABB=slot.transform*Visual.horizontal_bounds
			check(is_equal_approx(box.position.y,layer*Visual.horizontal_bounds.size.y*Visual.SPACING_FACTOR),"Layer bottom derives from measured mesh height")
		if layer>0:check(is_zero_approx(first.basis.x.dot(visual.instances[(layer-1)*3].basis.x)),"Adjacent layers are perpendicular")
	var top: Node3D=visual.instances[9]
	check(is_zero_approx(top.position.x) and is_zero_approx(top.position.z) and is_zero_approx(top.basis.x.dot(visual.instances[6].basis.x)),"Tenth log is centered and perpendicular to third layer")
	check((visual.instances[0].transform*Visual.horizontal_bounds).position.y>=-0.000001,"Bottom never penetrates ground")
	var ids: Array=descendants(visual).map(func(node):return node.get_instance_id())
	for update in 200:
		drop.availability_changed.emit()
		visual.set_amount(drop.amount)
	check(descendants(visual).map(func(node):return node.get_instance_id())==ids,"Repeated unchanged updates create no nodes or scene reloads")
	check(not descendants(view).any(func(node):return node is CollisionObject3D or node is CollisionShape3D),"Visual logs create no physics or pickup objects")
	var other=Visual.new();root.add_child(other);other.set_amount(10)
	for index in 10:check(other.instances[index].transform==visual.instances[index].transform,"Fixed layout is stable across stacks without consuming RNG")
	other.free();view.queue_free();await process_frame
	check(not is_instance_valid(view) and drop.availability_changed.get_connections().is_empty(),"Freed view disconnects its quantity updates")
func world_and_transport() -> void:
	var world=F.create(self)
	var position:=Vector3(5,0,18)
	var placed: Dictionary=world.place_ground_resources(R.LOG,1,Coord.to_sim(position))
	var stack=world.ground_resources.get_by_id(placed.stack_ids[0]);var view: Node=world._ground_views[stack]
	var id: StringName=stack.id;var cell: Vector2i=stack.cell;var point: Vector2=stack.world_position
	var nav_revision: int=world.navigation.revision
	for count in [1,3,4,6,7,9,10,8,5,1]:
		if stack.amount<count:
			var added: int=count-stack.amount
			check(world.place_ground_resources(R.LOG,added,point).placed==added,"Normal top-up places remaining units")
		elif stack.amount>count:
			var taken: int=stack.amount-count
			check(stack.reserve(&"visual_qa",taken) and world.ground_resources.take_reserved(stack,&"visual_qa",taken),"Normal owned pickup reduces existing stack")
		check(stack.amount==count and stack.id==id and stack.cell==cell and world._ground_views[stack]==view and view.log_visual.visible_count==count,"One unchanged gameplay stack drives its model count")
		check(world.ground_resources.get_at(cell)==stack and world.navigation.revision==nav_revision,"Rendering never edits cell index or navigation")
		await observe(world,stack,"count_%02d"%count)
	check(world.place_ground_resources(R.LOG,5,point).placed==5,"Prepare actual six-unit transport source")
	var actor=world.resident_runtimes[0]
	actor.commands.move_to(point)
	for step in 12000:
		Step.move_3d(actor,.05)
		if not actor.view.movement.is_moving():break
	actor.commands.cancel_current();actor.intents.abort_current(actor.intents.current_intent)
	check(world.logistics.use_executor(actor.data,world.game_time,world.world_locations,actor.intents,actor.schedule),"Use ordinary haul executor")
	var job=world.logistics.claim_transport(actor.data.id,Source.new(Source.Kind.GROUND,id),world.warehouse_data,R.LOG,func():return true)
	check(job!=null and world.logistics.start_claimed_job(job,actor.data.id),"One real job reserves one actual unit")
	if job!=null:
		for step in 18000:
			Step.move_3d(actor,.05)
			if actor.data.inventory.amount==1:break
		check(stack.amount==5 and view.log_visual.visible_count==5 and actor.data.inventory.amount==1,"Physical pickup removes exactly one unit and sixth visible model")
		await observe(world,stack,"real_pickup")
		for step in 18000:
			if world.logistics.get_job(actor.data.id)==null:break
			Step.move_3d(actor,.05)
		check(not job.is_active() and world.warehouse_data.resources.get_amount(R.LOG)==1 and actor.data.inventory.amount==0,"Unchanged physical delivery deposits exactly one log")
	var other: RefCounted=null
	for resource in [R.STONE,R.CLAY]:
		var result: Dictionary=world.place_ground_resources(resource,3,Coord.to_sim(position+Vector3(2,0,0)))
		other=world.ground_resources.get_by_id(result.stack_ids[0])
		var other_view: Node=world._ground_views[other]
		check(other_view.log_visual==null and other_view.quantity_label.visible and other_view.quantity_label.text=="×3","Other resource model and quantity label are unchanged")
		await observe(world,other,"other_%d"%resource)
	var models: Array=view.log_visual.instances.duplicate()
	var amount: int=stack.amount
	check(stack.reserve(&"last",amount) and world.ground_resources.take_reserved(stack,&"last",amount),"Last owned pickup follows existing registry API")
	check(not world._ground_views.has(stack) and world.ground_resources.get_at(cell)==null and world.ground_resources.get_by_id(id)==null,"Removing one gameplay stack removes its only view")
	await process_frame;await process_frame
	check(not is_instance_valid(view) and models.all(func(node):return not is_instance_valid(node)) and stack.availability_changed.get_connections().is_empty(),"Whole visual hierarchy and connections disappear without orphan logs")
	await observe(world,stack,"count_00")
	world.free();await process_frame
