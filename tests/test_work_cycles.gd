extends SceneTree
const Seed = preload("res://tests/utility_test_seed.gd")
const Setup = preload("res://tests/behavior_test_setup.gd")
const Balance = preload("res://scripts/balance_config.gd")
const Type = preload("res://scripts/need_type.gd").Type
const Activity = preload("res://scripts/resident_activity.gd").Type
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
var failures := 0
func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _run() -> void:
	for need_type in [Type.SOCIAL, Type.LEISURE]:
		for speed in [1, 2, 4, 10, 20]:
			var scene = Setup.make_scene(self)
			var resident = scene.resident_runtimes[2]
			resident.data.work_location_id = scene.gatherer_hut_data.id
			resident.decision.work_available = scene.production.can_work.bind(resident.data)
			scene.gatherer_hut_data.production_progress = 7
			scene.game_time.set_speed(speed)
			scene.game_time.debug_next_phase()
			resident.view._process(20)
			check(resident.data.activity == Activity.WORKING, "Arrival starts work cycle")
			resident.data.get_need(need_type).value = 100
			check(resident.data.get_need(need_type).get_priority() == (8000 if need_type == Type.SOCIAL else 7500), "SOCIAL/LEISURE can outrank 7000")
			var count: int = resident.decision.decision_count
			resident.decision.request_decision("ordinary_growth")
			paused = true
			scene.game_time.advance(1000)
			check(scene.gatherer_hut_data.production_progress == 7, "Pause freezes work and production")
			paused = false
			scene.game_time.advance(59.0 / speed)
			check(resident.data.activity == Activity.WORKING and resident.decision.decision_count == count, "Ordinary need cannot interrupt first 59 work minutes")
			resident.decision.rng.seed = Seed.for_action(resident.decision.collect_actions(true), "SOCIAL" if need_type == Type.SOCIAL else "LEISURE")
			scene.game_time.advance(1.0 / speed)
			check(resident.decision.decision_count > count, "60-minute boundary creates ordinary decision point at every speed")
			check(resident.intents.current_intent.reason_id == (&"social" if need_type == Type.SOCIAL else &"leisure"), "Seeded normal selector chooses the higher need before next work cycle")
			check(scene.gatherer_hut_data.resources.get_amount(FOOD) == 2 and scene.gatherer_hut_data.production_progress == 7, "60 work minutes produce two FOOD; building's remainder survives break")
			scene.game_time.debug_skip_minutes(1)
			check(scene.gatherer_hut_data.production_progress == 7, "Break contributes no production and does not reset progress")
			print("Work-cycle proof: 59 min WORKING -> 60 min decision -> ", "SOCIAL" if need_type == Type.SOCIAL else "LEISURE", "; building progress retained")
			scene.free()
	var restarted_scene = Setup.make_scene(self)
	var restarted_resident = restarted_scene.resident_runtimes[2]
	restarted_resident.data.work_location_id = restarted_scene.gatherer_hut_data.id
	restarted_resident.decision.work_available = restarted_scene.production.can_work.bind(restarted_resident.data)
	restarted_scene.game_time.debug_next_phase()
	restarted_resident.view._process(20)
	restarted_scene.game_time.debug_skip_minutes(60)
	check(restarted_resident.data.activity == Activity.WORKING and restarted_resident.decision._work_cycle_ends_at == restarted_scene.game_time.total_minutes + 60, "Work can win again and start the next cycle")
	restarted_resident.data.fatigue = 100
	check(restarted_resident.data.activity == Activity.SLEEPING and not restarted_resident.decision._work_cycle_active, "Forced fatigue interrupts the new work cycle immediately")
	check(restarted_scene.kitchen_data.resources.get_capacity(FOOD) == 20 and Balance.GATHERER_WORK_MINUTES_PER_FOOD == 30, "New FOOD balance")
	restarted_scene.free()
	print("Work cycle checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
