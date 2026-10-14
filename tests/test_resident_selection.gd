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
	var card=world.resident_card_view()
	var selection=world.resident_selection
	await physics_frame
	await physics_frame
	await process_frame
	check(selection.selected_entity==null and not card.visible,"No selection/card initially")
	var camera=world.get_node("World/Camera3D")
	Fixture.click(self,camera.unproject_position(actor.view.global_position+Vector3(0,0.72,0)))
	await physics_frame
	await physics_frame
	check(selection.selected_resident==actor.data and card.visible,"Real perspective ray selects original resident")
	check(card.name_label.text=="Имя: Степан" and card.age_label.text=="Возраст: 30","Resident name/age")
	check(card.profession_label.text=="Профессия: Носильщик","Profession")
	actor.data.resident_name="Проверка"
	actor.data.age=31
	card._process(0.25)
	check(card.name_label.text=="Имя: Проверка" and card.age_label.text=="Возраст: 31","Visible polling reads live fields")
	Fixture.click(self,card.name_label.get_global_rect().get_center())
	await physics_frame
	await physics_frame
	check(selection.selected_resident==actor.data,"Card click consumes input")
	paused=true
	Fixture.click(self,card.close_button.get_global_rect().get_center())
	await process_frame
	check(selection.selected_entity==null and not card.visible,"Close clears selection on pause")
	selection.select(actor.data)
	Fixture.click(self,Fixture.screen(world,Vector2(-650,400)))
	await physics_frame
	await physics_frame
	check(selection.selected_entity==null,"Empty ground clears on pause")
	paused=false
	camera.pan(Vector2.RIGHT,0.5)
	Fixture.click(self,camera.unproject_position(actor.view.global_position+Vector3(0,0.72,0)))
	await physics_frame
	await physics_frame
	check(selection.selected_resident==actor.data,"Resident selected after perspective camera pan")
	actor.view.free()
	check(selection.selected_resident==actor.data and is_instance_valid(actor.data),"Data selection independent of presentation lifetime")
	selection.clear()
	world.free()
	print("resident_selection: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
