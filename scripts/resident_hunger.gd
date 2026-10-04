extends Node
## Hunger evolves with simulation minutes, never rendering frames or UI.
const ResidentData = preload("res://scripts/resident_data.gd")
const Activity = preload("res://scripts/resident_activity.gd")
# 60 units = one hunger point: awake +4/minute, sleeping +1/minute.
const UNITS_PER_POINT := 60
var _data: ResidentData
var _growth_units: int = 0

func setup(game_time: Node, data: ResidentData) -> void:
	_data = data
	game_time.minute_changed.connect(_on_minute_changed)

func _on_minute_changed(_total_minutes: int) -> void:
	# GameTime emits once for EVERY elapsed minute, including debug jumps.
	if _data.hunger >= 100:
		_growth_units = 0
		return
	_growth_units += 1 if _data.activity == Activity.Type.SLEEPING else 4
	if _growth_units >= UNITS_PER_POINT:
		_data.hunger += 1
		_growth_units -= UNITS_PER_POINT
		if _data.hunger == 100:
			_growth_units = 0
