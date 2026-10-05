extends Node
const EventLog = preload("res://scripts/game_logger.gd")
var logger: EventLog
## One resident's controller bundle. Simulation data has no reference back here.
const Intents = preload("res://scripts/resident_intent_controller.gd")
const Schedule = preload("res://scripts/resident_schedule_controller.gd")
const Dynamics = preload("res://scripts/need_dynamics.gd")
const Decision = preload("res://scripts/decision_controller.gd")
const Needs = preload("res://scripts/resident_needs_controller.gd")
const Social = preload("res://scripts/resident_social_controller.gd")
var social = Social.new()
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
	for controller in [intents, schedule, need_dynamics, needs, decision, social]:
		add_child(controller)
	for controller in [schedule, needs, decision, social]:
		controller.logger = logger
	intents.setup(data)
	intents.intent_changed.connect(view.apply_intent)
	view.intent_completed.connect(intents.report_arrival)
	schedule.setup(clock, locations, intents)
	need_dynamics.setup(clock, data)
	needs.setup(clock, data, buildings, locations, intents, schedule)
	social.setup(self, clock)
	decision.social = social
	decision.setup(clock, data, intents, needs, schedule)

func _process(_delta: float) -> void:
	if logger != null and data != null: logger.sync_activity(data)
