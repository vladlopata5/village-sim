extends Node
const EventLog = preload("res://scripts/game_logger.gd")
var logger: EventLog
## Concrete SOCIAL and LEISURE actions, separate from selection of a need.
const Activity = preload("res://scripts/resident_activity.gd")
const NeedType = preload("res://scripts/need_type.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const Choice = preload("res://scripts/weighted_choice.gd")
const SATISFIED_VALUE := 15
const MAX_ACTION_MINUTES := 30
var world: Node
var runtime: Node
var clock: Node
var rng := RandomNumberGenerator.new()
var _active: Intent
var _option: Dictionary = {}
var _started_at := 0
func setup(owner_runtime: Node, game_clock: Node) -> void:
	runtime = owner_runtime
	clock = game_clock
	rng.seed = runtime.data.id.hash()
	clock.minute_changed.connect(_on_minute)
	runtime.intents.intent_arrived.connect(_on_arrival)
	runtime.intents.intent_changed.connect(_on_intent_changed)
func try_social(priority: int) -> bool:
	if world == null: return false
	var option = Choice.pick(world.options_for(runtime.data.id), rng)
	if option == null: return false
	_option = option
	_active = Intent.new(Intent.Type.MOVE_TO, &"social", world.option_position(option), priority, true)
	if not runtime.intents.submit(_active):
		_active = null
		_option = {}
		return false
	if logger != null: logger.sync_activity(runtime.data)
	return true
func try_leisure(priority: int) -> bool:
	_active = Intent.new(Intent.Type.NONE, &"leisure", Vector2.ZERO, priority, false)
	if not runtime.intents.submit(_active):
		_active = null
		return false
	_started_at = clock.total_minutes
	runtime.data.activity = Activity.Type.RELAXING
	if logger != null: logger.sync_activity(runtime.data)
	return true
func begin_talking() -> void:
	# The waiting IDLE participant also owns an independent current action.
	if _active == null:
		_active = Intent.new(Intent.Type.NONE, &"social", Vector2.ZERO,
			runtime.data.get_need(NeedType.Type.SOCIAL).get_priority(), false)
		runtime.intents.submit(_active)
	_active.interruptible = false
	_started_at = clock.total_minutes
	runtime.data.activity = Activity.Type.TALKING
	if logger != null:
		logger.sync_activity(runtime.data)
		logger.info(EventLog.SOCIAL, "%s: начал разговор" % runtime.data.resident_name)
func _on_arrival(intent: Intent) -> void:
	if intent != _active or intent.reason_id != &"social": return
	if not world.arrive(runtime.data.id, _option): _finish()
func _on_minute(minute: int) -> void:
	if _active == null: return
	var activity = runtime.data.activity
	if activity == Activity.Type.MOVING:
		if not world.valid_option(_option): _finish()
	elif activity in [Activity.Type.TALKING, Activity.Type.RELAXING]:
		var type = NeedType.Type.SOCIAL if activity == Activity.Type.TALKING else NeedType.Type.LEISURE
		if runtime.data.get_need(type).value <= SATISFIED_VALUE or minute - _started_at >= MAX_ACTION_MINUTES: _finish()
func _on_intent_changed(intent: Intent) -> void:
	if _active != null and intent != _active:
		_active = null
		_option = {}
		if world != null: world.leave(runtime.data.id)
func _finish() -> void:
	var previous = _active
	_active = null
	_option = {}
	if world != null: world.leave(runtime.data.id)
	if previous != null: runtime.intents.clear_completed(previous)
func group_dissolved() -> void:
	if runtime.data.activity == Activity.Type.TALKING and world.group_of(runtime.data.id) == null: _finish()
func _exit_tree() -> void:
	if is_instance_valid(world): world.leave(runtime.data.id)
