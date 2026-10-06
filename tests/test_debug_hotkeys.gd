extends SceneTree
const Setup = preload("res://tests/behavior_test_setup.gd")
const FOOD = preload("res://scripts/resource_type.gd").Type.FOOD
var failures := 0
var checks := 0
var recalculations := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func key(code: Key, shift: bool, pressed: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.shift_pressed = shift
	event.pressed = pressed
	event.echo = echo
	root.push_input(event, true)
func snapshot(scene: Node) -> Array:
	var selected = scene.resident_selection.selected_resident
	return [scene.game_time.total_minutes, selected.hunger, selected.fatigue, scene.kitchen_data.resources.get_amount(FOOD), recalculations]
func _run() -> void:
	var old_codes: Array = [KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F9, KEY_F10, KEY_F10, KEY_F11, KEY_F12]
	var codes: Array = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
	for index in range(9):
		var scene = Setup.make_scene(self)
		await process_frame
		var actor = scene.resident_runtimes[1]
		actor.data.hunger = 20
		actor.data.fatigue = 20
		scene.resident_selection.select(actor.data)
		recalculations = 0
		scene.logistics.changed.connect(func(): recalculations += 1)
		paused = true
		var before: Array = snapshot(scene)
		for shift in [false, true]:
			key(old_codes[index], shift)
			key(old_codes[index], shift, false)
		check(snapshot(scene) == before, "Old F-key with/without Shift cannot trigger debug command %d" % (index + 1))
		key(codes[index], false)
		key(codes[index], false, false)
		check(snapshot(scene) == before, "Bare digit never invokes debug command %d; speed controls remain separate" % (index + 1))
		var speed: int = scene.game_time.speed_multiplier
		key(codes[index], true)
		match index:
			0: check(scene.game_time.total_minutes == 420, "Shift+1 advances exactly 60 game minutes on pause")
			1: check(scene.game_time.total_minutes == 720, "Shift+2 advances exactly 360 game minutes on pause")
			2: check(scene.game_time.total_minutes == 420, "Shift+3 advances to ordinary next day phase boundary")
			3: check(actor.data.hunger == 45, "Shift+4 adds exactly 25 hunger")
			4: check(actor.data.fatigue == 100, "Shift+5 sets fatigue to 100")
			5: check(actor.data.hunger == 75, "Shift+6 sets hunger to 75")
			6: check(actor.data.hunger == 100, "Shift+7 sets critical hunger to 100")
			7: check(scene.kitchen_data.resources.get_amount(FOOD) == 1, "Shift+8 adds exactly 1 FOOD to local kitchen")
			8: check(recalculations == 1 and scene.kitchen_data.resources.get_amount(FOOD) == 0 and scene.warehouse_data.resources.get_amount(FOOD) == 10, "Shift+9 invokes one logistics recalculate without moving FOOD")
		check(scene.game_time.speed_multiplier == speed, "Debug digit does not also change simulation speed")
		var after: Array = snapshot(scene)
		key(codes[index], true, true, true)
		key(codes[index], true, false)
		check(snapshot(scene) == after, "Echo and release cannot repeat debug command %d" % (index + 1))
		paused = false
		scene.free()
	# Modifier abstraction accepts either physical Shift location, no side-specific binding.
	for side in [KEY_LOCATION_LEFT, KEY_LOCATION_RIGHT]:
		var scene = Setup.make_scene(self)
		await process_frame
		var actor = scene.resident_runtimes[1]
		actor.data.hunger = 20
		scene.resident_selection.select(actor.data)
		var modifier := InputEventKey.new()
		modifier.physical_keycode = KEY_SHIFT
		modifier.location = side
		modifier.shift_pressed = true
		modifier.pressed = true
		root.push_input(modifier, true)
		key(KEY_4, true)
		key(KEY_4, true, false)
		modifier.pressed = false
		modifier.shift_pressed = false
		root.push_input(modifier, true)
		check(actor.data.hunger == 45, "Left and right Shift use same debug modifier")
		scene.free()
	print("Debug hotkeys: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
