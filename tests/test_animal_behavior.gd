extends SceneTree
const Animal = preload("res://scripts/animal_data.gd")
const Behavior = preload("res://scripts/animal_behavior_controller.gd")
const Clock = preload("res://scripts/game_time.gd")
const Balance = preload("res://scripts/balance_config.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func fixture(id: StringName = &"sheep_test", minute: int = 600) -> Array:
	var clock := Clock.new()
	clock.total_minutes = minute
	root.add_child(clock)
	clock.set_process(false)
	var data := Animal.new(id,Vector3.ZERO,Vector3.ZERO)
	var controller := Behavior.new()
	root.add_child(controller)
	controller.wander_offer = func(_rng): return {"target":Vector3(1,0,1),"prepared":{}}
	controller.setup(data,clock)
	return [clock,data,controller]
func dispose(f: Array) -> void:
	f[2].free()
	f[0].free()
func grazing() -> void:
	var f := fixture()
	var clock = f[0]; var data = f[1]; var controller = f[2]
	check(data.species==Animal.Species.SHEEP and data.status==Animal.Status.WILD and data.wool_growth==0,"Wild sheep state starts at zero wool")
	check(data.habitat_radius==10.0 and data.contains(Vector3(10,0,0)) and not data.contains(Vector3(10.01,0,0)),"Habitat includes disk edge only")
	var minimum := 99; var maximum := 0
	for sample in range(200):
		controller._begin_graze(clock.total_minutes)
		var duration: int = data.behavior_ends_at-clock.total_minutes
		minimum=mini(minimum,duration); maximum=maxi(maximum,duration)
	check(minimum==30 and maximum==60,"Inclusive graze endpoints 30 and 60 are reachable")
	controller._begin_graze(600)
	var deadline: int = data.behavior_ends_at
	var state: int = controller.rng.state
	clock._advance_game_minutes(deadline-601)
	check(data.behavior==Animal.Behavior.GRAZE and data.wool_growth==0 and data.behavior_ends_at==deadline and controller.rng.state==state,"No reroll or partial wool before completion")
	clock._advance_game_minutes(1)
	check(data.wool_growth==1,"Full graze awards one wool")
	controller._on_minute(deadline)
	check(data.wool_growth==1,"Duplicate minute cannot award wool twice")
	controller._begin_graze(clock.total_minutes)
	controller.cancel_behavior()
	clock._advance_game_minutes(90)
	check(data.wool_growth==1 and data.behavior==Animal.Behavior.IDLE,"Cancelled graze has no delayed reward or restart")
	data.wool_growth=15
	controller._begin_graze(clock.total_minutes)
	clock._advance_game_minutes(data.behavior_ends_at-clock.total_minutes)
	check(data.wool_growth==15,"Growth saturates at15")
	data.wool_growth=-10
	check(data.wool_growth==0,"Wool cannot become negative")
	# A changed callback cancelling the just-completed period cannot be overwritten.
	controller._begin_graze(clock.total_minutes)
	var cancel_on_change: Callable = func():
		if data.behavior==Animal.Behavior.IDLE: controller.cancel_behavior()
	# One-shot avoids a recursive listener that cancels its own cancellation.
	data.changed.connect(cancel_on_change,CONNECT_ONE_SHOT)
	clock._advance_game_minutes(data.behavior_ends_at-clock.total_minutes)
	check(data.wool_growth==0 and data.behavior==Animal.Behavior.IDLE,"Reentrant cancellation wins before wool commit")
	dispose(f)
func sleep_cycle() -> void:
	var f := fixture(&"evening",1250)
	var clock = f[0]; var data = f[1]; var controller = f[2]
	controller._set_behavior(Animal.Behavior.GRAZE,1250,1295)
	var position: Vector3 = data.position
	clock._advance_game_minutes(10)
	check(data.behavior==Animal.Behavior.GRAZE and data.wool_growth==0,"21:00 does not interrupt existing graze")
	clock._advance_game_minutes(35)
	check(data.wool_growth==1 and data.behavior==Animal.Behavior.SLEEP and data.sleep_started_at==1295,"20:50 +45 finishes at21:35, then sleeps")
	var wake: int = data.wake_at
	check(wake>=1740 and wake<=1860 and data.behavior_ends_at==wake,"Wake sampled at sleep for next05–07")
	var rng_state: int = controller.rng.state
	clock._advance_game_minutes(wake-clock.total_minutes-1)
	check(data.behavior==Animal.Behavior.SLEEP and data.wake_at==wake and data.wool_growth==1 and controller.rng.state==rng_state and data.position==position,"Night sleep is stationary with no reroll or wool")
	clock._advance_game_minutes(1)
	check(data.behavior in [Animal.Behavior.GRAZE,Animal.Behavior.WANDER],"Wakes at its own minute even before06")
	dispose(f)
	f=fixture(&"night_spawn",1450)
	check(f[1].behavior==Animal.Behavior.SLEEP and f[1].wake_at>=1740 and f[1].wake_at<=1860,"After-midnight initialization targets upcoming morning")
	dispose(f)
	var a:=fixture(&"wake_a",1260);var b:=fixture(&"wake_b",1260)
	check(a[1].wake_at!=b[1].wake_at,"Chosen fixed IDs demonstrate independent wake times; equality in general is allowed")
	var prior_choices: int=a[2].choices
	a[2]._on_minute(1860)
	check(a[2].choices>prior_choices and a[1].behavior!=Animal.Behavior.SLEEP,"Large checkpoint crosses midnight and wake")
	dispose(a);dispose(b)
func randomness_and_failures() -> void:
	var a:=fixture(&"repeat");var b:=fixture(&"repeat");var other:=fixture(&"unrelated")
	var walks:=0;var grazes:=0
	for sample in range(2000):
		a[2]._choose(600);b[2]._choose(600)
		other[2]._choose(600)
		if a[1].behavior==Animal.Behavior.WANDER:walks+=1
		else:grazes+=1
		if a[1].behavior!=b[1].behavior or a[1].behavior_ends_at!=b[1].behavior_ends_at or a[2].rng.state!=b[2].rng.state:
			check(false,"Same ID and event stream remain deterministic independently of others")
	check(walks>1100 and walks<1300 and walks+grazes==2000,"Seeded actual behavior selection follows60/40 weights")
	var current_token: int=a[2].token
	a[2]._set_behavior(Animal.Behavior.WANDER,600,-1)
	a[2].finish_wander(current_token,true)
	check(a[1].behavior==Animal.Behavior.WANDER,"Old completion ignored")
	current_token=a[2].token
	a[2].finish_wander(current_token,false)
	check(a[1].behavior==Animal.Behavior.IDLE and a[1].behavior_ends_at==605,"Unreachable walk backs off5 game minutes")
	var choices: int=a[2].choices
	a[2].finish_wander(current_token,true)
	a[2]._on_minute(604)
	check(a[2].choices==choices,"Duplicate arrival and backoff ticks do not retry")
	a[2]._on_minute(605)
	check(a[2].choices==choices+1,"One new choice after backoff")
	for f in [a,b,other]:dispose(f)
func speeds() -> void:
	for speed in Clock.SUPPORTED_SPEEDS:
		var f:=fixture(StringName("speed_%d" % speed),600)
		f[2]._set_behavior(Animal.Behavior.GRAZE,600,630)
		f[0].set_speed(speed)
		f[0].advance(29.0/speed)
		check(f[1].wool_growth==0,"No early wool at x%d" % speed)
		f[0].advance(1.01/speed)
		check(f[1].wool_growth==1,"GameTime completes30-minute graze at x%d" % speed)
		dispose(f)
func run() -> void:
	grazing();sleep_cycle();randomness_and_failures();speeds()
	print("Animal behavior: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
