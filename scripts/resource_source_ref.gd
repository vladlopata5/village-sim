extends RefCounted
## Stable identity only. Amount/type/position always resolve from domain data.
enum Kind { CONTAINER, GROUND }
var _kind: Kind
var _id: StringName
var kind: Kind:
	get: return _kind
var id: StringName:
	get: return _id
func _init(source_kind: Kind, entity_id: StringName) -> void:
	_kind = source_kind
	_id = entity_id
func stable_key() -> String: return "%d:%s" % [kind,id]
