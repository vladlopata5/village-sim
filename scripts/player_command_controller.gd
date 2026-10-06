extends Node
## One active player command per resident. Reuses forced_interrupt cleanup.
const Command = preload("res://scripts/player_command.gd")
const Intent = preload("res://scripts/resident_intent.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const EventLog = preload("res://scripts/game_logger.gd")
var logger: EventLog
var active_command: Command
var _data: RefCounted
var _intents: Node
var _intent: Intent
var _next_id := 1
func setup(data: RefCounted, intents: Node) -> void:
	_data = data
	_intents = intents
	intents.intent_completed.connect(_on_completed)
func move_to(destination: Vector2) -> bool:
	if not destination.is_finite(): return false
	if active_command != null:
		active_command.state = Command.State.CANCELLED
		if logger != null: logger.info(EventLog.PLAYER, "%s: приказ MOVE_TO отменён — заменён новым приказом" % _data.resident_name)
	active_command = Command.new(StringName("%s_command_%d" % [_data.id, _next_id]), _data.id, destination)
	_next_id += 1
	_intent = Intent.new(Intent.Type.MOVE_TO, &"player_move", destination, 0, true)
	if logger != null:
		logger.info(EventLog.PLAYER, "%s: приказ MOVE_TO → %s" % [_data.resident_name, destination])
		logger.debug(EventLog.PLAYER, "%s: прервано %s из-за PlayerCommand" % [_data.resident_name, Activity.Type.keys()[_data.activity]])
	# Listener ownership is established before a synchronous arrival at the same point.
	var accepted: bool = _intents.begin_player_intent(_intent)
	if logger != null: logger.sync_activity(_data)
	return accepted
func _on_completed(intent: Intent) -> void:
	if intent != _intent or active_command == null: return
	active_command.state = Command.State.COMPLETED
	active_command = null
	_intent = null
	if logger != null: logger.info(EventLog.PLAYER, "%s: приказ MOVE_TO выполнен" % _data.resident_name)
