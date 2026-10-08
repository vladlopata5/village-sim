extends StaticBody3D
## Explicit data reference for picking, not a new gameplay entity.
enum Kind { RESIDENT, BUILDING }
@export var entity_kind: Kind = Kind.RESIDENT
var entity: RefCounted
func bind(data: RefCounted) -> void:
	entity = data
func show_selection(selected: bool) -> void:
	$SelectionIndicator.visible = selected
