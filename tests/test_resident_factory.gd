extends SceneTree
const Factory = preload("res://scripts/resident_factory.gd")
const Generator = preload("res://scripts/resident_generator.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
var failures := 0
func _initialize(): call_deferred("_run")
func check(value: bool, message: String):
	if not value:
		failures += 1
		push_error(message)
func signature(data) -> Array:
	var ids: Array = []
	for definition in data.traits: ids.append(definition.id)
	return [data.id, data.resident_name, data.age, ids, data.hunger, data.fatigue, data.mood]
func _run():
	var traits = [preload("res://assets/traits/stubborn.tres")]
	var a = Factory.create("a", "A", 25, Profession.Type.PORTER, traits, 20, 30, 60, &"shared_home", &"warehouse_01")
	var b = Factory.create("b", "B", 35, Profession.Type.NONE, traits, 10, 15, 70, &"shared_home", &"")
	check(a.inventory != b.inventory and a.activity == Activity.Type.IDLE and a.inventory.amount == 0, "Factory owns fresh inventory and initial activity")
	a.inventory.put(FOOD, 1)
	a.traits.clear()
	a.hunger = 90
	check(b.inventory.amount == 0 and b.hunger == 10 and b.traits.size() == 1 and traits.size() == 1, "Mutable data and trait lists never leak between residents")
	check(a.home_location_id == b.home_location_id, "Several residents may share a place ID")
	var first = Generator.new(123)
	var second = Generator.new(123)
	var other = Generator.new(456)
	var seen: Array = []
	for index in range(30):
		var generated = first.generate()
		check(signature(generated) == signature(second.generate()), "Seed reproduces full sequence")
		check(not seen.has(generated.id), "Unique IDs within generator namespace")
		seen.append(generated.id)
		check(generated.traits.size() in [2, 3] and generated.age >= 18 and generated.age <= 65, "Simple age and trait generation")
		check(generated.hunger >= 10 and generated.hunger <= 30 and generated.fatigue >= 5 and generated.fatigue <= 35 and generated.mood >= 45 and generated.mood <= 80, "Reasonable initial needs")
		check(generated.profession == Profession.Type.NONE and generated.home_location_id.is_empty() and generated.work_location_id.is_empty(), "Settlement assigns profession and places")
	check(signature(Generator.new(123).generate()) != signature(other.generate()), "Different seed changes generated data")
	print("Factory/generator checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
