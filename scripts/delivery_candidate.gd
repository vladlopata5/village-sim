extends RefCounted
## Temporary decision value. Never retained in the world or attached to a job.
const Instance = preload("res://scripts/building_instance.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
var source: Instance
var destination: Instance
var resource_type: ResourceType.Type
var amount := 1
var world_urgency := 0.0
var route_distance := 0.0
var distance_penalty := 0.0
var personal_modifier := 0.0
var porter_score := 0.0
func stable_key() -> String:
	return "%d:%s:%s" % [resource_type, source.id, destination.id]
