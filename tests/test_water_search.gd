extends "res://tests/test_textile_production.gd"
const Fields=preload("res://scripts/farm_fields.gd")
const Grid=preload("res://scripts/build_grid.gd")
const Nav=preload("res://scripts/navigation_grid.gd")
const Water=preload("res://scripts/water_sources.gd")
const Sources=preload("res://scripts/resource_sources.gd")
const Coordinates=preload("res://scripts/world_3d/world_coordinates.gd")
func run() -> void:
	var grid=Grid.new(Rect2(-16,-16,32,32));var nav=Nav.new(grid.bounds);var fields=Fields.new(grid)
	var sync=func(cells):
		var solids: Dictionary={}
		for cell in cells:solids[cell]=fields.terrain(cell)==Fields.Terrain.WATER
		nav.edit_terrain_cells(solids)
	fields.changed.connect(sync)
	var water=Water.new();water.setup(fields,nav,null)
	var lake: Array=[]
	for y in range(12,52):
		for x in range(12,52):lake.append(Vector2i(x,y))
	fields.set_terrain(lake,Fields.Terrain.WATER)
	check(water.banks.size()==160,"160 perimeter candidates for1600 water cells")
	var sources=Sources.new();sources.bind_water(water)
	var queries: Array=[0]
	sources.route_available=func(a,b):queries[0]+=1;return nav.has_walkable_path(Coordinates.to_world(a),Coordinates.to_world(b))
	var origin:=Coordinates.to_sim(grid.cell_to_world(Vector2i(8,8)))
	var began:=Time.get_ticks_usec()
	var selected=sources.find_first(R.WATER,origin,origin,&"",null)
	var duration:=Time.get_ticks_usec()-began
	check(selected!=null and queries[0]==2,"Selection stops after two route checks of first reachable bank, not A-star for every water cell")
	check(sources.reserve(selected,R.WATER,&"one") and not sources.reserve(selected,R.WATER,&"two"),"Bank access exclusive without limiting source volume")
	check(sources.pickup(selected,R.WATER,&"one") and not sources.pickup(selected,R.WATER,&"one") and sources.available(selected,R.WATER),"One finite cargo per owner, bank becomes reusable without regeneration")
	# Invalid first candidates do not prevent trying another accessible side.
	var blocked: Array=[0]
	sources.route_available=func(_a,_b):blocked[0]+=1;return blocked[0]>3
	selected=sources.find_first(R.WATER,origin,origin,&"",null)
	check(selected!=null and blocked[0]>=5,"Search skips unreachable prefix rather than declaring no work")
	sources.route_available=func(_a,_b):return false
	check(sources.find_first(R.WATER,origin,origin,&"",null)==null,"Fully unreachable lake yields no offer or claims")
	fields.changed.disconnect(sync)
	print("WATER_SEARCH_MEASUREMENT ",JSON.stringify({"water_cells":1600,"banks":water.banks.size(),"selection_usec":duration,"route_queries":queries[0]}))
	print("Water search: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
