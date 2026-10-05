extends SceneTree
const Clock = preload("res://scripts/game_time.gd")
const Production = preload("res://scripts/gatherer_production.gd")
const Building = preload("res://scripts/building_data.gd")
const BT = preload("res://scripts/building_type.gd").Type
const Data = preload("res://scripts/resident_data.gd")
const Profession = preload("res://scripts/resident_profession.gd").Type
const Activity = preload("res://scripts/resident_activity.gd").Type
const Locations = preload("res://scripts/world_locations_2d.gd")
const Location = preload("res://scripts/world_location.gd")
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
var failures := 0
func _initialize(): call_deferred("_run")
func check(value: bool, message: String):
	if not value:
		failures += 1
		push_error(message)
func fixture(workers: int = 1):
	var hut = Building.new(&"hut", "Hut", BT.GATHERER_HUT)
	hut.resources.set_allowed_resource_types([FOOD])
	hut.resources.set_capacity(FOOD, 5)
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
	for speed in [1, 2, 4]:
		for frames in [1, 30, 120]:
			var f = fixture()
			f.clock.set_speed(speed)
			paused = true
			f.clock.advance(1000)
			check(f.hut.production_progress == 0 and f.hut.resources.get_amount(FOOD) == 0, "Pause produces no progress or FOOD")
			paused = false
			for frame in range(frames): f.clock.advance(60.0 / speed / frames)
			check(f.hut.resources.get_amount(FOOD) == 1 and f.hut.production_progress == 0, "60 actual work minutes make one FOOD, independent of FPS/speed")
			dispose(f)
	var f = fixture()
	var data = f.residents[0]
	for state in [Activity.IDLE, Activity.MOVING, Activity.EATING, Activity.RESTING, Activity.RELAXING, Activity.TALKING, Activity.SLEEPING, Activity.HAULING]:
		data.activity = state
		f.clock.debug_skip_minutes(10)
		check(f.hut.production_progress == 0, "Assigned but not actually WORKING contributes zero")
	data.activity = Activity.WORKING
	f.positions[data.id] = Vector2(1000, 1000)
	f.clock.debug_skip_minutes(10)
	check(f.hut.production_progress == 0, "Working remotely contributes zero")
	f.positions[data.id] = f.view.position
	data.profession = Profession.PORTER
	f.clock.debug_skip_minutes(10)
	data.profession = Profession.GATHERER
	data.work_location_id = &"other"
	f.clock.debug_skip_minutes(10)
	check(f.hut.production_progress == 0, "Profession and workplace must both match")
	data.work_location_id = f.hut.id
	f.clock.debug_skip_minutes(45)
	check(f.hut.production_progress == 45 and f.hut.resources.get_amount(FOOD) == 0, "45 minutes remain building-owned progress")
	data.activity = Activity.EATING
	f.clock.debug_skip_minutes(100)
	check(f.hut.production_progress == 45, "Meal preserves progress")
	data.activity = Activity.WORKING
	f.clock.debug_skip_minutes(15)
	check(f.hut.resources.get_amount(FOOD) == 1 and f.hut.production_progress == 0, "Returns and continues from 45/60")
	# Changing the worker also preserves the same building state.
	f.hut.production_progress = 45
	data.profession = Profession.NONE
	var replacement = Data.new("replacement", "Replacement", 30, Profession.GATHERER)
	replacement.work_location_id = f.hut.id
	replacement.activity = Activity.WORKING
	f.residents.append(replacement)
	f.positions[replacement.id] = f.view.position
	f.clock.debug_skip_minutes(15)
	check(f.hut.resources.get_amount(FOOD) == 2 and f.hut.production_progress == 0, "Replacement worker inherits building progress, not former worker state")
	f.hut.resources.add(FOOD, 3)
	f.hut.production_progress = 45
	f.clock.debug_skip_minutes(100)
	check(f.hut.production_progress == 45 and f.hut.resources.get_amount(FOOD) == 5, "Full output freezes progress without banking more work")
	f.hut.resources.try_take(FOOD, 1)
	f.clock.debug_skip_minutes(15)
	check(f.hut.resources.get_amount(FOOD) == 5 and f.hut.production_progress == 0, "Freeing capacity resumes saved progress")
	var unsupported: int = 999
	check(not f.hut.resources.allows_resource(unsupported) and not f.hut.resources.set_capacity(unsupported, 5) and not f.hut.resources.add(unsupported, 1), "Production output allows only FOOD, without adding a new resource type")
	dispose(f)
	f = fixture(2)
	f.clock.debug_skip_minutes(15)
	check(f.hut.production_progress == 30, "Two workers add two work minutes per minute")
	f.clock.debug_skip_minutes(15)
	check(f.hut.resources.get_amount(FOOD) == 1 and f.hut.production_progress == 0, "Two real workers double production speed")
	dispose(f)
	print("Gatherer production checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
