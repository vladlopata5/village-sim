extends RefCounted
## A local seeded random stream, independent of the game's global RNG.
const Factory = preload("res://scripts/resident_factory.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const NAMES = ["Анна", "Фёдор", "Марина", "Иван", "Дарья"]
const TRAITS = [preload("res://assets/traits/hardworking.tres"), preload("res://assets/traits/sociable.tres"), preload("res://assets/traits/stubborn.tres")]
var _random = RandomNumberGenerator.new()
var _sequence: int = 0
var _namespace: String

func _init(seed_value: int, id_namespace: String = "generated") -> void:
	_random.seed = seed_value
	_namespace = id_namespace

func generate(display_name: String = ""):
	_sequence += 1
	var resident_id := "%s_%d_%04d" % [_namespace, _random.seed, _sequence]
	var generated_name: String = NAMES[_random.randi_range(0, NAMES.size() - 1)]
	var traits: Array = TRAITS.duplicate()
	for index in range(traits.size() - 1, 0, -1):
		var other := _random.randi_range(0, index)
		var saved = traits[index]
		traits[index] = traits[other]
		traits[other] = saved
	traits.resize(_random.randi_range(2, 3))
	return Factory.create(resident_id, generated_name if display_name.is_empty() else display_name, _random.randi_range(18, 65), Profession.Type.NONE, traits, _random.randi_range(10, 30), _random.randi_range(5, 35), _random.randi_range(45, 80), &"", &"")
