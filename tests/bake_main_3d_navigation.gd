extends SceneTree
const Coordinates = preload("res://scripts/prototypes/plane_coordinates.gd")
func _initialize() -> void: call_deferred("_bake")
func _bake() -> void:
	# The unchanged starter setup is the single input for this static migration asset.
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var navmesh := NavigationMesh.new()
	navmesh.cell_size = 2.0
	navmesh.cell_height = 1.0
	navmesh.agent_radius = 12.0
	navmesh.agent_height = 36.0
	navmesh.agent_max_climb = 1.0
	var source := NavigationMeshSourceGeometryData3D.new()
	source.add_faces(PackedVector3Array([Vector3(-1600,0,-1000),Vector3(1600,0,-1000),Vector3(1600,0,1000),Vector3(-1600,0,-1000),Vector3(1600,0,1000),Vector3(-1600,0,1000)]), Transform3D.IDENTITY)
	for building in main.buildings:
		var rect: Rect2 = building.footprint()
		var corners := PackedVector3Array([Coordinates.to_world(rect.position), Coordinates.to_world(rect.position + Vector2(0, rect.size.y)), Coordinates.to_world(rect.end), Coordinates.to_world(rect.position + Vector2(rect.size.x, 0))])
		source.add_projected_obstruction(corners, -1.0, 100.0, false)
	NavigationServer3D.bake_from_source_geometry_data(navmesh, source)
	var vertices := navmesh.get_vertices()
	for index in range(vertices.size()): vertices[index].y = 0.0
	navmesh.set_vertices(vertices)
	var result := ResourceSaver.save(navmesh, "res://scenes/main_3d_navigation.tres")
	print("Main 3D navmesh: %d polygons" % navmesh.get_polygon_count())
	main.free()
	quit(0 if result == OK and navmesh.get_polygon_count() > 0 else 1)
