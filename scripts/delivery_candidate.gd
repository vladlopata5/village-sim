extends RefCounted
## Temporary decision value. Never retained in the world or attached to a job.
const Instance = preload("res://scripts/building_instance.gd")
const ResourceType = preload("res://scripts/resource_type.gd")
var source_ref: RefCounted
var source: Instance
const Receiver = preload("res://scripts/haul_job.gd").Receiver
var receiver_kind: Receiver = Receiver.CONTAINER
var destination: Instance
var resource_type: ResourceType.Type
var amount := 1
var surplus_export := false # Narrow warehouse-surplus admission, not ordinary balancing.
var world_urgency := 0.0
var route_distance := 0.0
var distance_penalty := 0.0
var personal_modifier := 0.0
var porter_score := 0.0
func stable_key() -> String:
	if receiver_kind == Receiver.GROUND: return "%d:%s:GROUND:%s" % [resource_type,source_ref.stable_key(),source_ref.id]
	return "%d:%s:%s" % [resource_type, source_ref.stable_key() if source_ref != null else source.id, destination.id]
