extends SceneTree
## Each initial window/resolution is checked in a fresh process, before any card.
const F=preload("res://tests/residents_ui_fixture.gd")
const P=preload("res://scripts/resident_profession.gd").Type
const T=preload("res://scripts/building_type.gd").Type
const C=preload("res://scripts/world_3d/world_coordinates.gd")
const D=preload("res://scripts/building_definition.gd")
const Building=preload("res://scripts/building_instance.gd")
const Player=preload("res://scripts/player_control.gd")
const Selection=preload("res://scripts/resident_selection.gd")
const OUT="C:/Users/SW/Documents/Codex/outputs/ux1-1-unified-list-windows/"
var checks:=0
var failures:=0
var samples: Array=[]
var world: Node
var rendered:=false
var case_name: String
var expected: Rect2
func _initialize() -> void:call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func settle() -> void:
	for i in range(4):await process_frame
func outer(win: Control, label: String) -> void:
	check(win.get_rect()==expected,label+": exact shared rectangle")
	samples.append({"stage":label,"rect":str(win.get_rect()),"size":[win.size.x,win.size.y],"rows":win.rows.size(),"table":str(win.table.get_global_rect()),"footer":str(win.close_button.get_global_rect())})
func contents(win: Control, label: String) -> void:
	outer(win,label)
	check(win.get_global_rect().encloses(win.close_button.get_global_rect()),label+": footer inside")
	check(win.get_global_rect().encloses(win.table.get_global_rect()),label+": table inside")
	for row in win.rows.values():
		if row.visible:check(is_equal_approx(win.table.get_item_area_rect(row,0).size.y,38.0),label+": one-line normal row height")
func frame(label: String, win: Control) -> void:
	if rendered:
		await RenderingServer.frame_post_draw
		contents(win,label)
		var image:=root.get_texture().get_image()
		check(image.save_png(OUT+"rendered/"+case_name+"-"+label+".png")==OK,"PNG "+label)
	else:
		await process_frame
		contents(win,label)
func windows() -> Array:
	return [world.work_areas_window,world.buildings_window,world.settlement_panel]
func empty_projection(kind: StringName) -> void:
	# Empty buildings/residents registries are UI fixtures, not deletion of the Town Center.
	var player=Player.new();player.setup([],[])
	var selected=Selection.new();root.add_child(selected)
	var view=load("res://scenes/ui/"+("buildings_window.tscn" if kind==&"buildings" else "residents_window.tscn")).instantiate()
	world.game_ui.get_node("Windows").add_child(view)
	view.setup(player,selected);view.show();outer(view,"empty-show-sync")
	await settle();await frame("empty",view)
	check(view.rows.is_empty() and view.table.visible,"Empty registry leaves the fixed table available")
	view.free();selected.free()
func population(kind: StringName, win: Control) -> void:
	if kind==&"areas":
		for count in [1,4,70]:
			while world.work_areas.all().size()<count:world.work_areas.create(Vector2.ZERO,C.length_to_sim(8))
			await settle();await frame("rows-"+str(count),win)
	elif kind==&"buildings":
		check(win.rows.size()==1,"Canonical initial City Center is the one-row case")
		for count in [4,70]:
			while world.player_control.get_buildings().size()<count:
				var definition=D.for_type(T.HOME)
				definition.display_name="Очень длинное название здания для проверки усечения без увеличения строки"
				var id:=StringName("list_fixture_%d" % world.player_control.get_buildings().size())
				world.player_control.register_building(Building.new(id,definition))
			await settle();await frame("rows-"+str(count),win)
	else:
		win.search.text="fixture-no-match";win._projection_changed();await settle()
		check(win.visible_ids.is_empty(),"Zero matches leaves an empty resident table")
		await frame("filtered-empty",win)
		win.search.text=world.residents[0].resident_name;win._projection_changed();await settle()
		check(win.visible_ids.size()==1,"Single resident match")
		await frame("rows-1",win)
		win.search.text="";win._projection_changed();await settle();await frame("rows-4",win)
		var result=world.debug_spawn.spawn_residents(Vector3(-4,0,-8),50,P.NONE)
		var rest=world.debug_spawn.spawn_residents(Vector3(12,0,18),16,P.NONE)
		check(result.created+rest.created==66,"Real resident registry for long-list fixture")
		result.objects[0].resident_name="Очень длинное имя жителя для проверки усечения в таблице без переноса"
		for actor in world.resident_runtimes:
			actor.decision._deciding=true;actor.intents.abort_current(actor.intents.current_intent);actor.view.set_physics_process(false)
		await settle();await frame("rows-70",win)
	check(win.table.is_v_scroll_enabled() and win.rows.size()*38>win.table.size.y,"Long table scrolls instead of resizing window")
	var last: TreeItem=win.rows.values().back()
	win.table.scroll_to_item(last);await settle();await frame("scrolled",win)
	check(win.table.get_scroll().y>0,"Last item can be reached through real scrolling")
	var count_before: int=win.row_creation_count
	world.game_ui.close_window();world.game_ui.open_window(kind);await settle()
	check(win.row_creation_count==count_before,"Reopen preserves TreeItems")
