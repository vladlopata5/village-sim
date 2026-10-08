extends Node
## Rolls only at action boundaries. No persistent event pool and no AI feedback.
const Event = preload("res://scripts/social_event.gd")
const Entry = preload("res://scripts/social_narrative_entry.gd")
const Diary = preload("res://scripts/diary_entry.gd")
const Balance = preload("res://scripts/balance_config.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const EventLog = preload("res://scripts/game_logger.gd")
signal event_resolved(result: Event)
signal feed_message(text: String)
var enabled := true
var rng: RefCounted = RandomNumberGenerator.new()
var narrative_rng: RefCounted = RandomNumberGenerator.new()
var entries: Array = []
var diary_chance: float = Balance.SOCIAL_EVENT_DIARY_CHANCE
var logger: EventLog
var world: Node
var clock: Node
var buildings: Array = []
func _init() -> void:
	rng.randomize()
	narrative_rng.randomize()
	var values: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/social_events/entries.json"))
	for value in values: entries.append(Entry.new(value))
func set_seed(value: int) -> void:
	rng.seed = value
	narrative_rng.seed = value ^ 0x534F4349
func setup(social_world: Node, game_clock: Node, locations: Array) -> void:
	world = social_world
	clock = game_clock
	buildings = locations
	world.conversation_joined.connect(_on_conversation_joined)
	clock.phase_changed.connect(_on_phase_changed)
	for runtime in world.residents.values(): register(runtime)
func register(runtime: Node) -> void:
	runtime.needs.meal_begun.connect(_on_meal.bind(runtime))
	runtime.decision.work_cycle_started.connect(_on_work.bind(runtime))
	runtime.builder.work_cycle_started.connect(_on_work.bind(runtime))
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
	if rng.randf() >= chance_for(context): return null
	var pool := participant_pool(runtime, context, location_id)
	if pool.is_empty(): return null
	var other: Node = pool[rng.randi_range(0, pool.size() - 1)]
	return resolve(runtime.data, other.data, context, presence(runtime).get("tags", []), presence(other).get("tags", []))
func resolve(a: RefCounted, b: RefCounted, context: Event.Context, tags_a: Array = [], tags_b: Array = []) -> Event:
	if a == null or b == null or a.id == b.id: return null
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
	a.change_opinion(b.id, result.opinion_delta_1)
	b.change_opinion(a.id, result.opinion_delta_2)
	present(result, a, b, tags_a, tags_b)
	if logger != null:
		logger.debug(EventLog.SOCIAL, "context=%s A=%s B=%s; A attitude=%d roll=%d score=%d reaction=%s delta=%d; B attitude=%d roll=%d score=%d reaction=%s delta=%d; entry=%s" % [Event.Context.keys()[context], a.resident_name, b.resident_name, result.attitude_1_to_2, result.roll_1, result.attitude_1_to_2 + result.roll_1, Event.Reaction.keys()[result.reaction_1], result.opinion_delta_1, result.attitude_2_to_1, result.roll_2, result.attitude_2_to_1 + result.roll_2, Event.Reaction.keys()[result.reaction_2], result.opinion_delta_2, result.selected_entry_id])
	event_resolved.emit(result)
	return result
func matching_entries(result: Event, a: RefCounted, b: RefCounted, tags_a: Array, tags_b: Array) -> Array:
	var matches: Array = []
	for entry in entries:
		var orientations: Array = []
		if entry.matches(result.context, a, b, result.reaction_1, result.reaction_2, tags_a, tags_b): orientations.append(false)
		if entry.matches(result.context, b, a, result.reaction_2, result.reaction_1, tags_b, tags_a): orientations.append(true)
		# One ticket per entry, even if both orientations match.
		if not orientations.is_empty(): matches.append({"entry": entry, "orientations": orientations})
	return matches
func present(result: Event, a: RefCounted, b: RefCounted, tags_a: Array, tags_b: Array) -> void:
	var matches := matching_entries(result, a, b, tags_a, tags_b)
	if matches.is_empty():
		feed_message.emit("%s и %s провели время вместе." % [a.resident_name, b.resident_name])
		return
	var selected: Dictionary = matches[narrative_rng.randi_range(0, matches.size() - 1)]
	var entry: RefCounted = selected.entry
	var reverse: bool = selected.orientations[narrative_rng.randi_range(0, selected.orientations.size() - 1)]
	result.selected_entry_id = entry.id
	result.reversed_orientation = reverse
	var first: RefCounted = b if reverse else a
	var second: RefCounted = a if reverse else b
	for template in [entry.feed_text_a, entry.feed_text_b]:
		if not template.is_empty(): feed_message.emit(entry.render(template, first, second))
	if entry.diary_importance == Diary.Importance.NONE: return
	var minute: int = clock.total_minutes if is_instance_valid(clock) else 0
	for output in [[first, entry.diary_text_a], [second, entry.diary_text_b]]:
		if not output[1].is_empty() and narrative_rng.randf() < diary_chance:
			output[0].add_diary_entry(Diary.new(entry.render(output[1], first, second), entry.diary_importance, minute))
func _on_conversation_joined(id: String) -> void:
	var runtime = world.get_runtime(id)
	if runtime != null: trigger(runtime, Event.Context.CONVERSATION)
func _on_meal(building_id: StringName, runtime: Node) -> void:
	trigger(runtime, Event.Context.MEAL, building_id)
func _on_work(building_id: StringName, runtime: Node) -> void:
	trigger(runtime, Event.Context.WORK, building_id)
func _on_phase_changed(phase: String) -> void:
	if phase == "Утро":
		for runtime in world.residents.values():
			if is_instance_valid(runtime) and not runtime.is_queued_for_deletion(): runtime.data.expire_temporary_diary(clock.total_minutes)
