extends SceneTree
const Dispatcher = preload("res://scripts/ai_decision_dispatcher.gd")
class Queue extends "res://scripts/ai_decision_dispatcher.gd":
	var now := 1000000
	func _now_usec() -> int: return now
class Clock extends Node:
	var total_minutes := 360
class Receiver extends Node:
	var queue: Node
	var calls: Array = []
	var cost := 100
	var callback: Callable
	var accepts := true
	func execute_queued_decision(reason: String, context: Dictionary) -> bool:
		calls.append([reason, context])
		queue.now += cost
		if callback.is_valid(): callback.call()
		return accepts
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func service(queue: Node) -> void:
	await process_frame
	queue._process(0)
func run() -> void:
	var queue := Queue.new()
	var clock := Clock.new()
	root.add_child(clock); root.add_child(queue)
	queue.clock=clock;queue.set_process(false);queue.budget_usec=100
	var actors: Array=[]
	var order: Array=[]
	var waits: Array=[]
	queue.decision_serviced.connect(func(id,us,minutes,ok):waits.append([id,us,minutes,ok]))
	for index in 35:
		var actor:=Receiver.new();actor.queue=queue
		root.add_child(actor);actors.append(actor)
		actor.callback=func():order.append(index)
	await service(queue)
	check(queue.last_elapsed_usec==0 and queue.pending_count()==0,"Empty queue spends no budget")
	for index in 30:check(queue.request(str(index),actors[index],"work",{"value":index}),"Enqueue")
	for repeat in 100:
		for index in 30:queue.request(str(index),actors[index],"repeat")
	check(queue.pending_count()==30 and queue.duplicates==3000,"Dedup preserves one entry per resident")
	queue.cancel("9",actors[8]);check(queue.pending_count()==30,"Wrong identity cannot cancel")
	queue.cancel("9",actors[9]);check(queue.pending_count()==29,"Exact cancellation")
	for index in 29:
		await service(queue)
		check(queue.last_processed==1,"100us decision consumes 100us soft budget")
		var before:int=queue.executed;queue._process(0)
		check(before==queue.executed,"Only one drain per real frame")
	check(order==range(9)+range(10,30),"FIFO stable for equal priority/age")
	check(actors[0].calls[0][1].value==0,"Merging reasons keeps unspecified context")
	check(actors[0].calls[0][1].request_reasons.has("work") and actors[0].calls[0][1].request_reasons.has("repeat"),"All decision reasons retained")
	queue.request("old",actors[30],"old");actors[30].free()
	await service(queue);check(queue.discarded==1,"Freed weak receiver discarded")
	queue.request("reuse",actors[31],"old");queue.request("reuse",actors[32],"new")
	await service(queue);check(actors[31].calls.is_empty() and actors[32].calls.size()==1,"Same ID new runtime replaces old")
	queue.request("pause",actors[31],"paused");paused=true
	await service(queue);check(actors[31].calls.is_empty() and queue.pending_count()==1,"Pause retains requests without work")
	paused=false;await service(queue);check(actors[31].calls.size()==1,"Resume services request")
	queue.clear();order.clear()
	actors[33].callback=func():
		queue.request("self",actors[33],"state_changed",{"revision":2})
		queue.request("self",actors[33],"availability",{"resource":3})
		queue.request("later",actors[34],"next")
		queue._process(0)
	queue.request("self",actors[33],"first")
	await service(queue)
	check(actors[33].calls.size()==1 and actors[34].calls.is_empty() and queue.pending_count()==2,"Reentrant requests coalesce and never recurse")
	actors[33].callback=Callable()
	await service(queue);await service(queue)
	check(actors[33].calls.size()==2 and actors[34].calls.size()==1,"Changed self request safely runs on later frame")
	queue.clear();order.clear();queue.budget_usec=300
	for index in 8:queue.request(str(index),actors[index],"budget")
	await service(queue)
	check(queue.last_processed==3 and queue.pending_count()==5 and queue.last_elapsed_usec==300,"Time budget handles multiple cheap decisions")
	await service(queue);check(queue.last_processed==3 and queue.pending_count()==2,"Next frame resumes remaining work")
	queue.clear();queue.budget_usec=100
	actors[0].cost=2000;queue.request("costly",actors[0],"costly");queue.request("after",actors[1],"after")
	var overruns:int=queue.budget_overruns
	await service(queue)
	check(queue.last_processed==1 and queue.last_elapsed_usec==2000 and queue.pending_count()==1,"Monolithic decision finishes beyond soft budget")
	check(queue.budget_overruns==overruns+1,"Soft overrun is counted honestly")
	await service(queue);check(queue.pending_count()==0,"Costly decision does not block future service")
	actors[0].cost=100
	queue.clear();order.clear()
	queue.request("low",actors[0],"background",{},0)
	queue.request("up",actors[1],"background",{"revision":1},0)
	queue.request("up",actors[1],"urgent",{"revision":2},2)
	await service(queue)
	check(order==[1] and queue.pending_count()==1 and actors[1].calls[-1][1].revision==2,"Promotion uses latest context without extra entry")
	queue.now+=500001
	queue.request("fresh",actors[2],"urgent",{},2)
	await service(queue);check(order==[1,0],"Aged background outranks fresh urgent")
	queue.clear();order.clear()
	for index in 5:queue.request("aged%d"%index,actors[index],"background",{},0)
	for frame in 12:
		queue.now+=100000
		queue.request("fresh%d"%frame,actors[10+frame],"urgent",{},2)
		await service(queue)
	check(range(5).all(func(index):return order.has(index)),"Continuous priority traffic cannot starve earlier residents")
	queue.clear();queue.request("stale",actors[31],"stale");actors[31].accepts=false
	var discarded:int=queue.discarded
	clock.total_minutes+=7;queue.now+=20000
	await service(queue)
	check(queue.discarded==discarded+1 and waits[-1][2]==7 and waits[-1][1]>=20000,"Rejected stale execution and actual real/game waits recorded")
	queue.clear();check(queue.pending_count()==0,"Teardown clears pending references")
	for actor in actors:
		if is_instance_valid(actor):actor.free()
	queue.free();clock.free()
	print("AI dispatcher: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
