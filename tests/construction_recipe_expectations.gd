extends RefCounted
## Independent expected balance; production reads BuildingDefinition, never this fixture.
const T = preload("res://scripts/building_type.gd").Type
const R = preload("res://scripts/resource_type.gd").Type
const COSTS = {
	T.LUMBERJACK_HUT: {R.LOG:10},
	T.QUARRY: {R.LOG:8,R.STONE:4},
	T.GATHERER_HUT: {R.LOG:6},
	T.SHEPHERD_HUT: {R.LOG:4,R.PLANK:6},
	T.HOME: {R.LOG:8,R.STONE:2},
	T.SAWMILL: {R.LOG:6,R.STONE:6},
	T.STORAGE: {R.LOG:2,R.STONE:4,R.PLANK:6},
	T.FOOD: {R.LOG:6},
}

# Synthetic one-material tests isolate existing ownership/timing, not type stages.
static func single_stage(definition: RefCounted) -> void:
	definition.construction_stages.clear()
	definition.construction_stages.append(preload("res://scripts/construction_stage.gd").new(&"fixture","Строительство",definition.construction_requirements,definition.construction_work_required,&"complete"))
static func complete(site: RefCounted, activate: bool = true) -> void:
	for index in range(site.definition.construction_stages.size()+1):
		if site.can_complete_construction():break
		var stage: RefCounted=site.current_construction_stage()
		for resource in stage.materials:
			var missing: int=site.get_uncovered_construction_amount(resource)
			if missing>0:assert(site.add_delivered_material(resource,missing))
		assert(site.add_construction_work(site.current_work_remaining()))
	if activate:assert(site.complete_construction())
