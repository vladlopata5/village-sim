extends RefCounted
## One prospective meal, not stock or ownership. SourceRef still identifies a place.
const Source = preload("res://scripts/resource_source_ref.gd")
var source_ref: Source
var concrete_type: int

func _init(source: Source, resource: int) -> void:
	source_ref = source
	concrete_type = resource

func matches(other: RefCounted) -> bool:
	return other != null and concrete_type == other.concrete_type and source_ref.stable_key() == other.source_ref.stable_key()
