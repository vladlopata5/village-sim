extends RefCounted
## Explicit historical fixture; canonical new-game setup is tested separately.
static func instantiate():
	var world = load("res://scenes/main_3d.tscn").instantiate()
	world.legacy_reference_setup = true
	return world
