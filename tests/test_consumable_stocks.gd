extends SceneTree
const Stock=preload("res://scripts/consumable_stock.gd")
const Receiver=preload("res://scripts/consumable_receiver.gd")
const Recipe=preload("res://scripts/production_recipe.gd")
const Batch=preload("res://scripts/production_batch.gd")
const Box=preload("res://scripts/resource_container.gd")
const R=preload("res://scripts/resource_type.gd").Type
var checks:=0
var failures:=0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func fill(stock: RefCounted, resource: int, quantity: int) -> void:
	check(stock.reserve_in(resource,quantity) and stock.deliver(resource,quantity),"Converted complete physical units")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var fuel=Stock.new(&"fuel","Fuel",20,{R.LOG:5,R.PLANK:10})
	var water=Stock.new(&"water","Test stock only",30,{R.FOOD:3})
	var receiver=Receiver.new(&"test",fuel)
	fill(fuel,R.LOG,2)
	check(fuel.amount==10 and receiver.get_amount(R.LOG)==0,"Only numerical units remain")
	check(receiver.reserve_in(R.LOG,1) and receiver.reserve_in(R.LOG,1) and not receiver.reserve_in(R.LOG,1) and not receiver.reserve_in(R.PLANK,1),"All incoming materials share hard capacity")
	check(receiver.release_in(R.LOG,1) and receiver.add_reserved(R.LOG,1) and fuel.amount==15,"Release only one promise and convert the other")
	check(receiver.reserve_in(R.LOG,1) and receiver.add_reserved(R.LOG,1) and fuel.amount==20 and not receiver.add_reserved(R.LOG,1),"Exact full conversion once")
	check(fuel.reserve(&"use",2),"Reserve operation units")
	fuel.commit_payment(&"use")
	check(fuel.amount==18 and not receiver.reserve_in(R.LOG,1) and not fuel.reserve(&"too_many",19),"No partial conversion or negative stock")
	fill(water,R.FOOD,2)
	check(water.amount==6 and fuel.amount==18,"Independent stocks and coefficients")
	var box=Box.new(&"factory")
	box.set_capacity(R.MUSHROOM,10);box.set_capacity(R.FRIED_MUSHROOM,10);box.add(R.MUSHROOM,3)
	var recipe=Recipe.new({R.MUSHROOM:1},{R.FRIED_MUSHROOM:2},30,&"test")
	recipe.consumables={&"fuel":1,&"water":2}
	var batch=Batch.new(&"first",recipe,box,{&"fuel":fuel,&"water":water})
	check(batch.prepare("worker") and fuel.amount==18 and water.amount==6 and fuel.reserved_units()==1 and water.reserved_units()==2,"Preparation reserves without paying")
	batch.cancel();batch.cancel()
	check(fuel.reserved_units()==0 and water.reserved_units()==0 and box.get_reserved_out(R.MUSHROOM)==0,"Repeated pre-start cancellation releases every stock")
	batch=Batch.new(&"paid",recipe,box,{&"fuel":fuel,&"water":water})
	check(batch.prepare("worker"),"Prepare two stocks")
	var observed: Array=[]
	fuel.changed.connect(func():observed.append([fuel.amount,water.amount,box.get_amount(R.MUSHROOM)]),CONNECT_ONE_SHOT)
	check(batch.begin("worker") and observed==[[17,4,2]] and not batch.begin("worker"),"All payments precede the first observer, start is idempotent")
	batch.advance("worker",10);batch.release_worker("worker")
	check(batch.claim("other") and batch.begin("other") and fuel.amount==17 and water.amount==4,"Resume never pays twice")
	batch.advance("other",20)
	check(batch.finish("other") and box.get_amount(R.FRIED_MUSHROOM)==2 and not batch.finish("other"),"Exact output once")
	var insufficient=Batch.new(&"insufficient",recipe,box,{&"fuel":fuel})
	check(not insufficient.prepare("worker") and fuel.reserved_units()==0 and box.get_reserved_out(R.MUSHROOM)==0,"Missing second stock rolls all reservations back")
	var nested=Batch.new(&"nested",recipe,box,{&"fuel":fuel,&"water":water})
	check(nested.prepare("worker"),"Prepare nested cancellation")
	fuel.changed.connect(func():nested.cancel(),CONNECT_ONE_SHOT)
	check(not nested.begin("worker") and nested.is_terminal() and fuel.amount==16 and water.amount==2 and box.get_amount(R.MUSHROOM)==1,"Cancel during paid-start callbacks cannot partially pay or refund")
	check(fuel.reserved_units()==0 and water.reserved_units()==0 and box.get_reserved_in(R.FRIED_MUSHROOM)==0,"Nested cleanup leaves no obligations")
	print("Consumable stocks: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
