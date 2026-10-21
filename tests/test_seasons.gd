extends SceneTree
const Season=preload("res://scripts/season.gd")
const Clock=preload("res://scripts/game_time.gd")
const F=preload("res://tests/residents_ui_fixture.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func calendar() -> void:
	var expected: Dictionary={1:0,2:0,3:0,4:1,6:1,7:2,9:2,10:3,12:3,13:0,16:1,25:0,12000000000010:3,12000000000013:0}
	var clock=Clock.new();root.add_child(clock);clock.set_process(false)
	for day in expected:
		clock.total_minutes=(day-1)*Clock.MINUTES_PER_DAY
		check(clock.get_day()==day and clock.get_season()==expected[day] and Season.for_day(day)==expected[day],"Absolute day/season %d"%day)
		check(clock.get_season_name()==Season.NAMES[expected[day]],"Single UI name definition")
	check(Season.for_day(0)==Season.Type.SPRING,"Invalid pre-calendar day clamps to spring")
	clock.free()
func transitions() -> void:
	for speed in Clock.SUPPORTED_SPEEDS:
		var clock=Clock.new();clock.total_minutes=0;root.add_child(clock);clock.set_process(false);clock.set_speed(speed)
		var events: Array=[];var minutes: Array=[]
		clock.season_changed.connect(func(previous,current):events.append([previous,current,clock.get_day(),clock.total_minutes]))
		clock.minute_changed.connect(func(now):minutes.append(now))
		clock.advance(4319.0/speed)
		check(events.is_empty() and clock.get_day()==3 and clock.get_season()==Season.Type.SPRING,"No false season before day4 x%d"%speed)
		clock.advance(1.0/speed)
		check(events==[[0,1,4,4320]],"One transition exactly at day4 midnight x%d"%speed)
		clock.advance(0)
		check(events.size()==1,"Zero step cannot repeat event")
		clock.advance((24*1440-4320.0)/speed)
		check(clock.get_day()==25 and clock.get_season()==Season.Type.SPRING and events.size()==8,"Large time step crosses two cycles x%d"%speed)
		for index in events.size():
			check(events[index]==[index%4,(index+1)%4,4+index*3,4320*(index+1)],"Every crossed boundary emitted once and in order")
		check(minutes.size()==34560 and minutes[0]==1 and minutes[-1]==34560,"Season calendar preserves every minute")
		clock.free()
func visuals_and_ui() -> void:
	var world=F.create(self);var clock=world.game_time;var panel=world.game_ui.info_panel
	var mesh: MeshInstance3D=world.get_node("World/Ground/Mesh")
	var scene_state: SceneState=load("res://scenes/main_3d.tscn").get_state()
	var authored_material: StandardMaterial3D
	for node_index in scene_state.get_node_count():
		if String(scene_state.get_node_path(node_index)).ends_with("World/Ground/Mesh"):
			for property_index in scene_state.get_node_property_count(node_index):
				if scene_state.get_node_property_name(node_index,property_index)==&"material_override":authored_material=scene_state.get_node_property_value(node_index,property_index)
	var spring: Color=authored_material.albedo_color
	check(mesh.material_override!=authored_material and mesh.material_override.albedo_color==spring,"World owns one duplicate and preserves authored spring RGB")
	check(spring==Color(0.28,0.43,0.27) and panel.day_summary.text=="День 1 · Весна","Original grass and compact season label at day1")
	var grass_material: StandardMaterial3D=mesh.material_override
	var ground_mesh: Mesh=mesh.mesh
	var collision: Shape3D=world.get_node("World/Ground/Collision").shape
	var roads=world.roads;var view=world.road_layer
	var path:=Vector2i(185,120);var dirt:=path+Vector2i.RIGHT
	roads.set_trample_level(path,7);roads.set_trample_level(path+Vector2i.UP,15);roads.add_road(dirt)
	view.flush_updates()
	var batch: MultiMesh=view.multimesh
	var nav_revision: int=world.navigation.revision
	var tint: StandardMaterial3D=world.mycelium_view.patches.multimesh.mesh.material
	var nature_color: Color=tint.albedo_color
	var non_grass: Array=[]
	for holder in [world.get_node("World/BuildingViews")]+world.tree_views.values():
		for node in holder.find_children("*","MeshInstance3D",true,false):
			if node.material_override is StandardMaterial3D:non_grass.append([node.material_override,node.material_override.albedo_color])
	var snapshot: Dictionary={}
	clock.season_changed.connect(func(_previous,current):
		check(roads.levels==snapshot.levels and roads._random.state==snapshot.random,"Season callback never changes wear levels/probability RNG")
		check(world.navigation.revision==nav_revision and mesh.mesh==ground_mesh and world.get_node("World/Ground/Collision").shape==collision,"No navigation, ground mesh or collision rebuild")
		check(view.multimesh==batch and mesh.material_override==grass_material,"Season reuses grass material and road batch")
		# Dummy headless storage returns black instead of the GPU instance color.
		# The same test is also run with the real renderer to validate readback.
		if DisplayServer.get_name()!="headless":
			for cell in view._cells:
				var actual: Color=batch.get_instance_color(view._slots[cell]);var expected: Color=view.color_for(cell)
				check(maxf(absf(actual.r-expected.r),maxf(absf(actual.g-expected.g),absf(actual.b-expected.b)))<0.005,"Existing visible path buffer receives new seasonal blend")
		check(grass_material.albedo_color==Season.palette(current,spring).grass,"Palette applied before next minute")
		check(view.color_for(dirt)==view.DIRT_COLOR and tint.albedo_color==nature_color,"Manual dirt and independent mycelium land tint unchanged")
		for pair in non_grass:check(pair[0].albedo_color==pair[1],"Non-grass material unchanged")
	)
	for day in [4,7,10,13]:
		if day==7:
			world.resident_selection.select(world.residents[0]);panel.set_expanded(true);panel.select_tab(&"inventory")
		elif day==10:world.resident_selection.select_building(world.warehouse_data);panel.select_tab(&"storage")
		elif day==13:world.resident_selection.clear()
		var selected: Variant=world.resident_selection.selected_entity
		var active_tab: StringName=panel.active_tab
		# Rebase only the fixture clock to the minute preceding a real calendar boundary.
		clock.total_minutes=(day-1)*1440-1
		snapshot.levels=roads.levels.duplicate();snapshot.random=roads._random.state
		clock.advance(1.0)
		check(clock.get_day()==day and panel.day_summary.text=="День %d · %s"%[day,clock.get_season_name()],"Minute path updates current day/season even while hidden")
		check(world.resident_selection.selected_entity==selected and panel.active_tab==active_tab,"Season preserves resident/building selection and inventory/storage tab")
		check(view.color_for(path).is_equal_approx(grass_material.albedo_color.lerp(view.DIRT_COLOR,roads.trample_level(path)/15.0)),"Partial natural path blends seasonal grass with original dirt")
		check(world.navigation.revision==nav_revision,"Whole clock boundary does not change navigation")
	check(mesh.material_override.albedo_color==spring and authored_material.albedo_color==spring,"Next spring restores exact source color without mutating shared scene")
	world._season_changed(0,0);world._season_changed(0,0)
	check(mesh.material_override==grass_material and grass_material.albedo_color==spring,"Repeated application is idempotent, no color drift")
	check(panel.day_summary.visible and panel._tabs.is_empty(),"Cleared selection retains compact current season")
	var palette_colors: Array=[]
	for season in Season.Type.values():palette_colors.append(Season.palette(season,spring).grass)
	check(palette_colors[1]!=spring and palette_colors[1]!=palette_colors[2] and palette_colors[3]==Color.WHITE,"Central seasonal palette distinct, winter white")
	var winter=load("res://scenes/main_3d.tscn").instantiate();winter.get_node("GameTime").total_minutes=9*1440;root.add_child(winter)
	winter.game_time.set_process(false);winter.game_logger.console_enabled=false
	check(winter.game_time.get_day()==10 and winter.game_time.get_season()==Season.Type.WINTER and winter.get_node("World/Ground/Mesh").material_override.albedo_color==Color.WHITE,"Day10 startup initializes winter without waiting for a transition")
	check(winter.game_ui.info_panel.day_summary.text=="День 10 · Зима" and grass_material.albedo_color==spring,"Second world season/initial UI independent of first")
	winter.free();world.free()
func run() -> void:
	calendar();transitions();visuals_and_ui()
	print("Seasons: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
