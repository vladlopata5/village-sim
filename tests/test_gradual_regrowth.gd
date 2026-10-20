extends SceneTree
const Roads=preload("res://scripts/road_grid.gd")
const Clock=preload("res://scripts/game_time.gd")
const Layer=preload("res://scripts/world_3d/road_layer_3d.gd")
const Navigation=preload("res://scripts/navigation_grid.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func dense(seed_value: int=73, level: int=15):
	var model=Roads.new(Rect2(0,0,8,8))
	model.setup_trampling(360,seed_value)
	for index in model.levels.size():model.set_trample_level(model._cell(index),level)
	return model
func scheduling() -> void:
	var model=dense()
	var changed: Array[Vector2i]=[]
	model.levels_changed.connect(func(batch):changed.append_array(batch))
	model.on_minute(1379)
	check(changed.is_empty() and model._night_cursor==0,"No regrowth before23")
	model.on_minute(1380)
	check(changed.is_empty() and model._night_running and model._night_cursor==0,"23:00 starts in constant work without mass decay")
	model.on_minute(1382)
	check(model._night_cursor==1 and changed.size()==1,"Only the due minute portion changes")
	var before: int=model._night_cursor
	model.on_minute(1382)
	check(model._night_cursor==before and changed.size()==1,"Duplicate minute is a no-op")
	model.on_minute(1440)
	check(model._night_cursor==floori(256.0*60/420) and model._night_running,"Midnight continues same cycle")
	model.on_minute(1799)
	check(model._night_cursor<256,"Night does not finish early")
	model.on_minute(1800)
	check(model._night_cursor==256 and not model._night_running,"06:00 completes the full permutation")
	check(changed.size()==256 and model.levels.count(14)==256,"Every unused cell including15 loses exactly one")
	var unique: Dictionary={}
	for point in changed:unique[point]=true
	check(unique.size()==256,"No index is skipped or processed twice")
	model.on_minute(2000)
	check(changed.size()==256,"Daytime stops processing")
	model.on_minute(3240)
	check(model.levels.count(13)==256 and changed.size()==512,"Following night runs once again")
	var zeros=dense(73,1)
	zeros.on_minute(1800)
	check(zeros._active.is_empty() and zeros.levels.count(0)==256,"Decay to zero removes all active cells safely")
	for count in [1,2,15,225]:
		var shaped=Roads.new(Rect2(0,0,count*0.5,0.5))
		shaped.setup_trampling(360);shaped.on_minute(1380)
		var indices: Dictionary={}
		for position in count:indices[shaped._night_index(position)]=true
		check(indices.size()==count,"Coprime permutation visits all %d cells" % count)
	var big=Roads.new()
	big.setup_trampling(360);big.on_minute(1380);big.on_minute(1381)
	check(big._night_cursor==97,"Main grid first minute has97 checks, not40960")
	var cursor: int=big._night_cursor
	big.on_minute(1382)
	check(big._night_cursor-cursor==98,"Main grid fractional quota is distributed")
func use_periods() -> void:
	var model=dense()
	model.chance=0
	var day:=Vector2i(0,0)
	model.visit(day)
	model.on_minute(1380)
	check(model._previous_used.has(model._index(day)) and model._used.is_empty(),"Daily marks swap without becoming current-night visits")
	var future: Vector2i=model._cell(model._night_index(255))
	if future==day:future=model._cell(model._night_index(254))
	model.on_minute(1440)
	model.visit(future)
	model.on_minute(1800)
	check(model.trample_level(day)==15,"Previous-period visit protects current night")
	check(model.trample_level(future)==15,"Current-night visit before turn protects current night")
	check(model._previous_used.is_empty() and model._used.has(model._index(future)),"Old marks retired gradually; next-period mark survives dawn")
	model.on_minute(3240)
	check(model.trample_level(day)==14 and model.trample_level(future)==15,"Night visit also protects following daily cycle")
	model.on_minute(4680)
	check(model.trample_level(future)==14,"Protection expires only after its full period")
	var later=dense()
	later.chance=0;later.on_minute(1382)
	var processed: Vector2i=later._cell(later._night_index(0))
	later.visit(processed)
	later.on_minute(1800)
	check(later.trample_level(processed)==14,"Visit after processing never causes another decay")
	later.on_minute(3240)
	check(later.trample_level(processed)==14,"Post-processing visit is retained for next night")
func mutations() -> void:
	var model=Roads.new(Rect2(0,0,8,8))
	model.setup_trampling(360);model.chance=1
	var old:=Vector2i(0,0)
	model.visit(old)
	model.on_minute(1380)
	model.clear_trampling([old])
	check(not model._previous_used.has(model._index(old)),"Building footprint removes old-period marks during scan")
	var late: Vector2i=model._cell(model._night_index(255))
	model.visit(late)
	check(model.trample_level(late)==1,"New physical wear may appear during night")
	model.clear_trampling([late])
	check(not model._used.has(model._index(late)) and model.trample_level(late)==0,"Footprint also removes current-period marks and active entry")
	model.visit(late)
	model.on_minute(1800)
	check(model.trample_level(late)==1,"Recreated visited cell remains protected without changing permutation")
	var first: Vector2i=model._cell(model._night_index(0))
	model.visit(first)
	model.on_minute(1801)
	check(model.trample_level(first)==1,"New wear after consumed index is not reconsidered")
	var initialized=Roads.new(Rect2(0,0,8,8))
	initialized.setup_trampling(1560)
	initialized.set_trample_level(old,15)
	initialized.on_minute(1800)
	check(initialized.trample_level(old)==15 and not initialized._night_running,"Midnight initialization cannot process earlier day")
	initialized.on_minute(3240)
	check(initialized.trample_level(old)==14,"First future complete night still runs")
func deterministic() -> void:
	var a=dense(912);var b=dense(912)
	var order_a: Array[Vector2i]=[];var order_b: Array[Vector2i]=[]
	a.levels_changed.connect(func(batch):order_a.append_array(batch))
	b.levels_changed.connect(func(batch):order_b.append_array(batch))
	a.on_minute(1800)
	for minute in range(1380,1801):b.on_minute(minute)
	check(order_a==order_b and a.levels==b.levels,"Skipped minutes and minute stepping preserve exact seeded order")
	var quadrants: Dictionary={}
	for point in order_a.slice(0,64):quadrants[Vector2i(int(point.x>=8),int(point.y>=8))]=true
	check(quadrants.size()==4 and a._night_step!=1 and a._night_step!=255,"Early changes are dispersed, not a coordinate wave")
	var sparse=dense(17);var stepwise=dense(17)
	sparse.on_minute(4680)
	for minute in range(1380,4681):stepwise.on_minute(minute)
	check(sparse.levels==stepwise.levels and sparse.levels.count(12)==256,"Multi-day catch-up loses or duplicates no portions")
	var state: int=a._random.state
	seed(109);var expected_global: int=randi();seed(109)
	a.on_minute(3240)
	check(a._random.state==state and randi()==expected_global,"Night order never consumes entry or global RNG")
	for speed_value in Clock.SUPPORTED_SPEEDS:
		var model=dense();var clock=Clock.new();root.add_child(clock);clock.set_process(false)
		clock.total_minutes=1379;clock.set_speed(speed_value)
		model.setup_trampling(1379)
		clock.minute_changed.connect(model.on_minute)
		clock.advance(421.0/speed_value)
		check(model.levels.count(14)==256 and not model._night_running,"GameTime x%d completes each portion by06" % speed_value)
		clock.free()
func presentation() -> void:
	var model=Roads.new(Rect2(0,0,8,8));model.setup_trampling(360)
	var cell:=Vector2i(2,2);model.set_trample_level(cell,11)
	var layer=Layer.new();root.add_child(layer);layer.setup(model)
	var original: Color=layer.color_for(cell)
	var nav=Navigation.new(Rect2(0,0,8,8),0)
	var revision: int=nav.revision
	model.on_minute(1800);layer.flush_updates()
	check(model.trample_level(cell)==10 and model.execution_speed(cell,1)==1,"Night portion turns11 into10 and removes execution bonus")
	check(layer.color_for(cell)!=original and layer.multimesh.visible_instance_count==1,"Existing addressed colour mechanism follows regrowth")
	model.set_trample_level(cell,1);model.on_minute(3240);layer.flush_updates()
	check(layer.multimesh.visible_instance_count==0 and model._active.is_empty(),"Level1 disappears without rebuilding layer")
	check(nav.revision==revision,"Night cycle never changes navigation revision")
	layer.free()
func run() -> void:
	scheduling();use_periods();mutations();deterministic();presentation()
	print("Gradual regrowth: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
