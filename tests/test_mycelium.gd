extends SceneTree
const Land=preload("res://scripts/mycelium.gd")
const Growth=preload("res://scripts/mushroom_growth.gd")
const Grid=preload("res://scripts/build_grid.gd")
const Clock=preload("res://scripts/game_time.gd")
const Balance=preload("res://scripts/balance_config.gd")
var checks:=0
var failures:=0
class FixedRandom extends RefCounted:
	var choice:=4
	var chance:=0.0
	var choices:=0
	var chances:=0
	func randi_range(_low: int,_high: int) -> int:choices+=1;return choice
	func randf() -> float:chances+=1;return chance
func _initialize() -> void:call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func quantities() -> void:
	check(Land.RESOURCE_TYPE==preload("res://scripts/resource_type.gd").Type.MUSHROOM,"Natural stock has one explicit fixed MUSHROOM type, not a haul source")
	var land=Land.new(Grid.new(Rect2(0,0,10,10)));var source:=Vector2i(8,8)
	check(land.add_mycelium(source) and not land.add_mycelium(source) and not land.add_mycelium(Vector2i(-1,0)),"Persistent unique in-bounds land cells")
	var random=FixedRandom.new()
	check(land.attempt(source,random).grew and land.amount(source)==1,"Source cell can grow on itself")
	random.choice=8
	check(land.attempt(source,random).grew and land.amount(source+Vector2i.ONE)==1,"Neighbor within Chebyshev radius one")
	check(land.add_mushrooms(source,20)==3 and land.amount(source)==4 and land.add_mushrooms(source)==0,"Pile API clamps to four whole units")
	check(land.remove_mushrooms(source,2)==2 and land.amount(source)==2 and land.remove_mushrooms(source,99)==2 and not source in land.mushroom_cells(),"Partial and final removal; no zero stock entry")
	check(land.has_mycelium(source) and land.remove_mushrooms(source)==0 and land.add_mushrooms(source,-1)==0,"Stock removal never removes mycelium")
	land.remove_mushrooms(source+Vector2i.ONE,4)
	random.choice=4;random.chance=0.5
	check(not land.attempt(source,random).grew and random.choices==3 and random.chances==3,"Failed 50 percent draw consumes exactly one attempt, no retries")
	land.allowed=func(_cell):return false
	check(not land.attempt(source,random).grew and random.choices==4 and random.chances==3,"Blocked cell loses attempt without probability draw")
	land.allowed=Callable();random.chance=0.0
	var neighbor:=source+Vector2i.RIGHT;land.add_mycelium(neighbor)
	land.add_mushrooms(source,4);land.add_mushrooms(source+Vector2i.DOWN,4);land.add_mushrooms(source+Vector2i.ONE,2)
	check(land.zone_amount(source)==10 and land.zone_amount(neighbor)==10,"Adjacent sources read the same actual overlapping stock")
	check(not land.attempt(source,random).grew and random.choices==4,"Full source zone does not select another target")
	land.remove_mushrooms(source,1)
	random.choice=4
	check(land.attempt(source,random).grew and land.zone_amount(source)==10,"Own growth stops at zone limit")
	check(not land.attempt(neighbor,random).grew,"Neighbor sees previous committed growth")
	var boundary=Land.new(Grid.new(Rect2(0,0,1,1)));boundary.add_mycelium(Vector2i.ZERO);random.choice=0
	check(not boundary.attempt(Vector2i.ZERO,random).grew and boundary.total()==0,"Out-of-map candidate consumes attempt safely")
	var nested=Land.new(Grid.new());nested.add_mycelium(source);var seen: Array=[]
	nested.mushrooms_changed.connect(func(cell,_amount):
		seen.append(nested.amount(cell))
		if nested.amount(cell)<4:nested.add_mushrooms(cell,4))
	check(nested.add_mushrooms(source)==1 and nested.amount(source)==4 and seen==[1,4],"Reentrant adds observe committed stock and cannot exceed local capacity")
	for connection in nested.mushrooms_changed.get_connections():nested.mushrooms_changed.disconnect(connection.callable)
func scheduled(seed_value: int, jump: bool, speed: int = 20) -> Dictionary:
	var clock=Clock.new();root.add_child(clock);clock.set_process(false);clock.total_minutes=1379;clock.set_speed(speed)
	var land=Land.new(Grid.new());land.add_mycelium(Vector2i(20,20));land.add_mycelium(Vector2i(21,20))
	var growth=Growth.new();root.add_child(growth);growth.setup(land,clock,seed_value)
	var events: Array=[]
	growth.attempted.connect(func(cell,minute,result):events.append([cell,minute,result.duplicate()]))
	if jump:growth._on_minute(1800+1440*2)
	else:clock.advance(float(1800+1440*2-1379)/speed)
	var state: Array=[]
	for cell in land.mushroom_cells():state.append([cell,land.amount(cell)])
	var before:=events.size();growth._on_minute(1800+1440*2);growth._on_minute(1400)
	check(events.size()==before and growth.pending_count()==0,"Duplicate/backward notification cannot replay attempts; day queue empty")
	var counts: Dictionary={};var moments: Dictionary={}
	var previous:=0
	for row in events:
		var minute: int=row[1];var source: Vector2i=row[0]
		var window: Vector2i=clock.night_interval_at_or_after(minute)
		check(minute>=window.x and minute<window.y and minute>=previous,"Events are chronological and strictly inside actual night")
		previous=minute
		var key:=str(source)+":"+str(window.x)
		counts[key]=int(counts.get(key,0))+1
		if not moments.has(key):moments[key]=[]
		moments[key].append(minute)
		if row[2].grew:check((row[2].cell-source).abs().x<=1 and (row[2].cell-source).abs().y<=1,"Successful target stays within radius")
	for key in counts:
		check(counts[key]==5 and moments[key].duplicate().size()==5,"Exactly five attempts per source per night")
		var unique: Dictionary={}
		for minute in moments[key]:unique[minute]=true
		check(unique.size()==5,"Five distinct minute slots, no all-at-once source growth")
	check(events.size()==30 and counts.size()==6,"Three complete nights for two sources, no day growth")
	clock.free();growth.free()
	return {"events":events,"state":state}
func timing() -> void:
	var expected=scheduled(71,true)
	for speed in Clock.SUPPORTED_SPEEDS:check(scheduled(71,false,speed)==expected,"Real GameTime speed/jump determinism at x"+str(speed))
	check(scheduled(71,true)==expected,"Same seed and event sequence reproduce quantities and moments")
	check(scheduled(72,true).events!=expected.events,"Dedicated growth seed controls its own schedule")
	var clock=Clock.new();root.add_child(clock);clock.set_process(false);clock.total_minutes=360
	var land=Land.new(Grid.new());land.add_mycelium(Vector2i(30,30))
	var growth=Growth.new();root.add_child(growth);growth.setup(land,clock,9)
	clock.debug_skip_minutes(1019)
	check(land.total()==0 and growth.pending_count()==0,"No scheduled list and no growth throughout daytime")
	clock.debug_skip_minutes(1);check(growth.pending_count()<=5,"Schedule starts at exact 23:00 boundary")
	clock.debug_skip_minutes(60);check(clock.total_minutes==1440 and growth.pending_count()<=5,"Midnight retains the same night's bounded schedule")
	clock.debug_skip_minutes(360);check(growth.pending_count()==0,"06:00 completes and releases the schedule")
	clock.free();growth.free()
func run() -> void:
	quantities();timing()
	print("Mycelium: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
