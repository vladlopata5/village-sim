extends Node
const EventLog = preload("res://scripts/game_logger.gd")
var logger: EventLog
## One resident's controller bundle. Simulation data has no reference back here.
const Intents = preload("res://scripts/resident_intent_controller.gd")
const Schedule = preload("res://scripts/resident_schedule_controller.gd")
const Dynamics = preload("res://scripts/need_dynamics.gd")
const Decision = preload("res://scripts/decision_controller.gd")
const Needs = preload("res://scripts/resident_needs_controller.gd")
const Wander = preload("res://scripts/resident_wander_controller.gd")
const Social = preload("res://scripts/resident_social_controller.gd")
const Commands = preload("res://scripts/player_command_controller.gd")
const Assignments = preload("res://scripts/resident_assignment_controller.gd")
var farmer = preload("res://scripts/resident_farmer_controller.gd").new()
var clothing = preload("res://scripts/resident_clothing_controller.gd").new()
var shepherd = preload("res://scripts/resident_shepherd_controller.gd").new()
var self_logistics = preload("res://scripts/resident_self_logistics.gd").new()
var recipe_work = preload("res://scripts/resident_recipe_controller.gd").new()
var builder = preload("res://scripts/resident_builder_controller.gd").new()
var assignments = Assignments.new()
var commands = Commands.new()
var social = Social.new()
var wander = Wander.new()
var data: RefCounted
var view: Node
var intents = Intents.new()
var schedule = Schedule.new()
var need_dynamics = Dynamics.new()
var decision = Decision.new()
var needs = Needs.new()
var food_availability: RefCounted

func setup(resident: RefCounted, presentation: Node, clock: Node, locations: RefCounted, buildings: Array, housing: RefCounted = null) -> void:
	data = resident
	data.skill_changed.connect(_on_skill_changed)
	view = presentation
	for controller in [intents, commands, schedule, need_dynamics, needs, assignments, decision, social, wander, builder, recipe_work, self_logistics, shepherd, clothing, farmer]:
		add_child(controller)
	for controller in [commands, schedule, needs, assignments, decision, social, wander, builder, recipe_work]:
		controller.logger = logger
	intents.setup(data)
	if view.has_method("bind_building_use") and locations.get("uses")!=null:
		view.bind_building_use(locations.uses,intents)
	intents.intent_changed.connect(decision.capture_work_assignment.bind(data))
	view.intent_completed.connect(intents.report_arrival)
	commands.setup(data, intents)
	schedule.fallback_housing = housing
	schedule.setup(clock, locations, intents, buildings)
	schedule.production_continues = func(): return recipe_work.keeps_shift_action() or shepherd.keeps_shift_action() or farmer.keeps_shift_action()
	if view.has_signal("building_use_unavailable"):
		view.building_use_unavailable.connect(_on_building_use_unavailable)
	intents.intent_changed.connect(view.apply_intent)
	view.apply_intent(intents.current_intent)
	if view.has_method("exit_for_action"): needs.exit_building_provider = view.exit_for_action
	need_dynamics.eating_rate_provider = needs.get_hunger_eating_rate
	need_dynamics.setup(clock, data)
	needs.food_availability = food_availability
	needs.setup(clock, data, buildings, locations, intents, schedule)
	assignments.setup(data, needs, intents, social, clock)
	decision.assignments = assignments
	decision.clothing = clothing
	social.setup(self, clock)
	social.conversation_position_requested.connect(view.move_to)
	wander.setup(self, clock)
	decision.wander = wander
	decision.social = social
	decision.setup(clock, data, intents, needs, schedule)
	builder.setup(data, clock, locations, buildings, intents, decision)
	recipe_work.setup(self, clock, locations, buildings)
	# Complete cleanup in simulation before an executor can arrive synchronously.
	intents.intent_changed.disconnect(view.apply_intent)
	intents.intent_changed.connect(view.apply_intent)

func _process(_delta: float) -> void:
	if logger != null and data != null: logger.sync_activity(data)

func _on_skill_changed(skill: int, amount: int, previous_level: int) -> void:
	if logger == null: return
	var label: String = preload("res://scripts/skill_type.gd").display_name(skill)
	var level: int = data.get_skill_level(skill)
	logger.debug(EventLog.AI, "%s: %s +%d XP (%d XP, ур. %d)" % [data.resident_name, label, amount, data.get_skill_xp(skill), level])
	if level > previous_level:
		logger.info(EventLog.AI, "%s: навык «%s» повышен до уровня %d" % [data.resident_name, label, level])

func _on_building_use_unavailable(intent: RefCounted) -> void:
	if intent.reason_id in [&"night_home",&"night_outdoor"]:
		schedule.on_sleep_slot_unavailable(intent)
		return
	intents.abort_current(intent)
	decision.call_deferred("request_decision","building_slot_unavailable")

func _exit_tree() -> void:
	# Physical removal must not leave a permanent housing member or occupied sleep slot.
	if data!=null: data.household_id=&""
	if is_instance_valid(view) and is_instance_valid(intents): intents.abort_current(intents.current_intent)
