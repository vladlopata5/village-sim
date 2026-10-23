extends "res://tests/test_textile_production.gd"
const Coord=preload("res://scripts/world_3d/world_coordinates.gd")
const Activity=preload("res://scripts/resident_activity.gd").Type
const Need=preload("res://scripts/need_type.gd").Type
const Slot=preload("res://scripts/world_3d/building_slot_3d.gd")
var observer: Callable
func observe(world: Node,label: String) -> void:
	if observer.is_valid():await observer.call(world,label)
func prepare(extra: int=0) -> Node:
	var world=F.create(self)
	F.building(world,T.GAZEBO,Vector3(-12,0,16))
	if extra>0:check(world.debug_spawn.spawn_residents(Vector3(-10,0,24),extra,P.NONE).created==extra,"Additional actual residents for group/capacity proof")
	for index in world.resident_runtimes.size():
		var actor=world.resident_runtimes[index]
		actor.decision._deciding=true;actor.intents.abort_current(actor.intents.current_intent);actor.view.set_physics_process(false)
		actor.view.global_position=Vector3(-16+index*1.5,0,20)
		for need in actor.data.needs.values():need.value=0;need.base_weight=0
	return world
func gazebo(world: Node):return world.buildings.filter(func(place):return place.type==T.GAZEBO)[0]
func occupied(world: Node) -> int:return world.building_uses.inside_count(gazebo(world).id)
func begin_pair(world: Node) -> RefCounted:
	var actors: Array=world.resident_runtimes
	check(actors[0].social.try_social_at(actors[1].data.id,5600),"Ordinary targeted social action plans physical gazebo meeting")
	check(actors[1].social._active.priority==actors[1].data.get_need(Need.SOCIAL).get_priority(),"Invited resident retains own ordinary social priority")
	check(occupied(world)==2 and actors[0].data.activity==Activity.MOVING and actors[1].data.activity==Activity.MOVING,"Two positions reserved before both approach")
	check(world.social_world.groups.size()==1 and world.social_world.groups.values()[0].participants.is_empty(),"Planning owns one existing group, with no premature talking members")
	F.walk(world,actors[0])
	check(actors[0].data.activity==Activity.IDLE and actors[0].intents.has_current_action() and not actors[1].data.activity==Activity.TALKING,"First arrival waits with owned action, without talking remotely")
	F.walk(world,actors[1])
	var group=world.social_world.group_of(actors[0].data.id)
	check(group!=null and group.participants.size()==2 and group.venue_id==gazebo(world).id and actors[1].data.activity==Activity.TALKING,"Both real arrivals start the ordinary two-member conversation")
	return group
