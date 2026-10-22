extends "res://tests/test_textile_production.gd"
const Fields=preload("res://scripts/farm_fields.gd")
const Grid=preload("res://scripts/build_grid.gd")
const Nav=preload("res://scripts/navigation_grid.gd")
const Water=preload("res://scripts/water_sources.gd")
const Coordinates=preload("res://scripts/world_3d/world_coordinates.gd")
func run() -> void:
	var grid=Grid.new(Rect2(-5,-5,10,10));var nav=Nav.new(grid.bounds);var fields=Fields.new(grid)
	var clock=preload("res://scripts/game_time.gd").new();root.add_child(clock);clock.set_process(false);clock.total_minutes=420
	fields.setup(clock)
	var sync=func(cells):
		var edits: Dictionary={}
		for cell in cells:edits[cell]=fields.terrain(cell)==Fields.Terrain.WATER
		nav.edit_terrain_cells(edits)
	fields.changed.connect(sync)
	var water=Water.new();water.setup(fields,nav,null)
	var center:=Vector2i(10,10)
	check(fields.set_terrain([center],Fields.Terrain.WATER) and not nav.is_cell_walkable(center),"Water closes only its own navigation cell")
	check(water.banks.size()==4 and not water.banks.has(center+Vector2i.ONE),"Exactly four side-adjacent banks, no diagonals")
	var left:=grid.cell_to_world(Vector2i(4,10));var right:=grid.cell_to_world(Vector2i(15,10))
	var path: PackedVector3Array=nav.find_path(left,right)
	check(not path.is_empty() and Array(path).all(func(point):return nav.world_to_cell(point)!=center),"Ordinary smoothed path goes around water")
	check(nav.find_path(left,grid.cell_to_world(center)).is_empty(),"Movement target in water is rejected")
	check(not fields.reserve([center],&"farmer",Fields.State.BARE),"Water cannot be plowed")
	var bank:=center+Vector2i.LEFT
	for surface in [Fields.Terrain.GRASS,Fields.Terrain.DIRT,Fields.Terrain.SAND]:
		fields.set_terrain([bank],surface)
		check(nav.is_cell_walkable(bank) and water.banks.has(bank),"Every land surface provides a bank")
		var id: StringName=water.banks[bank]
		check(water.reserve(id,&"collector") and water.pickup(id,&"collector"),"Every land surface supports finite collection from infinite source")
	check(fields.reserve([bank],&"farmer",Fields.State.BARE) and fields.plow(bank,&"farmer"),"Sand uses ordinary plowing, becoming dirt")
	var barrier: Array=[]
	for y in 20:barrier.append(Vector2i(10,y))
	check(fields.set_terrain(barrier,Fields.Terrain.WATER) and not nav.has_walkable_path(left,right),"Full water wall disconnects ordinary navigation")
	check(fields.set_terrain([center],Fields.Terrain.SAND) and nav.has_walkable_path(left,right),"Restoring land reopens connectivity")
	fields.set_terrain([center],Fields.Terrain.WATER)
	nav.add_blocker(&"overlap",Rect2(0,0,.5,.5));nav.remove_blocker(&"overlap")
	check(not nav.is_cell_walkable(center),"Removing another obstacle never opens water")
	fields.set_terrain([center],Fields.Terrain.GRASS)
	check(nav.is_cell_walkable(center),"Terrain owner releases only its own solids")
	fields.changed.disconnect(sync)
	clock.free()
	await world_checks()
	print("Water terrain: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func world_checks() -> void:
	var world=F.create(self)
	var cell: Vector2i=world.build_grid.world_to_cell(Vector3(-15,0,18))
	var cells: Array=[]
	for y in 5:
		for x in 7:cells.append(cell+Vector2i(x,y))
	check(world.paint_terrain(cells,Fields.Terrain.WATER),"Canonical debug edit commits empty water region")
	world.placement.select(D.for_type(T.WELL));world.placement.update_world_position(world.build_grid.cell_to_world(cell+Vector2i(3,2)))
	check(not world.placement.can_place() and not world.roads.add_road(cell) and not world._farm_cell_allowed(cell),"Water rejects buildings, roads and farming")
	check(world.place_ground_resources(R.LOG,1,Coordinates.to_sim(world.build_grid.cell_to_world(cell+Vector2i(3,2))),world.ground_resources.PlacementMode.NATURAL).placed==0,"Natural drops cannot occupy water, including overflow search")
	check(world.paint_terrain(cells,Fields.Terrain.SAND),"Water returns to ordinary sand")
	world.placement.update_world_position(world.build_grid.cell_to_world(cell+Vector2i(3,2)))
	check(world.placement.can_place() and world.roads.add_road(cell) and world._farm_cell_allowed(cell+Vector2i(1,0)),"Sand allows construction, roads and farming")
	check(not world.paint_terrain([cell],Fields.Terrain.WATER),"Tool does not silently destroy manual road")
	var roadside: Vector2i=cell+Vector2i(0,-1)
	check(world.paint_terrain([roadside],Fields.Terrain.WATER) and world.water_sources.banks.has(cell) and world.roads.contains(cell),"A manual road on dry land is a valid shore without special sand")
	var bank_id: StringName=world.water_sources.banks[cell]
	check(world.water_sources.reserve(bank_id,&"road_user") and world.water_sources.pickup(bank_id,&"road_user"),"Road bank supports ordinary source collection")
	var actor=world.resident_runtimes[0]
	var occupied: Vector2i=world.build_grid.world_to_cell(actor.view.global_position)
	check(not world.paint_terrain([occupied],Fields.Terrain.WATER),"Tool refuses resident underfoot")
	check(not world.paint_terrain(world.build_grid.occupied_cells(world.warehouse_data.id),Fields.Terrain.WATER),"Tool refuses occupied building")
	await process_frame
	world.free()
