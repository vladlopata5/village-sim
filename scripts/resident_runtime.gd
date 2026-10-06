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
var commands = Commands.new()
var social = Social.new()
var wander = Wander.new()
var data: RefCounted
var view: Node2D
var intents = Intents.new()
var schedule = Schedule.new()
var need_dynamics = Dynamics.new()
var decision = Decision.new()
var needs = Needs.new()

func setup(resident: RefCounted, presentation: Node2D, clock: Node, locations: RefCounted, buildings: Array) -> void:
	data = resident
	view = presentation
	for controller in [intents, commands, schedule, need_dynamics, needs, decision, social, wander]:
		add_child(controller)
	for controller in [commands, schedule, needs, decision, social, wander]:
		controller.logger = logger
	intents.setup(data)
	intents.intent_changed.connect(decision.capture_work_assignment.bind(data))
	intents.intent_changed.connect(view.apply_intent)
	view.intent_completed.connect(intents.report_arrival)
	commands.setup(data, intents)
	schedule.setup(clock, locations, intents)
	need_dynamics.setup(clock, data)
	needs.setup(clock, data, buildings, locations, intents, schedule)
	social.setup(self, clock)
	social.conversation_position_requested.connect(view.move_to)
	wander.setup(self, clock)
	decision.wander = wander
	decision.social = social
	decision.setup(clock, data, intents, needs, schedule)
	# Complete cleanup in simulation before an executor can arrive synchronously.
	intents.intent_changed.disconnect(view.apply_intent)
	intents.intent_changed.connect(view.apply_intent)

func _process(_delta: float) -> void:
	if logger != null and data != null: logger.sync_activity(data)
