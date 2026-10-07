extends SceneTree
const Clock = preload("res://scripts/game_time.gd")
const Data = preload("res://scripts/resident_data.gd")
const Dynamics = preload("res://scripts/need_dynamics.gd")
const Activity = preload("res://scripts/resident_activity.gd")
const NeedType = preload("res://scripts/need_type.gd")
var failures := 0
func _initialize(): call_deferred("_run")
func check(value: bool, message: String):
	if not value:
		failures += 1
		push_error(message)
func _run():
	var expected = {Activity.Type.IDLE: 41, Activity.Type.MOVING: 42, Activity.Type.WORKING: 44, Activity.Type.HAULING: 45, Activity.Type.EATING: 41, Activity.Type.SLEEPING: 10, Activity.Type.RESTING: 30, Activity.Type.TALKING: 41, Activity.Type.RELAXING: 41}
	for activity in expected:
		for speed in [1, 2, 4, 10, 20]:
			for frames in [1, 30, 120]:
				var clock = Clock.new()
				root.add_child(clock)
				clock.set_process(false)
				clock.set_speed(speed)
				var data = Data.new("test", "Тест", 30)
				data.activity = activity
				if activity == Activity.Type.SLEEPING: data.start_sleep(preload("res://scripts/balance_config.gd").HOME_SLEEP_QUALITY)
				data.fatigue = 40
				data.get_need(NeedType.Type.SOCIAL).value = 50
				data.get_need(NeedType.Type.LEISURE).value = 50
				data.hunger = 80 if activity == Activity.Type.EATING else 20
				var dynamics = Dynamics.new()
				root.add_child(dynamics)
				dynamics.setup(clock, data)
				for frame in range(frames): clock.advance(60.0 / speed / frames)
				check(data.fatigue == expected[activity], "Same fatigue rate for activity/speed/FPS")
				check(data.hunger == (0 if activity == Activity.Type.EATING else (21 if activity == Activity.Type.SLEEPING else 24)), "Common hunger dynamics preserves awake/sleep and gradual meal rates")
				check(data.get_need(NeedType.Type.SOCIAL).value == clampi(50 + int(float(Dynamics.SOCIAL_RATES[activity]) * (0.2 if activity == Activity.Type.SLEEPING else 1.0) / (5 if Dynamics.SOCIAL_RATES[activity] > 0 else 1)), 0, 100), "Social rate is independent of speed/FPS")
				check(data.get_need(NeedType.Type.LEISURE).value == clampi(50 + int(float(Dynamics.LEISURE_RATES[activity]) * (0.2 if activity == Activity.Type.SLEEPING else 1.0) / (5 if Dynamics.LEISURE_RATES[activity] > 0 else 1)), 0, 100), "Leisure rate is independent of speed/FPS")
				var values = [data.hunger, data.fatigue, data.get_need(NeedType.Type.SOCIAL).value, data.get_need(NeedType.Type.LEISURE).value]
				paused = true
				clock.advance(1000)
				check(values == [data.hunger, data.fatigue, data.get_need(NeedType.Type.SOCIAL).value, data.get_need(NeedType.Type.LEISURE).value], "Pause freezes both needs")
				paused = false
				clock.free()
				dynamics.free()
	var a = Data.new("a", "A", 20)
	var b = Data.new("b", "B", 20)
	a.get_need(NeedType.Type.HUNGER).value = 200
	check(a.hunger == 100 and b.hunger == 0 and a.get_need(NeedType.Type.FATIGUE) != b.get_need(NeedType.Type.FATIGUE), "Bounded needs belong to individual resident; aliases share one value")
	a.fatigue = 50
	check(a.get_need(NeedType.Type.FATIGUE).get_priority() == 5000, "Value times weight")
	a.get_need(NeedType.Type.FATIGUE).base_weight = 120
	check(a.get_need(NeedType.Type.FATIGUE).get_priority() == 6000, "Effective weight is a separate extension point")
	print("Need dynamics checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
