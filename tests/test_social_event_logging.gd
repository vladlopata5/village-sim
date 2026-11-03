extends SceneTree
const Service = preload("res://scripts/social_event_service.gd")
const Event = preload("res://scripts/social_event.gd")
const Data = preload("res://scripts/resident_data.gd")
const EventLog = preload("res://scripts/game_logger.gd")
const Setup = preload("res://tests/behavior_test_setup.gd")
class FixedRng extends RefCounted:
	var values: Array = [0]
	var cursor := 0
	var probability := 0.0
	func randf() -> float: return probability
	func randi_range(low: int, high: int) -> int:
		var value: int = values[cursor % values.size()]
		cursor += 1
		return clampi(value,low,high)
var checks := 0
var failures := 0
var logs: Array = []
var info_logs: Array = []
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	var service := Service.new()
	root.add_child(service)
	service.logger=EventLog.new()
	service.logger.debug_enabled=true
	service.logger.console_enabled=false
	service.logger.line_logged.connect(func(line,level):
		if level==EventLog.Level.DEBUG: logs.append(line)
		elif line.contains("[SOCIAL_EVENT]"): info_logs.append(line))
	var game_clock=preload("res://scripts/game_time.gd").new()
	root.add_child(game_clock)
	game_clock.set_process(false)
	game_clock.total_minutes=635
	service.logger.setup(game_clock)
	var random := FixedRng.new()
	service.rng=random
	var a := Data.new("a","Анна",25)
	var b := Data.new("b","Степан",30)
	for context in Event.Context.values():
		for first_roll in [-100,0,100]:
			for second_roll in [-100,0,100]:
				# Reset opinion so all nine reaction combinations are explicit.
				a.set_opinion(b.id,0); b.set_opinion(a.id,0)
				random.values=[first_roll,second_roll]; random.cursor=0
				logs.clear(); info_logs.clear()
				var outcome:=service.resolve(a,b,context)
				check(outcome!=null,"Accepted interaction exists independently of presentation")
				check(logs.size()==1 and logs[0].contains("context="+Event.Context.keys()[context]),"Exactly one diagnostic DEBUG for mechanical event")
				check(info_logs.size()==1 and info_logs[0].begins_with("[10:35][SOCIAL_EVENT]"),"One ordinary log per event with game time")
				check(info_logs[0].contains("context="+Event.Context.keys()[context]) and info_logs[0].contains("A=Анна B=Степан"),"Ordinary log contains context and both names")
				check(info_logs[0].contains("reaction=%s delta=%+d" % [Event.Reaction.keys()[outcome.reaction_1],outcome.opinion_delta_1]) and info_logs[0].contains("reaction=%s delta=%+d" % [Event.Reaction.keys()[outcome.reaction_2],outcome.opinion_delta_2]),"Ordinary log contains both reactions and signed deltas")
				check(a.memories.find().is_empty() and b.memories.find().is_empty(),"Ordinary mechanics does not invent Diary")
				check(a.get_opinion(b.id)==Service.delta(outcome.reaction_1) and b.get_opinion(a.id)==Service.delta(outcome.reaction_2),"Mechanical directed opinion updates preserved")
	service.free()
	game_clock.free()
	var scene=Setup.make_scene(self)
	service=scene.social_events
	service.enabled=true
	service.logger.debug_enabled=true
	logs.clear(); info_logs.clear()
	service.logger.line_logged.connect(func(line,level):
		if level==EventLog.Level.DEBUG and line.contains("context="): logs.append(line)
		elif level==EventLog.Level.INFO and line.contains("[SOCIAL_EVENT]"): info_logs.append(line))
	random=FixedRng.new(); random.probability=1
	service.rng=random
	var actor=scene.resident_runtimes[1]
	for context in [Event.Context.CONVERSATION,Event.Context.WORK]: check(service.trigger(actor,context,scene.kitchen_data.id)==null,"Failed partial chance creates no event")
	check(service.trigger(actor,Event.Context.MEAL,scene.kitchen_data.id)==null,"100% MEAL without eligible participants creates no event")
	check(logs.is_empty() and info_logs.is_empty(),"Failed chance rolls never write SocialEvent DEBUG or ordinary logs")
	random.probability=0
	check(service.trigger(actor,Event.Context.CONVERSATION)==null and logs.is_empty() and info_logs.is_empty(),"No eligible participants also creates no event/log")
	scene.free()
	print("Social diagnostic checks: %d, failures: %d" % [checks,failures])
	quit(0 if failures==0 else 1)
