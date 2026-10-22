extends RefCounted
## An additional construction plan and concrete target configuration, never a second executor.
const Stage = preload("res://scripts/construction_stage.gd")
var id: StringName = &"level_2"
var from_level := 1
var to_level := 2
var construction_requirements: Dictionary = {}
var construction_work_required := 180
var max_builders := 2
var construction_stages: Array[Stage] = []
var capacities: Dictionary = {}
var worker_capacity := 1
var local_resource_capacity := 0
var recipes: Array = []
var description := ""
func is_valid() -> bool:
	if id.is_empty() or from_level<1 or to_level!=from_level+1 or worker_capacity<1 or local_resource_capacity<0 or max_builders<1:return false
	var amounts: Dictionary={};var minutes:=0;var ids: Dictionary={}
	for stage in construction_stages:
		if stage==null or not stage.is_valid() or ids.has(stage.id):return false
		ids[stage.id]=true;minutes+=stage.work_minutes
		for resource in stage.materials:amounts[resource]=int(amounts.get(resource,0))+stage.materials[resource]
	if minutes!=construction_work_required or minutes<=0 or amounts!=construction_requirements:return false
	for resource in capacities:
		if resource not in preload("res://scripts/resource_type.gd").Type.values() or not capacities[resource] is int or capacities[resource]<0:return false
	var recipe_ids: Dictionary={}
	for recipe in recipes:
		if recipe==null or not recipe.is_valid() or recipe_ids.has(recipe.id):return false
		recipe_ids[recipe.id]=true
	return true
