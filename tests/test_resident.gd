extends SceneTree
const ResidentData = preload("res://scripts/resident_data.gd")
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var data = scene.resident_data
	var view = scene.get_node("World/ResidentView2D")
	check(data is RefCounted and not data is Node, "Resident data exists outside the scene tree")
	check(data.id == "resident_001", "Resident ID")
	check(data.resident_name == "Степан" and data.age == 30 and data.profession == preload("res://scripts/resident_profession.gd").Type.PORTER, "Test resident fields")
	check(view.resident_data == data, "View receives the original data reference")
	check(view.is_visible_in_tree(), "Placeholder visible in the world")
	var original_position: Vector2 = view.position
	await process_frame
	await process_frame
	check(view.position == original_position, "Resident remains stationary")
	# Removing the representation must not remove the resident's data.
	view.free()
	check(is_instance_valid(scene.resident_data) and scene.resident_data == data, "Data survives removal of the view")
	# The same data can be passed to a replacement representation.
	var replacement = load("res://scenes/resident_view_2d.tscn").instantiate()
	replacement.setup(data)
	scene.get_node("World").add_child(replacement)
	check(replacement.resident_data == data, "Replacement view reuses existing resident")
	var view_count: int = 0
	for child in scene.get_node("World").get_children():
		if child.get_script() == preload("res://scripts/resident_view_2d.gd"):
			view_count += 1
	check(view_count == 1, "Exactly one resident representation")
	scene.queue_free()
	print("Resident checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
