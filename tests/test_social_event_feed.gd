extends SceneTree
const Service = preload("res://scripts/social_event_service.gd")
const Event = preload("res://scripts/social_event.gd")
const Entry = preload("res://scripts/social_narrative_entry.gd")
const Data = preload("res://scripts/resident_data.gd")
const Diary = preload("res://scripts/diary_entry.gd")
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
var feed: Array = []
var logs: Array = []
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
	service.logger.line_logged.connect(func(line,_level): logs.append(line))
	service.feed_message.connect(func(text): feed.append(text))
	var random := FixedRng.new()
	service.rng=random
	var a := Data.new("a","Анна",25)
	var b := Data.new("b","Степан",30)
	service.entries=[]
	for context in Event.Context.values():
		for first_roll in [-100,0,100]:
			for second_roll in [-100,0,100]:
				# Reset opinion so all nine reaction combinations are explicit.
				a.set_opinion(b.id,0); b.set_opinion(a.id,0)
				random.values=[first_roll,second_roll]; random.cursor=0
				feed.clear(); logs.clear()
				var outcome:=service.resolve(a,b,context)
				check(outcome!=null and feed.size()==2,"Every successful no-match event emits Feed, all contexts/outcomes")
				check(logs.size()==1 and logs[0].contains("entry=none feed=2 diary=0"),"Exactly one DEBUG for event with output counts")
				check(a.diary_entries.is_empty() and b.diary_entries.is_empty(),"Fallback alone never creates Diary")
				check(a.get_opinion(b.id)==Service.delta(outcome.reaction_1) and b.get_opinion(a.id)==Service.delta(outcome.reaction_2),"Fallback preserves mechanical opinion updates")
				var word: String = "Приятно" if first_roll>50 else "раздражает" if first_roll< -50 else "ничего особенного"
				check(feed[0].contains("Анна") and feed[0].contains("Степан") and feed[0].contains(word),"Reaction-aware fallback with correct names")
	print(logs[0])
	var narrative := Entry.new({"id":"specific","feed_text_a":"%A% встретил %B%","diary_text_a":"diary %A%","diary_importance":Diary.Importance.TEMPORARY})
	service.entries=[narrative]
	random.values=[100,-100]
	service.diary_chance=0
	feed.clear(); logs.clear()
	var result:=service.resolve(a,b,Event.Context.MEAL)
	check(feed.size()==1 and feed[0].contains("встретил"),"One narrative line sufficient, no fallback duplication")
	check(logs[0].contains("feed=1 diary=0"),"Narrative counters correct")
	check(a.diary_entries.is_empty() and b.diary_entries.is_empty(),"Diary chance zero remains independent")
	# Use forced orientation for stable assertions, leave filtering itself untouched.
	narrative.conditions={"reaction_a":"POSITIVE"}
	narrative.feed_text_a=""
	service.diary_chance=1
	feed.clear(); logs.clear()
	result=service.resolve(a,b,Event.Context.MEAL)
	check(feed.size()==2 and result.selected_entry_id=="specific","Selected entry without Feed uses fallback, selection preserved")
	check(a.diary_entries.size()==1 and b.diary_entries.is_empty(),"Selected narrative still controls independent Diary")
	check(logs[0].contains("feed=2 diary=1"),"Diary success counted in DEBUG")
	var before: int = a.get_opinion(b.id)
	feed.clear()
	var output:=service.present(result,a,b,[],[])
	check(a.get_opinion(b.id)==before and output.feed==2,"Repeated presentation/fallback never changes opinion")
	narrative.diary_importance=Diary.Importance.NONE
	narrative.feed_text_a=" "; narrative.feed_text_b="\t"
	feed.clear(); logs.clear()
	result=service.resolve(a,b,Event.Context.WORK)
	check(feed.size()==2 and logs[0].contains("diary=0"),"Whitespace output also falls back; NONE never creates Diary")
	narrative.feed_text_b="%B%: normal"
	feed.clear()
	service.resolve(a,b,Event.Context.WORK)
	check(feed.size()==1 and feed[0].ends_with("normal"),"B-only narrative output suppresses fallback")
	check(service.resolve(a,a,Event.Context.WORK)==null,"Rejected self event has no output")
	service.free()
	var scene=Setup.make_scene(self)
	service=scene.social_events
	service.enabled=true
	service.logger.debug_enabled=true
	logs.clear()
	service.logger.line_logged.connect(func(line,level):
		if level==EventLog.Level.DEBUG and line.contains("context="): logs.append(line))
	random=FixedRng.new(); random.probability=1
	service.rng=random
	var actor=scene.resident_runtimes[1]
	for context in [Event.Context.CONVERSATION,Event.Context.WORK]: check(service.trigger(actor,context,scene.kitchen_data.id)==null,"Failed partial chance creates no event")
	check(service.trigger(actor,Event.Context.MEAL,scene.kitchen_data.id)==null,"100% MEAL without eligible participants creates no event")
	check(logs.is_empty(),"Failed chance rolls never write SocialEvent DEBUG")
	random.probability=0
	check(service.trigger(actor,Event.Context.CONVERSATION)==null and logs.is_empty(),"No eligible participants also creates no event/log")
	scene.free()
	print("Social Feed guarantee checks: %d, failures: %d" % [checks,failures])
	quit(0 if failures==0 else 1)
