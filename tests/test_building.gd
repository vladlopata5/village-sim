extends SceneTree
const Fixture = preload("res://tests/canonical_ui_fixture.gd")
const Coordinates = preload("res://scripts/world_3d/world_coordinates.gd")
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func run() -> void:
	var world=Fixture.make(self)
	var building=world.warehouse_data
	var view=world.world_locations.get_view(building.id)
	var place=world.world_locations.get_location(building.id)
	check(building is RefCounted and not building is Node,"Building data is nonvisual")
	check(place.id==building.id and place.display_name==building.display_name,"Location links stable identity")
	check(view.building_data==building and view.is_visible_in_tree(),"Canonical view uses original data")
	check(view.global_position==Coordinates.to_world(building.position),"World conversion at registered center")
	var point: Variant=world.world_locations.get_position(building.id)
	check(point is Vector2 and not building.footprint().has_point(point),"Authored entrance is real walkable action location")
	check(world.get_node("World/BuildingViews").get_child_count()==world.buildings.size(),"One canonical view per building")
	view.free()
	check(is_instance_valid(building) and world.world_locations.get_location(building.id)==place,"Removing view preserves data/location")
	check(world.world_locations.get_position(building.id)==null,"Missing view leaves no fake action coordinate")
	var replacement=preload("res://scripts/world_3d/building_view_3d.gd").new()
	world.get_node("World/BuildingViews").add_child(replacement)
	replacement.position=Coordinates.to_world(building.position)
	replacement.setup(building)
	world.building_uses.register(building,replacement)
	world.world_locations.register(place,replacement)
	check(world.world_locations.get_view(building.id)==replacement and replacement.building_data==building,"Replacement reuses original identity")
	world.free()
	print("building: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
