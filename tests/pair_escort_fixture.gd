extends RefCounted
const Resident = preload("res://scripts/resident_data.gd")
const Front = preload("res://scripts/world_3d/resident_executor_3d.gd")
const Back = preload("res://scripts/world_3d/animal_executor_3d.gd")
const Animal = preload("res://scripts/animal_data.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
class CountedGrid:
	extends "res://scripts/navigation_grid.gd"
	var raw_calls := 0
	var smooth_calls := 0
	func find_raw_path(start: Vector3, target: Vector3) -> PackedVector3Array:
		raw_calls+=1
		return super.find_raw_path(start,target)
	func smooth_path(raw: PackedVector3Array) -> PackedVector3Array:
		smooth_calls+=1
		return super.smooth_path(raw)
static var serial := 0
static func make(tree: SceneTree, start: Vector3=Vector3(0.25,0,0.25), back: Vector3=Vector3(-4.25,0,0.25), goal: Vector3=Vector3(12.25,0,0.25), grid: RefCounted=null, back_script: Script=null) -> Dictionary:
	serial+=1
	var clock=preload("res://scripts/game_time.gd").new();tree.root.add_child(clock);clock.set_process(false)
	var nav=grid if grid!=null else CountedGrid.new(Rect2(-32,-24,64,48))
	var data=Resident.new("escort_test_%d" % serial, "Ведущий",25)
	var intents=preload("res://scripts/resident_intent_controller.gd").new();tree.root.add_child(intents);intents.setup(data)
	var front=Front.new();tree.root.add_child(front);front.navigation=nav;front.position=start;front.setup(data);front.set_physics_process(false)
	var uses=preload("res://scripts/world_3d/building_use_3d.gd").new();uses.navigation=nav;front.bind_building_use(uses,intents)
	intents.intent_changed.connect(front.apply_intent)
	front.intent_completed.connect(intents.report_arrival)
	front.intent_failed.connect(intents.abort_current)
	clock.speed_changed.connect(front.set_time_speed)
	var sheep=back_script.new() if back_script!=null else Back.new();tree.root.add_child(sheep);sheep.navigation=nav
	sheep.setup(Animal.new(StringName("escort_sheep_%d" % serial),Vector3.ZERO,back),clock);sheep.set_physics_process(false);sheep.behavior.cancel_behavior()
	# Normal behavior really resumes; isolate pair A* counts from the next wild offer.
	sheep.behavior.wander_offer=func(_rng):return {}
	var pair=preload("res://scripts/world_3d/pair_escort_3d.gd").new();tree.root.add_child(pair);pair.set_physics_process(false)
	var intent=Intent.new(Intent.Type.MOVE_TO,&"escort_fixture",Coordinates.to_sim(goal),50,true)
	intents.submit(intent)
	nav.raw_calls=0;nav.smooth_calls=0
	return {"clock":clock,"nav":nav,"front":front,"back":sheep,"pair":pair,"intents":intents,"intent":intent,"goal":goal}
static func tick(f: Dictionary, delta: float) -> void:
	f.clock.advance(delta)
	# Ordinary executors must not apply a second step while owned by the pair.
	f.front._physics_process(delta)
	f.back._physics_process(delta)
	f.pair.advance(delta)
static func finish(f: Dictionary, delta: float=0.05, steps: int=20000) -> void:
	for step in steps:
		if not f.pair.is_active():break
		tick(f,delta)
static func dispose(f: Dictionary) -> void:
	for key in ["pair","front","back","intents","clock"]:
		if is_instance_valid(f[key]):f[key].free()
