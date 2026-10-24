extends "res://tests/test_resident_model.gd"
## VIS3: visual playback follows actual integration, including escort holds.
func manual_player(actor: Node) -> AnimationPlayer:
	var player: AnimationPlayer=actor.view.model.animation_player
	player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return player
func pose(skeleton: Skeleton3D) -> Array[Transform3D]:
	var result: Array[Transform3D]=[]
	for index in skeleton.get_bone_count(): result.append(skeleton.get_bone_pose(index))
	return result
func run() -> void:
	await animation_contract()
	await activity_contract()
	print("Resident animation: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func animation_contract() -> void:
	var actors: Array=[]
	for id in ["animated_a","animated_b"]:
		var created=Executor.new();created.navigation=Grid.new(Rect2(-30,-30,60,60));root.add_child(created)
		created.setup(Resident.new(id,id,30));created.set_physics_process(false);created.position=Vector3(.25,0,.25)
		actors.append(created)
	var actor=actors[0];var model=actor.view.model;var player=manual_player(actor)
	var other=actors[1];var second=manual_player(other)
	var skeleton: Skeleton3D=model.instance.find_children("*","Skeleton3D",true,false)[0]
	var standing: Array[Transform3D]=pose(skeleton)
	check(Model.MODEL.resource_path=="res://assets/models/creatures/zhabka_animated.glb","Animated shared source replaces VIS2 artwork")
	check(player!=null and player.has_animation(&"walk") and player.has_animation(&"idle"),"Cached player discovers actual imported walk and authored standing pose")
	check(player!=second and model.instance!=other.view.model.instance and player.get_animation(&"walk")==second.get_animation(&"walk"),"Independent scene/player state shares immutable animation data")
	check(not player.is_playing() and not model.walking and not second.is_playing(),"Spawned residents stand without walking")
	check(player.get_animation(&"walk").loop_mode==Animation.LOOP_LINEAR,"Walk is configured to loop without modifying GLB")
	var starts: Array=[];player.animation_started.connect(func(name):starts.append(name))
	var origin: Transform3D=actor.transform;var visual: Transform3D=model.model_basis.transform
	var revision: int=actor.navigation.revision;var speed: float=actor.get_base_movement_speed()
	var collider=colliders(actor.view)[0];var shape: Transform3D=collider.transform
	actor.move_to(Coord.to_sim(actor.position+Vector3(15,0,0)))
	check(not player.is_playing(),"A pending command alone does not start walk")
	actor._physics_process(.025)
	check(actor.position.x>origin.origin.x and model.walking and player.is_playing(),"Physical displacement starts walk")
	player.advance(.25);var phase: float=player.current_animation_position
	actor._physics_process(.025)
	check(is_equal_approx(player.current_animation_position,phase) and starts.count(&"walk")==1,"Continuous movement never restarts the clip")
	# Retargeting changes direction, without an artificial stop or phase reset.
	actor.move_to(Coord.to_sim(actor.position+Vector3(0,0,15)));actor._physics_process(.025)
	check(starts.count(&"walk")==1 and is_equal_approx(player.current_animation_position,phase) and facing(model).dot(Vector3.BACK)>.999,"Turning preserves phase and actual heading")
	player.advance(3.0)
	check(player.is_playing() and player.current_animation_position<player.get_animation(&"walk").length and pose(skeleton)!=standing,"Several cycles continue changing the skeleton")
	check(actor.transform.origin!=origin.origin and model.model_basis.transform==visual and collider.transform==shape and actor.scale==Vector3.ONE,"Animation cannot translate gameplay root or fitting/collision transforms")
	var fixed: Transform3D=actor.transform;var model_root: Transform3D=model.instance.transform
	for loop in 20: player.advance(.37)
	check(actor.transform==fixed and model.instance.transform==model_root and actor.navigation.revision==revision and actor.get_base_movement_speed()==speed,"Repeated cycles have no root drift or navigation/speed changes")
	check(not second.is_playing() and not other.view.model.walking,"One walking resident never starts another")
	other.move_to(Coord.to_sim(other.position+Vector3(-10,0,0)));other._physics_process(.025);second.advance(.1)
	check(second.is_playing() and not is_equal_approx(player.current_animation_position,second.current_animation_position),"Later walker has independent playback phase")
	actor.movement.set_paused(true);actor._physics_process(.025)
	check(not model.walking and not player.is_playing() and pose(skeleton)==standing and second.is_playing(),"A physically held resident returns to authored standing pose only for itself")
	actor.movement.set_paused(false);actor._physics_process(.025)
	check(model.walking and starts.count(&"walk")==2,"Motion resumes with one new start")
	actor.movement.stop();actor._physics_process(.025)
	check(not player.is_playing() and pose(skeleton)==standing,"Cancellation clears random step pose")
	actor.move_to(Coord.to_sim(Vector3(5000,0,5000)));actor._physics_process(.025)
	check(not actor.movement.is_moving() and not player.is_playing(),"Failed route never walks in place")
	actor.move_to(Coord.to_sim(actor.position+Vector3(.2,0,0)));actor._physics_process(.1)
	check(not actor.movement.is_moving() and not player.is_playing(),"Arrival stops walk in the same visual update")
	# An owned leader can wait without its owner calling advance_owned at all.
	var owner=Node.new();root.add_child(owner)
	check(actor.claim_movement(owner),"Existing escort ownership remains available")
	actor.movement.set_target(actor.position+Vector3(5,0,0));actor.advance_owned(owner,.1,.5,.03)
	check(model.walking,"Owned physical movement starts walk")
	player.advance(.2);phase=player.current_animation_position
	actor._physics_process(.01)
	check(model.walking and is_equal_approx(player.current_animation_position,phase),"Owned motion observer does not spuriously restart or stop a just-advanced leader")
	actor._physics_process(.01)
	check(not model.walking and not player.is_playing(),"Held escort leader stops even when advance_owned is skipped")
	actor.advance_owned(owner,.1,.5,0.0)
	check(not model.walking,"Zero escort distance budget does not walk")
	actor.advance_owned(owner,.1,.5,.03);actor.release_movement(owner,false)
	check(not player.is_playing() and pose(skeleton)==standing,"Escort release stops immediately and restores standing")
	await physics_frame;await process_frame # Existing escort release guard defers ordinary motion within the same frame.
	for cycle in 8:
		actor.move_to(Coord.to_sim(actor.position+Vector3(4,0,0)));actor._physics_process(.01)
		check(model.walking,"Rapid restart follows physical motion")
		actor.movement.stop();actor._physics_process(.01)
		check(not player.is_playing() and pose(skeleton)==standing,"Rapid stop is stable")
	# Imported tracks are local bones, with no accumulated X/Z translation.
	var walk: Animation=player.get_animation(&"walk")
	for track in walk.get_track_count():
		var path: NodePath=walk.track_get_path(track)
		check(path.get_subname_count()==1 and path.get_concatenated_names()=="Арматура/Skeleton3D","Walk targets skeleton bones, never the executor or visual placement root")
		if walk.track_get_type(track)==Animation.TYPE_POSITION_3D:
			for key in walk.track_get_key_count(track):
				var value: Vector3=walk.track_get_key_value(track,key)
				check(is_zero_approx(value.x) and is_zero_approx(value.z),"Root bone has bounded authored vertical bob, without horizontal locomotion")
	actor.queue_free();other.queue_free();owner.queue_free();await process_frame
	check(not is_instance_valid(model) and not is_instance_valid(player) and not is_instance_valid(second),"Removing residents removes all playback nodes")
func activity_contract() -> void:
	var world=F.create(self);await physics_frame;await process_frame
	var actor=world.resident_runtimes[0];var executor=actor.view;var model=executor.view.model
	var mill=F.building(world,T.SAWMILL,Vector3(-12,0,16))
	check(world.player_control.assign_workplace(actor.data.id,mill.id,P.SAWYER) and mill.resources.add(R.LOG,1),"Normal production uses unchanged job and input")
	executor.global_position=Vector3(-16,0,20)
	check(world._request_work(actor),"Normal work decision accepts job")
	executor._physics_process(.025)
	check(model.walking,"Walk starts on actual approach to production")
	F.walk(world,actor);executor._physics_process(.025)
	check(actor.recipe_work.phase==preload("res://scripts/resident_recipe_controller.gd").Phase.WORKING and not model.walking and not model.animation_player.is_playing(),"Worker-slot arrival keeps production active and feet still")
	await observe(world,"working")
	actor.intents.abort_current(actor.intents.current_intent)
	world.player_control.clear_work_assignment(actor.data.id)
	var gazebo=F.building(world,T.GAZEBO,Vector3(-20,0,16));var partner=world.resident_runtimes[1]
	executor.global_position=Vector3(-24,0,20);partner.view.global_position=Vector3(-22,0,20)
	check(actor.social.try_social_at(partner.data.id,5600),"Existing SOC1 plans a real gazebo approach")
	executor._physics_process(.025);partner.view._physics_process(.025)
	check(model.walking and partner.view.view.model.walking,"Both social approaches walk independently")
	F.walk(world,actor);F.walk(world,partner);executor._physics_process(.025);partner.view._physics_process(.025)
	check(world.social_world.group_of(actor.data.id)!=null and world.social_world.group_of(actor.data.id).venue_id==gazebo.id and actor.data.activity==preload("res://scripts/resident_activity.gd").Type.TALKING,"Normal physical arrivals start SOC1 talk")
	check(not model.walking and not partner.view.view.model.walking,"Conversation does not play walking")
	await observe(world,"talking")
	world.free();await process_frame
