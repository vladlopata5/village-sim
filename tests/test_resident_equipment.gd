extends SceneTree
const Data=preload("res://scripts/resident_data.gd")
const Equipment=preload("res://scripts/resident_equipment.gd")
const Item=preload("res://scripts/equipped_item.gd")
const R=preload("res://scripts/resource_type.gd").Type
const P=preload("res://scripts/resident_profession.gd").Type
const Clock=preload("res://scripts/game_time.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(text)
func model() -> void:
	var first=Data.new("first","Первый",20);var second=Data.new("second","Второй",20)
	check(first.equipment.item()==null and second.equipment.item()==null and first.inventory.amount==0,"New residents own empty equipment, separate from work cargo")
	for resource in R.values():
		check(Equipment.allowed(resource)==(resource==R.WOOL_CLOTHING),"Explicit slot eligibility, never category/quantity alone")
		if resource!=R.WOOL_CLOTHING:check(not first.equipment.set_item(Equipment.Slot.CLOTHING,Item.new(resource)),"Invalid equipment cannot enter slot")
	var clothing=Item.new(R.WOOL_CLOTHING)
	check(first.equipment.set_item(Equipment.Slot.CLOTHING,clothing) and clothing.durability==1.0,"Full concrete item installed")
	first.profession=P.TAILOR;first.inventory.put(R.WOOL,1)
	check(first.equipment.item()==clothing and second.equipment.item()==null and first.inventory.amount==1,"Profession/work cargo never own or clear clothing")
	first.equipment.advance(3888)
	check(clothing.remaining_minutes==432 and is_equal_approx(clothing.durability,.1) and not first.equipment.needs_clothing(),"Exactly10 percent is not a replacement request")
	first.equipment.advance(1)
	check(clothing.remaining_minutes==431 and first.equipment.needs_clothing() and first.equipment.item()==clothing,"Strict below10 retains old clothing")
	check(not first.equipment.receive(R.WOOL_CLOTHING,func():return false) and first.equipment.item()==clothing,"Failed economic take retains exact old item")
	var calls: Array=[]
	var take=func():
		calls.append(true)
		check(not first.equipment.receive(R.WOOL_CLOTHING,func():return true) and not first.equipment.set_item(Equipment.Slot.CLOTHING,null),"Reentrant transfer/edit rejected")
		return true
	check(first.equipment.receive(R.WOOL_CLOTHING,take) and calls.size()==1 and first.equipment.item()!=clothing and first.equipment.item().durability==1,"Successful take alone replaces and destroys old slot reference")
	check(not first.equipment.receive(R.WOOL_CLOTHING,take) and calls.size()==1,"Healthy clothing cannot be automatically replaced")
	first.equipment.advance(4319)
	check(first.equipment.item()!=null and first.equipment.item().remaining_minutes==1,"Item lasts until final game minute")
	first.equipment.advance(1);first.equipment.advance(9999)
	check(first.equipment.item()==null and first.equipment.needs_clothing() and first.inventory.amount==1,"Full wear removes item, never work cargo, no negative durability")
	check(second.equipment.item()==null,"Residents remain independent")
func speeds() -> void:
	for speed in [1,2,4,10,20]:
		var clock=Clock.new();root.add_child(clock);clock.set_process(false);clock.total_minutes=0;clock.set_speed(speed)
		var equipment=Equipment.new();equipment.set_item(Equipment.Slot.CLOTHING,Item.new(R.WOOL_CLOTHING))
		clock.minute_changed.connect(func(_now):equipment.advance(1))
		clock.advance(4319.0/speed)
		check(clock.total_minutes==4319 and equipment.item().remaining_minutes==1,"Game clock life independent of x%d"%speed)
		clock.advance(1.0/speed)
		check(clock.total_minutes==4320 and equipment.item()==null,"Exact4320 lifetime with large game-time step x%d"%speed)
		clock.free()
func run() -> void:
	model();speeds();print("Resident equipment: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