func contexts(kind: StringName, win: Control) -> void:
	for source in [world.residents[0],world.warehouse_data]:
		if source==world.warehouse_data:world.resident_selection.select_building(source)
		else:world.resident_selection.select(source)
		world.game_ui.info_panel.set_expanded(true)
		await settle();contents(win,"card-after-list")
		world.game_ui.close_window();world.game_ui.open_window(kind)
		outer(win,"card-before-list-sync");await settle();contents(win,"card-before-list")
		check(not win.get_global_rect().intersects(world.game_ui.info_panel.get_global_rect()),"List reserves the same card column")
	world.resident_selection.clear();await settle();contents(win,"card-closed")
func run() -> void:
	var args=OS.get_cmdline_user_args()
	if args.is_empty():
		for resolution in [Vector2i(1906,932),Vector2i(1280,720)]:
			for kind in ["areas","buildings","residents"]:
				var output: Array=[]
				var code:=OS.execute(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/test_list_window_layout.gd","--",kind,str(resolution.x),str(resolution.y)],output,true)
				print(output[0] if not output.is_empty() else "No child output")
				check(code==0,"Fresh "+kind+" "+str(resolution))
		print("List window subprocesses: ",checks," checks, ",failures," failures");quit(1 if failures else 0);return
	rendered="--rendered" in args
	var kind:=StringName(args[0]);var width:=int(args[1]);var height:=int(args[2])
	case_name=str(kind)+"-"+str(width)+"x"+str(height)
	DirAccess.make_dir_recursive_absolute(OUT+"rendered")
	root.size=Vector2i(width,height)
	expected=Rect2(12,12,1116 if width==1906 else 924,476)
	world=F.create(self);await settle()
	var win: Control=world.work_areas_window if kind==&"areas" else (world.buildings_window if kind==&"buildings" else world.settlement_panel)
	# First user action; no other window/card has been opened.
	world.game_ui.open_window(kind)
	outer(win,"show-sync");await frame("first-visible",win)
	await settle();await frame("settled",win)
	contents(win,"before-close");world.game_ui.close_window();world.game_ui.open_window(kind)
	outer(win,"reopen-sync");await frame("reopened",win)
	if kind!=&"areas":
		world.game_ui.close_window();await empty_projection(kind);world.game_ui.open_window(kind)
	await population(kind,win);await contexts(kind,win)
	var layout_events: Array=[]
	for panel in windows():panel.resized.connect(func():layout_events.append(true))
	await settle();await settle()
	check(layout_events.is_empty(),"Stable content does not reapply geometry each frame")
	# All windows follow the same viewport change, including hidden ones.
	root.size=Vector2i(1280,720) if width==1906 else Vector2i(1906,932)
	expected=Rect2(12,12,924 if width==1906 else 1116,476)
	await settle()
	for panel in windows():outer(panel,"resized-hidden-or-visible")
	for id in [&"areas",&"buildings",&"residents"]:
		world.game_ui.open_window(id)
		var panel=world.game_ui._windows[id]
		outer(panel,"other-window-after-resize");await settle();contents(panel,"other-window-settled")
	var file=FileAccess.open(OUT+("rendered/" if rendered else "")+case_name+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"samples":samples}));file.close()
	world.free();await settle()
	print(case_name,": ",checks," checks, ",failures," failures");quit(1 if failures else 0)
