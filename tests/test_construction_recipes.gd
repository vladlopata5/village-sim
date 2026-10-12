extends SceneTree
const Def = preload("res://scripts/building_definition.gd")
const B = preload("res://scripts/building_instance.gd")
const T = preload("res://scripts/building_type.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const P = preload("res://scripts/resident_profession.gd").Type
const Phase = preload("res://scripts/resident_builder_controller.gd").Phase
const Expected = preload("res://tests/construction_recipe_expectations.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func fixture() -> Node:
	var world = load("res://scenes/main_3d.tscn").instantiate()
	root.add_child(world)
	world.game_time.set_process(false)
	world.game_logger.console_enabled = false
	world.social_events.enabled = false
	world.game_time.total_minutes = 420
	for actor in world.resident_runtimes:
		actor.decision._deciding = true
		actor.intents.abort_current(actor.intents.current_intent)
		actor.view.set_physics_process(false)
		for need in actor.data.needs.values():
			need.value = 0
			need.base_weight = 0
	return world
func place(world: Node, category: int):
	world.placement.select(Def.for_type(category))
	world.placement.update_world_position(Vector3(-10,0,16))
	return world.placement.confirm()
func walk(actor: Node, phase: int) -> void:
	for step in range(12000):
		if actor.builder.phase != phase: break
		preload("res://tests/handling_test_step.gd").move_3d(actor,0.05)
	check(actor.builder.phase != phase,"Physical builder trip finishes")
func capture(label: String) -> void:
	if not "--rendered" in OS.get_cmdline_user_args(): return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("C:/Users/SW/Documents/Codex/outputs/construction-recipes-update/" + label + ".png") == OK,"Rendered recipe capture")
func run() -> void:
	var town = Def.for_type(T.TOWN_CENTER)
	check(town.construction_requirements.is_empty() and town.construction_work_required == 0 and town.max_builders == 0 and not town.player_buildable,"Town Center construction remains unchanged")
	for category in Expected.COSTS:
		var definition = Def.for_type(category)
		var cost: Dictionary = Expected.COSTS[category]
		check(definition.construction_requirements == cost,"Exact agreed recipe: " + definition.display_name)
		check(definition.construction_requirements.values().all(func(amount): return amount > 0),"No zero material requirements")
		check(definition.construction_requirements.has(R.PLANK) == (category == T.STORAGE),"Only Storage requests PLANK")
		var world = fixture()
		# Controlled supply for integration of each recipe, not a new-game economic fixture.
		var source = world.warehouse_data
		for resource in R.values(): source.resources.add(resource,100-source.resources.get_amount(resource))
		var site = place(world,category)
		check(site != null and site.state == B.State.UNDER_CONSTRUCTION,"Real placement creates construction")
		if site == null:
			world.free()
			continue
		check(site.definition.construction_requirements == cost and site.construction_delivered.values().all(func(amount): return amount == 0),"New site reads current definition")
		var card = world.get_node("HUD/BuildingCard")
		world.resident_selection.select_building(site)
		for resource in R.values():
			check(site.get_missing_amount(resource) == cost.get(resource,0),"Missing amount matches recipe")
			check(((preload("res://scripts/resource_type.gd").display_name(resource) + ":") in card.construction_materials.text) == cost.has(resource),"Card only lists required resources")
		var button: Button = null
		for child in world.construction_panel.building_buttons.get_children():
			if child.text == site.display_name: button = child
		check(button != null,"Construction menu exposes type")
		for resource in cost:
			check(("%s: %d" % [preload("res://scripts/resource_type.gd").display_name(resource),cost[resource]]) in button.tooltip_text,"Pre-placement cost tooltip uses actual recipe")
		await capture("recipe_%s_initial" % definition.id)
		check(not world.logistics.allows_external_delivery(source,site,R.LOG),"Existing Porter policy excludes unfinished destinations; Builder supplies construction")
		var actor = world.resident_runtimes[1]
		world.player_control.assign_profession(actor.data.id,P.BUILDER)
		check(world._request_work(actor),"Normal WORK selects site and first required material")
		var first: int = actor.builder._resource
		check(cost.has(first) and source.resources.get_reserved_out(first) == 1 and site.get_construction_reserved_in(first) == 1,"Actual outbound/inbound reserve required resource only")
		walk(actor,Phase.GOING_TO_SOURCE)
		walk(actor,Phase.CARRYING_TO_SITE)
		check(site.get_delivered_amount(first) == 1 and not site.are_construction_materials_complete() and site.construction_progress == 0 and not site.complete_construction(),"Partial physical delivery cannot complete construction")
		await capture("recipe_%s_partial" % definition.id)
		# Cancellation releases the already-started next trip before pickup.
		check(world.cancel_construction(site.id),"Normal cancel removes mixed-resource site")
		for resource in R.values():
			check(source.resources.get_reserved_out(resource) == 0 and site.get_construction_reserved_in(resource) == 0,"Cancellation releases all owned reservations")
		check(actor.data.inventory.amount == 0,"No phantom cargo before pickup")
		world.free()

		world = fixture()
		source = world.warehouse_data
		for resource in R.values(): source.resources.add(resource,100-source.resources.get_amount(resource))
		site = place(world,category)
		world.resident_selection.select_building(site)
		actor = world.resident_runtimes[1]
		world.player_control.assign_profession(actor.data.id,P.BUILDER)
		check(world._request_work(actor),"Full recipe starts ordinary Builder workflow")
		for trip in range(40):
			if actor.builder.phase not in [Phase.GOING_TO_SOURCE,Phase.CARRYING_TO_SITE]: break
			world.game_time.total_minutes = 420
			walk(actor,actor.builder.phase)
		check(site.are_construction_materials_complete(),"All required materials physically delivered")
		for resource in R.values():
			check(site.get_delivered_amount(resource) == cost.get(resource,0) and source.resources.get_amount(resource) == 100-cost.get(resource,0),"Exact consumption, no absent or surplus resource spent")
			check(source.resources.get_reserved_out(resource) == 0 and site.get_construction_reserved_in(resource) == 0,"Full delivery clears resource reservations")
			check(not site.add_delivered_material(resource,1),"No extra material accepted after exact supply")
		await capture("recipe_%s_supplied" % definition.id)
		walk(actor,Phase.GOING_TO_SITE)
		check(actor.builder.phase == Phase.BUILDING,"Real access-point arrival starts work")
		for cycle in range(4):
			if site.is_built(): break
			if actor.builder.phase == Phase.NONE:
				check(world._request_work(actor),"Normal cycle decision resumes work")
				walk(actor,Phase.GOING_TO_SITE)
			world.game_time.total_minutes += 60
			actor.builder._on_minute(world.game_time.total_minutes)
		check(site.is_built() and site.construction_progress == definition.construction_work_required and site.active_builder_ids.is_empty(),"Exact materials plus unchanged work complete existing lifecycle")
		await capture("recipe_%s_built" % definition.id)
		world.free()
	print("Construction recipes: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
