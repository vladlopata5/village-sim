extends SceneTree
const Batch=preload("res://scripts/shearing_batch.gd")
const Stock=preload("res://scripts/resource_container.gd")
const Animal=preload("res://scripts/animal_data.gd")
const R=preload("res://scripts/resource_type.gd").Type
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func run() -> void:
	var seen: Array=[]
	for potential in [3,4,5]:
		var random:=RandomNumberGenerator.new()
		for seed_value in 1000:
			random.seed=seed_value
			if random.randi_range(3,5)==potential:random.seed=seed_value;break
		for progress in [0,1,30,60,90,119,120]:
			for stock in [0,17,19]:
				var inventory=Stock.new(&"wool");inventory.set_allowed_resource_types([R.WOOL]);inventory.set_capacity(R.WOOL,20)
				if stock>0:inventory.add(R.WOOL,stock)
				var animal=Animal.new(&"sheep",Vector3.ZERO,Vector3.ZERO);animal.wool_growth=15
				var work=Batch.new(&"operation",inventory)
				check(work.prepare("shepherd") and inventory.get_reserved_in(R.WOOL)==1,"Reserve one output place even at19/20")
				# Repeat RNG state so each independently created batch selects the controlled Q.
				var start_state: int=random.state
				check(work.begin_shearing("shepherd",random) and work.potential==potential,"Q is selected once at actual service start")
				random.state=start_state
				work.advance("shepherd",progress)
				var result: Dictionary=work.settle("shepherd",animal,func():return true)
				var produced:=floori(float(potential)*progress/120)
				var levels:=ceili(15.0*progress/120)
				check(result.produced==produced and result.saved==mini(20-stock,produced) and result.discarded==maxi(produced-(20-stock),0),"Partial/overflow output floor matches agreed formula")
				check(animal.wool_growth==15-levels and inventory.get_amount(R.WOOL)==stock+result.saved and inventory.get_reserved_in(R.WOOL)==0,"Rounded wool removal and exact container settlement")
				var actual: int=inventory.get_amount(R.WOOL)
				work.cancel();work.settle("shepherd",animal,func():return true)
				check(inventory.get_amount(R.WOOL)==actual and animal.wool_growth==15-levels,"Repeat cancellation cannot produce or remove wool twice")
		seen.append(potential)
	closing_and_reentry()
	print("Shearing batches: %d checks, %d failures; Q=%s" % [checks,failures,str(seen)])
	quit(1 if failures else 0)
func closing_and_reentry() -> void:
	var inventory=Stock.new(&"full");inventory.set_capacity(R.WOOL,20);inventory.add(R.WOOL,20)
	check(not Batch.new(&"full",inventory).prepare("shepherd"),"Full buffer refuses a new batch")
	inventory.try_take(R.WOOL,10)
	var animal=Animal.new(&"closing_sheep",Vector3.ZERO,Vector3.ZERO);animal.wool_growth=15
	var work=Batch.new(&"closed",inventory);var random:=RandomNumberGenerator.new();random.seed=4
	work.prepare("shepherd");work.begin_shearing("shepherd",random);work.advance("shepherd",60)
	var result: Dictionary=work.settle("shepherd",animal,func():return false)
	check(result.saved==0 and result.discarded==result.produced and inventory.get_amount(R.WOOL)==10 and animal.wool_growth==7 and inventory.get_reserved_in(R.WOOL)==0,"Closed building discards partial output without bypassing container rules")
	var reentrant=Stock.new(&"reentrant");reentrant.set_capacity(R.WOOL,20)
	var active=Batch.new(&"reentrant_job",reentrant);animal=Animal.new(&"reentrant_sheep",Vector3.ZERO,Vector3.ZERO);animal.wool_growth=15
	active.prepare("worker");active.begin_shearing("worker",random);active.advance("worker",120)
	var nested: Array=[]
	var callback=func(_r,_n):nested.append(active.settle("worker",animal,func():return true))
	reentrant.changed.connect(callback)
	result=active.settle("worker",animal,func():return true)
	check(reentrant.get_amount(R.WOOL)==result.produced and animal.wool_growth==0 and nested.size()==1,"Reentrant output callback sees terminal result, never repeats transaction")
	reentrant.changed.disconnect(callback)
	var closing_stock=Stock.new(&"closing_during_topup");closing_stock.set_capacity(R.WOOL,20)
	var closing_work=Batch.new(&"closing_work",closing_stock)
	var closing_animal=Animal.new(&"closing_during_commit",Vector3.ZERO,Vector3.ZERO);closing_animal.wool_growth=15
	closing_work.prepare("worker");closing_work.begin_shearing("worker",random);closing_work.advance("worker",120)
	var accepting: Array=[true]
	var close=func(_resource):accepting[0]=false
	closing_stock.reservations_changed.connect(close)
	var closed_result: Dictionary=closing_work.settle("worker",closing_animal,func():return accepting[0])
	check(closed_result.saved==0 and closed_result.discarded==closed_result.produced and closing_stock.get_reserved_in(R.WOOL)==0 and closing_stock.get_amount(R.WOOL)==0,"Close during top-up reservation is revalidated before atomic output")
	closing_stock.reservations_changed.disconnect(close)