func run() -> void:
	await formation_and_joining()
	await cancellations()
	await fallback()
	await reservation_callbacks()
	await failed_join_route()
	await simultaneous_pairs()
	await exact_target_departure()
	await talk_assignment()
	await ordinary_choice()
	print("Social venues: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func formation_and_joining() -> void:
	var world=prepare(2);var actors: Array=world.resident_runtimes
	world.resident_selection.select_building(gazebo(world))
	var group=begin_pair(world)
	check(world.building_card_view().get_node("%Summary").text.contains("2 / 4"),"Local claim events update selected gazebo visitor count")
	if group==null:world.free();return
	await observe(world,"pair")
	var fixed: Dictionary={}
	for actor in actors.slice(0,2):fixed[actor.data.id]=actor.view.global_position
	for index in [2,3]:
		check(actors[index].social.try_social_at(actors[0].data.id,5600),"Third/fourth chooses current group")
		check(group.pending.has(actors[index].data.id) and occupied(world)==index+1 and not actors[index].data.id in group.participants,"Newcomer reserves own slot before joining")
		F.walk(world,actors[index])
		check(world.social_world.groups.size()==1 and group.participants.size()==index+1 and world.social_world.group_of(actors[index].data.id)==group,"Arrival joins original group, never creates a second pair")
		for id in fixed:check(world.social_world.get_runtime(id).view.global_position==fixed[id],"Existing talkers stay in their slots when newcomer arrives")
		fixed[actors[index].data.id]=actors[index].view.global_position
	check(not actors[4].social.try_social_at(actors[0].data.id,5600) and occupied(world)==4,"Fifth cannot enter a full four-place group")
	check(world.social_world.options_for(actors[4].data.id).all(func(option):return option.group_id!=group.id),"Full group is absent from ordinary social options")
	check(world.building_card_view().get_node("%Summary").text.contains("4 / 4"),"Selected card shows all four occupied/reserved positions")
	await observe(world,"four")
	# An occupied pavilion does not suppress unrelated conversations.
	check(actors[4].social.try_social_at(actors[5].data.id,5600) and not actors[4].social._option.has("venue_group"),"Another pair uses old street action beside occupied gazebo")
	F.walk(world,actors[4])
	check(world.social_world.groups.size()==2 and world.social_world.group_of(actors[4].data.id).venue_id.is_empty(),"Street and gazebo groups coexist independently")
	actors[0].social.cancel_social()
	check(group.participants.size()==3 and occupied(world)==3,"Independent departure frees one position, three talkers continue")
	actors[1].intents.abort_current(actors[1].intents.current_intent)
	check(group.participants.size()==2 and occupied(world)==2,"Forced action cancellation preserves two-member group")
	actors[2].social.cancel_social();await process_frame
	check(not world.social_world.groups.has(group.id) and occupied(world)==0 and actors[3].data.activity!=Activity.TALKING,"Singleton dissolves with every claim released")
	await observe(world,"released")
	world.free();await process_frame
func cancellations() -> void:
	for mode in ["approach","late","critical","hunger","command","removed_resident","demolish","callback"]:
		var world=prepare();var actors: Array=world.resident_runtimes
		if mode in ["critical","hunger","command","removed_resident","demolish","callback"]:begin_pair(world)
		else:check(actors[0].social.try_social_at(actors[1].data.id,5600),"Pending pair exists for failure control")
		if mode=="approach":actors[0].commands.move_to(Coord.to_sim(Vector3(-18,0,24)))
		elif mode=="late":
			F.walk(world,actors[0]);world.game_time.debug_skip_minutes(59)
			check(occupied(world)==2,"Waiting cannot reroll or expire early")
			world.game_time.debug_skip_minutes(1)
		elif mode=="critical":
			actors[0].decision._deciding=false;actors[0].data.fatigue=100
			check(actors[0].data.activity==Activity.SLEEPING,"Real critical fatigue interrupts social action")
		elif mode=="hunger":
			actors[0].decision._deciding=false;actors[0].data.hunger=100
			check(actors[0].intents.current_intent.reason_id==&"eat","Real critical hunger supersedes venue conversation")
		elif mode=="command":actors[0].commands.move_to(Coord.to_sim(Vector3(-18,0,24)))
		elif mode=="removed_resident":
			world.social_world.unregister(actors[0].data.id);actors[0].queue_free();await process_frame
		elif mode=="demolish":check(world.change_construction_direction(gazebo(world).id,true),"D1 accepts occupied gazebo and synchronously cleans social action")
		else:
			world.social_world.membership_changed.connect(func():world.social_venues._cancel_building(gazebo(world).id),CONNECT_ONE_SHOT)
			actors[0].social.cancel_social()
		await process_frame
		check(occupied(world)==0 and world.social_world.groups.is_empty(),"Failure releases all pending/active places without late completion: "+mode)
		world.social_venues._cancel_building(gazebo(world).id)
		check(occupied(world)==0,"Repeated cleanup is idempotent")
		world.free();await process_frame
func fallback() -> void:
	for mode in ["unreachable","unbuilt","far","no_building"]:
		var world=prepare();var actors: Array=world.resident_runtimes;var place=gazebo(world)
		if mode=="unreachable":world.navigation.add_blocker(&"test_cutoff",Rect2(Vector2(-14,14),Vector2(4,4)))
		elif mode=="unbuilt":world.change_construction_direction(place.id,true)
		elif mode=="far":
			actors[0].view.global_position=Vector3(-35,0,20);actors[1].view.global_position=Vector3(-33,0,20)
		else:world.social_venues._removed(place.id)
		check(actors[0].social.try_social_at(actors[1].data.id,5600) and not actors[0].social._option.has("venue_group") and occupied(world)==0,"Unavailable venue preserves ordinary street planning: "+mode)
		F.walk(world,actors[0])
		var group=world.social_world.group_of(actors[0].data.id)
		check(group!=null and group.venue_id.is_empty(),"Ordinary conversation still starts after actual approach")
		if group!=null:
			actors[2].view.global_position=actors[1].view.global_position+Vector3(3,0,0)
			check(actors[2].social.try_social_at(actors[1].data.id,5600),"Third may still join old street conversation")
			F.walk(world,actors[2]);check(group.participants.size()==3,"Street membership rules retained")
		world.free();await process_frame

func reservation_callbacks() -> void:
	for joining in [false,true]:
		var world=prepare();var actors: Array=world.resident_runtimes;var place=gazebo(world)
		if joining:begin_pair(world)
		var markers: Array=world.building_uses.view(place.id).get_markers(Slot).filter(func(marker):return marker.purpose==Slot.Purpose.VISITOR)
		world.building_uses.slots_changed.connect(func(_id,_purpose):world.change_construction_direction(place.id,true),CONNECT_ONE_SHOT)
		var actor: Node=actors[2] if joining else actors[0]
		actor.social.try_social_at(actors[1].data.id,5600)
		check(world.social_world.groups.is_empty() and markers.all(func(marker):return marker.occupant.is_empty()),"Demolition inside acquire callback rolls back unpublished initial/joining reservation")
		world.free();await process_frame
func failed_join_route() -> void:
	var world=prepare();var actors: Array=world.resident_runtimes;var group=begin_pair(world)
	check(actors[2].social.try_social_at(actors[0].data.id,5600),"Third has accepted route and reserved position")
	var target: Vector3=group.venue_claims[actors[2].data.id].global_position
	world.navigation.add_blocker(&"late_obstacle",Rect2(Vector2(target.x,target.z)-Vector2(.2,.2),Vector2(.4,.4)))
	F.walk(world,actors[2])
	check(not actors[2].intents.has_current_action() and not group.pending.has(actors[2].data.id) and group.participants.size()==2 and occupied(world)==2,"Real navigation failure frees newcomer slot without moving or ending original pair")
	world.free();await process_frame

func simultaneous_pairs() -> void:
	var world=prepare();var actors: Array=world.resident_runtimes
	world.building_uses.slots_changed.connect(func(_id,_purpose):actors[2].social.try_social_at(actors[3].data.id,5600),CONNECT_ONE_SHOT)
	check(actors[0].social.try_social_at(actors[1].data.id,5600),"First initial pair reserves a gazebo atomically")
	check(occupied(world)==2 and world.social_world.groups.size()==1 and not actors[2].social._option.has("venue_group"),"Reentrant second pair cannot claim another conversation in the same gazebo")
	world.free();await process_frame

func exact_target_departure() -> void:
	var world=prepare();var actors: Array=world.resident_runtimes;var group=begin_pair(world)
	check(actors[2].social.try_social_at(actors[0].data.id,5600),"Third joins ordinary existing venue group")
	F.walk(world,actors[2])
	check(actors[3].social.try_social_at(actors[0].data.id,5600) and actors[3].social._option.target_id==actors[0].data.id and actors[3].social._option.exact_target,"Targeted approach retains the requested resident identity")
	actors[0].social.cancel_social()
	check(group.participants.size()==2,"Other pair stays after the requested partner leaves")
	F.walk(world,actors[3])
	check(group.participants.size()==2 and occupied(world)==2 and not actors[3].intents.has_current_action(),"Target departure cancels pending targeted join instead of silently replacing partner")
	world.free();await process_frame

func talk_assignment() -> void:
	var world=prepare();var actors: Array=world.resident_runtimes
	var assignment_type=preload("res://scripts/resident_assignment.gd")
	for actor in actors.slice(0,2):actor.data.get_need(Need.SOCIAL).base_weight=80;actor.data.get_need(Need.SOCIAL).value=100
	var task=assignment_type.new(&"gazebo_talk",actors[0].data.id,assignment_type.TALK_TO,StringName(actors[1].data.id))
	check(world.player_control.add_assignment(actors[0].data.id,task) and actors[0].assignments.start(task.id),"Existing TALK_TO assignment plans the same physical gazebo meeting")
	F.walk(world,actors[0]);world.game_time.debug_skip_minutes(5)
	check(task.state==assignment_type.State.ACTIVE and world.social_world.group_of(actors[0].data.id)==null,"Waiting for partner gives no completed/shared conversation time")
	for step in 2000:
		actors[1].view._physics_process(.05)
		if not actors[1].view.movement.is_moving():break
	check(world.social_world.group_of(actors[0].data.id)!=null,"Actual second arrival starts assigned conversation")
	world.game_time.debug_skip_minutes(14)
	check(task.state==assignment_type.State.ACTIVE,"Fourteen actual shared minutes remain insufficient")
	world.game_time.debug_skip_minutes(1)
	check(task.state==assignment_type.State.COMPLETED,"Fifteen actual shared minutes complete original TALK_TO once")
	world.free();await process_frame

func ordinary_choice() -> void:
	var world=prepare();var actors: Array=world.resident_runtimes
	check(actors[0].social.try_social(5600) and actors[0].social._option.has("venue_group"),"Ordinary weighted social choice can select a nearby gazebo without a targeted command")
	for actor in actors:
		if actor.social._option.has("venue_group"):F.walk(world,actor)
	var group=world.social_world.group_of(actors[0].data.id)
	check(group!=null and group.participants.size()==2 and occupied(world)==2,"Ordinary-choice participants physically arrive and talk through the same group")
	await observe(world,"ordinary-choice")
	world.free();await process_frame
