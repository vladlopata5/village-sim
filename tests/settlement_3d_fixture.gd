extends RefCounted
## Replace only the root script before instantiation; all canonical nodes/resources
## remain identical. Changing script on a live instance leaks orphan initializers.
static func instantiate():
	var packed: PackedScene=load("res://scenes/main_3d.tscn").duplicate()
	var state: Dictionary=packed._bundled.duplicate(true)
	var variants: Array=state.variants
	for index in range(variants.size()):
		if variants[index] is Script and variants[index].resource_path=="res://scripts/world_3d/main_3d.gd":
			variants[index]=preload("res://tests/seeded_world_3d.gd")
	state.variants=variants
	packed._bundled=state
	return packed.instantiate()
