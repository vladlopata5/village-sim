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
	var actor=world.resident_runtimes[0]
	var data=actor.data
	check(data is RefCounted and not data is Node,"Data exists outside SceneTree")
	check(data.id=="resident_001" and data.resident_name=="Степан" and data.age==30,"Stable starter fields")
	check(actor.view.resident_data==data and actor.view.view.resident_data==data,"Executor/view share real domain data")
	check(actor.view.view.is_visible_in_tree(),"Canonical presentation visible")
	var point=actor.view.global_position
	await process_frame
	check(actor.view.global_position==point,"Isolated resident stationary")
	actor.view.view.free()
	check(is_instance_valid(data) and data==world.player_control.get_resident(data.id),"Removing visual preserves registry")
	var replacement=preload("res://scripts/world_3d/resident_view_3d.gd").new()
	actor.view.add_child(replacement)
	replacement.setup(data)
	check(replacement.resident_data==data,"Replacement reuses same data")
	world.free()
	print("resident: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
