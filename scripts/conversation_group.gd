extends RefCounted
## Membership only; no renderer, fixed pairs, or maximum size.
var id: int
var participants: Array[String] = []
func _init(group_id: int) -> void: id = group_id
