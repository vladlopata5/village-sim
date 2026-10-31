extends SceneTree
const F=preload("res://tests/residents_ui_fixture.gd")
const E=preload("res://scripts/social_event.gd")
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(message)
func run() -> void:
	var world=F.create(self)
	var received: Array[String]=[]
	world.game_events.resident_message.connect(func(_id,resident_name,text):received.append("%s: «%s»." % [resident_name,text]))
	var initial: int=world.social_feed.messages.size()
	var event=world.social_events.resolve(world.residents[0],world.residents[1],E.Context.CONVERSATION)
	check(event!=null and world.social_feed.messages.size()==initial,"Ordinary social interaction invents no chat text")
	# Exercise existing EventEngine and independent shepherd UI routes, not a new story.
	world.game_events.resident_message.emit(world.residents[0].id,world.residents[0].resident_name,"я вкусно поел")
	check(world.social_feed.messages.back().text==received.back(),"EventEngine message keeps exact sender and text")
	world.resident_runtimes[0].shepherd.say("Мне некуда привести овцу")
	check(world.social_feed.messages.back().text=="%s: «Мне некуда привести овцу»." % world.residents[0].resident_name,"Independent diagnostic resident message remains available")
	var before: Array=received.duplicate()
	world.social_feed._show_latest()
	check(received==before,"Rendering cannot generate additional social messages")
	check(world.social_feed._column.get_child(0).text==world.social_feed.messages.back().text,"Latest actual message remains at top")
	var game_minute: int=world.game_time.total_minutes
	paused=true
	await create_timer(12.15,true).timeout
	check(world.social_feed.messages.is_empty() and not world.social_feed.visible,"Original 12-second real lifetime expires even while simulation paused")
	check(world.game_time.total_minutes==game_minute and received==before,"Expiry does not advance game time or publish events")
	paused=false
	world.free()
	print("E5 social feed: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
