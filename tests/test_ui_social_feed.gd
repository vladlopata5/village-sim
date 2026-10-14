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
	world.social_events.feed_message.connect(func(text):received.append(text))
	var event=world.social_events.resolve(world.residents[0],world.residents[1],E.Context.CONVERSATION)
	check(event!=null and not received.is_empty(),"Real social resolution supplies presentation")
	check(world.social_feed.messages.map(func(label):return label.text)==received,"Feed preserves payload and signal publication order")
	var before: Array=received.duplicate()
	world.social_feed._show_latest()
	check(received==before,"Rendering cannot generate additional social messages")
	check(world.social_feed._column.get_child(0).text==received[-1],"Latest actual event payload at top")
	var game_minute: int=world.game_time.total_minutes
	paused=true
	await create_timer(12.15,true).timeout
	check(world.social_feed.messages.is_empty() and not world.social_feed.visible,"Original 12-second real lifetime expires even while simulation paused")
	check(world.game_time.total_minutes==game_minute and received==before,"Expiry does not advance game time or publish events")
	paused=false
	world.free()
	print("E5 social feed: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
