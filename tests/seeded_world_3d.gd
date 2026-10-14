extends "res://scripts/world_3d/main_3d.gd"
const Seed = preload("res://tests/settlement_seed.gd")
func _create_starting_buildings() -> void: Seed.buildings(self)
func _starting_home_id(index: int) -> StringName: return Seed.home_id(index)
func _create_starting_home(data: ResidentData, index: int) -> void: Seed.home(self,data,index)
