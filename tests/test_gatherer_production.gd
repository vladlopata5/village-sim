extends SceneTree
const Clock = preload("res://scripts/game_time.gd")
const Production = preload("res://scripts/gatherer_production.gd")
const Building = preload("res://scripts/building_data.gd")
const BT = preload("res://scripts/building_type.gd").Type
const Data = preload("res://scripts/resident_data.gd")
const Profession = preload("res://scripts/resident_profession.gd").Type
const Activity = preload("res://scripts/resident_activity.gd").Type
const Locations = preload("res://tests/domain_locations.gd")
const Location = preload("res://scripts/world_location.gd")
const MUSHROOM = preload("res://scripts/resource_type.gd").Type.MUSHROOM
var failures := 0
func _initialize(): call_deferred("_run")
func check(value: bool, message: String):
	if not value:
		failures += 1
		push_error(message)
func fixture(workers: int = 1):
	var hut = Building.new(&"hut", "Hut", BT.GATHERER_HUT)
	hut.resources.set_allowed_resource_types([MUSHROOM])
	hut.resources.set_capacity(MUSHROOM, 5)
	var view = Node2D.new()
	root.add_child(view)
	view.position = Vector2(20, 30)
	var locations = Locations.new()
	locations.register(Location.new(hut.id, hut.display_name), view)
	var residents: Array = []
	var positions: Dictionary = {}
	for i in range(workers):
		var data = Data.new("worker_%d" % i, "Worker", 30, Profession.GATHERER)
		data.work_location_id = hut.id
		data.activity = Activity.WORKING
		residents.append(data)
		positions[data.id] = view.position
	var clock = Clock.new()
	root.add_child(clock)
	clock.set_process(false)
	var controller = Production.new()
	root.add_child(controller)
	controller.setup(clock, hut, residents, locations, func(id): return positions.get(id))
	return {"hut": hut, "view": view, "clock": clock, "production": controller, "residents": residents, "positions": positions}
func dispose(f):
	f.clock.free()
	f.production.free()
	f.view.free()
func _run():
	for speed in [1,2,4,10,20]:
		for workers in [1,4]:
			var f=fixture(workers)
			f.clock.set_speed(speed)
			for data in f.residents:
				for state in Activity.values():
					data.activity=state
					f.clock.advance(60.0/speed)
			check(f.hut.resources.get_amount(MUSHROOM)==0 and f.hut.production_progress==0,"No activity/speed/worker count virtually creates mushrooms")
			check(not f.production.can_work(f.residents[0]),"Without bound natural stock there is no gathering work")
			check(f.hut.resources.get_capacity(MUSHROOM)==5,"Existing five-unit output capacity retained")
			dispose(f)
	print("No virtual gatherer production: ","PASS" if failures==0 else "FAIL")
	quit(1 if failures else 0)
