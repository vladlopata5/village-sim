extends RefCounted
## Presentation history only; no psychological memory modifiers.
enum Importance { NONE, TEMPORARY, KEY }
var text: String
var importance: Importance
var created_minute: int
func _init(description: String, kind: Importance, minute: int) -> void:
	text = description
	importance = kind
	created_minute = minute
