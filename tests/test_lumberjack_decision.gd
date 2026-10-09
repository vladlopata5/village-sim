extends SceneTree
const Profession = preload("res://scripts/resident_profession.gd")
const Balance = preload("res://scripts/balance_config.gd")
const Modifiers = preload("res://scripts/resident_modifiers.gd")
const Resources = preload("res://scripts/resource_type.gd")
var checks := 0
var failures := 0
var lines: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func logged(line: String, _level: int) -> void: lines.append(line)
func world():
	var scene = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(scene)
	scene.game_time.set_process(false)
	scene.game_logger.line_logged.connect(logged)
	for actor in scene.resident_runtimes:
		actor.view.set_physics_process(false)
		if actor.data.resident_name != "Марина": actor.decision._deciding = true
	return scene
func prepare_marina(scene: Node) -> Node:
	var marina = scene.resident_runtimes[3]
	check(marina.data.resident_name=="Марина","Regression uses actual starting Marina")
	scene.game_time.debug_skip_minutes(8)
	check(scene.player_control.assign_profession(marina.data.id,Profession.Type.LUMBERJACK),"Assign at 06:08 through management API")
	check(marina.data.work_location_id.is_empty() and marina.data.profession==Profession.Type.LUMBERJACK,"UI enum/world-work profession does not need workplace")
	for kind in range(4): marina.data.get_need(kind).value = 0
	return marina
func run() -> void:
	var scene = world()
	await physics_frame
	var marina = prepare_marina(scene)
	scene.game_time.debug_skip_minutes(52) # Real phase boundary drives the existing schedule/AI.
	var worker = marina.get_node("Lumberjack")
	check(scene.game_time.get_phase()=="День" and scene._work_available(marina),"Main3D forestry provider exposes reachable standing tree")
	check(marina.decision._has_work(),"AI workplace gate admits lumberjack world-work")
	var work: Array = marina.decision.collect_actions(marina.decision._has_work()).filter(func(row): return row.id=="WORK")
	check(work.size()==1 and work[0].priority==Modifiers.action_utility(marina.data,Modifiers.Action.WORK,Balance.WORK_PRIORITY),"Forestry receives unchanged standard WORK utility")
	check(lines.any(func(line): return "Марина: выбрал работу" in line),"Real selector chose WORK at 07:00")
	check(worker.tree != null and marina.intents.current_intent.reason_id==&"chop_tree","Ordinary AI creates CHOP_TREE task without directly calling worker")
	if worker.tree != null:
		var tree = worker.tree
		check(tree.reservation_owner_id==StringName(marina.data.id),"Concrete selected tree belongs to Marina")
		check(not worker.chopping,"Travel precedes chopping")
		for step in range(600):
			marina.view._physics_process(0.05)
			if not marina.view.movement.is_moving(): break
		check(worker.chopping and marina.view.get_sim_position().distance_to(worker.target)<8,"Real executor reaches access point and begins work")
		scene.game_time.debug_skip_minutes(60)
		check(tree.state==tree.State.DEPLETED and scene.ground_resources.drops.size()==3,"Normal AI-selected tree yields exactly three LOG")
		check(scene.ground_resources.drops.all(func(drop): return drop.resource_type==Resources.Type.LOG and drop.amount==1),"Physical LOG unit representation preserved")
	scene.free()
	lines.clear()
	scene = world()
	await physics_frame
	marina = prepare_marina(scene)
	for tree in scene.trees: tree.claim(&"other_worker")
	scene.game_time.debug_skip_minutes(52)
	check(not scene._work_available(marina) and not marina.decision._has_work(),"All trees unavailable removes WORK availability")
	check(not marina.decision.collect_actions(marina.decision._has_work()).any(func(row): return row.id=="WORK"),"No available tree means no WORK candidate")
	check(marina.get_node("Lumberjack").tree==null and marina.intents.current_intent.reason_id==&"wander","Existing normal wander remains available without trees")
	check(not lines.any(func(line): return "Марина: выбрал работу" in line),"Unavailable forestry does not start work")
	scene.free()
	print("Lumberjack decision: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
