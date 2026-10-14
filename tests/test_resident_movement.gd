extends SceneTree
const Fixture = preload("res://tests/canonical_ui_fixture.gd")
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func run() -> void:
	var world=Fixture.make(self)
	var actor=world.resident_runtimes[0]
	var executor=actor.view
	var camera=world.get_node("World/Camera3D")
	var origin=Vector2(-650,450)
	var target=origin+Vector2(300,0)
	for trait_type in actor.data.traits.duplicate(): actor.data.remove_trait(trait_type)
	actor.view.global_position=Coordinates.to_world(origin)
	await physics_frame
	await physics_frame
	Fixture.click(self,Fixture.screen(world,target),MOUSE_BUTTON_RIGHT)
	await physics_frame
	await physics_frame
	check(not executor.movement.is_moving(),"RMB without selection does nothing")
	world.resident_selection.select(actor.data)
	Fixture.click(self,Fixture.screen(world,target),MOUSE_BUTTON_RIGHT)
	await physics_frame
	await physics_frame
	check(executor.movement.is_moving() and actor.commands.active_command!=null,"RMB issues real canonical command")
	for speed in [1,2,4]:
		executor.global_position=Coordinates.to_world(origin)
		world.game_time.set_speed(speed)
		executor.move_to(target)
		executor._physics_process(0.25)
		check(is_equal_approx(executor.get_sim_position().distance_to(origin),30.0*speed),"Normal speed scales once")
	world.game_time.set_speed(1)
	executor.global_position=Coordinates.to_world(origin)
	executor.move_to(target)
	for i in range(4): executor._physics_process(0.125)
	var short_frames=executor.global_position
	executor.global_position=Coordinates.to_world(origin)
	executor.move_to(target)
	executor._physics_process(0.5)
	check(executor.global_position.is_equal_approx(short_frames),"Frame count independent movement")
	executor.move_to(origin+Vector2(80,60))
	executor._physics_process(20)
	check(not executor.movement.is_moving() and executor.get_sim_position().is_equal_approx(origin+Vector2(80,60)),"Stops without overshoot")
	executor.move_to(target)
	paused=true
	var before=executor.global_position
	executor.set_physics_process(true)
	await create_timer(0.1,true).timeout
	executor.set_physics_process(false)
	check(executor.global_position==before,"Pause blocks physics advancement")
	world.game_time.set_speed(2)
	paused=false
	executor._physics_process(0.125)
	check(is_equal_approx(executor.global_position.distance_to(before),Coordinates.length_to_world(30)),"Resume uses current frame without catch-up")
	var route_target=executor.movement._target
	Fixture.click(self,world.resident_card_view().name_label.get_global_rect().get_center(),MOUSE_BUTTON_RIGHT)
	await physics_frame
	await physics_frame
	check(executor.movement._target==route_target,"UI RMB does not replace route")
	camera.pan(Vector2.RIGHT,0.2)
	Fixture.click(self,Fixture.screen(world,origin),MOUSE_BUTTON_RIGHT)
	await physics_frame
	await physics_frame
	check(executor.movement._target.is_equal_approx(Coordinates.to_world(origin)),"Perspective pan preserves cursor world coordinate")
	world.resident_selection.clear()
	check(executor.movement.is_moving(),"Selection clear preserves command")
	executor.set_physics_process(true)
	before=executor.global_position
	await create_timer(0.1).timeout
	check(executor.global_position!=before,"Actual unpaused physics moves resident")
	check(actor.data.hunger==20 and actor.data.fatigue==35 and actor.data.mood==65,"Movement does not mutate needs")
	world.free()
	print("resident_movement: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
