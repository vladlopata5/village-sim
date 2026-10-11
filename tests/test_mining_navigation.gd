extends SceneTree
const Grid = preload("res://scripts/navigation_grid.gd")
const Rock = preload("res://scripts/rock_data.gd")
const Locations = preload("res://scripts/world_3d/natural_source_locations_3d.gd")
const C = preload("res://scripts/world_3d/world_coordinates.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	var map := Grid.new(Rect2(-10,-10,20,20))
	var rock := Rock.new(&"rock",C.to_sim(Vector3(4.25,0,0.25)))
	var area := Rect2(3.35,-0.65,1.8,1.8)
	map.add_blocker(rock.id,area)
	var resolver := Locations.new()
	resolver.navigation=map
	var point: Variant = resolver.resolve(rock,C.to_sim(Vector3(-4.25,0,0.25)))
	check(point is Vector2 and resolver.is_available(point) and resolver.in_range(rock,point),"Hard source annulus has reachable outside approach")
	check(not map.is_world_walkable(C.to_world(rock.position)),"Hard center invalid")
	var generation := map.topology_generation
	for cycle in 10:
		check(rock.claim(&"worker") and rock.add_work(&"worker",60)==cycle+1,"Finite cycles unique")
		check(map.topology_generation==generation,"Domain mutations never edit topology")
	map.add_blocker(&"other",area)
	map.remove_blocker(rock.id)
	check(not map.is_world_walkable(C.to_world(rock.position)) and map.topology_generation==generation,"Overlapping blocker survives depletion")
	map.remove_blocker(&"other")
	check(map.is_world_walkable(C.to_world(rock.position)),"Final obstacle owner removal opens cells")
	map.add_blocker(&"wall",Rect2(0,-10,0.5,20))
	check(resolver.resolve(rock,C.to_sim(Vector3(-4.25,0,0.25)))==null,"Unreachable annulus rejected by connectivity")
	print("Mining navigation: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
