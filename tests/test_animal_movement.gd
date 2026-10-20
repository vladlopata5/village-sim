extends SceneTree
const Animal = preload("res://scripts/animal_data.gd")
const Executor = preload("res://scripts/world_3d/animal_executor_3d.gd")
const Clock = preload("res://scripts/game_time.gd")
const Balance = preload("res://scripts/balance_config.gd")
class CountingGrid:
	extends "res://scripts/navigation_grid.gd"
	var raw_calls := 0
	var smooth_calls := 0
	func find_raw_path(start: Vector3, target: Vector3) -> PackedVector3Array:
		raw_calls += 1
		return super.find_raw_path(start,target)
	func smooth_path(raw: PackedVector3Array) -> PackedVector3Array:
		smooth_calls += 1
		return super.smooth_path(raw)
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func fixture() -> Array:
	var clock := Clock.new();root.add_child(clock);clock.set_process(false)
	var nav := CountingGrid.new(Rect2(-16,-16,32,32))
	var actor := Executor.new();root.add_child(actor);actor.navigation=nav
	actor.setup(Animal.new(&"movement_sheep",Vector3.ZERO,Vector3(-4.25,0,-2.25)),clock)
	actor.set_physics_process(false);actor.behavior.cancel_behavior()
	nav.raw_calls=0;nav.smooth_calls=0
	return [clock,nav,actor]
func dispose(f: Array) -> void:
	f[2].free();f[0].free()
func walk(f: Array, target: Vector3) -> void:
	f[2].behavior._set_behavior(Animal.Behavior.WANDER,f[0].total_minutes,-1)
	f[2]._move(f[2].behavior.token,target,{})
func physical() -> void:
	for speed in Clock.SUPPORTED_SPEEDS:
		var speed_fixture:=fixture();var speed_grid=speed_fixture[1];var speed_actor=speed_fixture[2]
		speed_grid.add_blocker(&"wall",Rect2(-0.5,-4,1,4))
		var revision: int=speed_grid.revision
		walk(speed_fixture,Vector3(4.25,0,-2.25));speed_actor.set_time_speed(speed)
		var previous: Vector3=speed_actor.position
		var travelled:=0.0;var reached:=false;var safe:=true
		# Prevent a completed walk immediately starting another movement in this fixture.
		speed_actor.behavior.behavior_finished.connect(func(_kind,_success):speed_actor.behavior.cancel_behavior())
		for step in range(2400):
			speed_actor._physics_process(1.0/60)
			var distance: float=previous.distance_to(speed_actor.position)
			if distance>Balance.SHEEP_WALK_SPEED*speed/60+0.0001:safe=false
			travelled+=distance;previous=speed_actor.position
			if not speed_grid.is_world_walkable(speed_actor.position) or not speed_actor.data.contains(speed_actor.position):safe=false
			if speed_actor.position.is_equal_approx(Vector3(4.25,0,-2.25)):reached=true;break
		check(reached and safe and travelled>8.5,"Physical obstacle detour, no teleport, habitat, x%d" % speed)
		check(speed_grid.raw_calls==1 and speed_grid.smooth_calls==1 and speed_grid.revision==revision,"One route per walk; moving sheep publishes no revision, x%d" % speed)
		check(speed_actor.data.position==speed_actor.position,"Data reflects sole executor position")
		check(speed_actor.view.rotation.y!=0.0,"View turns toward physical movement")
		dispose(speed_fixture)
	var f:=fixture();var actor=f[2];var nav=f[1]
	actor.behavior._begin_graze(360)
	var prior: Vector3=actor.position
	for step in range(120):actor._physics_process(1.0/60)
	check(actor.position==prior and nav.raw_calls==0 and actor.view.head.position.y<0.45,"Graze is stationary, distinct, and has no path queries")
	actor.behavior._begin_sleep(1260)
	for step in range(120):actor._physics_process(1.0/60)
	check(actor.position==prior and nav.raw_calls==0 and actor.view.body.position.y<0.0,"Sleep lowers body, remains stationary, no path queries")
	check(actor.movement.surface_speed.call(Vector2i.ZERO,1.25)==1.0 and actor.movement.surface_speed.call(Vector2i.ZERO,0.2)==0.2,"No fast road bonus, slow tree terrain retained")
	actor.behavior.cancel_behavior()
	var random:=RandomNumberGenerator.new();random.seed=12
	var offer: Dictionary=actor._wander_offer(random)
	check(not offer.is_empty() and actor.data.contains(offer.target) and Array(offer.prepared.raw).all(actor.data.contains),"Bounded target offer and complete raw path stay in disk")
	var raw_before: int=nav.raw_calls
	actor.behavior._set_behavior(Animal.Behavior.WANDER,360,-1)
	actor._move(actor.behavior.token,offer.target,offer.prepared);actor._physics_process(0.01)
	check(nav.raw_calls==raw_before and nav.smooth_calls==1,"Offer reused once; no second A* before movement")
	dispose(f)
func obstacles() -> void:
	var f:=fixture();var actor=f[2];var nav=f[1]
	walk(f,Vector3(4.25,0,-2.25));actor._physics_process(0.1)
	nav.add_blocker(&"new_wall",Rect2(-0.5,-4,1,4));actor._physics_process(0.1)
	check(nav.raw_calls==2 and actor.movement.current_path().size()>2,"Changed world triggers normal safe replan")
	nav.add_blocker(&"closed",Rect2(0,-16,1,32));actor._physics_process(0.1)
	check(not actor.movement.is_moving() and actor.data.behavior==Animal.Behavior.IDLE,"Unreachable replan ends attempt with backoff")
	var calls: int=nav.raw_calls
	for step in range(100):actor._physics_process(0.016)
	check(nav.raw_calls==calls,"No path retry every physics tick after failure")
	dispose(f)
	f=fixture();actor=f[2];nav=f[1]
	actor.data.habitat_radius=0.1
	actor.data.habitat_center=actor.position
	var random:=RandomNumberGenerator.new();random.seed=1
	check(actor._wander_offer(random).is_empty() and nav.raw_calls<=Balance.SHEEP_TARGET_ATTEMPTS,"No acceptable target terminates within candidate bound")
	dispose(f)
	f=fixture();actor=f[2]
	actor.movement.set_target(Vector3(12,0,0));actor._physics_process(0.1)
	check(not actor.movement.is_moving(),"Even a replacement path outside habitat is stopped before physical movement")
	dispose(f)
func canonical() -> void:
	var world=load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_logger.console_enabled=false
	check(world.animals.size()==3 and world.animal_executors.size()==3,"Canonical world creates exactly3 sheep")
	var ids: Dictionary={}
	for index in world.animals.size():
		var animal=world.animals[index];var actor=world.animal_executors[index]
		ids[animal.id]=true
		check(animal.habitat_center==Vector3(4.25,0,6.25) and animal.habitat_radius==10,"Common authored habitat and10WORLD radius")
		check(world.navigation.is_world_walkable(actor.global_position) and actor.navigation==world.navigation,"Valid spawn and shared navigation")
		check(world.runtime_placement_blockers.has_blocker(animal.id) and not world.navigation._blockers.has(animal.id),"Blocks placement only, no moving navigation obstacle")
		check(not actor.movement.cell_entered.is_connected(world.roads.visit),"Sheep never trample roads")
	check(ids.size()==3 and world.animal_executors[0].behavior.rng.state!=world.animal_executors[1].behavior.rng.state,"Stable unique IDs and independent random streams")
	world.free()
	await process_frame
func run() -> void:
	physical();obstacles();await canonical()
	print("Animal movement/world: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
