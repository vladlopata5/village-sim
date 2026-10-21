extends SceneTree
const Fields=preload("res://scripts/farm_fields.gd")
const Grid=preload("res://scripts/build_grid.gd")
const Clock=preload("res://scripts/game_time.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func prepare(fields: RefCounted, cells: Array) -> void:
	for cell in cells:
		check(fields.reserve([cell],&"plow",Fields.State.BARE) and fields.plow(cell,&"plow"),"One owned grass/dirt cell becomes plowed")
func claims() -> void:
	var clock=Clock.new();clock.total_minutes=0;root.add_child(clock);clock.set_process(false)
	var fields=Fields.new(Grid.new());fields.setup(clock)
	var cells: Array=[Vector2i(1,1),Vector2i(2,1),Vector2i(3,1),Vector2i(4,1),Vector2i(5,1)]
	check(fields.terrain(cells[0])==Fields.Terrain.GRASS and fields.state(cells[0])==Fields.State.BARE,"Grass and agricultural state start separate")
	check(not fields.reserve([Vector2i(-1,0)],&"bad",Fields.State.BARE) and not fields.reserve([cells[0],cells[0]],&"bad",Fields.State.BARE),"Bounds and duplicate cells rejected atomically")
	check(not fields.reserve(cells+[Vector2i(6,1)],&"big",Fields.State.BARE),"Cycle cannot reserve more than five cells")
	check(not fields.reserve(cells,&"geometry",Fields.State.BARE,func(_cell):return false) and fields.owned_cells(&"geometry").is_empty(),"Geometry rejection leaves no partial claims")
	prepare(fields,cells)
	check(fields.reserve([cells[2]],&"other",Fields.State.PLOWED),"Second farm reserves independent plowed cell")
	check(not fields.reserve(cells,&"sow",Fields.State.PLOWED) and fields.owned_cells(&"sow").is_empty(),"Overlapping operation cannot partially claim five targets")
	fields.release(&"other")
	check(fields.reserve(cells,&"sow",Fields.State.PLOWED) and fields.reserve(cells,&"sow",Fields.State.PLOWED),"One sow operation owns five cells idempotently")
	check(not fields.reserve([cells[1]],&"competitor",Fields.State.PLOWED),"Competing farmer blocked")
	check(not fields.sow(cells[0],&"sow",1,func():return false) and fields.state(cells[0])==Fields.State.PLOWED and fields.owned(cells[0],&"sow"),"Failed seed payment preserves plowed cell and own claim")
	for cell in cells.slice(0,3):check(fields.sow(cell,&"sow",1,func():return true) and fields.maturity(cell)==0,"Successful sow starts at maturity0")
	fields.release(&"sow");fields.release(&"sow")
	check(cells.slice(0,3).all(func(cell):return fields.state(cell)==Fields.State.SOWN) and cells.slice(3).all(func(cell):return fields.state(cell)==Fields.State.PLOWED and not fields.claimed(cell)),"Cancellation preserves three completed crops and frees two untouched cells")
	clock.advance(1440)
	check(fields.maturity(cells[0])==1,"One midnight grows one stage")
	var revision: int=fields.revision;clock.minute_changed.emit(clock.total_minutes)
	check(fields.maturity(cells[0])==1 and fields.revision==revision,"Repeated minute never grows twice")
	clock.advance(8*1440)
	check(fields.plot_cells().is_empty() and cells.all(func(cell):return fields.terrain(cell)==Fields.Terrain.DIRT),"First winter clears all crops/plow into persistent dirt")
	check(not fields.reserve([cells[0]],&"winter",Fields.State.BARE),"No winter plowing")
	clock.advance(3*1440)
	check(fields.terrain(cells[0])==Fields.Terrain.DIRT and fields.reserve([cells[0]],&"next_spring",Fields.State.BARE) and fields.plow(cells[0],&"next_spring"),"Next spring keeps dirt and permits re-plowing")
	clock.free()
func speed_and_late_seed() -> void:
	for speed in Clock.SUPPORTED_SPEEDS:
		var clock=Clock.new();clock.total_minutes=0;root.add_child(clock);clock.set_process(false);clock.set_speed(speed)
		var fields=Fields.new(Grid.new());fields.setup(clock);var cell:=Vector2i(5,5)
		prepare(fields,[cell]);fields.reserve([cell],&"seed",Fields.State.PLOWED);fields.sow(cell,&"seed",1,func():return true)
		clock.advance(6*1440.0/speed)
		check(clock.get_day()==7 and fields.maturity(cell)==6,"Large advance grows every night, x%d"%speed)
		clock.advance(3*1440.0/speed)
		check(fields.state(cell)==Fields.State.BARE and fields.terrain(cell)==Fields.Terrain.DIRT,"Winter death independent of speed")
		clock.free()
	var late_clock=Clock.new();late_clock.total_minutes=5*1440;root.add_child(late_clock);late_clock.set_process(false)
	var late_fields=Fields.new(Grid.new());late_fields.setup(late_clock);var late_cell:=Vector2i(5,5)
	prepare(late_fields,[late_cell]);late_fields.reserve([late_cell],&"late",Fields.State.PLOWED);late_fields.sow(late_cell,&"late",6,func():return true)
	late_clock.advance(3*1440)
	check(late_fields.maturity(late_cell)==3 and late_fields.mow(late_cell,&"late")==-1,"Late summer planting may remain unharvestable in autumn")
	check(not late_fields.reserve([Vector2i(6,5)],&"autumn",Fields.State.BARE),"Autumn cannot plow or seed")
	late_clock.advance(1440);check(late_fields.state(late_cell)==Fields.State.BARE,"Late crop dies in winter without yield")
	late_clock.free()
func yields() -> void:
	var seen4: Dictionary={};var seen6: Dictionary={}
	for age in [4,5,6,8]:
		for seed_value in 40:
			var clock=Clock.new();clock.total_minutes=maxi(0,6-age)*1440;root.add_child(clock);clock.set_process(false)
			var fields=Fields.new(Grid.new(),seed_value);fields.setup(clock);var cell:=Vector2i(8,8)
			fields.reserve([cell],&"plow",Fields.State.BARE);fields.plow(cell,&"plow")
			fields.reserve([cell],&"sow",Fields.State.PLOWED);fields.sow(cell,&"sow",clock.get_day(),func():return true)
			clock.total_minutes+=age*1440;clock.minute_changed.emit(clock.total_minutes)
			check(fields.maturity(cell)==age,"Independent crop maturity")
			fields.reserve([cell],&"mow",Fields.State.SOWN)
			var result: int=fields.mow(cell,&"mow");var random_state: int=fields._random.state
			check((result in [0,1] if age==4 else (result==1 if age==5 else result in [1,2])) and fields.state(cell)==Fields.State.BARE and fields.terrain(cell)==Fields.Terrain.DIRT,"Age-specific yield and dirt after mowing")
			check(fields.mow(cell,&"mow")==-1 and fields._random.state==random_state,"Repeated completion cannot roll or yield again")
			if age==4:seen4[result]=true
			if age>=6:seen6[result]=true
			clock.free()
	check(seen4.has(0) and seen4.has(1) and seen6.has(1) and seen6.has(2),"Deterministic seed sample exercises both half-chance outcomes")
func run() -> void:
	claims();speed_and_late_seed();yields()
	print("Farm fields: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
