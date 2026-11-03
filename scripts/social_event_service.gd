extends Node
## Rolls only at action boundaries. No persistent event pool and no AI feedback.
const Event = preload("res://scripts/social_event.gd")
const Balance = preload("res://scripts/balance_config.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const EventLog = preload("res://scripts/game_logger.gd")
signal event_resolved(result: Event)
signal interaction_committed(result: Event)
var enabled := true
var rng: RefCounted = RandomNumberGenerator.new()
var logger: EventLog
var world: Node
var clock: Node
var buildings: Array = []
var _attempt_sequence := 0
var _resolve_depth := 0
var _publishing_commits := false
var _committed: Array = []
func _init() -> void:
	rng.randomize()
func set_seed(value: int) -> void:
	rng.seed = value
func setup(social_world: Node, game_clock: Node, locations: Array) -> void:
	world = social_world
	clock = game_clock
	buildings = locations
	world.conversation_joined.connect(_on_conversation_joined)
	for runtime in world.residents.values(): register(runtime)
func register(runtime: Node) -> void:
	runtime.needs.meal_begun.connect(_on_meal.bind(runtime))
	runtime.decision.work_cycle_started.connect(_on_work.bind(runtime))
	runtime.builder.work_cycle_started.connect(_on_work.bind(runtime))
	runtime.recipe_work.work_cycle_started.connect(_on_work.bind(runtime))
func chance_for(context: Event.Context) -> float:
	match context:
		Event.Context.CONVERSATION: return Balance.SOCIAL_EVENT_CHANCE_CONVERSATION
		Event.Context.MEAL: return Balance.SOCIAL_EVENT_CHANCE_MEAL
		_: return Balance.SOCIAL_EVENT_CHANCE_WORK
static func attitude(a: RefCounted, b: RefCounted) -> int:
	return clampi(a.get_opinion(b.id) + a.get_trait_preference_score(b), Balance.SOCIAL_ATTITUDE_MIN, Balance.SOCIAL_ATTITUDE_MAX)
static func reaction(score: int) -> Event.Reaction:
	if score < -Balance.SOCIAL_REACTION_THRESHOLD: return Event.Reaction.NEGATIVE
	if score > Balance.SOCIAL_REACTION_THRESHOLD: return Event.Reaction.POSITIVE
	return Event.Reaction.NEUTRAL
static func delta(value: Event.Reaction) -> int:
	match value:
		Event.Reaction.NEGATIVE: return Balance.SOCIAL_EVENT_NEGATIVE_DELTA
		Event.Reaction.POSITIVE: return Balance.SOCIAL_EVENT_POSITIVE_DELTA
		_: return Balance.SOCIAL_EVENT_NEUTRAL_DELTA
func presence(runtime: Node) -> Dictionary:
	if runtime.data.activity == Activity.Type.EATING and not runtime.needs.meal_location_id().is_empty():
		return {"building_id": runtime.needs.meal_location_id(), "tags": ["EATING", "VISITOR"]}
	if runtime.data.activity == Activity.Type.WORKING:
		if runtime.builder.phase == runtime.builder.Phase.BUILDING and runtime.builder.site != null:
			return {"building_id": runtime.builder.site.id, "tags": ["WORKING", "WORKER"]}
		if runtime.recipe_work.phase == runtime.recipe_work.Phase.WORKING and runtime.recipe_work.building != null:
			return {"building_id":runtime.recipe_work.building.id,"tags":["WORKING","WORKER"]}
		var work: Dictionary = runtime.decision.get_committed_work_assignment()
		if not work.is_empty(): return {"building_id": work.location_id, "tags": ["WORKING", "WORKER"]}
	if runtime.data.activity == Activity.Type.TALKING:
		var group = world.group_of(runtime.data.id)
		if group != null:
			# A stationary conversation is meaningful presence; a passing route is not.
			for building in buildings:
				if building.is_built() and building.footprint().has_point(group.center):
					return {"building_id": building.id, "tags": ["TALKING", "VISITOR"]}
			return {"tags": ["TALKING", "VISITOR"]}
	return {}
func participant_pool(runtime: Node, context: Event.Context, location_id: StringName = &"") -> Array:
	var pool: Array = []
	var group = world.group_of(runtime.data.id) if context == Event.Context.CONVERSATION else null
	for other in world.residents.values():
		if other == runtime or not is_instance_valid(other) or other.is_queued_for_deletion(): continue
		if context == Event.Context.CONVERSATION:
			if group != null and other.data.activity == Activity.Type.TALKING and other.data.id in group.participants: pool.append(other)
		else:
			var state := presence(other)
			if not location_id.is_empty() and state.get("building_id", &"") == location_id: pool.append(other)
	return pool
func trigger(runtime: Node, context: Event.Context, location_id: StringName = &"") -> Event:
	if not enabled: return null
	var chance := chance_for(context)
	var roll: float = rng.randf() # Keep the existing draw even at 100%.
	if chance < 1.0 and roll >= chance: return null
	var pool := participant_pool(runtime, context, location_id)
	if pool.is_empty(): return null
	var other: Node = pool[rng.randi_range(0, pool.size() - 1)]
	var first := presence(runtime)
	var second := presence(other)
	return resolve(runtime.data, other.data, context, first.get("tags", []), second.get("tags", []), location_id if not location_id.is_empty() else first.get("building_id", &""))
func resolve(a: RefCounted, b: RefCounted, context: Event.Context, tags_a: Array = [], tags_b: Array = [], location_id: StringName = &"") -> Event:
	if a == null or b == null or a.id == b.id: return null
	_attempt_sequence += 1
	var attempt := _attempt_sequence
	var minute: int = clock.total_minutes if is_instance_valid(clock) else 0
	_resolve_depth += 1
	var result := Event.new()
	result.context = context
	result.resident_1_id = a.id
	result.resident_2_id = b.id
	# Snapshot BOTH attitudes before either direction is mutated.
	result.attitude_1_to_2 = attitude(a, b)
	result.attitude_2_to_1 = attitude(b, a)
	result.roll_1 = rng.randi_range(-100, 100)
	result.roll_2 = rng.randi_range(-100, 100)
	result.reaction_1 = reaction(result.roll_1 + result.attitude_1_to_2)
	result.reaction_2 = reaction(result.roll_2 + result.attitude_2_to_1)
	result.opinion_delta_1 = delta(result.reaction_1)
	result.opinion_delta_2 = delta(result.reaction_2)
	var applied_1: Dictionary = a.apply_opinion_change(b.id, result.opinion_delta_1)
	var applied_2: Dictionary = b.apply_opinion_change(a.id, result.opinion_delta_2)
	result._participant_sources = [weakref(a), weakref(b)]
	# Owned operation values are historical facts, not later callback-edited state.
	result._confirmed_context = {
		"occurrence_id": JSON.stringify(["social.resolved", attempt]),
		"trigger": "social.resolved", "minute": minute,
		"actor": {"kind": "resident", "id": a.id},
		"other": {"kind": "resident", "id": b.id},
		"payload": {
			"interaction": Event.Context.keys()[context],
			"reaction_1": Event.Reaction.keys()[result.reaction_1],
			"reaction_2": Event.Reaction.keys()[result.reaction_2],
			"opinion_delta_1": result.opinion_delta_1, "opinion_delta_2": result.opinion_delta_2,
			"applied_delta_1": applied_1.after - applied_1.before, "applied_delta_2": applied_2.after - applied_2.before,
			"opinion_before_1": applied_1.before, "opinion_after_1": applied_1.after,
			"opinion_before_2": applied_2.before, "opinion_after_2": applied_2.after,
			"attitude_1_to_2": result.attitude_1_to_2, "attitude_2_to_1": result.attitude_2_to_1,
			"roll_1": result.roll_1, "roll_2": result.roll_2,
			"location_id": String(location_id), "time_known": is_instance_valid(clock),
			"tags_1": tags_a.duplicate(), "tags_2": tags_b.duplicate()
		}
	}
	_committed.append(result)
	if logger != null:
		logger.info(EventLog.SOCIAL_EVENT, "context=%s A=%s B=%s | %s attitude=%d roll=%d reaction=%s delta=%+d | %s attitude=%d roll=%d reaction=%s delta=%+d" % [Event.Context.keys()[context], a.resident_name, b.resident_name, a.resident_name, result.attitude_1_to_2, result.roll_1, Event.Reaction.keys()[result.reaction_1], result.opinion_delta_1, b.resident_name, result.attitude_2_to_1, result.roll_2, Event.Reaction.keys()[result.reaction_2], result.opinion_delta_2])
		logger.debug(EventLog.SOCIAL, "context=%s A=%s B=%s; A attitude=%d roll=%d score=%d reaction=%s delta=%d; B attitude=%d roll=%d score=%d reaction=%s delta=%d" % [Event.Context.keys()[context], a.resident_name, b.resident_name, result.attitude_1_to_2, result.roll_1, result.attitude_1_to_2 + result.roll_1, Event.Reaction.keys()[result.reaction_1], result.opinion_delta_1, result.attitude_2_to_1, result.roll_2, result.attitude_2_to_1 + result.roll_2, Event.Reaction.keys()[result.reaction_2], result.opinion_delta_2])
	event_resolved.emit(result)
	_resolve_depth -= 1
	_publish_commits()
	return result
func _publish_commits() -> void:
	if _resolve_depth > 0 or _publishing_commits: return
	_publishing_commits = true
	while not _committed.is_empty(): interaction_committed.emit(_committed.pop_front())
	_publishing_commits = false
func _on_conversation_joined(id: String) -> void:
	var runtime = world.get_runtime(id)
	if runtime != null: trigger(runtime, Event.Context.CONVERSATION)
func _on_meal(building_id: StringName, runtime: Node) -> void:
	trigger(runtime, Event.Context.MEAL, building_id)
func _on_work(building_id: StringName, runtime: Node) -> void:
	trigger(runtime, Event.Context.WORK, building_id)
