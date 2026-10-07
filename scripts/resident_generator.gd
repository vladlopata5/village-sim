extends RefCounted
## A local seeded random stream, independent of the game's global RNG.
const Factory = preload("res://scripts/resident_factory.gd")
const Profession = preload("res://scripts/resident_profession.gd")
const NAMES = ["Анна", "Фёдор", "Марина", "Иван", "Дарья"]
const Trait = preload("res://scripts/trait_type.gd")
const Balance = preload("res://scripts/balance_config.gd")
var _preference_random = RandomNumberGenerator.new()
var _random = RandomNumberGenerator.new()
var _sequence: int = 0
var _namespace: String

func _init(seed_value: int, id_namespace: String = "generated") -> void:
	_random.seed = seed_value
	_preference_random.seed = seed_value ^ 0x50524546
	_namespace = id_namespace

func generate(display_name: String = ""):
	_sequence += 1
	var resident_id := "%s_%d_%04d" % [_namespace, _random.seed, _sequence]
	var generated_name: String = NAMES[_random.randi_range(0, NAMES.size() - 1)]
	var traits := generate_traits()
	var preferences := generate_preferences()
	return Factory.create(resident_id, generated_name if display_name.is_empty() else display_name, _random.randi_range(18, 65), Profession.Type.NONE, traits, _random.randi_range(10, 30), _random.randi_range(5, 35), _random.randi_range(45, 80), &"", &"", preferences.liked, preferences.disliked)

func generate_traits() -> Array:
	var available: Array = Trait.Type.values()
	var first: int = available[_random.randi_range(0, available.size() - 1)]
	available.erase(first)
	available.erase(Trait.conflict(first))
	return [first, available[_random.randi_range(0, available.size() - 1)]]

func generate_preferences() -> Dictionary:
	# Own RNG stream preserves the existing character generation sequence.
	var available: Array = Trait.Type.values()
	var liked: Array = []
	var disliked: Array = []
	for category in range(2):
		var list: Array = liked if category == 0 else disliked
		var count: int = Balance.LIKED_TRAITS_PER_RESIDENT if category == 0 else Balance.DISLIKED_TRAITS_PER_RESIDENT
		for _index in range(count):
			if available.is_empty(): break
			var index := _preference_random.randi_range(0, available.size() - 1)
			list.append(available.pop_at(index))
	return {"liked": liked, "disliked": disliked}
