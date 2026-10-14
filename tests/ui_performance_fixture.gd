extends SceneTree
const F=preload("res://tests/residents_ui_fixture.gd")
const OUT="C:/Users/SW/Documents/Codex/outputs/ui-e5-polish/"
var rows:=[]
func _initialize() -> void: call_deferred("run")
func nodes(node: Node) -> int:
	var count:=1 if node is Control else 0
	for child in node.get_children(): count+=nodes(child)
	return count
func metric(node: Object, key: String) -> Variant:
	return node.get(key)
func run() -> void:
	root.size=Vector2i(1600,900)
	for population in [30,100]:
		var world=F.create(self)
		# Debug spawn admits at most 50 per command. Verify the actual population.
		while world.residents.size()<population:
			var spawned: Dictionary=world.debug_spawn.spawn_residents(Vector3(-4,0,-8),mini(50,population-world.residents.size()),0)
			assert(spawned.created>0,"Performance fixture must register requested population")
		assert(world.residents.size()==population)
		for actor in world.resident_runtimes:
			actor.decision._deciding=true;actor.view.set_physics_process(false)
			actor.intents.abort_current(actor.intents.current_intent)
		var ui=world.game_ui
		var card=ui.resident_card
		var window=world.settlement_panel
		for speed in [1,20]:
			world.game_time.set_speed(speed)
			for opened in [false,true]:
				if opened:
					world.resident_selection.select(world.residents[0]);ui.info_panel.set_expanded(true)
					ui.open_window(&"residents")
				else: ui.close_window();world.resident_selection.clear()
				await process_frame;await process_frame
				var identities=window.rows.values().map(func(item): return item.get_instance_id())
				var count:=nodes(ui)
				var before=[metric(card,"refresh_count"),metric(window,"refresh_count"),metric(window,"row_creation_count"),metric(window,"poll_count")]
				var started:=Time.get_ticks_usec()
				# Same rendered cadence and real GameTime events; no autonomous AI/pathfinding.
				for sample in range(12):
					world.game_time.advance(0.25)
					await create_timer(0.25).timeout
				var after=[metric(card,"refresh_count"),metric(window,"refresh_count"),metric(window,"row_creation_count"),metric(window,"poll_count")]
				rows.append({"population":population,"speed":speed,"opened":opened,"rendered":DisplayServer.get_name()!="headless","wall_us":Time.get_ticks_usec()-started,"ui_nodes":count,"ui_nodes_after":nodes(ui),"tree_identity_stable":identities==window.rows.values().map(func(item):return item.get_instance_id()),"counts_before":before,"counts_after":after,"need_subscriptions":world.residents[0].needs.values()[0].changed.get_connections().size()})
				print(JSON.stringify(rows[-1]))
		world.free()
		await process_frame
	var label:="baseline" if "--baseline" in OS.get_cmdline_user_args() else "after"
	var file:=FileAccess.open(OUT+label+"-performance.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(rows,"\t"))
	quit()
