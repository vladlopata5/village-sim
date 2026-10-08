extends SceneTree
## Manual editor-time tool: bake only the prototype ground and static building.
## Run with --headless --path <project> --script res://tests/bake_prototype_navigation.gd
const Coordinates = preload("res://scripts/prototypes/plane_coordinates.gd")
func _initialize() -> void: call_deferred("_bake")
func _bake() -> void:
	var scene = load("res://scenes/prototypes/2_5d_prototype.tscn").instantiate()
	root.add_child(scene)
	var navmesh := NavigationMesh.new()
	navmesh.cell_size = 0.1
	navmesh.cell_height = 0.05
	navmesh.agent_radius = 0.5
	navmesh.agent_height = 1.8
	navmesh.agent_max_climb = 0.1
	navmesh.agent_max_slope = 10.0
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_EXPLICIT
	navmesh.geometry_source_group_name = &"prototype_navigation_geometry"
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navmesh, source, scene)
	# Explicit solid exclusion: collider surfaces alone can leave a hollow box interior.
	var footprint: Rect2 = scene.building.footprint()
	var corners := PackedVector3Array([
		Coordinates.to_world(footprint.position),
		Coordinates.to_world(footprint.position + Vector2(0, footprint.size.y)),
		Coordinates.to_world(footprint.end),
		Coordinates.to_world(footprint.position + Vector2(footprint.size.x, 0))])
	source.add_projected_obstruction(corners, -0.1, 3.2, false)
	NavigationServer3D.bake_from_source_geometry_data(navmesh, source)
	var vertices := navmesh.get_vertices()
	# Recast raises flat faces by one voxel; normalize the flat ground to Y=0.
	for index in range(vertices.size()): vertices[index].y = 0.0
	navmesh.set_vertices(vertices)
	var result := ResourceSaver.save(navmesh, "res://scenes/prototypes/prototype_navigation.tres")
	print("Prototype navmesh: %d polygons; save=%d" % [navmesh.get_polygon_count(), result])
	scene.free()
	quit(0 if result == OK and navmesh.get_polygon_count() > 0 else 1)
