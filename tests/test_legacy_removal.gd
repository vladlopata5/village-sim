extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
func run() -> void:
	check(ProjectSettings.get_setting("application/run/main_scene")=="res://scenes/main_3d.tscn","Only canonical project main")
	for path in ["scenes/main.tscn","scenes/resident_card.tscn","scenes/building_card.tscn","scripts/resident_view_2d.gd","scripts/world_locations_2d.gd","scripts/building_placement_input.gd","scripts/interaction_targets_2d.gd","scripts/prototype_hud.gd"]:
		check(not FileAccess.file_exists("res://"+path),"Retired resource absent: "+path)
	var main_source=FileAccess.get_file_as_string("res://scripts/main.gd")
	check(not main_source.contains("ResidentView2D") and not main_source.contains("interaction_targets") and not main_source.contains("logistics_label"),"Shared assembly has no old presentation dependencies")
	var world=preload("res://tests/canonical_ui_fixture.gd").make(self)
	await process_frame
	check(world.ready_for_play and world.residents.size()==4 and world.buildings.size()==1,"Canonical new game retained")
	check(world.world_locations.uses==world.building_uses,"Authored canonical action bridge")
	check(world.game_ui.resident_card.get_script()==preload("res://scripts/resident_card.gd"),"Shared resident presenter retained")
	check(world.game_ui.building_card.get_script()==preload("res://scripts/building_card.gd"),"Shared building presenter retained")
	var time=world.game_ui.time_controls
	world.game_time.debug_skip_minutes(1)
	await process_frame
	await process_frame
	check(time.clock_label.text==world.game_time.get_clock_text(),"Clock no longer depends on old Main relay")
	world.game_time.set_speed(4)
	check(time.speed_buttons[2].button_pressed,"Speed signal updates canonical controls")
	check(world.resident_runtimes[0].builder.material_planner.is_valid(),"P1 planner still bound")
	check(ResourceLoader.exists("res://scenes/prototypes/2_5d_prototype.tscn"),"Independent tested prototype preserved")
	world.free()
	print("Legacy removal: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
