extends RefCounted
## Independent expected balance; production reads BuildingDefinition, never this fixture.
const T = preload("res://scripts/building_type.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const COSTS = {
	T.LUMBERJACK_HUT: {R.LOG:10},
	T.QUARRY: {R.LOG:8,R.STONE:4},
	T.GATHERER_HUT: {R.LOG:6},
	T.HOME: {R.LOG:8,R.STONE:2},
	T.SAWMILL: {R.LOG:6,R.STONE:6},
	T.STORAGE: {R.LOG:2,R.STONE:4,R.PLANK:6},
	T.FOOD: {R.LOG:6},
}
