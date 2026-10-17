extends SceneTree
const F = preload("res://tests/residents_ui_fixture.gd")
const C = preload("res://scripts/world_3d/world_coordinates.gd")
const P = preload("res://scripts/resident_profession.gd").Type
const T = preload("res://scripts/building_type.gd").Type
const Activity = preload("res://scripts/resident_activity.gd").Type
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func capture(world: Node, label: String, focus: Vector2) -> void:
	if "--render-qa" not in OS.get_cmdline_user_args(): return
	var camera = world.get_viewport().get_camera_3d()
	var forward: Vector3 = -camera.global_basis.z
	var center: Vector3 = camera.global_position+forward*(-camera.global_position.y/forward.y)
	var point: Vector3 = C.to_world(focus)
	camera.global_position += Vector3(point.x-center.x,0,point.z-center.z)
	camera.set_zoom_distance(48/(2*tan(deg_to_rad(camera.fov/2))))
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var folder := "C:/Users/SW/Documents/Codex/outputs/work-areas-w2/rendered"
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder+"/"+label+".png")
func run() -> void:
	var world = F.create(self)
	await process_frame
	var actor = world.resident_runtimes[0]
	var other = world.resident_runtimes[1]
	var panel = world.game_ui.info_panel
	var highlight = world.work_highlight
	var hut = F.building(world,T.LUMBERJACK_HUT,Vector3(-24,0,-20))
	var quarry = F.building(world,T.QUARRY,Vector3(26,0,-20))
	var saw = F.building(world,T.SAWMILL,Vector3(-13,0,0))
	var hut_view = world.world_locations.get_view(hut.id)
	var quarry_view = world.world_locations.get_view(quarry.id)
	var saw_view = world.world_locations.get_view(saw.id)
	check(world.player_control.assign_workplace(actor.data.id,hut.id,P.LUMBERJACK),"Lumberjack has a real hut assignment")
	world.resident_selection.select(actor.data)
	panel.set_expanded(true)
	panel.select_tab(&"bio")
	check(not hut_view.indicator.visible and not highlight.circle.visible,"Bio tab does not highlight the resident workplace")
	panel.select_tab(&"work")
	check(hut_view.indicator.visible and highlight.circle.visible,"Work tab highlights hut and its standard circle")
	check(world.resident_selection.selected_resident==actor.data and world.resident_selection.selected_building==null,"Map accent preserves resident selection and card")
	check(actor.data.activity==Activity.IDLE and highlight.circle.visible,"An idle assigned resident still has a work area")
	check(highlight.circle.position.is_equal_approx(C.to_world(hut.position)+Vector3(0,0.02,0)),"Standard circle reads building position using 25:1 coordinates")
	check(is_equal_approx(highlight.circle.mesh.get_aabb().size.x,2*hut.definition.work_radius),"Standard circle uses the actual definition work radius")
	check(world.work_areas.all().is_empty(),"Drawing a building area creates no registered WorkArea")
	check(not world.navigation_debug.visible and not hut_view.work_area.visible,"Resident overlay works with navigation debug disabled")
	var mesh = highlight.circle.mesh
	var indicator_mesh = hut_view.indicator.mesh
	var count: int = world.residents.size()
	var nodes_before: int = highlight.get_child_count()
	var decisions: int = actor.decision.decision_count
	var nav_revision: int = world.navigation.revision
	var source_queries: Array = []
	var original: Callable = world.logistics.sources.route_available
	world.logistics.sources.route_available = func(start,target): source_queries.append([start,target]); return original.call(start,target)
	for iteration in range(30):
		highlight.refresh()
		highlight._process(0.016)
		panel._apply()
	check(highlight.circle.mesh==mesh and hut_view.indicator.mesh==indicator_mesh and highlight.get_child_count()==nodes_before,"Repeated card updates reuse the same geometry and nodes")
	check(actor.decision.decision_count==decisions and world.navigation.revision==nav_revision and source_queries.is_empty(),"Highlight refresh does not request work, change navigation or query source routes")
	world.logistics.sources.route_available = original
	await capture(world,"01-hut-and-area",hut.position)
	# The debug layer and resident overlay do not clear each other's state.
	world._set_navigation_debug(true)
	check(hut_view.work_area.visible and highlight.circle.visible,"Debug circle coexists with the resident outline")
	panel.select_tab(&"relations")
	check(not hut_view.indicator.visible and not highlight.circle.visible and hut_view.work_area.visible,"Leaving Work hides its accent and preserves navigation debug")
	world._set_navigation_debug(false)
	panel.select_tab(&"work")
	check(highlight.circle.visible and not hut_view.work_area.visible,"Disabling debug cannot hide an active resident area")
	# Existing standard areas, including profession-specific applicability.
	check(world.player_control.assign_workplace(actor.data.id,quarry.id,P.MINER),"Miner is assigned to a quarry")
	check(not hut_view.indicator.visible and quarry_view.indicator.visible and highlight.circle.visible and highlight.circle.position.is_equal_approx(C.to_world(quarry.position)+Vector3(0,0.02,0)),"Reassignment updates building and circle immediately")
	await capture(world,"02-quarry-and-area",quarry.position)
	world.player_control.assign_workplace(actor.data.id,saw.id,P.SAWYER)
	check(not quarry_view.indicator.visible and saw_view.indicator.visible and not highlight.circle.visible,"Other production highlights only its workplace")
	world.player_control.assign_workplace(other.data.id,quarry.id,P.PORTER)
	world.resident_selection.select(other.data)
	panel.set_expanded(true);panel.select_tab(&"work")
	check(quarry_view.indicator.visible and not highlight.circle.visible and not saw_view.indicator.visible,"A quarry porter does not inherit the miner's working circle")
	world.resident_selection.select(actor.data)
	world.player_control.assign_workplace(actor.data.id,hut.id,P.LUMBERJACK)
	var area = world.work_areas.create(C.to_sim(Vector3(-5,0,8)),C.length_to_sim(15))
	world.player_control.assign_work_area(actor.data.id,area.id)
	check(highlight.circle.visible and not hut_view.indicator.visible and not quarry_view.indicator.visible and not saw_view.indicator.visible,"Free lumberjack shows only its assigned area")
	check(highlight.circle.position.is_equal_approx(C.to_world(area.center)+Vector3(0,0.02,0)) and is_equal_approx(highlight.circle.mesh.get_aabb().size.x,30),"Independent area uses actual center and radius in world units")
	# Also capture the normal flow of opening Work after an area was assigned.
	panel.select_tab(&"bio")
	panel.select_tab(&"work")
	await capture(world,"03-free-area",area.center)
	mesh = highlight.circle.mesh
	area.update(C.to_sim(Vector3(-1,0,8)),area.radius)
	check(highlight.circle.mesh==mesh and highlight.circle.position.is_equal_approx(C.to_world(area.center)+Vector3(0,0.02,0)),"Moving an area updates the transform without rebuilding its mesh")
	area.update(area.center,C.length_to_sim(9))
	check(highlight.circle.mesh!=mesh and is_equal_approx(highlight.circle.mesh.get_aabb().size.x,18),"Radius edit redraws the same domain geometry without altering it")
	mesh = highlight.circle.mesh
	for iteration in range(20): highlight.refresh()
	check(highlight.circle.mesh==mesh,"An unchanged area revision does not rebuild the circle")
	panel.select_tab(&"bio")
	check(not highlight.circle.visible,"Switching to Bio hides the independent area")
	await capture(world,"04-work-tab-closed",area.center)
	panel.select_tab(&"work")
	panel.set_expanded(false)
	check(not highlight.circle.visible,"Collapsed card has no work overlay")
	panel.set_expanded(true)
	check(highlight.circle.visible,"Expanding the remembered Work tab restores its assigned area")
	panel.hide()
	check(not highlight.circle.visible,"Hiding the card clears its accent")
	panel.show()
	check(highlight.circle.visible,"Showing a Work card restores the accent")
	world.game_ui.hide()
	highlight._process(0.0)
	check(not highlight.circle.visible,"Hidden ancestor UI does not leave a work contour")
	world.game_ui.show()
	highlight._process(0.0)
	world.resident_selection.select(other.data)
	check(not highlight.circle.visible and quarry_view.indicator.visible,"Selecting another resident replaces, rather than accumulates, work highlights")
	world.resident_selection.select_building(hut)
	check(not highlight.circle.visible and not quarry_view.indicator.visible and hut_view.indicator.visible,"Selecting a building clears work accents and preserves ordinary selection")
	world.resident_selection.clear()
	check(not hut_view.indicator.visible and not highlight.circle.visible,"Cleared selection removes all work highlighting")
	world.resident_selection.select(actor.data)
	panel.set_expanded(true);panel.select_tab(&"work")
	world.player_control.clear_work_assignment(actor.data.id)
	check(not highlight.circle.visible,"A resident without assignment has no invented region")
	world.player_control.assign_profession(actor.data.id,P.MINER)
	world.player_control.assign_work_area(actor.data.id,area.id)
	check(highlight.circle.visible,"Free mining uses the same area visualization")
	world.work_areas.remove(area.id)
	check(not highlight.circle.visible,"Removed independent reference clears safely")
	actor.data.work_area_id = &"missing_area"
	highlight._process(0.0)
	check(not highlight.circle.visible,"Stale independent ID does not invent a circle")
	world.player_control.assign_workplace(actor.data.id,quarry.id,P.MINER)
	world.player_control.unregister_building(quarry.id)
	check(not quarry_view.indicator.visible and not highlight.circle.visible,"Unregistered building clears both accents without requiring a new selection")
	# Current assignment is highlighted; an already accepted forestry action is untouched.
	world.player_control.assign_workplace(actor.data.id,hut.id,P.LUMBERJACK)
	var lumberjack = actor.get_node("Lumberjack")
	check(lumberjack.request_work() and lumberjack.kind==&"CHOP","Real forestry work is accepted before UI reassignment")
	var intent = actor.intents.current_intent
	var claimed = lumberjack.tree
	var free_area = world.work_areas.create(C.to_sim(Vector3(40,0,25)),C.length_to_sim(10))
	world.player_control.assign_work_area(actor.data.id,free_area.id)
	check(lumberjack.tree==claimed and claimed.reservation_owner_id==StringName(actor.data.id) and actor.intents.current_intent==intent,"Changing work highlight does not cancel or redirect accepted chop")
	check(highlight.circle.visible and not hut_view.indicator.visible and highlight.circle.position.is_equal_approx(C.to_world(free_area.center)+Vector3(0,0.02,0)),"Overlay reflects the new assignment while old work is retained")
	panel._close()
	check(not highlight.circle.visible and actor.intents.current_intent==intent and lumberjack.tree==claimed,"Closing the card clears only presentation")
	lumberjack.abort(false)
	actor.intents.abort_current(actor.intents.current_intent)
	# Geometry fields of a standard area lack signals; cheap identity checks see changes.
	world.resident_selection.select(actor.data)
	world.player_control.assign_workplace(actor.data.id,hut.id,P.LUMBERJACK)
	panel.set_expanded(true);panel.select_tab(&"work")
	var saved_radius: float = hut.definition.work_radius
	hut.definition.work_radius = 11.0
	highlight._process(0.0)
	check(is_equal_approx(highlight.circle.mesh.get_aabb().size.x,22),"Standard geometry changes are detected without querying AI")
	hut.definition.work_radius = saved_radius
	highlight._process(0.0)
	var count_connections: int = world.work_areas.changed.get_connections().size()
	highlight.queue_free()
	await process_frame
	check(not hut_view.indicator.visible and world.work_areas.changed.get_connections().size()==count_connections-1,"Overlay teardown releases accents and its subscriptions")
	check(world.residents.size()==count,"Showing work assignment creates no game entities")
	var replacement = load("res://scripts/world_3d/resident_work_highlight_3d.gd").new()
	world.get_node("World").add_child(replacement)
	replacement.setup(panel,world.player_control,world.work_areas,world.world_locations)
	check(replacement.circle.visible and hut_view.indicator.visible,"Whole-world teardown starts with an active highlight")
	world.free()
	print("Work highlight: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
